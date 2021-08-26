#!/bin/bash

set -e
BUILDDIR="$(pwd)"
SCRIPTDIR="$(dirname "${0}")"

if [ -z "${TIMESCALE_PROMSCALE_EXTENSION}" ]; then
    echo "Please ensure TIMESCALE_PROMSCALE_EXTENSION envvar is set"
    exit 1
fi

if [ -z "${PG_VERSIONS}" ]; then
    echo "Please ensure all PostgreSQL major versions are listed in the PG_VERSIONS environment variable"
    exit 1
fi

# build and install the promscale_extension extension
for pg in ${PG_VERSIONS}; do
    if [ "${pg}" -ge "12" ]; then
        if "${SCRIPTDIR}/try_hot_forge.sh" "${pg}" promscale_extension "${TIMESCALE_PROMSCALE_EXTENSION}"; then
            continue
        fi

        cargo install --git https://github.com/JLockerman/pgx.git --branch timescale cargo-pgx
        [ -d "${BUILDDIR}/.git" ] || git clone https://github.com/timescale/promscale_extension "${BUILDDIR}"
        export PATH="/usr/lib/postgresql/${pg}/bin:${PATH}";
        cargo pgx init "--pg${pg}" "/usr/lib/postgresql/${pg}/bin/pg_config"
        cd "${BUILDDIR}" && git reset HEAD --hard && git checkout "${TIMESCALE_PROMSCALE_EXTENSION}"
        git clean -f -x
        PG_VER="pg${pg}" make install
    fi
done
