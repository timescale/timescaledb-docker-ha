#!/bin/bash

# these are the functions that perform the actual installations/builds of the extensions

install_timescaledb() {
    local version="$1" pg pkg=timescaledb dpkg deb_version unsupported_reason oss_only="" search_name
    [ "$OSS_ONLY" = true ] && oss_only="-DAPACHE_ONLY=1"

    for pg in $(available_pg_versions); do
        supported="$(supported_timescaledb "$pg" "$version")"
        if [ -n "$supported" ]; then
            log "$pkg-$version: $supported"
            continue
        fi

        if [ "$OSS_ONLY" = true ]; then
            search_name="timescaledb-2-oss-$version-postgresql-$pg"
        else
            search_name="timescaledb-2-$version-postgresql-$pg"
        fi

        read -rs dpkg deb_version <<< "$(find_deb "$search_name" "$version")"
        if [[ -n "$dpkg" && -n "$deb_version" ]]; then
            [[ "$DRYRUN" = true ]] && { log "would install debian package $dpkg-$deb_version"; continue; }
            if install_deb "$dpkg" "$deb_version"; then continue; fi
            log "failed installing $dpkg $deb_version"
        else
            log "couldn't find debian package for $search_name $version"
        fi

        log "building $pkg-$version for pg$pg"

        [[ "$DRYRUN" = true ]] && continue

        PATH="/usr/lib/postgresql/$pg/bin:${ORIGINAL_PATH}"
        git_clone "https://github.com/${GITHUB_REPO}" "$pkg" || continue
        git_checkout $pkg "$version" || continue
        (
            set -e
            cd /build/$pkg

            [ "$version" = "2.2.0" ] && sed -i 's/RelWithDebugInfo/RelWithDebInfo/g' CMakeLists.txt

            ./bootstrap \
                -DTAP_CHECKS=OFF \
                -DWARNINGS_AS_ERRORS=off \
                -DCMAKE_BUILD_TYPE=RelWithDebInfo \
                -DREGRESS_CHECKS=OFF \
                -DGENERATE_DOWNGRADE_SCRIPT=ON \
                -DPROJECT_INSTALL_METHOD="${INSTALL_METHOD}" \
                ${oss_only}

            cd build

            make

            # https://github.com/timescale/timescaledb/commit/531f7ed8b16e4d1a99021d3d2b843bbc939798e3
            [ "$version" = "2.5.2" ] && sed -i 's/pg_temp./_timescaledb_internal./g' sql/**/*.sql

            make install

            if [ "$OSS_ONLY" = true ]; then
                log "removing timescaledb-tsl due to OSS_ONLY"
                rm -f /usr/lib/postgresql/"$pg"/lib/timescaledb-tsl-*
            fi
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
            if install_deb "$dpkg" "$deb_version"; then continue; fi
            log "failed installing $dpkg $deb_version"
        else
            log "couldn't find debian package for timescaleb-toolkit-postgresql-$pg $version"
        fi

        log "building $pkg-$version for pg$pg (cargo-pgx: $cargo_pgx_version)"

        [[ "$DRYRUN" = true ]] && continue

        PATH="/usr/lib/postgresql/$pg/bin:${ORIGINAL_PATH}"
        cargo_pgx_init "$cargo_pgx_version" "$pg" || continue
        git_clone https://github.com/timescale/timescaledb-toolkit.git $pkg || continue
        git_checkout $pkg "$version" || continue
        (
            cd /build/$pkg || exit 1
            CARGO_TARGET_DIR_NAME=target ./tools/build "-pg$pg" -profile "$rust_release" install || { echo "failed cargo pgx install for pg$pg, $pkg-$version"; exit 1; }
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
            if install_deb "$dpkg" "$deb_version"; then continue; fi
            log "failed installing $dpkg $deb_version"
        else
            log "couldn't find debian package for promscale-extension-postgresql-$pg $version"
        fi

        log "building $pkg version $version for pg$pg (cargo-pgx: $cargo_pgx_version)"

        [[ "$DRYRUN" = true ]] && continue

        PATH="/usr/lib/postgresql/$pg/bin:${ORIGINAL_PATH}"
        cargo_pgx_init "$cargo_pgx_version" "$pg" || continue
        git_clone https://github.com/timescale/promscale_extension.git $pkg || continue
        git_checkout $pkg "$version" || continue
        (
            cd /build/$pkg || exit 1
            cp templates/promscale.control ./promscale.control
            cargo pgx install ${rust_release} --features "pg$pg" || { echo "failed cargo pgx install for pg$pg, $pkg-$version"; exit 1; }
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
