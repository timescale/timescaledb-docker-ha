#!/bin/bash

set -e -o pipefail

if [ ! -s /.image_config ]; then
    echo "no, or empty /.image_config found"
    exit 1
fi
. /.image_config

if [ -s /build/scripts/shared_versions.sh ]; then
    . /build/scripts/shared_versions.sh
elif [ -s /cicd/scripts/shared_versions.sh ]; then
    . /cicd/scripts/shared_versions.sh
else
    echo "couldn't find shared_version.sh in /build/scripts, or in /cicd/scripts"
    exit 1
fi

VERBOSE=""
EXIT_STATUS=0

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

available_pg_versions() {
    (cd /usr/lib/postgresql && ls)
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
    check_promscale "$pg" "$lib"
    check_toolkit "$pg" "$lib"
    check_oss_extensions "$pg" "$lib"
    check_others "$pg" "$lib"
}

check_timescaledb() {
    local pg="$1" lib="$2" unsupported_reason found=false

    if [ -z "$TIMESCALEDB_VERSIONS" ]; then
        error "no timescaledb versions requested, why are we here?"
        return 1
    fi

    # record an empty version so we'll get an empty table row if we don't have any versions
    record_ext_version timescaledb "$pg" ""

    if [ ! -s "$lib/timescaledb.so" ]; then
        error "no timescaledb loader found for pg$pg"
    fi

    for ver in $TIMESCALEDB_VERSIONS; do
        if [[ "$ver" = master || "$ver" = main ]]; then
            continue
        fi
        if [[ -s "$lib/timescaledb-$ver.so" ]]; then
            if [ "$OSS_ONLY" = true ]; then
                if [ -s "$lib/timescaledb-tsl-$ver.so" ]; then
                    error "found non-OSS timescaledb-tsl-$ver for pg$pg"
                else
                    found=true
                    record_ext_version timescaledb "$pg" "$ver"
                fi
            else
                if [ -s "$lib/timescaledb-tsl-$ver.so" ]; then
                    found=true
                    record_ext_version timescaledb "$pg" "$ver"
                else
                    error "found timescaledb-$ver, but not tsl-$ver for pg$pg"
                fi
            fi
        else
            unsupported_reason="$(supported_timescaledb "$pg" "$ver")"
            if [ -n "$unsupported_reason" ]; then
                log "skipped: timescaledb-$ver: $unsupported_reason"
            else
                error "timescaledb-$ver not found for pg$pg"
            fi
        fi
    done

    if [ "$found" = false ]; then error "failed to find any timescaledb extensions for pg$pg"; fi
}

check_oss_extensions() {
    if [ "$OSS_ONLY" != true ]; then return 0; fi

    local pg="$1" lib="$2"
    for pattern in timescaledb_toolkit promscale; do
        files="$(find "$lib" -maxdepth 1 -name "${pattern}*")"
        if [ -n "$files" ]; then error "found $pattern files for pg$pg when OSS_ONLY is true"; fi
    done
}

check_promscale() {
    if [ -z "$PROMSCALE_VERSIONS" ]; then return; fi
    local pg="$1" lib="$2" ver found=false

    if [ "$OSS_ONLY" = true ]; then
        # we don't do anything here as we depend on `check_oss_extensions` to flag on inappropriate versions of promscale
        return
    fi

    # record an empty version so we'll get an empty table row if we don't have any versions
    record_ext_version promscale_extension "$pg" ""

    for ver in $PROMSCALE_VERSIONS; do
        if [[ "$ver" = master || "$ver" = main ]]; then
            log "skipping looking for promscale-$ver"
            continue
        fi
        if [ -s "$lib/promscale-$ver.so" ]; then
            found=true
            record_ext_version promscale_extension "$pg" "$ver"
        else
            unsupported_reason="$(supported_promscale "$pg" "$ver")"
            if [ -n "$unsupported_reason" ]; then
                log "skipped: promscale-$ver: $unsupported_reason"
            else
                error "promscale-$ver not found for pg$pg"
            fi
        fi
    done

    if [ "$found" = false ]; then error "no promscale versions found for pg$pg"; fi
}

check_toolkit() {
    if [ -z "$TOOLKIT_VERSIONS" ]; then return; fi
    local pg="$1" lib="$2" found=false

    if [ "$OSS_ONLY" = true ]; then
        # we don't do anything here as we depend on `check_oss_extensions` to flag on inappropriate versions of promscale
        return
    fi

    # record an empty version so we'll get an empty table row if we don't have any versions
    record_ext_version toolkit "$pg" ""

    for ver in $TOOLKIT_VERSIONS; do
        if [[ "$ver" = master || "$ver" = main ]]; then
            log "skipping looking for toolkit-$ver"
            continue
        fi

        if [ -s "$lib/timescaledb_toolkit-$ver.so" ]; then
            found=true
            record_ext_version toolkit "$pg" "$ver"
        else
            unsupported_reason="$(supported_toolkit "$pg" "$ver")"
            if [ -n "$unsupported_reason" ]; then
                log "skipped: toolkit-$ver: $unsupported_reason"
            else
                error "toolkit-$ver not found for pg$pg"
            fi
        fi
    done

    if [ "$found" = false ]; then error "no toolkit versions found for pg$pg"; fi
}

