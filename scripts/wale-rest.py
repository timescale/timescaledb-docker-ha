#!/usr/bin/python

from flask import Flask, request
from subprocess import Popen
import sys
import logging
import logging.config
import os
from logging.config import dictConfig

API_PORT = int(os.getenv('WALE_LISTEN_PORT', '5000'))
PGDATA = os.getenv('PGDATA', '/var/lib/postgresql/data')
PGWAL = os.getenv('PGWAL', PGDATA + '/pg_wal')
WALE_BIN = os.getenv('WALE_BIN', '/usr/local/bin/wal-e')
WALE_FLAGS = os.getenv('WALE_FLAGS', '--terse')
WALE_PUSH_FLAGS = os.getenv('WALE_PUSH_FLAGS', '')
WALE_FETCH_FLAGS = os.getenv('WALE_FETCH_FLAGS', '-p=0')


class WaleWrapper:

    api = None

    def __init__(self):

        self.api = Flask('RestAPI')

        log_conf = {
            'version': 1,
            'handlers': {
                'console': {
                    'class': 'logging.StreamHandler',
                    'stream': sys.stdout,
                }
            },
            'root': {
                'handlers': ['console'],
                'level': 'INFO'
            }
        }

        logging.config.dictConfig(log_conf)
        logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)

        # create routes
        self.api.add_url_rule('/ping', view_func=self.ping, methods=['GET'])
        self.api.add_url_rule('/wal-push/<path:path>', view_func=self.push, methods=['GET'])
        self.api.add_url_rule('/wal-fetch/<path:path>', view_func=self.fetch, methods=['GET'])

        self.api.logger.info('Ready to receive wal-e commands')

        # start API
        self.api.run(host='0.0.0.0', port=API_PORT, debug=False)

    def perform_command(self, cmd, log_line, error_line, return_line):

        self.api.logger.info('{}: {}'.format(log_line, cmd))

        p = Popen(cmd)
        outs, errs = p.communicate()

        if p.returncode != 0:
            self.api.logger.error(error_line + ': ' + str(errs))
            return errs, 500

        return return_line

    def push(self, path):

        if '/' in path:
            path = path.split('/')[-1]

        file_path = PGWAL + '/' + path

        command = [WALE_BIN]
        if len(WALE_FLAGS) > 0:
            for s in WALE_FLAGS.split():
                command.append(s)
        command.append('wal-push')
        if len(WALE_PUSH_FLAGS) > 0:
            for s in WALE_PUSH_FLAGS.split():
                command.append(s)
        command.extend([file_path])
        print(command)

        return self.perform_command(command,
                                    'Pushing wal file {}'.format(file_path),
                                    'Failed to push wal {}'.format(file_path),
                                    'Pushed wal {}'.format(file_path))

    def fetch(self, path):

        if '/' in path:
            path = path.split('/')[-1]

        file_id = path

        file_path  = PGWAL + '/' + file_id

        command = [WALE_BIN]
        if len(WALE_FLAGS) > 0:
            for s in WALE_FLAGS.split():
                command.append(s)
        command.append('wal-fetch')
        if len(WALE_FETCH_FLAGS) > 0:
            for s in WALE_FETCH_FLAGS.split():
                command.append(s)
        command.extend([file_id, file_path])
        print(command)

        return self.perform_command(command,
                                    'Fetching wal {}'.format(file_id),
                                    'Failed to fetch wal {}'.format(file_id),
                                    'Fetched wal {}'.format(file_id))

    def ping(self):
        return 'pong'


if __name__ == '__main__':
    _ = WaleWrapper()
