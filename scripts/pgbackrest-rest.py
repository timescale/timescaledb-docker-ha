#!/usr/bin/python3
"""
The purpose of this script/program is to be able to trigger backups using an api.

The reason to not have the CronJob execute the backup but only to trigger the backup
is as follows:

- a Kubernetes Cronjob is running in its own pod (different from the database)
- the backup process requires direct access to the data files
- therefore the backup process needs to run inside the same pod
  as the database
- therefore a CronJob cannot execute the backup process itself

By creating this script, we can run this in a sidecar container inside the same pod as
the database. As it has an api, we can extend the api so backups become discoverable.

To ensure we don't do very silly stuff, we will only allow 1 backup to take place at any given
time. Ensuring we have long running tasks and are still responsive and sending out
timely diagnostic messages pretty much means we have multiple threads. That's why multithreading
is thrown in the mix.

Apart from the main thread we use 3 more threads:

1. HTTPServer
2. Backup
3. History

The HTTPServer is a regular HTTPServer with an extra Event thrown in to allow communication
with the other thread(s).
The backup thread its sole purpose is to run the backup once triggered using the api.
The history will gather metadata about backups from pgBackRest using a scheduled interval, or when
triggered by the backup thread.

Doing multihtreading in Python is pretty much ok for this task; this program is not here
to do a lot of heavy lifting, only ensuring backups are being triggered. All the work is
done by pgBackRest.
"""

import argparse
import datetime
import io
import json
import logging
import os
import signal
import sys
import time
import urllib.parse

from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from subprocess import Popen, PIPE, check_output, STDOUT
from threading import Thread, Event, Lock

# We only ever want a single backup to be actively running. We have a global object that we share
# between the HTTP and the backup threads. Concurrent write access is prevented by a Lock and an Event
backup_history = dict()
current_backup = None
stanza = None

EPOCH = datetime.datetime(1970, 1, 1, 0, 0, 0).replace(tzinfo=datetime.timezone.utc)
LOGLEVELS = {'debug': 10, 'info': 20, 'warning': 30, 'error': 40, 'critical': 50}


def parse_arguments(args):
    """Parse the specified arguments"""
    parser = argparse.ArgumentParser(description="This program provides an api to pgBackRest",
                                     formatter_class=lambda prog: argparse.HelpFormatter(prog, max_help_position=40, width=120))
    parser.add_argument('--loglevel', help='Explicitly provide loglevel', default='info', choices=list(LOGLEVELS.keys()))
    parser.add_argument('-p', '--port', help='http listen port', type=int, default=8081)
    parser.add_argument('-s', '--stanza', help='stanza to be used by pgBackRest', default=os.environ.get('PGBACKREST_STANZA', None))

    parsed = parser.parse_args(args or [])

    return parsed


def utcnow():
    """Wraps around datetime utcnow to provide a consistent way of returning a truncated now in utc"""
    return datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc).replace(microsecond=0)


def json_serial(obj):
    """JSON serializer for objects not serializable by default json code"""
    if isinstance(obj, (datetime.datetime,)):
        return obj.isoformat()
    elif isinstance(obj, (datetime.timedelta,)):
        return obj.total_seconds()
    elif isinstance(obj, (PostgreSQLBackup,)):
        return obj.details()

    raise TypeError("Type %s not serializable" % type(obj))


