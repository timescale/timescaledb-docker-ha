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
if [ "${PG_MAJOR}" -ge 17 ] 2>/dev/null; then
    SHARED_PRELOAD_LIBRARIES="${SHARED_PRELOAD_LIBRARIES},pg_textsearch"
fi
EXTENSION_DIR="$(pg_config --sharedir)/extension"

echo "shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'" >>"${PGDATA}/postgresql.conf"

pg_ctl start

# Bounded on purpose: an unbounded wait turns "the server never came up" into a
# silent hang until the surrounding container is reaped, which then surfaces as
# an unrelated docker error instead of the actual failure.
ready=false
for _ in $(seq 1 150); do
	if pg_isready -q; then ready=true; break; fi
	sleep 0.2
done

if [ "${ready}" != true ]; then
	echo "smoketest: server did not accept connections within 30s" >&2
	pg_isready >&2 || true
	ls -la /var/run/postgresql/ >&2 || true
	pg_ctl status >&2 || true
	exit 1
fi

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

psql -AtXq -f "${SCRIPTDIR}/version_info.sql" >/tmp/version_info.log
pg_ctl stop -m immediate
exit 0
