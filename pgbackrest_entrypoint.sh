#!/bin/bash

function log {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - bootstrap - $1"
}

[ -z "${PGB_REPO1_S3_KEY_SECRET}" ] && {
    log "Environment variable PGB_REPO1_S3_KEY_SECRET is not set, you should fully configure this container"
    exit 1
}

# The pgBackRest configuration needs to be shared by all containers in the pod
# at some point in the future we may fetch it from an s3-bucket or some environment configuration,
# however, for now we store the file in a mounted volume that is accessible to all pods.
umask 0077
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

while ! pg_isready -h "${PGSOCKET}" -q; do
    log "Waiting for PostgreSQL to become available"
    sleep 3
done

pgbackrest check || {
    log "Creating pgBackrest stanza"
    pgbackrest stanza-create --log-level-stderr=info || exit 1
}

log "Starting pgBackrest api to listen for backup requests"
exec python3 /scripts/pgbackrest-rest.py --stanza=poddb --loglevel=debug
