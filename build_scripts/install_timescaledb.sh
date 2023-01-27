#!/bin/bash

set -e -o pipefail

if [ -z "$2" ]; then
    error "Usage: $0 PGVERSION [TSVERSION..]"
    exit 1
fi

PGVERSION="$1"
shift

log() {
    echo "$ARCH: $*" >&2
}

error() {
    echo "** $ARCH: ERROR: $* **" >&2
}

supported_timescaledb() {
    local pg="$1" ver="$2" major minor

    if [ "$pg" -lt 12 ]; then
        echo "timescaledb not supported in pg$pg (<12)"
        return
    fi

    if [ "$ver" = "main" ]; then
        # just attempt the build for main
        return
    fi

    major="$(echo "$ver" | cut -d. -f1)"
    minor="$(echo "$ver" | cut -d. -f2)"

    case "$pg" in
    15) if [[ "$major" -lt 2 || ( "$major" -eq 2 && "$minor" -lt 9 ) ]]; then
            echo "timescaledb-$ver not supported on pg15, requires 2.9+"
        fi;;

    14) if [[ "$major" -lt 2 || ( "$major" -eq 2 && "$minor" -lt 5 ) ]]; then
            echo "timescaledb-$ver not supported on pg14, requires 2.5+"
        fi;;

    13) if [ "$major" -lt 2 ]; then
            echo "timescaledb-$ver not supported on pg13, requires 2.0+"
        fi;;

    12) # pg12 builds all the versions
        ;;

    *) echo "timescaledb-$ver not supported on pg$pg, requires pg12+";;
    esac
}

export PATH="/usr/lib/postgresql/${PGVERSION}/bin:${PATH}"

if [ -n "$OSS_ONLY" ]; then
    log "building timescaledb for OSS_ONLY"
    OSS_ONLY="-DAPACHE_ONLY=1"
else
    OSS_ONLY=""
fi

for TAG in "$@"; do
    git reset HEAD --hard
    git checkout "${TAG}"
    git clean -f -d -x

    MAJOR_MINOR="$(awk '/^version/ {print $3}' version.config | cut -d. -f1,2)"

    if [ "${TAG}" = "2.2.0" ]; then sed -i 's/RelWithDebugInfo/RelWithDebInfo/g' CMakeLists.txt; fi

    unsupported_reason="$(supported_timescaledb "$PGVERSION" "${MAJOR_MINOR}")"
    if [ -n "$unsupported_reason" ]; then
        error "$unsupported_reason"
        continue
    fi

    ./bootstrap \
        -DTAP_CHECKS=OFF \
        -DWARNINGS_AS_ERRORS=off \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DREGRESS_CHECKS=OFF \
        -DGENERATE_DOWNGRADE_SCRIPT=ON \
        -DPROJECT_INSTALL_METHOD="${INSTALL_METHOD}" \
        ${OSS_ONLY}

    cd build

    make

    # https://github.com/timescale/timescaledb/commit/531f7ed8b16e4d1a99021d3d2b843bbc939798e3
    if [ "${TAG}" = "2.5.2" ]; then sed -i 's/pg_temp./_timescaledb_internal./g' sql/**/*.sql; fi

    make install

    if [ -n "$OSS_ONLY" ]; then
        log "removing timescaledb-tsl due to OSS_ONLY"
        rm -f /usr/lib/postgresql/"$PGVERSION"/lib/timescaledb-tsl-*
    fi

    cd ..
done

# https://github.com/timescale/timescaledb/commit/6dddfaa54e8f29e3ea41dab2fe7d9f3e37cd3aae
for file in "/usr/share/postgresql/${PGVERSION}/extension/timescaledb--"*.sql; do
    cat >> "${file}" << "__SQL__"
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

done
