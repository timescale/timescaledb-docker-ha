#!/usr/bin/python3

"""
This is a hack to get around Issue: https://github.com/zalando/postgres-operator/issues/574
"""


import yaml
import os
import sys


def inject_pgbackrest_configuration(pgconfig):
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


if __name__ == '__main__':
    with open(sys.argv[1], 'r+') as f:
        pgconfig = yaml.safe_load(f)
        inject_pgbackrest_configuration(pgconfig)

        # This namespace used in etcd/consul
        # Other provisions are also available, but this ensures no naming collisions
        # for deployments in separate Kubernetes Namespaces will occur
        # https://github.com/zalando/patroni/blob/master/docs/ENVIRONMENT.rst#globaluniversal
        if 'etcd' in pgconfig and os.getenv('POD_NAMESPACE'):
            pgconfig['namespace'] = os.getenv('POD_NAMESPACE')

        f.seek(0)
        yaml.dump(pgconfig, f, default_flow_style=False)
        f.truncate()
