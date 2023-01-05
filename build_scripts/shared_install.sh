#!/bin/bash

# these are the functions that perform the actual installations/builds of the extensions

install_toolkit() {
    local rust_release cargo_pgx_version="$1" version="$2" pg pkg=toolkit dpkg deb_version unsupported_reason
    [ -n "$RUST_RELEASE" ] && rust_release=release || rust_release=debug

    if [ "$OSS_ONLY" = true ]; then
        log "skipped toolkit-$version due to OSS_ONLY"
        return
    fi

    for pg in $(available_pg_versions); do
        supported="$(supported_toolkit "$pg" "$version")"
        if [ -n "$supported" ]; then
            log "$pkg-$version: $supported"
            continue
        fi

        read -rs dpkg deb_version <<< "$(find_deb "timescaledb-toolkit-postgresql-$pg" "$version")"
        if [[ -n "$dpkg" && -n "$deb_version" ]]; then
            [[ "$DRYRUN" = true ]] && { log "would install debian package $dpkg-$deb_version (cargo-pgx: $cargo_pgx_version)"; continue; }
            install_deb "$dpkg" "$deb_version"
            continue
        fi

        log "building $pkg-$version for pg$pg (cargo-pgx: $cargo_pgx_version)"

        [[ "$DRYRUN" = true ]] && continue

        PATH="/usr/lib/postgresql/$pg/bin:${ORIGINAL_PATH}"
        cargo_pgx_init "$cargo_pgx_version" "$pg" || { error "failed cargo-pgx $cargo_pgx_version"; continue; }
        git_clone https://github.com/timescale/timescaledb-toolkit.git $pkg || { error "failed $pkg clone"; continue; }
        git_checkout $pkg "$version" || { error "failed $pkg checkout $version"; continue; }
        (
            cd /build/$pkg || exit 1
            CARGO_TARGET_DIR_NAME=target ./tools/build "-pg$pg" -profile "$rust_release" install || error "failed building $pkg $version for pg$pg"
        )
        err=$?
        if [ $err -eq 0 ]; then
            log "installed $pkg-$version for pg$pg"
        else
            error "failed building $pkg-$version for pg$pg ($err)"
        fi
    done
    PATH="$ORIGINAL_PATH"
}

install_promscale() {
    local rust_release cargo_pgx_version="$1" version="$2" pg pkg=promscale dpkg deb_version unsupported_reason
    [ -n "$RUST_RELEASE" ] && rust_release=-r || rust_release=""

    if [ "$OSS_ONLY" = true ]; then
        log "skipped toolkit-$version due to OSS_ONLY"
        return
    fi

    for pg in $(available_pg_versions); do
        unsupported_reason="$(supported_promscale "$pg" "$version")"
        if [ -n "$unsupported_reason" ]; then
            log "$pkg-$version: $unsupported_reason"
            continue
        fi

        read -rs dpkg deb_version <<< "$(find_deb "promscale-extension-postgresql-$pg" "$version")"
        if [[ -n "$dpkg" && -n "$deb_version" ]]; then
            [[ "$DRYRUN" = true ]] && { log "would install debian package $dpkg-$deb_version (cargo-pgx: $cargo_pgx_version)"; continue; }
            if install_deb "$dpkg" "$deb_version"; then
                log "installed debian $dpkg-$deb_version"
                continue
            else
                log "failed installing $dpkg-$deb_version"
            fi
        fi

        log "building $pkg version $version for pg$pg (cargo-pgx: $cargo_pgx_version)"

        [[ "$DRYRUN" = true ]] && continue

        PATH="/usr/lib/postgresql/$pg/bin:${ORIGINAL_PATH}"
        cargo_pgx_init "$cargo_pgx_version" "$pg" || { echo "failed cargo-pgx $cargo_pgx_version"; continue; }
        git_clone https://github.com/timescale/promscale_extension.git $pkg || { echo "failed $pkg clone"; continue; }
        git_checkout $pkg "$version" || { echo "failed $pkg checkout $version"; continue; }
        (
            cd /build/$pkg || exit 1
            cp templates/promscale.control ./promscale.control
            cargo pgx install ${rust_release} --features "pg$pg" || echo "failed cargo pgx install for pg$pg, $pkg-$version"
        )
        err=$?
        if [ $err -eq 0 ]; then
            log "installed $pkg-$version for pg$pg"
        else
            error "failed building $pkg-$version for pg$pg ($err)"
        fi
    done
    PATH="$ORIGINAL_PATH"
}
