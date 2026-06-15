-- disable_oauth_protection.sql
-- Run this script when you want to operate without OAuth (REST_USES_OAUTH=FALSE).
--
-- After execution, the /dbflow/deploy/* endpoints are no longer protected by the
-- ORDS privilege layer.  Security is then provided exclusively by the
-- x-dbflow-token request header checked inside the rest_compile package.
--
-- Set REST_USES_OAUTH=FALSE and REST_CLIENT_TOKEN=<value from rest_compile_api_client.sql>
-- in apply.env, and remove or leave blank REST_OAUTH_TOKEN_URL / REST_OAUTH_BASIC_B64.
begin
    begin
        ords.delete_privilege('DBFLOW_REST_COMPILE_API_PRIV');
    exception when others then null; end;
    begin
        ords.delete_role('DBFLOW_REST_COMPILE_API_ROLE');
    exception when others then null; end;
    commit;
end;
/
