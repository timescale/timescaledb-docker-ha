\set patroni    `patroni --version | awk '{print $2}'`
\set pgbackrest `pgbackrest version  | awk '{print $2}'`

WITH versions(name, version) AS (
    SELECT
        name,
        default_version
    FROM
        pg_available_extensions
    WHERE
        name IN ('timescaledb', 'postgis', 'pg_prometheus', 'timescale_prometheus_extra')
    UNION ALL
    SELECT
        'postgresql',
        format('%s.%s', (v::int/10000), (v::int%1000))
    FROM
        current_setting('server_version_num') AS sub(v)
    UNION ALL
    SELECT
        'patroni',
        :'patroni'
    UNION ALL
    SELECT
        'pgBackRest',
        :'pgbackrest'
)
SELECT
    jsonb_pretty(
        jsonb_object_agg(
            name,
            version
        )
    )
FROM
    versions;