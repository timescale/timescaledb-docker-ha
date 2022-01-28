-- Get all triggers that are not internal foreign key constraint triggers on timescale dependent schemas.
-- Note: this list assumes any new schemas added to the extension should be present here as well.
DO $$
    BEGIN
        IF EXISTS(
                WITH depschemas AS
                 (
                     SELECT
                         dep.objid
                     FROM
                         pg_catalog.pg_depend dep
                             JOIN
                         pg_extension ext
                         ON (dep.refobjid = ext.oid)
                     WHERE
                             dep.deptype = 'e'
                       AND classid = 2615
                       AND ext.extname = 'timescaledb'
                 )
                SELECT
                    1
                FROM
                    pg_catalog.pg_class cl
                        JOIN depschemas ON (cl.relnamespace = depschemas.objid)
                        JOIN pg_catalog.pg_trigger tg ON (cl.oid = tg.tgrelid)
                        JOIN pg_catalog.pg_proc fn ON (tg.tgfoid = fn.oid)
                WHERE
                        tg.tgisinternal = 'f' OR fn.prolang != 12
            )
        THEN
            RAISE EXCEPTION 'User-defined triggers are defined on tables in one of the internal timescaledb schemas.'
                USING HINT = 'Please, drop those triggers before updating timescaledb extension';
        END IF;
    END
$$;