class PostgreSQLBackup ():
    """This Class represents a single PostgreSQL backup

    Metadata of the backup is kept, as well as output from the actual backup command."""
    def __init__(self, stanza, request={}, status='REQUESTED', started=None, finished=None):
        self.started = started or utcnow()
        self.finished = finished
        self.pgbackrest_info = {}
        self.label = self.started.strftime('%Y%m%d%H%M%S')
        self.request = request or {}
        self.stanza = stanza
        self.pid = None
        self.request.setdefault('command', 'backup')
        self.request.setdefault('type', 'full')

        if self.request and self.request.get('command', 'backup') != 'backup':
            raise ValueError('Invalid command ({0}), supported commands: backup'.format(self.request['command']))

        self.status = status
        self.returncode = None

    def info(self):
        info = {'label': self.label, 'status': self.status, 'started': self.started, 'finished': self.finished}
        info['pgbackrest'] = {'label': self.pgbackrest_info.get('label')}

        return info

    def details(self):
        details = self.info()
        details['returncode'] = self.returncode
        details['pgbackrest'] = self.pgbackrest_info
        details['pid'] = self.pid
        if self.started:
            details['duration'] = (self.finished or utcnow()) - self.started
        details['age'] = (utcnow() - self.started)

        return details

    def run(self):
        """Runs pgBackRest as a subprocess

        reads stdout/stderr and immediately logs these as well"""
        logging.info("Starting backup")

        self.status = 'RUNNING'

        cmd = ['pgbackrest',
               '--stanza={0}'.format(self.stanza),
               '--log-level-console=off',
               '--log-level-stderr=warn',
               self.request['command'],
               '--type={0}'.format(self.request['type'])]

        # We want to augment the output with our default logging format,
        # that is why we send both stdout/stderr to a PIPE over which we iterate
        try:
            p = Popen(cmd, stdout=PIPE, stderr=STDOUT)
            self.pid = p.pid

            for line in io.TextIOWrapper(p.stdout, encoding="utf-8"):
                if line.startswith('WARN'):
                    loglevel = logging.WARNING
                elif line.startswith('ERROR'):
                    loglevel = logging.ERROR
                else:
                    loglevel = logging.INFO
                logging.log(loglevel, line.rstrip())

            self.returncode = p.wait()
            self.finished = utcnow()
        # As many things can - and will - go wrong when calling a subprocess, we will catch and log that
        # error and mark this backup as having failed.
        except OSError as oe:
            logging.exception(oe)
            self.returncode = -1

        logging.debug('Backup details\n{0}'.format(json.dumps(self.details(), default=json_serial, indent=4, sort_keys=True)))
        if self.returncode == 0:
            self.status = 'FINISHED'
            logging.info('Backup successful: {0}'.format(self.label))
        else:
            self.status = 'ERROR'
            logging.error('Backup {0} failed with returncode {1}'.format(self.label, self.returncode,))


class EventHTTPServer(HTTPServer):
    """Wraps around HTTPServer to provide a global Lock to serialize access to the backup"""
    def __init__(self, backup_trigger, *args, **kwargs):
        HTTPServer.__init__(self, *args, **kwargs)
        self.backup_trigger = backup_trigger
        self.lock = Lock()


