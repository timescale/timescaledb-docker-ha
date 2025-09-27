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
    check_pgvectorscale "$pg" "$lib"
    check_tapir "$pg" "$lib"
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

    # TODO: fix after pg18 is released
    if [[ "$pg" -lt 18 && ! -s "$lib/timescaledb.so" ]]; then
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

    # TODO: fix after pg18 is released
    if [[ "$found" = false && "$pg" -lt 18 ]]; then error "failed to find any timescaledb extensions for pg$pg"; fi
}

check_oss_extensions() {
    if [ "$OSS_ONLY" != true ]; then return 0; fi

    local pg="$1" lib="$2"
    for pattern in timescaledb_toolkit; do
        files="$(find "$lib" -maxdepth 1 -name "${pattern}*")"
        if [ -n "$files" ]; then error "found $pattern files for pg$pg when OSS_ONLY is true"; fi
    done
}

check_toolkit() {
    if [ -z "$TOOLKIT_VERSIONS" ]; then return; fi
    local pg="$1" lib="$2" found=false

    if [ "$OSS_ONLY" = true ]; then
        # we don't do anything here as we depend on `check_oss_extensions` to flag on inappropriate versions
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

    # TODO: fix after pg18 is released
    if [[ "$found" = false && "$pg" -lt 18 ]]; then error "no toolkit versions found for pg$pg"; fi
}

check_pgvectorscale() {
    if [ -z "$PGVECTORSCALE_VERSIONS" ]; then return; fi
    local pg="$1" lib="$2" found=false

    # record an empty version so we'll get an empty table row if we don't have any versions
    record_ext_version pgvectorscale "$pg" ""

    for ver in $PGVECTORSCALE_VERSIONS; do
        if [[ "$ver" = master || "$ver" = main ]]; then
            log "skipping looking for vectorscale-$ver"
            continue
        fi

        if [ -s "$lib/vectorscale-$ver.so" ]; then
            found=true
            record_ext_version pgvectorscale "$pg" "$ver"
        else
            unsupported_reason="$(supported_pgvectorscale "$pg" "$ver")"
            if [ -n "$unsupported_reason" ]; then
                log "skipped: pgvectorscale-$ver: $unsupported_reason"
            else
                error "pgvectorscale-$ver not found for pg$pg"
            fi
        fi
    done

    if [[ "$found" = false && "$pg" -ge 13 && "$pg" -le 17 ]]; then error "no pgvectorscale versions found for pg$pg"; fi
}

check_tapir() {
    if [ -z "$TAPIR_VERSION" ]; then return; fi
    local pg="$1" lib="$2" found=false

    # Skip check if OSS_ONLY is true since Tapir is not OSS
    if [ "$OSS_ONLY" = true ]; then
        log "skipping tapir check (not OSS)"
        return
    fi

    # record an empty version so we'll get an empty table row if we don't have any versions
    record_ext_version tapir "$pg" ""

    if [ -s "$lib/tapir.so" ]; then
        found=true
        record_ext_version tapir "$pg" "$TAPIR_VERSION"
    else
        unsupported_reason="$(supported_tapir "$pg" "$TAPIR_VERSION")"
        if [ -n "$unsupported_reason" ]; then
            log "skipped: tapir-$TAPIR_VERSION: $unsupported_reason"
        else
            error "tapir-$TAPIR_VERSION not found for pg$pg"
        fi
    fi

    if [[ "$found" = false && "$pg" -eq 17 ]]; then error "tapir not found for pg$pg"; fi
}

# this checks for other extensions that should always exist
check_others() {
    local pg="$1" lib="$2" version status

    record_ext_version logerrors "$pg" ""
    if [ -n "$PG_LOGERRORS" ]; then
        if [ -s "$lib/logerrors.so" ]; then
            record_ext_version logerrors "$pg" "$PG_LOGERRORS"
        else
            should_skip_for_pg18 "$pg" "logerrors" || error "logerrors not found for pg$pg"
        fi
    fi

    record_ext_version pg_stat_monitor "$pg" ""
    if [ -n "$PG_STAT_MONITOR" ]; then
        if [ -s "$lib/pg_stat_monitor.so" ]; then
            record_ext_version pg_stat_monitor "$pg" "$PG_STAT_MONITOR"
        else
            should_skip_for_pg18 "$pg" pg_stat_monitor || error "pg_stat_monitor not found for pg$pg"
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

    record_ext_version ai "$pg" ""
    if [[ -n "$PGAI_VERSION" && "$pg" -gt 15 ]]; then
        # pgai has no .so file
        pgai_control="$(/usr/lib/postgresql/${pg}/bin/pg_config --sharedir)/extension/ai.control"
        if [ -f "$pgai_control" ]; then
            record_ext_version ai "$pg" "$PGAI_VERSION"
        else
            should_skip_for_pg18 "$pg" ai || error "ai not found for pg$pg"
        fi
    fi

    record_ext_version pgvecto.rs "$pg" ""
    # TODO: pgvecto.rs hasn't released a pg17 compatible version yet, check https://github.com/tensorchord/pgvecto.rs/releases
    if [[ -n "$PGVECTO_RS" && "$pg" -gt 13 && "$pg" -lt 17 ]]; then
        if [ -s "$lib/vectors.so" ]; then
            record_ext_version pgvecto.rs "$pg" "$PGVECTO_RS"
        else
            error "pgvecto.rs not found for pg$pg"
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
            IFS=\| read -rs version status <<< "$(dpkg-query -W -f '${version}|${status}' "postgresql-$pg-postgis-$ver" 2>/dev/null)" || true
            if [ "$status" = "install ok installed" ]; then
                record_ext_version postgis "$pg" "$version"
            else
                should_skip_for_pg18 "$pg" "postgis-$ver" && continue
                error "pg$pg extension postgis-$ver not found: $status"
            fi
        done
    fi

    for extname in "${PG_WANTED_EXTENSIONS[@]}"; do
        record_ext_version "$extname" "$pg" ""
        IFS=\| read -rs version status <<< "$(dpkg-query -W -f '${version}|${status}' "postgresql-$pg-$extname" 2>/dev/null)" || true
        if [ "$status" = "install ok installed" ]; then
            record_ext_version "$extname" "$pg" "$version"
        else
            # it's not a debian package, but is it still installed via other means?
            if [ -f "$lib/${extname}.so" ]; then
                record_ext_version "$extname" "$pg" "unknown"
            else
                should_skip_for_pg18 "$pg" "$extname" && continue
                ls "$lib"
                error "pg$pg extension $extname not found: $status (and not at $lib/${extname}.so)"
            fi
        fi
    done
}

check_packages() {
    local pkg
    for pkg in "${WANTED_PACKAGES[@]}"; do
        IFS=\| read -rs version status <<< "$(dpkg-query -W -f '${version}|${status}' "$pkg")" || true
        if [ "$status" = "install ok installed" ]; then
            log "found package $pkg-$version"
        else
            should_skip_for_pg18 "$pg" "$pkg" && continue
            error "package $pkg not found: $status"
        fi
    done
}

check_files() {
    local file
    for file in "${WANTED_FILES[@]}"; do
        if [ -f "$file" ]; then
            log "found file $file"
        else
            error "file $file is missing"
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
