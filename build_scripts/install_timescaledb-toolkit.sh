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
    # The packages aren't named totally consistent, therefore we ask - using apt info -
    # to describe all the versions that are there, which we then pattern match.
    DEBVERSION="$(apt info -a timescaledb-toolkit-postgresql-${PGVERSION} | awk '/Version:/ {print $2}' | grep "${TOOLKIT_VERSION}" | grep -v forge | head -n 1)"
    mkdir /tmp/dpkg
    apt-get download timescaledb-toolkit-postgresql-${PGVERSION}=${DEBVERSION}
    dpkg --install --admindir /tmp/dpkg --force-depends --force-not-root --force-overwrite timescaledb-toolkit-postgresql-${PGVERSION}*${TOOLKIT_VERSION}*.deb
    rm -rf /tmp/dpkg
done

# We want to enforce users that install toolkit 1.5+ when upgrading or reinstalling.
# NOTE: This does not affect versions that have already been installed, it only blocks
#       users from installing/upgrading to these versions
for file in "/usr/share/postgresql/${PGVERSION}/extension/timescaledb_toolkit--"*.sql; do

    base="${file%.sql}"
    target_version="${base##*--}"
    case "${target_version}" in
        "1.4"|"1.3"|"1.3.1")
            cat > "${file}" << __SQL__
DO LANGUAGE plpgsql
\$\$
BEGIN
    RAISE EXCEPTION 'TimescaleDB Toolkit version ${target_version} can not be installed. You can install TimescaleDB Toolkit 1.5.1 or higher';
END;
\$\$
__SQL__
            ;;
        *)
            ;;
    esac
done
