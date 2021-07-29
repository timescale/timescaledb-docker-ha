-- This is a very low level smoke test to see if installing extensions does not 
-- throw an error
\set ECHO queries
SELECT
    format('CREATE EXTENSION %I', name)
FROM
    pg_catalog.pg_available_extensions
WHERE
    name IN ('timescaledb')
\gexec
