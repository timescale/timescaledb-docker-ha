#!/bin/bash

# these are the functions that perform the actual installations/builds of the extensions

get_package_suffix() {
  local distro="${DISTRO:-}"
  local version="${DISTRO_VERSION:-}"

  case "${distro}:${version}" in
    ubuntu:jammy) echo "~ubuntu22.04" ;;
    ubuntu:noble) echo "~ubuntu24.04" ;;
    *)
      echo "Unsupported distribution: ${distro} ${version}" >&2
      return 1
      ;;
  esac
}

construct_package_name() {
    local pg_version=$1
    local ts_version=$2
    local package_suffix=$3
    local oss_only="${OSS_ONLY:-}"
    local arch="${ARCH:-}"
    
    if [ "${oss_only}" = true ]; then
        # example: timescaledb-2-oss-postgresql-18=2.23.0~ubuntu24.04
        echo "timescaledb-2-oss-postgresql-${pg_version}=${ts_version}${package_suffix}"
    else
        # example: timescaledb-2-2.23.0-postgresql-18=2.23.0~ubuntu24.04
        echo "timescaledb-2-${ts_version}-postgresql-${pg_version}=${ts_version}${package_suffix}"
    fi
}

construct_loader_package_name() {
    local pg_version=$1
    local ts_version=$2
    local package_suffix=$3

    # example: timescaledb-2-loader-postgresql-18=2.23.0~ubuntu24.04
    echo "timescaledb-2-loader-postgresql-${pg_version}=${ts_version}${package_suffix}"
}

ensure_packagecloud_repo() {
    if apt-cache policy | grep -qi "packagecloud.io/timescale/timescaledb"; then
        log "timescale packagecloud repository already configured, skipping re-add."
        apt-get update -y
        return 0
    fi

    log "configuring Timescale packagecloud repository..."
    curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor > /etc/apt/keyrings/timescale_timescaledb-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/timescale_timescaledb-archive-keyring.gpg] https://packagecloud.io/timescale/timescaledb/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") main" \
        > /etc/apt/sources.list.d/timescale_timescaledb.list
    apt-get update -y
}

install_timescaledb_for_pg_version() {
    local pg_version=$1
    local ts_version=$2
    local package_suffix
    local loader_package
    local main_package

    package_suffix=$(get_package_suffix "${ts_version}")
    log "package suffix: ${package_suffix}"
    
    # construct package names
    loader_package=$(construct_loader_package_name "${pg_version}" "${ts_version}" "${package_suffix}")
    main_package=$(construct_package_name "${pg_version}" "${ts_version}" "${package_suffix}")
    
    log "loader package: ${loader_package}"
    log "main package: ${main_package}"
    
    # install loader
    if ! apt-get install "${loader_package}" "${main_package}" -y; then
        apt-get update -f -y  # fix dependencies
        error "failed to install loader package"
    fi
    
    # Install extension
    if ! apt-get install "${main_package}" -y; then
        apt-get update -f -y
        error "failed to install main package"
    fi
    
    log "successfully installed TimescaleDB ${ts_version} for PostgreSQL ${pg_version}"
}

