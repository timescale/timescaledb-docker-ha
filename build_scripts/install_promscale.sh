#!/bin/sh
# This script was created to reduce the complexity of the RUN command
# that installs all combinations of PostgreSQL and TimescaleDB Toolkit

if [ -z "$1" ]; then
    echo "Usage: $0 [PROMSCALE_TAG..]" 
    exit 1
fi

set -e

mkdir -p /home/postgres/.pgx

for PROMSCALE_VERSION in "$@"; do
    git clean -e target -f -x
    git reset HEAD --hard
    git checkout "${PROMSCALE_VERSION}"


    MAJOR_MINOR="$(awk '/^version/ {print $3}' ./Cargo.toml | tr -d "\"" | cut -d. -f1,2)"
    MAJOR="$(echo "${MAJOR_MINOR}" | cut -d. -f1)"
    MINOR="$(echo "${MAJOR_MINOR}" | cut -d. -f2)"

    for pg in ${PG_VERSIONS}; do
        export PATH="/usr/lib/postgresql/${pg}/bin:${PATH}"

        if [ "${MAJOR}" -le 0 ] && [ "${MINOR}" -le 3 ]; then
            cargo install cargo-pgx --version '^0.2'
        else
            cargo install cargo-pgx --git https://github.com/timescale/pgx --branch promscale-staging
        fi
        cargo pgx init "--pg${pg}" "/usr/lib/postgresql/${pg}/bin/pg_config"
        if [ "${MAJOR}" -le 0 ] && [ "${MINOR}" -le 3 ]; then
            PG_VER=pg${pg} make install || exit 1;
        elif [ "${PROMSCALE_VERSION}" = "0.5.1" ]; then
            make package && cp -v --recursive "./target/release/promscale-pg${pg}/"* / || exit 1
        else
            (make package && make install) || exit 1;
        fi
    done
done
