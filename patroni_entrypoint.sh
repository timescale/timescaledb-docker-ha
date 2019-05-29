#!/bin/bash

function log {
	echo "$(date '+%Y-%m-%d %H:%M:%S') - bootstrap - $1"
}

# pgBackRest container
[ "${K8S_SIDECAR}" == "pgbackrest" ] && (
	REPOPATH="$(dirname "${PGBACKREST_CONFIG}")/repository"
	mkdir -p "${REPOPATH}"

	# The pgBackRest configuration needs to be shared by all containers in the pod
	# at some point in the future we may fetch it from an s3-bucket or some environment configuration,
	# however, for now we store the file in a mounted volume that is accessible to all pods.
	cat > "${PGBACKREST_CONFIG}" <<__EOT__
[global]
repo-path=${REPOPATH}

[poddb]
pg1-port=5432
pg1-host-user=${POSTGRES_USER}
pg1-path=${PGDATA}
pg1-socket-path=${PGSOCKET}

repo1-retention-full=2
__EOT__

	chmod 0600 "${PGBACKREST_CONFIG}"

	while ! pg_isready -h "${PGSOCKET}" -q
	do
		log "waiting for postgresql to become available"
		sleep 1
	done

) && exec python3 /scripts/pgbackrest-rest.py --stanza=poddb



python3 /scripts/configure_spilo.py patroni patronictl certificate

exec patroni /home/postgres/postgres.yml

