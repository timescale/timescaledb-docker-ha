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
