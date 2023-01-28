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

available_pg_versions() {
    (cd /usr/lib/postgresql && ls)
}

cargo_pgx_init() {
    local pgx_version="$1" pg_ver="$2" pg_versions

    if ! require_cargo_pgx_version "$pgx_version"; then
        error "failed requiring cargo-pgx-$pgx_version ($?)"
        return 1
    fi

    if [[ -z "$pg_ver" || "$pg" -eq 15 && "$pgx_version" =~ ^0\.[0-5]\.* ]]; then
        pg_versions="$(available_pg_versions)"
    else
        pg_versions="$pg_ver"
    fi
    args=()
    for pg in $pg_versions; do
        # pgx only got the pg15 feature in 0.6.0
        [[ "$pgx_version" =~ ^0\.[0-5]\.* && $pg -eq 15 ]] && continue

        args+=("--pg${pg}" "/usr/lib/postgresql/${pg}/bin/pg_config")
    done
    rm -f /home/postgres/.pgx/config.toml
    cargo pgx init "${args[@]}"
    err=$?
    if [ $err -ne 0 ]; then
        error "failed cargo pgx init ${args[*]} ($err)"
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
. "$SCRIPT_DIR"/shared_versions.sh

# This is where the actual installation functions are
. "$SCRIPT_DIR"/shared_install.sh

require_supported_arch
