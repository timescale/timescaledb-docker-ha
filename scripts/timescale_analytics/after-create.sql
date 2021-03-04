
GRANT USAGE ON SCHEMA timescale_analytics_experimental TO @database_owner@;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA timescale_analytics_experimental TO @database_owner@;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA timescale_analytics_experimental TO @database_owner@;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA timescale_analytics_experimental TO @database_owner@;

DO LANGUAGE plpgsql
$$
BEGIN
RAISE NOTICE 'features in timescale_analytics_experimental are unstable, and objects depending on them (views, tables, continuous aggregates, etc.) will be deleted on extension update (there will be a DROP SCHEMA timescale_analytics_experimental CASCADE), which on can happen at any time.';
END;
$$;