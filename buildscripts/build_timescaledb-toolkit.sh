#!/bin/bash

set -e
BUILDDIR="$(pwd)"
SCRIPTDIR="$(dirname "${0}")"

if [ -z "${TIMESCALEDB_TOOLKIT_EXTENSION}" ]; then
    echo "Please ensure TIMESCALEDB_TOOLKIT_EXTENSION envvar is set"
    exit 1
fi

# build and install the promscale_extension extension
for pg in ${PG_VERSIONS}; do
    if [ "${pg}" -ge "12" ]; then
        export PATH="/usr/lib/postgresql/${pg}/bin:${PATH}";

        for tookit in ${TIMESCALEDB_TOOLKIT_EXTENSION_PREVIOUS} ${TIMESCALEDB_TOOLKIT_EXTENSION}; do
            cd "${BUILDDIR}"

            if "${SCRIPTDIR}/try_hot_forge.sh" "${pg}" timescaledb-toolkit "${tookit}"; then
                continue
            fi

            cargo install --git https://github.com/JLockerman/pgx.git --branch timescale cargo-pgx
            [ -d "${BUILDDIR}/.git" ] || git clone https://github.com/timescale/timescaledb-toolkit "${BUILDDIR}"
            cargo pgx init "--pg${pg}" "/usr/lib/postgresql/${pg}/bin/pg_config"

            echo "building toolkit version ${tookit} for pg${pg}"
            git reset HEAD --hard
            git checkout "${tookit}"
            git clean -f -x
            cd extension && cargo pgx install --release
            cargo run --manifest-path ../tools/post-install/Cargo.toml -- "/usr/lib/postgresql/${pg}/bin/pg_config"
        done
    fi
done