class RequestHandler(BaseHTTPRequestHandler):
    """Serves the API for the pgBackRest backups"""

    def _write_response(self, status_code, body, content_type='text/html', headers=None):
        self.send_response(status_code)
        headers = headers or {}
        if content_type:
            headers['Content-Type'] = content_type
        for name, value in headers.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body.encode('utf-8'))

    def _write_json_response(self, status_code, body, headers=None):
        contents = json.dumps(body, sort_keys=True, indent=4, default=json_serial)
        self._write_response(status_code, contents, content_type='application/json', headers=headers)

    # We override the default BaseHTTPRequestHandler.log_message to have uniform logging output to stdout
    def log_message(self, format, *args):
        logging.info(("%s - - %s\n" % (self.address_string(), format % args)).rstrip())

    def do_GET(self):
        """List the backup(s) that can be identified through the path or query parameters

        Api:
        /backups/         list all backups
        /backups/{label}  get specific backup info for given label
                          accepts timestamp label as well as pgBackRest label
        /backups/{latest} shorthand for getting the backup info for the latest backup

        Query parameters:
        status            filter all backups for given status

        Example:   /backups/latest?status=ERROR
        Would list the last backup that failed
        """
        global backup_history

        url = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(url.query)

        # /backups/         list all backups
        backup_labels = sorted(backup_history, key=lambda b: backup_history[b].label)
        if query.get('status', None):
            for b in backup_labels[:]:
                if backup_history[b].status not in [s.upper() for s in query['status']]:
                    backup_labels.remove(b)

        if url.path == '/backups' or url.path == '/backups/':
            body = [backup_history[b].info() for b in backup_labels]
            self._write_json_response(status_code=200, body=body)

        # /backups/{label} get specific backup info
        # /backups/latest  shorthand for getting the backup info for the latest backup
        elif url.path.startswith('/backups/backup'):
            backup_label = url.path.split('/')[3]
            backup = None
            if backup_label == 'latest' and backup_labels:
                backup_label = backup_labels[-1]

            backup = backup_history.get(backup_label, None)

            # We also allow the backup label to be the one specified by pgBackRest
            if backup is None:
                for b in backup_history.values():
                    if b.pgbackrest_info.get('info', None):
                        backup = b

            if backup is None:
                self._write_response(status_code=HTTPStatus.NOT_FOUND, body='')
            else:
                self._write_json_response(status_code=HTTPStatus.OK, body=backup.details())
        else:
            self._write_response(status_code=HTTPStatus.NOT_FOUND, body='')

        return

    def do_POST(self):
        """POST a request to backup the database

        If no backup is currently running, will trigger the backup thread to
        start a backup that conforms to the request
        """
        global backup_history, current_backup, stanza

        url = urllib.parse.urlsplit(self.path)
        if url.path == '/backups' or url.path == '/backups/':
            try:
                content_len = int(self.headers.get('Content-Length', 0))
                post_body = json.loads(self.rfile.read(content_len).decode("utf-8")) if content_len else None
                with self.server.lock:
                    if self.server.backup_trigger.is_set():
                        headers = {'Location': '/backups/backup/{0}'.format(current_backup.label)}
                        self._write_json_response(status_code=HTTPStatus.CONFLICT, body={'error': 'backup in progress'}, headers=headers)
                    else:
                        self.server.backup_trigger.set()
                        current_backup = PostgreSQLBackup(request=post_body, stanza=stanza)
                        backup_history[current_backup.label] = current_backup

                        # We wait a few seconds just in case we quickly run into an error which we can report
                        max_time = time.time() + 1
                        while not current_backup.finished and time.time() < max_time:
                            time.sleep(0.1)

                        if current_backup.finished:
                            if current_backup.returncode == 0:
                                self._write_json_response(status_code=HTTPStatus.OK, body=current_backup.details())
                            else:
                                self._write_json_response(status_code=HTTPStatus.INTERNAL_SERVER_ERROR, body=current_backup.details())
                        else:
                            headers = {'Location': '/backups/backup/{0}'.format(current_backup.label)}
                            self._write_json_response(status_code=HTTPStatus.ACCEPTED, body=current_backup.details(), headers=headers)
            except json.JSONDecodeError:
                self._write_json_response(status_code=HTTPStatus.BAD_REQUEST, body={'error': 'invalid json document'})
            except ValueError as ve:
                self._write_json_response(status_code=HTTPStatus.BAD_REQUEST, body={'error': str(ve)})
        else:
            self._write_response(status_code=HTTPStatus.NOT_FOUND, body='')


def backup_poller(backup_trigger, history_trigger, shutdown_trigger):
    """Run backups every time the backup_trigger is fired

    Will stall for long amounts of time as backups can take hours/days.
    """
    global backup_history, current_backup

    logging.info('Starting loop waiting for backup events')
    while not shutdown_trigger.is_set():
        # This can probably be done more perfectly, but by sleeping 1 second we ensure 2 things:
        # - backups can be identified by their timestamp with a resolution of 1 second
        # - if there are any errors in the backup logic, we will not burn a single CPU in the while loop
        time.sleep(1)
        try:
            logging.debug('Waiting until backup triggered')
            backup_trigger.wait()
            if shutdown_trigger.is_set():
                break

            current_backup.run()
            history_trigger.set()
            backup_trigger.clear()
        except Exception as e:
            logging.error(e)
            # The currently running backup failed, we should clear the backup trigger
            # so a next backup can be started
            backup_trigger.clear()

    logging.warning('Shutting down thread')


