#!/bin/bash

function log {
	echo "$(date '+%Y-%m-%d %H:%M:%S') - bootstrap - $1"
}

# Making sure the data directory exists and has the right permission
install -m 0700 -d "${PGDATA}"

# pgBackRest container
[ "${K8S_SIDECAR}" == "pgbackrest" ] && exec /pgbackrest_entrypoint.sh

# Spilo is the original Docker image containing Patroni. The image uses
# some scripts to convert a SPILO_CONFIGURATION into a configuration for Patroni.
# At some point, we want to probably get rid of this script and do all this ourselves.
# For now, if the environment variable is set, we consider that a feature flag to use
# the original Spilo configuration script
[ ! -z "${SPILO_CONFIGURATION}" ] && {
    python3 /scripts/configure_spilo.py patroni patronictl certificate

    # The current postgres-operator does not pass on all the variables set by the Custom Resource.
    # We need a bit of extra work to be done
    # Issue: https://github.com/zalando/postgres-operator/issues/574
    python3 /scripts/augment_patroni_configuration.py /home/postgres/postgres.yml
}

exec patroni /home/postgres/postgres.yml