install_timescaledb() {
    local version="$1" pg pkg=timescaledb unsupported_reason oss_only=""
    [ "$OSS_ONLY" = true ] && oss_only="-DAPACHE_ONLY=1"

    ensure_packagecloud_repo
    
    ARCH=$(dpkg --print-architecture)
    log "detected architecture: ${ARCH}"
    
    # map OS to packagecloud naming
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION_CODENAME="${VERSION_CODENAME}"
    else
        error "cannot detect OS distribution"
        exit 1
    fi
    
    DISTRO="${OS_ID}"
    DISTRO_VERSION="${OS_VERSION_CODENAME}"

    for pg in $(available_pg_versions); do
        unsupported_reason="$(supported_timescaledb "$pg" "$version")"
        if [ -n "$unsupported_reason" ]; then
            log "$pkg-$version: $unsupported_reason"
            continue
        fi

        if [[ "$version" = main && "$pg" -lt 14 ]]; then
            log "$pkg-$version: unsupported for < pg14"
            continue
        fi

        log "installing $pkg-$version for pg$pg"

        [[ "$DRYRUN" = true ]] && continue

        # use deb packages only with timescaledb versions >= 2.24
        # skip deb install for branch names (main, feature/foo, etc.) and build from source instead
        if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] && [ "$(printf '%s\n' "$version" "2.24.0" | sort -V | tail -n1)" = "$version" ]; then
            log "installing deb package for $pkg-$version for pg$pg"
            
            install_timescaledb_for_pg_version "${pg}" "${version}"
            err=$?

            if [ $err -eq 0 ]; then
                log "installed $pkg-$version for pg$pg"
            else
                error "failed install $pkg-$version for pg$pg ($err)"
            fi

            if [ "$OSS_ONLY" = true ]; then
                log "removing timescaledb-tsl due to OSS_ONLY"
                rm -f /usr/lib/postgresql/"$pg"/lib/timescaledb-tsl-*
            fi
        else
            log "building $pkg-$version for pg$pg"

            PATH="/usr/lib/postgresql/$pg/bin:${ORIGINAL_PATH}"
            git_clone "https://github.com/${GITHUB_REPO}" "$pkg" || continue
            git_checkout $pkg "$version" || continue
            (
                set -e
                cd /build/$pkg

                [ "$version" = "2.2.0" ] && sed -i 's/RelWithDebugInfo/RelWithDebInfo/g' CMakeLists.txt

                # Set architecture-specific flags
                local cmake_c_flags=""
                # this part could use a more precise check, but most modern ARM CPUs already support
                # +crypto extensions, so in reality we can just rely on the architecture.
                if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
                    cmake_c_flags="-DCMAKE_C_FLAGS=-march=armv8.2-a+crypto"
                fi

                ./bootstrap \
                    -DTAP_CHECKS=OFF \
                    -DWARNINGS_AS_ERRORS=off \
                    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
                    -DREGRESS_CHECKS=OFF \
                    -DGENERATE_DOWNGRADE_SCRIPT=ON \
                    -DPROJECT_INSTALL_METHOD="${INSTALL_METHOD}" \
                    -DUSE_UMASH=1 \
                    ${cmake_c_flags} \
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
        fi
    done
}

