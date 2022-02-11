#!/bin/sh
# This script was created to reduce the complexity of the RUN command
# that installs all combinations of PostgreSQL and TimescaleDB Toolkit

if [ -z "$2" ]; then
    echo "Usage: $0 PGVERSION [TOOLKIT_TAG..]"
    exit 1
fi

PGVERSION="$1"
shift

if [ "${PGVERSION}" -lt 12 ]; then
    exit 0
fi

set -e

export PATH="/usr/lib/postgresql/${PGVERSION}/bin:${PATH}"
mkdir -p /home/postgres/.pgx

for TOOLKIT_VERSION in "$@"; do
    git clean -e target -f -x
    git reset HEAD --hard
    git checkout "${TOOLKIT_VERSION}"

    MAJOR_MINOR="$(awk '/^default_version/ {print $3}' ../timescaledb-toolkit/extension/timescaledb_toolkit.control | tr -d "'" | cut -d. -f1,2)"
    MAJOR="$(echo "${MAJOR_MINOR}" | cut -d. -f1)"
    MINOR="$(echo "${MAJOR_MINOR}" | cut -d. -f2)"
    if [ "${MAJOR}" -ge 1 ] && [ "${MINOR}" -ge 4 ]; then
        cargo install cargo-pgx --version '^0.2'
    else
        if [ "${PGVERSION}" -ge 14 ]; then
            echo "TimescaleDB Toolkit ${TOOLKIT_VERSION} is not supported on PostgreSQL ${PGVERSION}"
            continue;
        fi
        cargo install --git https://github.com/JLockerman/pgx.git --branch timescale cargo-pgx
    fi
    cat > /home/postgres/.pgx/config.toml <<__EOT__
[configs]
pg${PGVERSION} = "/usr/lib/postgresql/${PGVERSION}/bin/pg_config"
__EOT__
    cd extension
    cargo pgx install --release
    cargo run --manifest-path ../tools/post-install/Cargo.toml -- "/usr/lib/postgresql/${PGVERSION}/bin/pg_config"

    cd ..
done


## Sanity patches

# When installing the extension, no objects should yet exist, it would be an error if they do exist.
# The grep -v removes all the *upgrade* scripts (timescaledb_toolkit--from--to.sql) from the list, as we only
# want to do this for the *install* scripts.
for file in $(ls "/usr/share/postgresql/${PGVERSION}/extension/timescaledb_toolkit--"*.sql | grep -v -- '--.*--'); do
    sed -i 's/CREATE OR REPLACE/CREATE/gI' "${file}"
done

# The schema's being used should not yet exist, we only update the *first* occurence of
# CREATE SCHEMA IF NOT EXISTS as rust pgx generates multiple CREATE SCHEMA IF NOT EXISTS statements, which would
# fail if we would update them all.
sed -i '0,/CREATE SCHEMA IF NOT EXISTS/s//CREATE SCHEMA/' "/usr/share/postgresql/${PGVERSION}/extension/timescaledb_toolkit--"*.sql

# For all the *update* scripts only we add a sanity check for the trigger functions belonging
# to the extension
for update_file in "/usr/share/postgresql/${PGVERSION}/extension/"timescaledb_toolkit--*--*.sql; do
    cat > "${update_file}.tmp" <<__SQL__
DO LANGUAGE plpgsql
$$
DECLARE
fn_name  text;
fn_owner text;
BEGIN
SELECT
    oid::regproc::text,
    proowner::regrole::text
INTO
    fn_name,
    fn_owner
FROMc
    pg_proc
WHERE
    oid in ('disallow_experimental_view_dependencies'::regproc, 'disallow_experimental_dependencies'::regproc)
    AND proowner != current_user::regrole
LIMIT
    1;

IF FOUND
THEN
    RAISE EXCEPTION 'Function % is owned by %, which blocks an upgrade of timescaledb_toolkit', fn_name, fn_owner
        USING HINT = 'Please, drop the function before upgrading timescaledb_toolkit';
END IF;
END;
$$;
__SQL__

    cat "${update_file}" >> "${update_file}.tmp"
    mv "${update_file}.tmp" "${update_file}"
done
