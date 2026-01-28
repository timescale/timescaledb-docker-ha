#!/bin/bash

set -e

SCRIPTDIR="$(dirname "$0")"

# import the image configuration so we get PG_MAJOR for conditionally checking against pg18
. /.image_config
echo
echo " ** /.image_config:"
cat /.image_config
echo

initdb

SHARED_PRELOAD_LIBRARIES="timescaledb"
EXTENSION_DIR="$(pg_config --sharedir)/extension"

echo "shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'" >>"${PGDATA}/postgresql.conf"

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
    name IN ('timescaledb_toolkit')
ORDER BY
    name
\gexec

__SQL__

psql -AtXq -f "${SCRIPTDIR}/version_info.sql" >/tmp/version_info.log
pg_ctl stop -m immediate
exit 0
