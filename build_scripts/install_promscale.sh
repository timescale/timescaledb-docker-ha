#!/bin/sh
# This script was created to reduce the complexity of the RUN command
# that installs all combinations of PostgreSQL and TimescaleDB Toolkit

if [ -z "$2" ]; then
    echo "Usage: $0 PGVERSION [PROMSCALE_TAG..]"
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

for PROMSCALE_VERSION in "$@"; do
    git clean -e target -f -x
    git reset HEAD --hard
    git checkout "${PROMSCALE_VERSION}"

    MAJOR_MINOR_PATCH="$(awk '/^version/ {print $3}' ./Cargo.toml | tr -d "\"" | cut -d. -f1,2,3)"
    MAJOR="$(echo "${MAJOR_MINOR_PATCH}" | cut -d. -f1)"
    MINOR="$(echo "${MAJOR_MINOR_PATCH}" | cut -d. -f2)"
    PATCH="$(echo "${MAJOR_MINOR_PATCH}" | cut -d. -f3)"

    if [ "${MAJOR}" -le 0 ] && [ "${MINOR}" -le 3 ]; then
        cargo install cargo-pgx --version '^0.2'
    else
        cargo install cargo-pgx --git https://github.com/timescale/pgx --branch promscale-staging
    fi
    cargo pgx init --pg${PGVERSION} /usr/lib/postgresql/${PGVERSION}/bin/pg_config
    if [ "${MAJOR}" -le 0 ] && [ "${MINOR}" -le 3 ]; then
        PG_VER=pg${PGVERSION} make install || exit 1;
    elif [ "${MAJOR}" -le 0 ] && [ "${MINOR}" -le 5 ] && [ "${PATCH}" -le 0 ]; then
        (make package && make install) || exit 1;
    else
        make
        chown -R root:postgres ./target/release/promscale-pg${PGVERSION}
        cp ./target/release/promscale-pg${PGVERSION}/usr/share/postgresql/${PGVERSION}/extension/* /usr/share/postgresql/${PGVERSION}/extension/
        cp ./target/release/promscale-pg${PGVERSION}/usr/lib/postgresql/${PGVERSION}/lib/* /usr/lib/postgresql/${PGVERSION}/lib/
    fi
done