install_toolkit() {
    local rust_release cargo_pgrx_version="$1" version="$2" pg pkg=toolkit dpkg deb_version unsupported_reason pgrx_cmd
    [ -n "$RUST_RELEASE" ] && rust_release=release || rust_release=debug
    pgrx_cmd="$(cargo_pgrx_cmd "$cargo_pgrx_version")"

    if [ "$OSS_ONLY" = true ]; then
        log "skipped toolkit-$version due to OSS_ONLY"
        return
    fi

    for pg in $(available_pg_versions); do
        unsupported_reason="$(supported_toolkit "$pg" "$version")"
        if [ -n "$unsupported_reason" ]; then
            log "$pkg-$version: $unsupported_reason"
            continue
        fi

        read -rs dpkg deb_version <<< "$(find_deb "timescaledb-toolkit-postgresql-$pg" "$version")"
        if [[ -n "$dpkg" && -n "$deb_version" ]]; then
            [[ "$DRYRUN" = true ]] && { log "would install debian package $dpkg-$deb_version (cargo-$pgrx_cmd: $cargo_pgrx_version)"; continue; }
            if install_deb "$dpkg" "$deb_version"; then continue; fi
            log "failed installing $dpkg $deb_version"
        else
            log "couldn't find debian package for timescaleb-toolkit-postgresql-$pg $version"
        fi

        log "building $pkg-$version for pg$pg (cargo-$pgrx_cmd: $cargo_pgrx_version)"

        [ "$DRYRUN" = true ] && continue

        PATH="/usr/lib/postgresql/$pg/bin:${ORIGINAL_PATH}"
        cargo_pgrx_init "$cargo_pgrx_version" "$pg" || continue
        git_clone https://github.com/timescale/timescaledb-toolkit.git $pkg || continue
        git_checkout $pkg "$version" || continue
        (
            cd /build/$pkg || exit 1
            CARGO_TARGET_DIR_NAME=target ./tools/build "-pg$pg" -profile "$rust_release" install || { echo "failed toolkit build for pg$pg, $pkg-$version"; exit 1; }
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

timescaledb_post_install() {
    local pg
    # https://github.com/timescale/timescaledb/commit/6dddfaa54e8f29e3ea41dab2fe7d9f3e37cd3aae
    for pg in $(available_pg_versions); do
        for file in "/usr/share/postgresql/$pg/extension/timescaledb--"*.sql; do
            cat >>"${file}" <<"__SQL__"
DO $dynsql$
DECLARE
    alter_sql text;
BEGIN

    SET local search_path to 'pg_catalog';

    FOR alter_sql IN
        SELECT
            format(
                $$ALTER FUNCTION %I.%I(%s) SET search_path = 'pg_catalog'$$,
                nspname,
                proname,
                pg_catalog.pg_get_function_identity_arguments(pp.oid)
            )
        FROM
            pg_depend
        JOIN
            pg_extension ON (oid=refobjid)
        JOIN
            pg_proc pp ON (objid=pp.oid)
        JOIN
            pg_namespace pn ON (pronamespace=pn.oid)
        JOIN
            pg_language pl ON (prolang=pl.oid)
        LEFT JOIN LATERAL (
                SELECT * FROM unnest(proconfig) WHERE unnest LIKE 'search_path=%'
            ) sp(search_path) ON (true)
        WHERE
            deptype='e'
            AND extname='timescaledb'
            AND extversion < '2.5.2'
            AND lanname NOT IN ('c', 'internal')
            AND prokind = 'f'
            -- Only those functions/procedures that do not yet have their search_path fixed
            AND search_path IS NULL
            AND proname != 'time_bucket'
        ORDER BY
            search_path
    LOOP
        EXECUTE alter_sql;
    END LOOP;

    -- And for the sql time_bucket functions we prefer to *not* set the search_path to
    -- allow inlining of these functions
    WITH sql_time_bucket_fn AS (
        SELECT
            pp.oid
        FROM
            pg_depend
        JOIN
            pg_extension ON (oid=refobjid)
        JOIN
            pg_proc pp ON (objid=pp.oid)
        JOIN
            pg_namespace pn ON (pronamespace=pn.oid)
        JOIN
            pg_language pl ON (prolang=pl.oid)
        WHERE
            deptype = 'e'
            AND extname='timescaledb'
            AND extversion < '2.5.2'
            AND lanname = 'sql'
            AND proname = 'time_bucket'
            AND prokind = 'f'
            AND prosrc NOT LIKE '%OPERATOR(pg_catalog.%'
    )
    UPDATE
        pg_proc
    SET
        prosrc = regexp_replace(prosrc, '([-+]{1})', ' OPERATOR(pg_catalog.\1) ', 'g')
    FROM
        sql_time_bucket_fn AS s
    WHERE
        s.oid = pg_proc.oid;
END;
$dynsql$;
__SQL__
        done # for file
    done     # for pg
}

install_pgvectorscale() {
    local version="$1" pg pkg=pgvectorscale unsupported_reason arch_deb="$ARCH"
    if [ "$arch_deb" = aarch64 ]; then
        arch_deb=arm64
    fi

    for pg in $(available_pg_versions); do
        unsupported_reason="$(supported_pgvectorscale "$pg" "$version")"
        if [ -n "$unsupported_reason" ]; then
            log "$pkg-$version: $unsupported_reason"
            continue
        fi

        log "building $pkg-$version for pg$pg"

        [[ "$DRYRUN" = true ]] && continue

        (
            set -ex

            rm -rf /build/pgvectorscale
            mkdir /build/pgvectorscale
            cd /build/pgvectorscale

            curl --silent \
                 --fail \
                 --location \
                 --output artifact.zip \
                 "https://github.com/timescale/pgvectorscale/releases/download/$version/pgvectorscale-$version-pg${pg}-${arch_deb}.zip"

            unzip artifact.zip
            dpkg --install --log=/build/pgvectorscale/dpkg.log --admindir=/build/pgvectorscale/ --force-depends --force-not-root --force-overwrite pgvectorscale*"${arch_deb}".deb
        )
    done
}
