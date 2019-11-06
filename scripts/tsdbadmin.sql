set log_statement=none; set log_min_duration_statement=-1; BEGIN;
-- Source: sql/00_preparation.sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO LANGUAGE plpgsql
$$
BEGIN
    IF to_regrole('tsdbowner') IS NULL
    THEN
        CREATE ROLE tsdbowner NOLOGIN;
    END IF;
    IF to_regrole('tsdbadmin') IS NULL
    THEN
        CREATE ROLE tsdbadmin;
    END IF;
    GRANT tsdbowner TO tsdbadmin WITH admin option;
END;
$$;

CREATE SCHEMA IF NOT EXISTS tsdbadmin AUTHORIZATION tsdbowner;

-- Default privileges for public are quite liberal in PostgreSQL, therefore
-- we revoke USAGE from public on the schema
-- (comparable to the execute bit on a directory on a UNIX system).
-- The second barrier is to ensure that functions that are created are not
-- allowed to be executed by public, but only by roles that have been (indirectly)
-- granted the tsdb_administrator role.
REVOKE USAGE ON SCHEMA tsdbadmin FROM public;
ALTER DEFAULT PRIVILEGES IN SCHEMA tsdbadmin REVOKE ALL ON FUNCTIONS FROM public;
ALTER DEFAULT PRIVILEGES IN SCHEMA tsdbadmin GRANT EXECUTE ON FUNCTIONS TO tsdbadmin;
-- Source: sql/10_assert_admin.sql
/*
assert_admin will do nothing if the current role is directly or indirectly
a grantee of the username role with the admin option. Otherwise it will raise an exception.

The reason to use exceptions here is to offer a similar user experience to the regular
way of administrating users, i.e. DROP USER abc normally raises a sqlstate 42501 and
the application can handle that error. The same goes with these functions, they will throw
the permission denied error.
*/
CREATE OR REPLACE FUNCTION tsdbadmin.assert_admin(
    username name
)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    -- We need to ensure we get the correct role. As we may be called from Security Definer functions, we should
    -- be looking at the session_user, however, if that has been overruled by a SET ROLE, we should take
    -- the current role.
    admin_role name := cast(CASE current_setting('role') WHEN 'none' THEN session_user ELSE current_setting('role')::name END AS name);
BEGIN
    -- This will fail fast if the username does not exist
    PERFORM cast(username as regrole);

    -- A superuser is allowed to do everything, so we'll just allow it outright in that situation
    IF (SELECT rolsuper FROM pg_roles WHERE rolname = admin_role)
    THEN
        RETURN;
    END IF;

    /*
     We should never assert admin over a superuser or a createrole if we're not a superuser.

     This is purely a second line of defense - the user to be administered should never have
     superuser, but errors can be made, for example:
        tsdbadmin was granted a role with the superuser attribute
        a role that is managed by tsdbadmin was inadvertently given the createrole attribute

    The exploit would that you could then reset the password for such a user and therefore authenticate
    using that user and set/exploit the superuser/createrole for your own (limited) account.

    Therefore we are explicit about rejecting asserting admin
    over any role with the superuser or createrole attributes.
    */
    IF (SELECT rolsuper or rolcreaterole FROM pg_roles WHERE rolname = username)
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'must be superuser to alter superusers/createrole users';
    END IF;

    -- We want to find out if the user that is going to be created/altered/dropped is allowed to be
    -- administered by the admin_role.
    -- We allow this to be the case if admin_role has been granted username (WITH ADMIN OPTION),
    -- or if there exists a chain of grants WITH ADMIN that lead to the admin_role.
    -- To accomplish this, we use a recursive query, which walks through all the roles that
    -- have received the grants.
    -- The final step of the query is to figure out if admin_role is actually in this generated list.
    --
    -- Note: PostgreSQL itself does not allow recursive grants, so this recursive CTE
    -- construct is guaranteed to be finite.
    IF EXISTS (
        WITH RECURSIVE admin_parents AS (
            SELECT
                member
            FROM
                pg_auth_members
            WHERE
                roleid = username::regrole
                AND admin_option = true
            UNION ALL
            SELECT
                grandparent.member
            FROM
                pg_auth_members grandparent
            JOIN
                admin_parents ON (grandparent.roleid = admin_parents.member)
                AND grandparent.admin_option = true
        )
        SELECT
        FROM
            admin_parents
        WHERE
            member = admin_role::regrole)
    THEN
        RETURN;
    END IF;

    -- We raise an exception by default, to ensure whatever the flow is, if we get to this part of the function
    -- no assertion should succeed.
    RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = format('user %s does not have admin option on role "%s"', admin_role::regrole::text, username);
