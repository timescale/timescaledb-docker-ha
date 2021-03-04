\set patroni    `patroni --version | awk '{print $2}'`
\set pgbackrest `pgbackrest version  | awk '{print $2}'`

WITH versions(name, version) AS (
    SELECT
        format('%s.version', name),
        default_version
    FROM
        pg_available_extensions
    WHERE
        name IN ('timescaledb', 'postgis', 'pg_prometheus', 'timescale_prometheus_extra', 'promscale')
    UNION ALL
    SELECT
        'postgresql.version',
        format('%s.%s', (v::int/10000), (v::int%1000))
    FROM
        current_setting('server_version_num') AS sub(v)
    UNION ALL
    SELECT
        'patroni.version',
        :'patroni'
    UNION ALL
    SELECT
        'pgBackRest.version',
        :'pgbackrest'
    UNION ALL
    SELECT
        'timescaledb.available_versions',
        string_agg(version, ',' ORDER BY version)
    FROM
        pg_available_extension_versions
    WHERE
        name = 'timescaledb'
)
SELECT
    format('%s=%s', name, version)
FROM
    versions;