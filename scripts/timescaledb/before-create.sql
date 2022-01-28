-- Check if one of the timescaledb schemas are present in the database, while the extension is missing
-- Note: this list assumes any new schemas added to the extension should be present here as well.
DO $$
BEGIN
    IF EXISTS(
        SELECT
            1
        FROM
            pg_catalog.pg_namespace
        WHERE nspname IN (
            '_timescaledb_catalog',
            '_timescaledb_internal'
            '_timescaledb_cache',
            '_timescaledb_config',
            'timescaledb_experimental',
            'timescaledb_information'
        )
        AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'timescaledb')
    )
    THEN
        RAISE EXCEPTION 'Internal timescaledb schemas are present in the database, but timescaledb extension is missing'
            USING HINT = 'Please, drop those schemas before installing timescaledb extension';
    END IF;
END
$$;
