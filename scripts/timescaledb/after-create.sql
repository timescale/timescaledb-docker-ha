-- The pre_restore and post_restore function can only be successfully executed by a very highly privileged
-- user. To ensure the database owner can also execute these functions, we have to alter them
-- from SECURITY INVOKER to SECURITY DEFINER functions. Setting the search_path explicitly is good practice
-- for SECURITY DEFINER functions.
-- As this function does have high impact, we do not want anyone to be able to execute the function,
-- but only the database owner.
ALTER FUNCTION @extschema@.timescaledb_pre_restore() SET search_path = pg_catalog,pg_temp SECURITY DEFINER;
ALTER FUNCTION @extschema@.timescaledb_post_restore() SET search_path = pg_catalog,pg_temp SECURITY DEFINER;
REVOKE EXECUTE ON FUNCTION @extschema@.timescaledb_pre_restore() FROM public;
REVOKE EXECUTE ON FUNCTION @extschema@.timescaledb_post_restore() FROM public;
GRANT EXECUTE ON FUNCTION @extschema@.timescaledb_pre_restore() TO @database_owner@;
GRANT EXECUTE ON FUNCTION @extschema@.timescaledb_post_restore() TO @database_owner@;

-- To reduce the errors seen on pg_restore we grant access to timescaledb internal tables
DO $$DECLARE r record;
BEGIN
    FOR r IN SELECT tsch from unnest(ARRAY['_timescaledb_internal', '_timescaledb_config', '_timescaledb_catalog', '_timescaledb_cache']) tsch
        LOOP
            EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA ' ||  quote_ident(r.tsch) || ' GRANT ALL PRIVILEGES ON TABLES TO @database_owner@';
            EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA ' ||  quote_ident(r.tsch) || ' GRANT ALL PRIVILEGES ON SEQUENCES TO @database_owner@';
            EXECUTE 'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ' ||  quote_ident(r.tsch) || ' TO @database_owner@';
            EXECUTE 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ' ||  quote_ident(r.tsch) || ' TO @database_owner@';
            EXECUTE 'GRANT USAGE, CREATE ON SCHEMA ' ||  quote_ident(r.tsch) || ' TO @database_owner@';
        END LOOP;
END$$;

