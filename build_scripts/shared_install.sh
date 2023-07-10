#!/bin/bash

# these are the functions that perform the actual installations/builds of the extensions

install_timescaledb() {
    local version="$1" pg pkg=timescaledb unsupported_reason oss_only=""
    [ "$OSS_ONLY" = true ] && oss_only="-DAPACHE_ONLY=1"

    for pg in $(available_pg_versions); do
        unsupported_reason="$(supported_timescaledb "$pg" "$version")"
        if [ -n "$unsupported_reason" ]; then
            log "$pkg-$version: $unsupported_reason"
            continue
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
            CARGO_TARGET_DIR_NAME=target ./tools/build "-pg$pg" -profile "$rust_release" install || { echo "failed toolkig build for pg$pg, $pkg-$version"; exit 1; }
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
    local rust_release cargo_pgrx_version="$1" version="$2" pg pkg=promscale dpkg deb_version unsupported_reason pgrx_cmd
    [ -n "$RUST_RELEASE" ] && rust_release=-r || rust_release=""
    pgrx_cmd="$(cargo_pgrx_cmd "$cargo_pgrx_version")"

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
            [[ "$DRYRUN" = true ]] && { log "would install debian package $dpkg-$deb_version (cargo-$pgrx_cmd: $cargo_pgrx_version)"; continue; }
            if install_deb "$dpkg" "$deb_version"; then continue; fi
            log "failed installing $dpkg $deb_version"
        else
            log "couldn't find debian package for promscale-extension-postgresql-$pg $version"
        fi

        log "building $pkg version $version for pg$pg (cargo-$pgrx_cmd: $cargo_pgrx_version)"

        [ "$DRYRUN" = true ] && continue

        PATH="/usr/lib/postgresql/$pg/bin:${ORIGINAL_PATH}"
        cargo_pgrx_init "$cargo_pgrx_version" "$pg" || continue
        git_clone https://github.com/timescale/promscale_extension.git $pkg || continue
        git_checkout $pkg "$version" || continue
        (
            cd /build/$pkg || exit 1
            cp templates/promscale.control ./promscale.control
            cargo "$pgrx_cmd" install ${rust_release} --features "pg$pg" || { echo "failed cargo $pgrx_cmd install for pg$pg, $pkg-$version"; exit 1; }
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
