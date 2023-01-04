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

if [ -n "$GITHUB_STEP_SUMMARY" ]; then
    echo "## $(date -Iseconds)/$ARCH: image check started" >> "$GITHUB_STEP_SUMMARY"
fi

log() {
    local msg
    msg="$ARCH: $*"
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then echo "$msg" >> "$GITHUB_STEP_SUMMARY"; fi
    if [ ! "$VERBOSE" ]; then return; fi
    echo "$msg"
}

error() {
    local msg
    msg="$ARCH: ERROR: $*"
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then echo "**${msg}**" >> "$GITHUB_STEP_SUMMARY"; fi
    echo "$msg" >&2
    # shellcheck disable=SC2034  # EXIT_STATUS is used by callers, not us
    EXIT_STATUS=1
}

check_base_age() {
    # only check the BUILD_DATE during CI
    if [ "$CI" != true ]; then return 0; fi
    local age_threshold="$1"

    build_seconds="$(date -d"$BUILD_DATE" +%s)"
    now="$(date +%s)"
    age=$((now-build_seconds))
    if [ $age -gt "$age_threshold" ]; then
        error "the base image is too old ($age seconds old)"
    else
        log "the base image was built $age seconds ago"
    fi
}

check_base_components() {
    local pg="$1" lib="$2"

    check_timescaledb "$pg" "$lib"
    check_promscale "$lib"
    check_toolkit "$lib"
    check_oss_extensions "$lib"
    check_others "$lib"
}

check_timescaledb() {
    local pg="$1" lib="$2"
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
                if [[ "$pg" -ge 15 && "$ver" =~ ^(1\.|2\.[0-8]\.) ]]; then
                    log "timescaledb-$ver skipped for pg$pg"
                elif [[ "$pg" -eq 14 && "$ver" =~ ^(1\.|2\.[0-4]\.) ]]; then
                    log "timescaledb-$ver skipped for pg$pg"
                elif [[ "$pg" -eq 13 && "$ver" =~ ^1\. ]]; then
                    log "timescaledb-$ver skipped for pg$pg"
                elif [[ "$ARCH" = aarch64 && "$pg" -eq 12 && "$ver" =~ ^1\. ]]; then
                    log "timescaledb-$ver skipped for pg$pg"
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
        files="$(find "$lib" -maxdepth 1 -name "${pattern}*")"
        if [ -n "$files" ]; then error "found $pattern files for pg$pg when OSS_ONLY is true"; fi
    done
}

check_promscale() {
    if [ -z "$PROMSCALE_VERSIONS" ]; then return 0; fi
    local lib="$1"

    for ver in $PROMSCALE_VERSIONS; do
        if [ -s "$lib/promscale-$ver.so" ]; then
            log "found promscale-$ver for pg$pg"
        else
            # skip unsupported arch/version combinations
            case "$ARCH" in
            x86_64)
                if [[ "$pg" -ge 15 && "$ver" =~ ^0\.[0-7]\. ]]; then
                    log "promscale-$ver skipped for pg$pg"
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
    if [ -z "$TOOLKIT_VERSIONS" ]; then return 0; fi
    local lib="$1"

    for ver in $TOOLKIT_VERSIONS; do
        if [ -s "$lib/timescaledb_toolkit-$ver.so" ]; then
            log "found toolkit-$ver for pg$pg"
        else
            # skip unsupported arch/version combinations
            case "$ARCH" in
            x86_64)
                if [[ "$pg" -ge 15 && "$ver" =~ ^1\.([0-9]|1[012])\. ]]; then
                    log "toolkit-$ver skipped for pg$pg"
                else
                    error "toolkit-$ver not found for pg$pg"
                fi;;

            aarch64)
                if [[ "$pg" -ge 15 && "$ver" =~ ^1\.([0-9]|1[012])\. ]]; then
                    log "toolkit-$ver skipped for pg$pg"
                elif [[ "$ver" =~ ^1\.([0-9]|10)\. ]]; then
                    log "toolkit-$ver skipped for pg$pg"
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
            res="$(dpkg-query -W -f '${status}' "postgresql-$pg-postgis-$ver")"
            if [ "$res" = "install ok installed" ]; then
                log "found postgis version $ver for pg$pg"
            else
                error "postgis-$ver not found for pg$pg: $res"
            fi
        done
    fi
}
