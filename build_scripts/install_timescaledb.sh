#!/bin/sh
# This script was created to reduce the complexity of the RUN command
# that installs all combinations of PostgreSQL and TimescaleDB

set -e

if [ -z "$2" ]; then
    echo "Usage: $0 PGVERSION [TSVERSION..]"
    exit 1
fi

PGVERSION="$1"
shift

export PATH="/usr/lib/postgresql/${PGVERSION}/bin:${PATH}"

is_supported() {
    MAJOR="$(echo "$1" | cut -d. -f1)"
    MINOR="$(echo "$1" | cut -d. -f2)"
    if [ "${PGVERSION}" -ge 13 ] && [ "${MAJOR}" -eq 1 ]; then return 1; fi
    if [ "${PGVERSION}" -lt 12 ] && [ "${MINOR}" -ge 4 ]; then return 1; fi
    if [ "${PGVERSION}" -ge 14 ] && [ "${MINOR}" -lt 5 ]; then return 1; fi
    if [ "${PGVERSION}" -ge 13 ] && [ "${MINOR}" -lt 1 ]; then return 1; fi
    return 0
}

for TAG in "$@"; do
    git reset HEAD --hard
    git checkout "${TAG}"
    git clean -f -d -x

    MAJOR_MINOR="$(awk '/^version/ {print $3}' version.config | cut -d. -f1,2)"

    if [ "${TAG}" = "2.2.0" ]; then sed -i 's/RelWithDebugInfo/RelWithDebInfo/g' CMakeLists.txt; fi

    if is_supported "${MAJOR_MINOR}"; then
        ./bootstrap \
            -DTAP_CHECKS=OFF \
            -DWARNINGS_AS_ERRORS=off \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DREGRESS_CHECKS=OFF \
            -DGENERATE_DOWNGRADE_SCRIPT=ON \
            -DPROJECT_INSTALL_METHOD="${INSTALL_METHOD}${OSS_ONLY}"
        cd build
        make install
        cd ..
    else
        echo "TimescaleDB ${TAG} is not supported on PostgreSQL ${PGVERSION}"
    fi
done
