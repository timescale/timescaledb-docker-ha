#!/bin/bash

set -e
BUILDDIR="$(pwd)"
SCRIPTDIR="$(dirname "${0}")"

if [ -z "${TS_VERSIONS}" ]; then
    echo "Please ensure all TimescaleDB versions are listed in the TS_VERSIONS environment variable"
    exit 1
fi

if [ -z "${PG_VERSIONS}" ]; then
    echo "Please ensure all PostgreSQL major versions are listed in the PG_VERSIONS environment variable"
    exit 1
fi

clone_if_required() {
    if [ ! -d "${BUILDDIR}/.git" ]; then
        if [ "${GITHUB_TOKEN}" != "" ]; then
            git clone "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}" "${BUILDDIR}"
        else
            git clone "https://github.com/${GITHUB_REPO}" "${BUILDDIR}"
        fi
    fi
}

for pg in ${PG_VERSIONS}; do
    for ts in ${TS_VERSIONS}; do
        if [ "${pg}" -ge 13 ] && [[ "${ts}" =~ ^1\.* ]]; then echo "Skipping: TimescaleDB ${ts} is not supported on PostgreSQL ${pg}" && continue; fi
        if [ "${pg}" -ge 13 ] && [[ "${ts}" =~ ^2\.0\.* ]]; then echo "Skipping: TimescaleDB ${ts} is not supported on PostgreSQL ${pg}" && continue; fi
        if [ "${pg}" -ge 12 ] && [[ "${ts}" =~ ^1\.6\.* ]]; then echo "Skipping: TimescaleDB ${ts} is not supported on PostgreSQL ${pg}" && continue; fi
        if [ "${pg}" -lt 12 ] && [[ "${ts}" =~ ^2\.4\.* ]]; then echo "Skipping: TimescaleDB ${ts} is not supported on PostgreSQL ${pg}" && continue; fi

        if "${SCRIPTDIR}/try_hot_forge.sh" "${pg}" timescaledb "${ts}"; then
            continue
        fi

        clone_if_required
        cd "${BUILDDIR}"
        git reset HEAD --hard
        git clean -f -d -x
        git checkout "${ts}"
        rm -rf build
        if [ "${ts}" = "2.2.0" ]; then sed -i 's/RelWithDebugInfo/RelWithDebInfo/g' CMakeLists.txt; fi
        PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" ./bootstrap \
            -DTAP_CHECKS=OFF \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DREGRESS_CHECKS=OFF \
            -DGENERATE_DOWNGRADE_SCRIPT=ON \
            -DPROJECT_INSTALL_METHOD="${INSTALL_METHOD}${OSS_ONLY}"
        cd build
        make -j 6 install
    done
done
