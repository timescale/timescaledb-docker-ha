#!/bin/bash

set -e -o pipefail

ORIGINAL_PATH="$PATH"

log() {
    echo "$ARCH: $*" >&2
}

error() {
    echo "** $ARCH: ERROR: $* **" >&2
}

git_clone() {
    local src="$1" dst=/build/"$2" err

    [ -d "$dst"/.git ] && return 0
    git clone "$src" "$dst"
    err=$?
    if [ $err -ne 0 ]; then
        error "error cloning $dst ($err)"
        return $err
    fi
    log "git cloned to $dst"
    return 0
}

git_checkout() {
    local repo=/build/"$1" tag="$2" err

    git -C "$repo" checkout -f "$tag"
    err=$?
    if [ $err -ne 0 ]; then
        error "error checking out $tag for $repo ($err)"
        return $err
    fi
    git -C "$repo" clean -f -d -x
    err=$?
    if [ $err -ne 0 ]; then
        error "error checking out $tag for $repo ($err)"
        return $err
    fi
    return 0
}

cargo_installed() {
    if type -p cargo; then
        return 0
    fi
    return 1
}

cargo_pgx_installed() {
    if ! cargo_installed; then
        return 1
    fi
    if test cargo pgx --version >&/dev/null; then
        return 0
    fi
    return 1
}

cargo_pgrx_installed() {
    if ! cargo_installed; then
        return 1
    fi
    if test cargo pgrx --version >&/dev/null; then
        return 0
    fi
    return 1
}

cargo_pgx_version() {
    if ! cargo_pgx_installed; then
        return 1
    fi

    local current_pgx=uninstalled
    if test cargo pgx --version >&/dev/null; then
        current_pgx="$(cargo pgx --version | awk '{print $2}')"
    fi
    if [ "$current_pgx" != "uninstalled" ]; then
        echo "$current_pgx"
    fi
    return 0
}

cargo_pgrx_version() {
    if ! cargo_pgrx_installed; then
        return 1
    fi

    local current_pgrx=uninstalled
    if test cargo pgrx --version >&/dev/null; then
        current_pgrx="$(cargo pgrx --version | awk '{print $2}')"
    fi
    if [ "$current_pgrx" != "uninstalled" ]; then
        echo "$current_pgrx"
    fi
    return 0
}

require_cargo_pgx_version() {
    local version="$1" err
    [ -z "$version" ] && return 1

    if ! cargo_installed; then
        error "cargo is not available, cannot install cargo-pgx"
        return 1
    fi
    if ! cargo_pgx_installed; then
        cargo install cargo-pgx --version "=$version"
        err=$?
        if [ $err -ne 0 ]; then
            error "failed installing cargo-pgx-$version ($err)"
            return $err
        fi
        log "installed cargo-pgx-$version"
    fi

    local current_version
    current_version="$(cargo_pgx_version)"
    if [[ -z "$current_version" || "$current_version" != "$version" ]]; then
        cargo install cargo-pgx --version "=$version"
        err=$?
        if [ $err -ne 0 ]; then
            error "failed installing cargo-pgx-$version ($err)"
            return $err
        fi
        log "installed cargo-pgx-$version"
    fi
    return 0
}

require_cargo_pgrx_version() {
    local version="$1" err
    [ -z "$version" ] && return 1

    if ! cargo_installed; then
        error "cargo is not available, cannot install cargo-pgrx"
        return 1
    fi
    if ! cargo_pgrx_installed; then
        cargo install cargo-pgrx --version "=$version"
        err=$?
        if [ $err -ne 0 ]; then
            error "failed installing cargo-pgrx-$version ($err)"
            return $err
        fi
        log "installed cargo-pgrx-$version"
    fi

    local current_version
    current_version="$(cargo_pgrx_version)"
    if [[ -z "$current_version" || "$current_version" != "$version" ]]; then
        cargo install cargo-pgrx --version "=$version"
        err=$?
        if [ $err -ne 0 ]; then
            error "failed installing cargo-pgrx-$version ($err)"
            return $err
        fi
        log "installed cargo-pgrx-$version"
    fi
    return 0
}