# this checks for other extensions that should always exist
check_others() {
    local pg="$1" lib="$2" version status

    record_ext_version logerrors "$pg" ""
    if [ -n "$PG_LOGERRORS" ]; then
        if [ -s "$lib/logerrors.so" ]; then
            record_ext_version logerrors "$pg" "$PG_LOGERRORS"
        else
            error "logerrors not found for pg$pg"
        fi
    fi

    record_ext_version pg_stat_monitor "$pg" ""
    if [ -n "$PG_STAT_MONITOR" ]; then
        if [ -s "$lib/pg_stat_monitor.so" ]; then
            record_ext_version pg_stat_monitor "$pg" "$PG_STAT_MONITOR"
        else
            error "pg_stat_monitor not found for pg$pg"
        fi
    fi

    record_ext_version pgvector "$pg" ""
    if [ -n "$PGVECTOR" ]; then
        if [ -s "$lib/vector.so" ]; then
            record_ext_version pgvector "$pg" "$PGVECTOR"
        else
            error "pgvector not found for pg$pg"
        fi
    fi

    record_ext_version pg_auth_mon "$pg" ""
    if [ -n "$PG_AUTH_MON" ]; then
        if [ -s "$lib/pg_auth_mon.so" ]; then
            record_ext_version pg_auth_mon "$pg" "$PG_AUTH_MON"
        else
            error "pg_auth_mon not found for pg$pg"
        fi
    fi

    record_ext_version postgis "$pg" ""
    if [ -n "$POSTGIS_VERSIONS" ]; then
        for ver in $POSTGIS_VERSIONS; do
            IFS=\| read -rs version status <<< "$(dpkg-query -W -f '${version}|${status}' "postgresql-$pg-postgis-$ver")"
            if [ "$status" = "install ok installed" ]; then
                record_ext_version postgis "$pg" "$version"
            else
                error "pg$pg extension postgis-$ver not found: $status"
            fi
        done
    fi

    for extname in $PG_WANTED_EXTENSIONS; do
        record_ext_version "$extname" "$pg" ""
        IFS=\| read -rs version status <<< "$(dpkg-query -W -f '${version}|${status}' "postgresql-$pg-$extname" 2>/dev/null)"
        if [ "$status" = "install ok installed" ]; then
            record_ext_version "$extname" "$pg" "$version"
        else
            # it's not a debian package, but is it still installed via other means?
            if [ -f "$lib/${extname}.so" ]; then
                record_ext_version "$extname" "$pg" "unknown"
            else
                ls "$lib"
                error "pg$pg extension $extname not found: $status (and not at $lib/${extname}.so"
            fi
        fi
    done
}

check_packages() {
    local pkg
    for pkg in $WANTED_PACKAGES; do
        IFS=\| read -rs version status <<< "$(dpkg-query -W -f '${version}|${status}' "$pkg")"
        if [ "$status" = "install ok installed" ]; then
            log "found package $pkg-$version"
        else
            error "package $pkg not found: $status"
        fi
    done
}

EXTVERSIONS="$(mktemp -t extversions.$ARCH.XXXX)"
cleanup() {
    rm -f "$EXTVERSIONS".* >&/dev/null
}
trap cleanup ERR EXIT

record_ext_version() {
    local pkg="$1" pg="$2" version="$3"
    echo "$pkg|$version" >> "$EXTVERSIONS".pg"$pg"
}

sort_keys() {
    for k in "$@"; do echo "$k"; done | xargs -n 1 | sort -ifVu | xargs
}

ext_version_table() {
    local -A pkgs
    local versions
    echo "#### Installed PG extensions for $ARCH:"
    for pg in $(available_pg_versions); do
        echo "| PG$pg Extension | Versions |"
        echo "|:-|:-|"

        pkgs=()
        while read -r line; do
            IFS=\| read -rs pkg version <<< "$line"
            pkgs["$pkg"]+=" $version"
        done < "$EXTVERSIONS".pg"$pg"

        for pkg in $(sort_keys "${!pkgs[@]}"); do
            versions="$(sort_keys "${pkgs[$pkg]}")"
            echo "| $pkg | ${versions// /, } |"
        done

        echo
    done
}