def history_refresher(history_trigger, shutdown_trigger, interval):
    """Refresh backup history regularly from pgBackRest

     Will refresh the history when triggered, on when a timeout occurs.
    After the first pgBackRest run, this should show the history as it is known by
    pgBackRest.
    As the backup repository is supposed to be in S3, this means that calling the API
    to get information about the backup history should show you all the backups of all
    the pods, not just the backups of this pod.

    For details on what pgBackRest returns:
    https://pgbackrest.org/command.html#command-info/category-command/option-output
    """
    global backup_history, stanza

    while not shutdown_trigger.is_set():
        time.sleep(1)
        try:
            history_trigger.wait(timeout=interval)
            if shutdown_trigger.is_set():
                break

            logging.info('Refreshing backup history using pgbackrest')
            pgbackrest_out = check_output(['pgbackrest', '--stanza={0}'.format(stanza), 'info', '--output=json']).decode("utf-8")

            for b in backup_history.values():
                b.pgbackrest_info.clear()

            backup_info = json.loads(pgbackrest_out)

            if backup_info:
                for b in backup_info[0].get('backup', []):
                    pgb = PostgreSQLBackup(
                        stanza=stanza,
                        request=None,
                        started=EPOCH + datetime.timedelta(seconds=b['timestamp']['start']),
                        finished=EPOCH + datetime.timedelta(seconds=b['timestamp']['stop']),
                        status='FINISHED'
                    )
                    backup_history.setdefault(pgb.label, pgb)
                    backup_history[pgb.label].pgbackrest_info.update(b)
        # This thread should keep running, as it only triggers backups. Therefore we catch
        # all errors and log them, but The Thread Must Go On
        except Exception as e:
            logging.exception(e)
        finally:
            history_trigger.clear()

    logging.warning('Shutting down thread')


def main(args):
    """This is the core program

    To aid in testing this, we expect args to be a dictionary with already parsed options"""
    global stanza

    logging.basicConfig(format='%(asctime)s - %(levelname)s - %(threadName)s - %(message)s', level=LOGLEVELS[args['loglevel'].lower()])
    stanza = args['stanza']

    shutdown_trigger = Event()
    backup_trigger = Event()
    history_trigger = Event()

    backup_thread = Thread(target=backup_poller, args=(backup_trigger, history_trigger, shutdown_trigger), name='backup')
    history_thread = Thread(target=history_refresher, name='history', args=(history_trigger, shutdown_trigger, 3600))

    server_address = ('', args['port'])
    httpd = EventHTTPServer(backup_trigger, server_address, RequestHandler)
    httpd_thread = Thread(target=httpd.serve_forever, name='http')

    # For cleanup, we will trigger all events when signaled, all the threads
    # will investigate the shutdown trigger before acting on their individual
    # triggers
    def sigterm_handler(_signo, _stack_frame):
        logging.warning('Received kill {0}, shutting down'.format(_signo))
        shutdown_trigger.set()
        backup_trigger.set()
        history_trigger.set()
        httpd.shutdown()

        while backup_thread.is_alive() or history_thread.is_alive() or httpd_thread.is_alive():
            time.sleep(1)

    signal.signal(signal.SIGINT, sigterm_handler)
    signal.signal(signal.SIGTERM, sigterm_handler)

    backup_thread.start()
    history_trigger.set()
    history_thread.start()
    httpd_thread.start()


if __name__ == '__main__':
    main(vars(parse_arguments(sys.argv[1:])))
