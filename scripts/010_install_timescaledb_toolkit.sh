#!/bin/bash

. /.image_config

create_sql=$(mktemp)

# Checks to support bitnami image with same scripts so they stay in sync
if [ -n "${BITNAMI_IMAGE_VERSION:-}" ]; then
	if [ -z "${POSTGRES_USER:-}" ]; then
		POSTGRES_USER=${POSTGRESQL_USERNAME}
	fi

	if [ -z "${POSTGRES_DB:-}" ]; then
		POSTGRES_DB=${POSTGRESQL_DATABASE}
	fi

	if [ -z "${PGDATA:-}" ]; then
		PGDATA=${POSTGRESQL_DATA_DIR}
	fi
fi

if [ -z "${POSTGRESQL_CONF_DIR:-}" ]; then
	POSTGRESQL_CONF_DIR=${PGDATA}
fi

# OSS images do not ship timescaledb_toolkit, so only create it when available
cat <<EOF >"${create_sql}"
SELECT 'CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit CASCADE'
FROM pg_catalog.pg_available_extensions
WHERE name = 'timescaledb_toolkit'
\gexec
EOF

# create extension timescaledb_toolkit in initial databases
psql -U "${POSTGRES_USER}" postgres -f "${create_sql}"
psql -U "${POSTGRES_USER}" template1 -f "${create_sql}"

if [ "${POSTGRES_DB:-postgres}" != 'postgres' ]; then
	psql -U "${POSTGRES_USER}" "${POSTGRES_DB}" -f "${create_sql}"
fi