available_pg_versions() {
    # this allows running out-of-container with dry-run to test script logic
    if [[ "$DRYRUN" = true && ! -d /usr/lib/postgresql ]]; then
        echo 12 13 14 15
    else
        (cd /usr/lib/postgresql && ls)
    fi
}

cargo_pgrx_cmd() {
    local pgrx_version="$1"
    if [[ "$pgrx_version" =~ ^0\.[0-7]\.* ]]; then echo "pgx"; else echo "pgrx"; fi
}

cargo_pgrx_init() {
    local pgrx_version="$1" pg_ver="$2" pg_versions pgrx_cmd
    pgrx_cmd="$(cargo_pgrx_cmd "$pgrx_version")"

    if [ "$pgrx_cmd" = pgx ]; then
        if ! require_cargo_pgx_version "$pgrx_version"; then
            error "failed requiring cargo-pgx-$pgrx_version ($?)"
            return 1
        fi
    else
        if ! require_cargo_pgrx_version "$pgrx_version"; then
            error "failed requiring cargo-pgrx-$pgrx_version ($?)"
            return 1
        fi
    fi

    if [[ -z "$pg_ver" || "$pg" -eq 15 && "$pgrx_version" =~ ^0\.[0-5]\.* ]]; then
        pg_versions="$(available_pg_versions)"
    else
        pg_versions="$pg_ver"
    fi
    args=()
    for pg in $pg_versions; do
        # pgrx only got the pg15 feature in 0.6.0
        [[ "$pgrx_version" =~ ^0\.[0-5]\.* && $pg -eq 15 ]] && continue

        args+=("--pg${pg}" "/usr/lib/postgresql/${pg}/bin/pg_config")
    done
    rm -f "/home/postgres/.$pgrx_cmd/config.toml"
    cargo "$pgrx_cmd" init "${args[@]}"
    err=$?
    if [ $err -ne 0 ]; then
        error "failed cargo $pgrx_cmd init ${args[*]} ($err)"
        return $err
    fi
    return 0
}

find_deb() {
    local name="$1" version="$2" pkg
    pkg="$(apt-cache search "$name" 2>/dev/null| awk '{print $1}' | grep -v -- "-dbgsym")"
    if [ -n "$pkg" ]; then
        # we have a base package, do we have the requested version too?
        deb_version="$(apt-cache show "$pkg" 2>/dev/null | awk '/^Version:/ {print $2}' | grep -v forge | grep "$version" | head -n 1 || true)"
        if [[ -n "$pkg" && -n "$deb_version" ]]; then
            echo "$pkg" "$deb_version"
            return
        fi
    fi
}

install_deb() {
    local pkg="$1" version="$2" err
    local tmpdir="/tmp/deb-$pkg.$$"
    [ -n "$version" ] && version="=$version"

    mkdir "$tmpdir"
    (
        cd "$tmpdir"
        apt-get download "$pkg""$version"
        dpkg --install --log="$tmpdir"/dpkg.log --admindir="$tmpdir" --force-depends --force-not-root --force-overwrite "$pkg"_*.deb
        err=$?
        if [ $err -ne 0 ]; then
            error "failed installing debian package $pkg$version ($err)"
            exit $err
        fi
        exit 0
    )
    err=$?
    rm -rf "$tmpdir"
    if [ $err -eq 0 ]; then log "installed debian package $pkg$version"; fi
    return $err
}

# This is where we set arch/pg/extension version support checks, used by install and cicd
[ -s "$SCRIPT_DIR/shared_versions.sh" ] && . "$SCRIPT_DIR"/shared_versions.sh

# This is where the actual installation functions are
[ -s "$SCRIPT_DIR/shared_install.sh" ] && . "$SCRIPT_DIR"/shared_install.sh

require_supported_arch
