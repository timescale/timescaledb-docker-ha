#!/bin/bash

# Check to make sure these extensions are available in all pg versions
PG_WANTED_EXTENSIONS=(
    cron
    h3
    h3_postgis
    hll
    hypopg
    ip4r
    orafce
    pg-qualstats
    pg-stat-kcache
    pg_uuidv7
    pgaudit
    pgextwlist
    pglogical
    pgpcre
    pgrouting
    pgsodium
    pgvector
    pldebugger
    repack
    rum
    unit
    wal2json
)

# These aren't available yet in pg18. This should be modified as time gets closer to the full release, and then
# eventually updated for pg19
SKIP_FOR_PG18=(
    ai
    rum
    pldebugger
    timescaledb
)

should_skip_for_pg18() {
    local pg="$1" pkg="$2"
    [ "$pg" -lt 18 ] && return 1
    for p in "${SKIP_FOR_PG18[@]}"; do
        [ "$p" = "$pkg" ] && return 0
    done
    return 1
}

WANTED_PACKAGES=(
    patroni
    pgbackrest
    timescaledb-tools
)

WANTED_FILES=(
    /usr/bin/pgbackrest_exporter
    /usr/bin/timescaledb-tune
    /usr/local/bin/pgbouncer_exporter
    /usr/local/bin/yq
)

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

if [ -s /build/scripts/versions.yaml ]; then
    VERSION_DATA="$(< /build/scripts/versions.yaml)"
elif [ -s /cicd/scripts/versions.yaml ]; then
    VERSION_DATA="$(< /cicd/scripts/versions.yaml)"
elif [ -s versions.yaml ]; then
    VERSION_DATA="$(< versions.yaml)"
else
    error "could not locate versions.yaml"
    exit 1
fi

DEFAULT_PG_MIN="$(yq .default-pg-min <<< "$VERSION_DATA")"
[ -z "$DEFAULT_PG_MIN" ] && { error "default-pg-min is required in versions.yaml"; exit 1; }
DEFAULT_PG_MAX="$(yq .default-pg-max <<< "$VERSION_DATA")"
[ -z "$DEFAULT_PG_MAX" ] && { error "default-pg-max is required in versions.yaml"; exit 1; }

pkg_versions() {
    local pkg="$1"
    yq ".$pkg | keys | .[]" <<<"$VERSION_DATA" | xargs
}

# expand the list of requested package versions (usage: $1=pkg $2=single argument with the contents of the environment
# variable containing the requested versions)
requested_pkg_versions() {
    local pkg="$1" envvar="$2"
    local -a versions
    readarray -t versions <<< "$envvar"
    case "${#versions[@]}" in
    0) return;;
    1)  case "${versions[0]}" in
        all) pkg_versions "$pkg"; return;;
        latest) latest_pkg_version "$pkg"; return;;
        esac;;
    esac
    echo "$envvar"
}

latest_pkg_version() {
    local pkg="$1"
    local -a versions
    readarray -t versions <<< "$(yq ".$pkg | keys | .[]" <<<"$VERSION_DATA")"
    echo "${versions[-1]}"
}

# locate the cargo-pgrx key from versions.yaml
pkg_cargo_pgrx_version() {
    local pkg="$1" ver="$2" cargopgrx

    cargopgrx="$(yq ".$pkg | pick([\"$ver\"]) | .[].cargo-pgrx" <<<"$VERSION_DATA")"
    if [ "$cargopgrx" = null ]; then return; else echo "$cargopgrx"; fi
}

# install the rust extensions ordered from oldest required cargo-pgrx to newest to keep
# the number of rebuilds for cargo-pgrx to a minimum
install_rust_extensions() {
    local cargopgrx sorted_pgrx_versions
    declare -A pgrx_versions=()

    for ver in $TOOLKIT_VERSIONS; do
        cargopgrx="$(pkg_cargo_pgrx_version "toolkit" "$ver")"
        if [ -z "$cargopgrx" ]; then
            error "no cargo-pgrx version found for toolkit-$ver"
            continue
        fi
        pgrx_versions[$cargopgrx]+=" toolkit-$ver"
    done

    sorted_pgrx_versions="$(for pgrx_ver in "${!pgrx_versions[@]}"; do echo "$pgrx_ver"; done | sort -Vu)"
    for pgrx_ver in $sorted_pgrx_versions; do
        ext_versions="$(for ext_ver in ${pgrx_versions[$pgrx_ver]}; do echo "$ext_ver"; done | sort -Vu)"
        for ext_ver in $ext_versions; do
            ext="$(echo "$ext_ver" | cut -d- -f1)"
            ver="$(echo "$ext_ver" | cut -d- -f2-)"
            case "$ext" in
            toolkit)   install_toolkit   "$pgrx_ver" "$ver";;
            esac
        done
    done
}