END;
$function$;
-- Source: sql/11_assert_password_requirements.sql
/*
The reason to use exceptions here is to offer a similar user experience to the regular
way of enforcing password requirements, for example when using the passwordcheck
extension, you'll get the following error:

ERROR:  22023: password is too short

*/
CREATE OR REPLACE FUNCTION tsdbadmin.assert_password_requirements(
    password text
)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
 SET log_statement TO 'none' -- We do not want any function handling passwords to be logged
AS $function$
DECLARE
    error_message text;
    sqlstate_code text;
    minimum_password_length int := 8;
BEGIN
    IF length(password) < minimum_password_length
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '28LEN',
            MESSAGE = format('New password has length %s, minimum length is %s', length(password), minimum_password_length);
    END IF;
EXCEPTION WHEN OTHERS THEN
-- We want to rethrow errors that occured, but we want to remove the context,
-- as the context may contain the password, so we rethrow without that context.
    GET STACKED DIAGNOSTICS
        error_message  = MESSAGE_TEXT,
        sqlstate_code = RETURNED_SQLSTATE;
    RAISE EXCEPTION USING
        ERRCODE = sqlstate_code,
        MESSAGE = error_message;
END;
$function$;
-- Source: sql/30_reset_password.sql
CREATE OR REPLACE FUNCTION tsdbadmin.reset_password(
    INOUT username name,
    INOUT password text DEFAULT NULL,
    password_length integer DEFAULT NULL,
    password_encryption text DEFAULT NULL
)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET log_statement TO 'none' -- We do not want any function handling passwords to be logged
AS $function$
DECLARE
    minimum_password_length int := 8;
    error_message text;
    sqlstate_code text;
    prev_password_encryption text;
BEGIN
    PERFORM tsdbadmin.assert_admin(username);

    -- We're only setting the defaults here, to allow upstream function calls to
    -- use NULL as a signal to use the default values
    password_length := coalesce(password_length, 16);

    IF password IS NULL
    THEN
        SELECT substr(encode(random_bytes, 'base64'), 1, password_length)
          INTO password
          FROM gen_random_bytes(1024) AS s(random_bytes);
    END IF;

    PERFORM tsdbadmin.assert_password_requirements(password);

    prev_password_encryption := current_setting('password_encryption');
    password_encryption := coalesce(password_encryption, prev_password_encryption);
    PERFORM set_config('password_encryption'::text, password_encryption, true);

    EXECUTE format('ALTER USER %I WITH ENCRYPTED PASSWORD %L', username, password);

    PERFORM set_config('password_encryption'::text, prev_password_encryption, true);

EXCEPTION WHEN OTHERS THEN
-- We want to rethrow errors that occured, but we want to remove the context,
-- as the context may contain the password, so we rethrow without that context.
    GET STACKED DIAGNOSTICS
        error_message = MESSAGE_TEXT,
        sqlstate_code = RETURNED_SQLSTATE;
    RAISE EXCEPTION USING
        ERRCODE = sqlstate_code,
        MESSAGE = error_message;
END;
$function$;

DO LANGUAGE plpgsql
$$
DECLARE
    pgcrypto_namespace oid := (SELECT extnamespace FROM pg_extension WHERE extname='pgcrypto');
BEGIN
    EXECUTE format('ALTER FUNCTION tsdbadmin.reset_password SET search_path TO pg_catalog, %s;', pgcrypto_namespace::regnamespace);

    /* We ensure the dependency we created on pgcrypto.gen_random_bytes is part of the catalogs

    ERROR:  2BP01: cannot drop extension pgcrypto because other objects depend on it
    DETAIL:  function reset_password(name,text,integer,text) depends on function pgcrypto.gen_random_bytes(integer)

    */
    INSERT INTO pg_catalog.pg_depend (classid, objid, objsubid, refclassid, refobjid, refobjsubid, deptype)
    SELECT
        'pg_catalog.pg_proc'::regclass,
        'tsdbadmin.reset_password'::regproc,
        0,
        'pg_catalog.pg_proc'::regclass,
        format('%s.gen_random_bytes', pgcrypto_namespace::regnamespace)::regproc,
        0,
        'n'
    ;
END;
$$;
-- Source: sql/33_alter_user.sql
CREATE OR REPLACE FUNCTION tsdbadmin.alter_user(
    INOUT username name,
    createdb boolean DEFAULT NULL,
    inherit boolean DEFAULT NULL,
    login boolean DEFAULT NULL,
    connection_limit boolean DEFAULT NULL,
    valid_until timestamp with time zone DEFAULT NULL,
    new_name name DEFAULT NULL,
    password text DEFAULT NULL,
    password_encryption text DEFAULT NULL
)
 RETURNS name
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET log_statement TO 'none' -- We do not want any function handling passwords to be logged
AS $function$
DECLARE
    error_message text;
    sqlstate_code text;
    statement text;
    role_r pg_catalog.pg_roles;
