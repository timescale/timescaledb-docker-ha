#!/usr/bin/python3

"""
This is a hack to get around Issue: https://github.com/zalando/postgres-operator/issues/574
"""


import yaml
import sys


def inject_pgbackrest_configuration(filename):
    with open(filename, 'r+') as f:
        pgconfig = yaml.safe_load(f)
        pgconfig['postgresql']['create_replica_methods'] = ['pgbackrest', 'basebackup']
        pgconfig['postgresql']['pgbackrest'] = {
            'command': '/usr/bin/pgbackrest --stanza=poddb --delta restore --log-level-stderr=info',
            'keep_data': True,
            'no_params': True
        }

        pgconfig['bootstrap']['dcs'].setdefault('postgresql', {})
        pgconfig['bootstrap']['dcs']['postgresql']['recovery_conf'] = {
            'recovery_target_timeline': 'latest',
            'standby_mode': 'on',
            'restore_command': 'pgbackrest --stanza=demo archive-get %f "%p"',
        }

        f.seek(0)
        yaml.dump(pgconfig, f, default_flow_style=False)
        f.truncate()


if __name__ == '__main__':
    inject_pgbackrest_configuration(sys.argv[1])
