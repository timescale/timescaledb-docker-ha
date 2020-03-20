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

if [ -f "${PGDATA}/postmaster.pid" ]; then
    # the postmaster will refuse to start if the pid of the pidfile is currently
    # in use by the same OS user. This protection mechanism however is not strict
    # enough in a container environment, as we only have the pids in our own namespace.
    # The Volume containing the data directory could accidentally be mounted
    # inside multiple containers, so relying on visibility of the pid is not enough.
    #
    # There is only 1 way for us to communicate to the other postmaster (in another container?)
    # on the same $PGDATA: by removing the pidfile.
    #
    # The other postmaster will shutdown immediately as soon as it determines that its
    # pidfile has been removed. This is a Very Good Thing: it prevents multiple postmasters
    # on the same directory, even in a container environment.
    # See also https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=7e2a18)
    #
    # The downside of this change is that it will delay the startup of a crashed container;
    # as we're dealing with data, we'll choose correctness over uptime in this instance.
    log "Removing stale pidfile ..."
    rm "${PGDATA}/postmaster.pid"
    log "Sleeping a little to ensure no other postmaster is running anymore"
    sleep 65
fi

exec patroni /home/postgres/postgres.yml
