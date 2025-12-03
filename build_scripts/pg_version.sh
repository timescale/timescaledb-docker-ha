#!/bin/bash

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"

MAJOR="${1}"
if [ -z "${MAJOR}" ]; then
	echo "missing major version"
	exit 2
fi

PINNED=$(yq ".postgres_versions[\"${MAJOR}\"]" "$SCRIPT_DIR/versions.yaml")
if [ "${PINNED}" = "null" ]; then
	echo "could not find ${MAJOR} pinned version"
	exit 2
fi

echo "${PINNED}"
