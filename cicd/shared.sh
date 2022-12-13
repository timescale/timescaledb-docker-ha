#!/bin/bash

set -e -o pipefail

if [ ! -f /.image_config ]; then
    echo "no /.image_config found"
    exit 1
fi
. /.image_config

ARCH="$(arch)"
VERBOSE=""
EXIT_STATUS=0

log() {
    if [ ! $VERBOSE ]; then return; fi
    echo "- $ARCH: $*"
}

error() {
    echo "E $ARCH: $*"
    EXIT_STATUS=1
}

check_base_age() {
    # only check the BUILD_DATE during CI
    if [ "$CI" != true ]; then return 0; fi
    local age_threshold="$1"

    build_seconds="$(date -d"$BUILD_DATE" +%s)"
    now="$(date +%s)"
    age=$((now-build_seconds))
    if [ $age -gt $age_threshold ]; then
        error "the image is too old ($age seconds old)"
    else
        log "this image was built $age seconds ago"
    fi
}

check_base_components() {
    local lib="$1"

    check_timescaledb "$lib"
    check_promscale "$lib"
    check_toolkit "$lib"
    check_oss_extensions "$lib"
    check_others "$lib"
}

check_timescaledb() {
    local lib="$1"
    if [ -z "$TIMESCALEDB_VERSIONS" ]; then
        error "no timescaledb versions requested, why are we here?"
        return 1
    fi

    for ver in $TIMESCALEDB_VERSIONS; do
        if [[ -s "$lib/timescaledb-$ver.so" ]]; then
            if [ "$OSS_ONLY" = true ]; then
                if [ -s "$lib/timescaledb-tsl-$ver.so" ]; then
                    error "found timescaledb-tsl-$ver for pg$pg"
                else
                    log "found timescaledb-$ver for pg$pg"
                fi
            else
                if [ -s "$lib/timescaledb-tsl-$ver.so" ]; then
                    log "found timescaledb-$ver and tsl-$ver for pg$pg"
                else
                    error "found timescaledb-$ver, but not tsl-$ver for pg$pg"
                fi
            fi
        else
            # skip unsupported arch/version combinations
            case "$ARCH" in
            x86_64|aarch64)
                if [[ $pg -ge 15 && $ver =~ ^(1\.|2\.[0-8]\.) ]]; then
                    : # skip pg15 with tsdb < 2.9
                elif [[ $pg -eq 14 && $ver =~ ^(1\.|2\.[0-4]\.) ]]; then
                    : # skip pg14 with tsdb < 2.5
                elif [[ $pg -eq 13 && $ver =~ ^1\. ]]; then
                    : # skip pg13 with tsdb < 2.0
                elif [[ $ARCH = aarch64 && $pg -eq 12 && $ver =~ ^1\. ]]; then
                    : # skip pg12 arm64 < 2.0
                else
                    error "timescaledb-$ver not found for pg$pg"
                fi;;

            *) error "unexpected arch";;
            esac
        fi
    done
}

check_oss_extensions() {
    if [ "$OSS_ONLY" != true ]; then return 0; fi

    local lib="$1"
    for pattern in timescaledb_toolkit promscale; do
        files="$(find $lib -maxdepth 1 -name "${pattern}*")"
        if [ -n "$files" ]; then error "found $pattern files for pg$pg when OSS_ONLY is true"; fi
    done
}

check_promscale() {
    if [ -z "$TIMESCALE_PROMSCALE_EXTENSIONS" ]; then return 0; fi
    local lib="$1"

    for ver in $TIMESCALE_PROMSCALE_EXTENSIONS; do
        if [ -s "$lib/promscale-$ver.so" ]; then
            log "found promscale-$ver for pg$pg"
        else
            # skip unsupported arch/version combinations
            case "$ARCH" in
            x86_64)
                if [[ $pg -ge 15 && $ver =~ ^0\.[0-7]\. ]]; then
                    : # skip pg15 with any promscale
                else
                    error "promscale-$ver not found for pg$pg"
                fi;;

            aarch64) log "promscale has no arm support yet for pg$pg";;

            *) error "unexpected arch";;
            esac
        fi
    done
}

check_toolkit() {
    if [ -z "$TIMESCALEDB_TOOLKIT_EXTENSIONS" ]; then return 0; fi
    local lib="$1"

    for ver in $TIMESCALEDB_TOOLKIT_EXTENSIONS; do
        if [ -s "$lib/timescaledb_toolkit-$ver.so" ]; then
            log "found toolkit-$ver for pg$pg"
        else
            # skip unsupported arch/version combinations
            case "$ARCH" in
            x86_64)
                if [[ $pg -ge 15 && $ver =~ ^1\.([0-9]|1[012])\. ]]; then
                    : # skip pg15 with toolkit < 1.13
                else
                    error "toolkit-$ver not found for pg$pg"
                fi;;

            aarch64)
                if [[ $pg -ge 15 && $ver =~ ^1\.([0-9]|1[012])\. ]]; then
                    : # skip pg15 with toolkit < 1.13
                elif [[ $ver =~ ^1\.([0-9]|10)\. ]]; then
                    : # skip all versions prior to 1.11
                else
                    error "toolkit-$ver not found for pg$pg"
                fi;;

            *) error "unexpected arch";;
            esac
        fi
    done
}

# this checks for other extensions that should always exist
check_others() {
    if [ -n "$PG_LOGERRORS" ]; then
        if [ -s "$lib/logerrors.so" ]; then
            log "found logerrors for pg$pg"
        else
            error "logerrors not found for pg$pg"
        fi
    fi

    if [ -n "$PG_STAT_MONITOR" ]; then
        if [ -s "$lib/pg_stat_monitor.so" ]; then
            log "found pg_stat_monitor for pg$pg"
        else
            error "pg_stat_monitor not found for pg$pg"
        fi
    fi

    if [ -n "$PG_AUTH_MON" ]; then
        if [ -s "$lib/pg_auth_mon.so" ]; then
            log "found pg_auth_mon for pg$pg"
        else
            error "pg_auth_mon not found for pg$pg"
        fi
    fi

    if [ -n "$POSTGIS_VERSIONS" ]; then
        for ver in $POSTGIS_VERSIONS; do
            res="$(dpkg-query -W -f '${status}' postgresql-$pg-postgis-$ver)"
            if [ "$res" = "install ok installed" ]; then
                log "found postgis version $ver for pg$pg"
            else
                error "postgis-$ver not found for pg$pg: $res"
            fi
        done
    fi
}
