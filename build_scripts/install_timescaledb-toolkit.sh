#!/bin/sh
# This script was created to reduce the complexity of the RUN command
# that installs all combinations of PostgreSQL and TimescaleDB Toolkit

if [ -z "$1" ]; then
    echo "Usage: $0 [TOOLKIT_TAG..]"
    exit 1
fi

if [ -z "${PGVERSIONS}" ]; then
    echo "Please export all PG Versions through PGVERSIONS env variable"
    exit 1
fi

set -e

mkdir -p /home/postgres/.pgx

for TOOLKIT_VERSION in "$@"; do
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

    for PGVERSION in $PGVERSIONS; do
        if [ "${PGVERSION}" -le 12 ]; then continue; fi
        if [ "${PGVERSION}" -ge 14 ] && [ "${TOOLKIT_VERSION}" = "forge-stable-1.3.1" ]; then continue; fi
        cat > /home/postgres/.pgx/config.toml <<__EOT__
[configs]
pg${PGVERSION} = "/usr/lib/postgresql/${PGVERSION}/bin/pg_config"
__EOT__
        cd extension
        cargo pgx install --release
        cargo run --manifest-path ../tools/post-install/Cargo.toml -- "/usr/lib/postgresql/${PGVERSION}/bin/pg_config"
        cd ..
    done
done

# We want to enforce users that install toolkit 1.5+ when upgrading or reinstalling.
# NOTE: This does not affect versions that have already been installed, it only blocks
#       users from installing/upgrading to these versions
for PGVERSION in $PGVERSIONS; do
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
done