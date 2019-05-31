#!/bin/bash

function log {
	echo "$(date '+%Y-%m-%d %H:%M:%S') - bootstrap - $1"
}

# Making sure the data directory exists and has the right permission
install -m 0700 -d "${PGDATA}"

# pgBackRest container
[ "${K8S_SIDECAR}" == "pgbackrest" ] && (
	# The pgBackRest configuration needs to be shared by all containers in the pod
	# at some point in the future we may fetch it from an s3-bucket or some environment configuration,
	# however, for now we store the file in a mounted volume that is accessible to all pods.
	mkdir -p "$(dirname "${PGBACKREST_CONFIG}")"
	cat > "${PGBACKREST_CONFIG}" <<__EOT__
[global]
process-max=4

repo1-type=s3
repo1-path=${PGB_REPO1_PATH}
repo1-cipher-type=none
repo1-retention-diff=2
repo1-retention-full=2
repo1-s3-bucket=${PGB_REPO1_S3_BUCKET}
repo1-s3-endpoint=s3.amazonaws.com
repo1-s3-key=${PGB_REPO1_S3_KEY}
repo1-s3-key-secret=${PGB_REPO1_S3_KEY_SECRET}
repo1-s3-region=us-east-2
start-fast=y


[poddb]
pg1-port=5432
pg1-host-user=${POSTGRES_USER:-postgres}
pg1-path=${PGDATA}
pg1-socket-path=${PGSOCKET}

recovery-option=standby_mode=on
recovery-option=recovery_target_timeline=latest
recovery-option=recovery_target_action=shutdown


[global:archive-push]
compress-level=3
__EOT__

	echo "$(date '+%Y-%m-%d %H:%M:%S') - init - prepared pgBackRest configuration"

) && exec python3 /scripts/pgbackrest-rest.py --stanza=poddb --loglevel=debug

python3 /scripts/configure_spilo.py patroni patronictl certificate

# The current postgres-operator does not pass on all the variables set by the Custom Resource.
# We need a bit of extra work to be done
# Issue: https://github.com/zalando/postgres-operator/issues/574
python3 /scripts/augment_patroni_configuration.py /home/postgres/postgres.yml

exec patroni /home/postgres/postgres.yml