version_is_supported() {
    local pkg="$1" pg="$2" ver="$3" pdata pgmin pgmax arch
    pg="$(major_version_only "$pg")"
    local -a pgversions

    pdata="$(yq ".$pkg | pick([\"$ver\"]) | .[]" <<<"$VERSION_DATA")"
    if [ "$pdata" = null ]; then
        echo "not found in versions.yaml"
        return
    fi

    arch="$(yq .arch <<<"$pdata")"
    if [ "$arch" = null ]; then arch="both"; fi
    if [[ "$arch" != "both" && "$arch" != "$ARCH" ]]; then echo "unsupported arch $ARCH"; return; fi

    pgmin="$(yq .pg-min <<<"$pdata")"
    pgmin="$(major_version_only "$pgmin")"
    if [ "$pgmin" = null ]; then pgmin="$DEFAULT_PG_MIN"; fi
    if [ "$pg" -lt "$pgmin" ]; then echo "pg$pg is too old"; return; fi

    pgmax="$(yq .pg-max <<<"$pdata")"
    pgmax="$(major_version_only "$pgmax")"
    if [ "$pgmax" = null ]; then pgmax="$DEFAULT_PG_MAX"; fi
    if [ "$pg" -gt "$pgmax" ]; then echo "pg$pg is too new"; return; fi

    pdata="$(yq .pg[] <<<"$pdata")"
    if [ -n "$pdata" ]; then
        local found=false
        readarray -t pgversions <<<"$pdata"
        for pgv in "${pgversions[@]}"; do
            if [ "$pgv" = "$pg" ]; then found=true; break; fi
        done
        if [ "$found" = "false" ]; then echo "does not support pg$pg"; return; fi
    fi
}

# Ensure PG version matching is performed only based upon MAJOR version.
#
# This is a bit simplistic, but the system will otherwise break when
# building a version of PG which specifies a minor or patch version.
major_version_only() {
    echo -n "${1%%.*}" # Trim the longest matching pattern `.*` (bash pattern, not regex).
}

supported_timescaledb() {
    local pg="$1" ver="$2"

    # just attempt the build for main/master/or other branch build
    if [[ "$ver" = main || "$ver" = master || "$ver" =~ [a-z_-]*/[A-Za-z0-9_-]* ]]; then
        return
    fi

    version_is_supported timescaledb "$pg" "$ver"
}

supported_toolkit() {
    local pg="$1" ver="$2"

    # just attempt the build for main/master/or other branch build
    if [[ "$ver" = main || "$ver" = master || "$ver" =~ [a-z_-]*/[A-Za-z0-9_-]* ]]; then
        return
    fi

    version_is_supported toolkit "$pg" "$ver"
}

supported_pgvectorscale() {
    local pg="$1" ver="$2"

    # just attempt the build for main/master/or other branch build
    if [[ "$ver" = main || "$ver" = master || "$ver" =~ [a-z_-]*/[A-Za-z0-9_-]* ]]; then
        return
    fi

    version_is_supported pgvectorscale "$pg" "$ver"
}

require_supported_arch() {
    if [[ "$ARCH" != amd64 && "$ARCH" != aarch64 ]]; then
        echo "unsupported architecture: $ARCH" >&2
        exit 1
    fi
}

TIMESCALEDB_VERSIONS="$(requested_pkg_versions timescaledb "$TIMESCALEDB_VERSIONS")"
TOOLKIT_VERSIONS="$(requested_pkg_versions toolkit "$TOOLKIT_VERSIONS")"
PGVECTORSCALE_VERSIONS="$(requested_pkg_versions pgvectorscale "$PGVECTORSCALE_VERSIONS")"
