#!/bin/bash

set -e

SCRIPTDIR="$(dirname "$0")"

initdb

SHARED_PRELOAD_LIBRARIES="timescaledb"
EXTENSION_DIR="$(pg_config --sharedir)/extension"

echo "shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'" >> "${PGDATA}/postgresql.conf"
pg_ctl start

while ! pg_isready; do
    sleep 0.2
done

psql -d postgres -f - <<__SQL__
ALTER SYSTEM set log_statement to 'all';
SELECT pg_reload_conf();

CREATE EXTENSION timescaledb;

\set ECHO queries
SELECT
    format('CREATE EXTENSION IF NOT EXISTS %I CASCADE', name)
FROM
    pg_catalog.pg_available_extensions
WHERE
    name IN ('timescaledb_toolkit', 'postgis')
ORDER BY
    name
\gexec

__SQL__

psql -AtXq -f "${SCRIPTDIR}/version_info.sql" > /tmp/version_info.log
pg_ctl stop -m immediate
exit 0
