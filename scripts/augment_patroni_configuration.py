#!/usr/bin/python3

"""
This is a hack to get around Issue: https://github.com/zalando/postgres-operator/issues/574

This script will be deprecated as soon as we configure Patroni fully from k8s. Until that time
the configure_spilo.py script is used, with its valuable output and its quirks.
"""
import yaml
import os
import sys

TSDB_DEFAULTS = """
postgresql:
  parameters:
    logging_collector: 'off'
    log_destination: 'stderr'
  create_replica_methods:
  - pgbackrest
  - basebackup
  pgbackrest:
    command: '/usr/bin/pgbackrest --stanza=poddb --delta restore --log-level-stderr=info'
    keep_data: True
    no_params: True
    no_master: True
bootstrap:
  dcs:
    postgresql:
      recovery_conf:
        recovery_target_timeline: latest
        standby_mode: 'on'
        restore_command: 'pgbackrest --stanza=poddb archive-get %f "%p"'
"""


def merge(source, destination):
    """Merge source into destination.

    Values from source override those of destination"""
    for key, value in source.items():
        if isinstance(value, dict):
            # get node or create one
            node = destination.setdefault(key, {})
            merge(value, node)
        else:
            destination[key] = value

    return destination


if __name__ == '__main__':
    if len(sys.argv) == 1:
        print("Usage: {0} <patroni.yaml>".format(sys.argv[0]))
        sys.exit(2)
    with open(sys.argv[1], 'r+') as f:
        # Not all postgresql parameters that are set in the SPILO_CONFIGURATION environment variables
        # are overridden by the configure_spilo.py script.
        #
        # Therefore, what we do is:
        #
        # 1. We run configure_spilo.py to generate a sane configuration
        # 2. We override that configuration with our sane TSDB_DEFAULTS
        # 3. We override that configuration with our explicitly passed on settings

        tsdb_defaults = yaml.safe_load(TSDB_DEFAULTS) or {}
        spilo_generated_configuration = yaml.safe_load(f) or {}
        operator_generated_configuration = yaml.safe_load(os.environ.get('SPILO_CONFIGURATION', '{}')) or {}

        final_configuration = merge(operator_generated_configuration, merge(tsdb_defaults, spilo_generated_configuration))

        # This namespace used in etcd/consul
        # Other provisions are also available, but this ensures no naming collisions
        # for deployments in separate Kubernetes Namespaces will occur
        # https://github.com/zalando/patroni/blob/master/docs/ENVIRONMENT.rst#globaluniversal
        if 'etcd' in final_configuration and os.getenv('POD_NAMESPACE'):
            final_configuration['namespace'] = os.getenv('POD_NAMESPACE')

        f.seek(0)
        yaml.dump(final_configuration, f, default_flow_style=False)
        f.truncate()
