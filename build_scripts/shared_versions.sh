#!/bin/bash

# These associative arrays declare which version of cargo-pgx is required for versions of toolkit and promscale. The
# values are regular expressions that need to match all the version tags for the cargo-pgx versions in the keys
# shellcheck disable=SC2034 # used by callers
declare -A pgx_toolkit_versions=(
    ["0.2.4"]="1.[67].0"
    ["0.4.5"]="1.(8|9|10|11).*"
    ["0.5.4"]="1.12.[01]"
    ["0.6.1"]="main|1.1[34].*"
)
# shellcheck disable=SC2034 # used by callers
declare -A pgx_promscale_versions=(
    ["0.3.1"]="0.5.*"
    ["0.4.5"]="0.[67].0"
    ["0.6.1"]="master|0.7.([1-9]).*|0.8.0"
)

# Check to make sure these extensions are available in all pg versions
PG_WANTED_EXTENSIONS="pglogical wal2json pgextwlist pgrouting pg-stat-kcache cron pldebugger hypopg unit repack hll"

WANTED_PACKAGES="patroni pgbackrest timescaledb-tools"

# These functions return "" if the combination of architecture, pg version, and package version are supported,
# otherwise it returns a reason string. Both the cicd/install_checks, and the install_extensions scripts use
# this to decide what should be built/included.

ARCH="$(arch)"
# standardize architecture names
if [ "$ARCH" = arm64 ]; then
    ARCH=aarch64
elif [ "$ARCH" = x86_64 ]; then
    ARCH=amd64
fi

require_supported_arch() {
    if [[ "$ARCH" != amd64 && "$ARCH" != aarch64 ]]; then
        echo "unsupported architecture: $ARCH" >&2
        exit 1
    fi
}

supported_timescaledb() {
    local pg="$1" ver="$2" major minor

    if [ "$pg" -lt 12 ]; then
        echo "timescaledb not supported in pg$pg (<12)"
        return
    fi

    if [ "$ver" = "main" ]; then
        # just attempt the build for main
        return
    fi

    major="$(echo "$ver" | cut -d. -f1)"
    minor="$(echo "$ver" | cut -d. -f2)"

    case "$pg" in
    15) if [[ "$major" -lt 2 || ( "$major" -eq 2 && "$minor" -lt 9 ) ]]; then
            echo "timescaledb-$ver not supported on pg15, requires 2.9+"
        fi;;

    14) if [[ "$major" -lt 2 || ( "$major" -eq 2 && "$minor" -lt 5 ) ]]; then
            echo "timescaledb-$ver not supported on pg14, requires 2.5+"
        fi;;

    13) if [ "$major" -lt 2 ]; then
            echo "timescaledb-$ver not supported on pg13, requires 2.0+"
        fi;;

    12) # pg12 builds all the versions
        ;;

    *) echo "timescaledb-$ver not supported on pg$pg, requires pg12+";;
    esac
}

supported_toolkit() {
    local pg="$1" ver="$2"

    if [ "$OSS_ONLY" = true ]; then
        echo "toolkit isn't supported for OSS_ONLY"
    elif [[ "$ver" = master || "$ver" = main ]]; then
        : # just attempt the build
    elif [[ "$pg" -lt 12 ]]; then
        echo "pg$pg is not supported, 12+ required"
    elif [[ "$pg" -gt 15 ]]; then
        echo "pg$pg is not supported, 15 and lower are required"
    elif [[ "$ver" =~ ^(0\.*|1\.[0-5]\.) ]]; then
        echo "toolkit-$ver is not supported"
    elif [[ "$pg" -eq 15 && ( "$ver" =~ 1\.([6-9]|10|11|12)\.* || $ver = 1.13.0 ) ]]; then
        echo "pg15 requires 1.13.1+"
    elif [[ "$ARCH" = aarch64 && ( "$ver" =~ 1\.([6-9]|10|11|12)\.* || $ver = 1.13.0 ) ]]; then
        echo "toolkit-$ver not supported on aarch64, 1.13.1+ is required"
    fi
}

supported_promscale() {
    local pg="$1" ver="$2"

    if [ "$OSS_ONLY" = true ]; then
        echo "promscale isn't supported for OSS_ONLY"
    elif [[ "$ver" = master || "$ver" = main ]]; then
        : # just attempt the build
    elif [[ "$pg" -lt 12 ]]; then
        echo "pg$pg is not supported"
    elif [[ "$pg" -gt 15 ]]; then
        echo "pg$pg is not supported"
    elif [[ "$ver" =~ ^0\.[0-4]\. ]]; then
        echo "promscale-$ver is too old"
    elif [[ "$pg" -eq 15 && "$ver" =~ ^0\.[0-7].* ]]; then
        echo "promscale-$ver is too old for pg$pg, requires 0.8.0+"
    elif [[ "$ARCH" = aarch64 ]]; then
        if [[ "$ver" =~ ^0\.[0-7]\.* ]]; then
            echo "promscale on aarch64 for versions prior to 0.8.0 aren't supported"
        fi
    fi
}
