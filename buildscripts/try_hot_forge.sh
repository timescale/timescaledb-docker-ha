#!/bin/bash

set -e

if [ -z "$3" ]; then
    echo "Usage: $0 PGVERSION EXTNAME EXTVERSION"
    exit 1
fi

if [ -n "${HOT_FORGE_BUCKET}" ]; then
    echo "Trying to install $2 $3 for PostgreSQL $1 using Hot Forge ..."
    HOT_FORGE_PATCH="${HOT_FORGE_BUCKET}/pg${1}-${2}-${3}.tgz"
    hot-forge info --patch "${HOT_FORGE_PATCH}" || exit 1
    hot-forge install --patch "${HOT_FORGE_PATCH}" --hardlink --overwrite || exit 1
    rm -rf "${HOT_FORGE_ROOT}" && exit 0
fi

exit 1