BEGIN
    PERFORM tsdbadmin.assert_admin(username);

    -- Changing a username clears any md5 passwords, therefore
    -- we should change the username before setting a potentially new password
    IF new_name IS NOT NULL AND new_name != username
    THEN
        EXECUTE format('ALTER USER %I RENAME TO %I', username, new_name);
        username := new_name;
    END IF;

    IF password IS NOT NULL THEN
        PERFORM tsdbadmin.reset_password(username, password, password_encryption => password_encryption);
    END IF;

    EXECUTE format('ALTER USER %I WITH %s %s %s %s %s',
                username,
                CASE WHEN createdb    THEN 'CREATEDB' WHEN NOT createdb THEN 'NOCREATEDB' END,
                CASE WHEN inherit     THEN 'INHERIT'  WHEN NOT inherit  THEN 'NOINHERIT'  END,
                CASE WHEN login       THEN 'LOGIN'    WHEN NOT login    THEN 'NOLOGIN'    END,
                CASE WHEN connection_limit IS NOT NULL THEN format('CONNECTION LIMIT %s', connection_limit) END,
                CASE WHEN valid_until IS NOT NULL THEN format('VALID UNTIL %L', valid_until) END);

EXCEPTION WHEN OTHERS THEN
-- We want to rethrow errors that occured, but we want to remove the context,
-- as the context may contain the password, so we rethrow without that context.
    GET STACKED DIAGNOSTICS
        error_message = MESSAGE_TEXT,
        sqlstate_code = RETURNED_SQLSTATE;
    RAISE EXCEPTION USING
        ERRCODE = sqlstate_code,
        MESSAGE = error_message;
END;
$function$;


DO $$
BEGIN
    IF true != null THEN
        RAISE NOTICE 'test';
    END IF;
END;
$$;
-- Source: sql/36_create_user.sql
CREATE OR REPLACE FUNCTION tsdbadmin.create_user(
    INOUT username name,
    createdb boolean DEFAULT false,
    inherit boolean DEFAULT true,
    login boolean DEFAULT true,
    connection_limit boolean DEFAULT NULL,
    valid_until timestamp with time zone DEFAULT NULL,
    if_not_exists boolean DEFAULT false,
    INOUT password text DEFAULT NULL,
    password_length integer DEFAULT 16,
    password_encryption text DEFAULT NULL,
    OUT created boolean
)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET log_statement TO 'none' -- We do not want any function handling passwords to be logged
AS $function$
DECLARE
    error_message text;
    sqlstate_code text;
BEGIN
    created := false;
    IF to_regrole(username) IS NULL OR if_not_exists = false
    THEN
        EXECUTE format('CREATE USER %I', username);
        EXECUTE format('GRANT %I TO %I WITH ADMIN OPTION', username, CASE current_setting('role') WHEN 'none' THEN session_user ELSE current_setting('role') END);
        SELECT rp.password
          INTO password
          FROM tsdbadmin.reset_password(username, password, password_length => password_length, password_encryption => password_encryption) AS rp;
        created := true;
    ELSIF password IS NOT NULL
    THEN
        SELECT rp.password
          INTO password
          FROM tsdbadmin.reset_password(username, password, password_encryption => password_encryption) AS rp;
    END IF;

    PERFORM tsdbadmin.alter_user(
        username => username,
        password => null,
        createdb => createdb,
        inherit => inherit,
        login => login,
        connection_limit => connection_limit,
        valid_until => valid_until
    );
EXCEPTION WHEN OTHERS THEN
-- We want to rethrow errors that occured, but we want to remove the context,
-- as the context may contain the password, so we rethrow without that context.
    GET STACKED DIAGNOSTICS
        error_message = MESSAGE_TEXT,
        sqlstate_code = RETURNED_SQLSTATE;
    RAISE EXCEPTION USING
        ERRCODE = sqlstate_code,
        MESSAGE = error_message;
END;
$function$;
-- Source: sql/38_drop_user.sql
CREATE OR REPLACE FUNCTION tsdbadmin.drop_user(
    INOUT username name,
    if_exists boolean DEFAULT false
)
 RETURNS name
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path to 'pg_catalog'
AS $function$
BEGIN
    IF if_exists AND to_regrole(username) IS NULL
    THEN
        RAISE NOTICE USING
            ERRCODE = '00000',
            MESSAGE = format('role "%s" does not exist, skipping', username);
        RETURN;
    END IF;

    PERFORM tsdbadmin.assert_admin(username);

    EXECUTE format('DROP USER %I', username);
