#!/usr/bin/python

from flask import Flask, request
from subprocess import Popen
import sys
import logging
import logging.config
import os
from logging.config import dictConfig

API_PORT = int(os.getenv('WALE_LISTEN_PORT', '5000'))
WAL_PATH = os.getenv('WAL_PATH', '/data/wal/pgwal/')
WALE_BIN = os.getenv('WALE_BIN', '/usr/local/bin/wal-e')
WALE_PUSH_FLAGS = os.getenv('WALE_PUSH_FLAGS', '--terse')
WALE_FETCH_FLAGS = os.getenv('WALE_FETCH_FLAGS', '')
CLUSTER_PATH = os.getenv('CLUSTER_PATH', '')


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
        self.api.add_url_rule('/push/<path:path>', view_func=self.push, methods=['GET'])
        self.api.add_url_rule('/fetch/<path:path>', view_func=self.fetch, methods=['GET'])

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

        file_path = WAL_PATH + path

        if len(WALE_PUSH_FLAGS) > 0:
            command = [WALE_BIN, WALE_PUSH_FLAGS, 'wal-push', file_path]
        else:
            command = [WALE_BIN, 'wal-push', file_path]

        return self.perform_command(command,
                                    'Pushing wal file {}'.format(file_path),
                                    'Failed to push wal {}'.format(file_path),
                                    'Pushed wal {}'.format(file_path))

    def fetch(self, path):

        if '/' in path:
            path = path.split('/')[-1]

        file_id = path

        file_path  = WAL_PATH + '/' + file_id
        if WALE_FETCH_FLAGS != '':
            command = [WALE_BIN, WALE_FETCH_FLAGS, 'wal-fetch', file_id, file_path]
        else:
            command = [WALE_BIN, 'wal-fetch', file_id, file_path]

        return self.perform_command(command,
                                    'Fetching wal {}'.format(file_id),
                                    'Failed to fetch wal {}'.format(file_id),
                                    'Fetched wal {}'.format(file_id))

if __name__ == '__main__':
    _ = WaleWrapper()
