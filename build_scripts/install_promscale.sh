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

INSTALLED=false
for PROMSCALE_VERSION in "$@"; do
    DEBVERSION="$(apt info -a promscale-extension-postgresql-${PGVERSION} | awk '/Version:/ {print $2}' | grep "${PROMSCALE_VERSION}" | head -n 1)"
    if apt-get download promscale-extension-postgresql-${PGVERSION}=${DEBVERSION}; then
        mkdir /tmp/dpkg
        dpkg --install --admindir /tmp/dpkg --force-depends --force-not-root --force-overwrite promscale-extension-postgresql-${PGVERSION}*${DEBVERSION}*.deb
        rm -rf /tmp/dpkg
        INSTALLED=true
    else
        echo "couldn't find promscale-extension version $PROMSCALE_VERSION for pg$PGVERSION"
    fi
done

if [ "$INSTALLED" = false ]; then
    echo "No promscale versions installed!"
    exit 1
fi
