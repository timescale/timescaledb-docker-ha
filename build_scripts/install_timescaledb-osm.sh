#!/bin/sh
# This script was created to reduce the complexity of the RUN command
# that installs all combinations of PostgreSQL and TimescaleDB OSM


if [ "$#" -ne 4 ]; then
    echo "Usage: $0 OSM_TAG PG_VERSION PGX_VERSION TOKEN"
    exit 1
fi

TAG="${1}"
PG_VER="${2}"
PGX_VER="${3}"
TOKEN="${4}"
ARTIFACT="osm-${TAG}-pg${PG_VER}-pgx${PGX_VER}"

# retrieve download url for given artifact
ARTIFACT_URL=$(curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${TOKEN}" https://api.github.com/repos/timescale/timescaledb-osm/actions/artifacts | jq ".artifacts[] | select(.name==\"${ARTIFACT}\") | .archive_download_url" | sed 's/\"//g')

# download the artifact
curl -LJO -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${TOKEN}" "${ARTIFACT_URL}"

# install
unzip "${ARTIFACT}".zip
mkdir /tmp/dpkg
dpkg --install --admindir /tmp/dpkg --force-depends --force-not-root --force-overwrite timescaledb-osm-postgresql-${PG_VER}_${TAG}*.deb || exit 1
rm -rf /tmp/dpkg
rm -rf "${ARTIFACT}".zip