END;
$function$
;
COMMENT ON SCHEMA tsdbadmin IS $comment$
# tsdbadmin

tsdbadmin allows users to create, alter and drop users in a PostgreSQL instance.
It does so by providing some utility functions in the `postgres` database.

This can also be achieved by giving the user the `CREATEROLE` privilege, however
that privilege extends to *all roles* that are not `superuser` roles,
which does not allow for very fine-grained control over roles and users.

By using these functions, any user that has the `tsdbowner` role granted,
will be able to:

* Create new roles
* Alter roles that it created*
* Drop roles that it created*

*: Or have been created by a role that it created, recursively

This in turn allows you to delegate the management of roles to separate users,
without them being able to manage each others roles.

# Functions
These functions allow you to fully administer your roles.

* [alter_user](#alter_user)
* [create_user](#create_user)
* [drop_user](#drop_user)
* [reset_password](#reset_password)

And these functions are utility functions that are also installed:

* [assert_admin](#assert_admin)
* [assert_password_requirements](#assert_password_requirements)

# User facing functions

## alter_user()
alter_user changes the attributes of a PostgreSQL role.

Users can only alter those users for which they have been granted the
`WITH ADMIN OPTION` in a particular way.
When users are created using the [create_user](#create_user) function, the
`WITH ADMIN OPTION` is automatically granted to the creator.

For example, user `grandparent` has created the user `child1` and `child2` using
the `create_user` function.
Afterwards, `child1` has created the user `grandchild1` and `child2` has created
the user `grandchild2`.

* `grandchild1` can now be altered by both `parent1` and `grandparent`
* `grandchild2` can now be altered by both `parent2` and `grandparent`
* `grandchild1` cannot be altered by `parent2`
* `grandchild2` cannot be altered by `parent1`

### Arguments
| Name | Description | Example | Default |
|:--|:--|:--|:--|
| username | User or role name to be altered | `jdoe` | |
| createdb  | `CREATEDB` parameter¹ | `false` | `NULL` (no change) |
| inherit  |  `INHERIT` parameter¹ | `true` | `NULL` (no change) |
| login  |  `LOGIN` parameter¹ | `true` | `NULL` (no change) |
| connection_limit | `CONNECTION LIMIT` parameter¹ | `10` | `NULL` (no change) |
| valid_until | `VALID UNTIL` parameter¹ | `2020-02-01 10:00` | `NULL` (no change) |
| new_name | rename to `new_name`¹ | `johndoe` | `NULL` (no change) |
| password | `PASSWORD` parameter¹ | `g6yuAFCz9Yv5ZMA` | `NULL` (no change) |
| password_encryption | The hashing algorithm² | `scram-sha-256` | `NULL` (default) |

1. [ALTER ROLE](https://www.postgresql.org/docs/current/sql-alterrole.html) documentation
2. [password_encryption](
https://www.postgresql.org/docs/current/runtime-config-connection.html#GUC-PASSWORD-ENCRYPTION)
documentation

### Return value
| Name | Description | Example |
|:--|:--|:--|
| username | The user that was altered | `johndoe` |

### Alter User Examples

**Allow `jdoe` to create databases**
```sql
SELECT * FROM tsdbadmin.alter_user('jdoe', createdb => true);
```
**Rename `jdoe` to `johndoe`**
```sql
SELECT * FROM tsdbadmin.alter_user('jdoe', new_name => 'johndoe');
```

## create_user()
create_user adds a new role to a PostgreSQL database cluster.

Every user that has privileges to execute `create_user` can create new database
roles. Roles created through this function are granted with the [admin option]
(https://www.postgresql.org/docs/current/sql-grant.html#SQL-GRANT-DESCRIPTION-ROLES)
to the creator.

If no password is provided, a new password will be generated using the
[reset_password](#reset_password) function.

### Arguments
| Name | Description | Example | Default |
|:--|:--|:--|:--|
| username | User or role name to be altered | `jdoe` | |
| createdb  | `CREATEDB` parameter¹ | `true` | `false` |
| inherit  |  `INHERIT` parameter¹ | `false` | `true` |
| login  |  `LOGIN` parameter¹ | `false` | `false`
| connection_limit | `CONNECTION LIMIT` parameter¹ | `10` | `NULL` (no limit) |
| valid_until | `VALID UNTIL` parameter¹ | `2020-02-01` | `NULL` (no limit) |
| if_not_exists | If set, does not raise error if user exists | `true` | `false` |
| password | `PASSWORD` parameter¹ | `g6yuAFCz9Yv5ZMA` | `NULL` (auto-generate) |
| password_length | Set length of auto-generated password | 32 | 16 |
| password_encryption | The hashing algorithm² | `scram-sha-256` | `NULL` (default) |

1. [CREATE ROLE](https://www.postgresql.org/docs/current/sql-createrole.html)
documentation
2. [password_encryption](
https://www.postgresql.org/docs/current/runtime-config-connection.html#GUC-PASSWORD-ENCRYPTION)
documentation

### Return values
| Name | Description | Example |
|:--|:--|:--|
| username | The user that was created | `johndoe` |
| password | The password that was set for this user | `lY0WYsa3KI00Myg` |

## drop_user()

drop_user removes the specified role.

Users can only drop those users for which they have been granted the
`WITH ADMIN OPTION` in a particular way.
When users are created using the [create_user](#create_user) function, the
`WITH ADMIN OPTION` is automatically granted to the creator.

### Arguments
| Name | Description | Example | Default |
|:--|:--|:--|:--|
| username | User or role name to be dropped | `jdoe` | |
| if_exists | If set, does not raise error if user does not exist | `true` | `false` |

### Return value
| Name | Description | Example |
|:--|:--|:--|
| username | The user that was dropped | `jdoe` |

## reset_password()

reset_password changes the password of the specified user. If no password is specified,
it will auto-generate one.

The context of the `ALTER ROLE` statement that will (re)set the password is changed so
that the statement containing the password will not be logged, regardless of the
current session value of the[`log_statement`](
https://www.postgresql.org/docs/current/runtime-config-logging.html#GUC-LOG-STATEMENT)
parameter.

This function relies on the `gen_random_bytes`
function of the [`pgcrypto`](https://www.postgresql.org/docs/current/pgcrypto.html)
extension to generate new passwords, which is documented to generate cryptographically
strong random bytes.

The currently supported 
### Arguments
| Name | Description | Example | Default |
|:--|:--|:--|:--|
| username | User or role name to be dropped | `jdoe` | |
| password | If set, set this password | `g6yuAFCz9Yv5ZMA` | `NULL` (auto-generate) |
| password_length | Set length of auto-generated password | 32 | 16 |
| password_encryption | The hashing algorithm¹ | `scram-sha-256` | `NULL` (default) |

1. [password_encryption](
https://www.postgresql.org/docs/current/runtime-config-connection.html#GUC-PASSWORD-ENCRYPTION)
documentation

### Return values
| Name | Description | Example |
|:--|:--|:--|
| username | The user that was created | `johndoe` |
| password | The password that was set for this user | `lY0WYsa3KI00Myg` |

### Reset Password examples

**Generate new password for jdoe**
```sql
SELECT * FROM tsdbadmin.reset_password('jdoe');
```
**Set new password for jdoe**
```sql
SELECT * FROM tsdbadmin.reset_password('jdoe', password => 'ThisIsNotAStrongPassword');
```

**Reset password for jdoe, with `md5` hashing algorithm**
```sql
SELECT * FROM tsdbadmin.reset_password('jdoe', password_encryption => 'md5');
```

# Utility functions

## assert_admin()

> WARNING: This function does not return a value, on assertion failure it raises an exception.

assert_admin will do nothing if the current role is directly or indirectly a grantee
of the `username` role with the admin option. Otherwise it will raise an exception.

### Arguments
| Name | Description | Example | Default |
|:--|:--|:--|:--|
| username | User or role name to be verified | `jdoe` | |

### Assert Admin Examples

* Role `grandparent` is member `WITH ADMIN` of `parent`
* Role `grandparent` is member `WITH ADMIN` of `aunt`
* Role `parent` is member `WITH ADMIN` of `child`

**`grandparent` is admin of `child`**
```sql
SET ROLE 'grandparent';
SELECT tsdbadmin.assert_admin('child');
 assert_admin 
--------------
 
(1 row)
```

**`aunt` is not admin of `child`**
```sql
SET ROLE 'aunt';
SELECT tsdbadmin.assert_admin('child');
ERROR:  user aunt does not have admin option on role "child"
```

## assert_password_requirements()

> WARNING: This function does not return a value, on assertion failure it raises an exception.

assert_password_requirements will do nothing if the password passes validation, it will
raise an exception otherwise.

Currently implemented requirements:

1. Password Length should be 8 characters or more

### Arguments
| Name | Description | Example | Default |
|:--|:--|:--|:--|
| password | The password to verify | `ttd8FXLMCKatAfl` | |
$comment$;
COMMIT;
