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

