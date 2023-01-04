#!/bin/bash

set -e -o pipefail

ARCH="$(arch)"

log() {
    echo "$(date -Iseconds)/$ARCH: $*"
}

error() {
    echo "** $(date -Iseconds)/$ARCH: ERROR: $* **" >&2
}

git_clone() {
    local src="$1"
    local dst=/build/"$2"

    [ -d "$dst"/.git ] && return 0
    git clone "$src" "$dst"
}

git_checkout() {
    local repo=/build/"$1"
    local tag="$2"

    git -C "$repo" checkout "$tag"
    git -C "$repo" clean -f -d -x
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
    local version="$1"
    [ -z "$version" ] && return 1

    if ! cargo_installed; then
        echo "cargo is not available, cannot install cargo-pgx"
        return 1
    fi
    if ! cargo_pgx_installed; then
        cargo install cargo-pgx --version "=$version"
        return $?
    fi

    local current_version
    current_version="$(cargo_pgx_version)"
    if [[ -z "$current_version" || "$current_version" != "$version" ]]; then
        cargo install cargo-pgx --version "=$version"
        return $?
    fi
    return 1
}

available_pg_versions() {
    (cd /usr/lib/postgresql && ls)
}

cargo_pgx_init() {
    local pgx_version="$1" pg_ver="$2" pg_versions

    if ! require_cargo_pgx_version "$pgx_version"; then
        echo "failed cargo-pgx init ($?)"
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
    local pkg="$1" version="$2" tmpdir
    tmpdir="/tmp/deb-$pkg.$$"

    echo "install debian package $pkg-$version"

    mkdir "$tmpdir"
    (
        cd "$tmpdir"
        apt-get download "$pkg"="$version"
        dpkg --install --log="$tmpdir"/dpkg.log --admindir="$tmpdir" --force-depends --force-not-root --force-overwrite "$pkg"_*.deb
    )
    ret=$?
    rm -rf "$tmpdir"
    return $ret
}
