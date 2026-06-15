-- rest_compile_api_token_only.sql
-- Run this instead of rest_compile_api_client.sql when you do NOT want OAuth.
-- No role, no privilege, no OAuth client is created.
-- Copy the printed REST_CLIENT_TOKEN value into apply.env and set REST_USES_OAUTH=FALSE.
-- To remove an existing ORDS privilege that would otherwise block requests, run
-- disable_oauth_protection.sql beforehand.
declare
  l_workspace    varchar2(200);
  l_client_token varchar2(64);
begin
  select workspace
    into l_workspace
    from apex_workspaces
   where rownum = 1;

  select lower(rawtohex(
             standard_hash(
                 nvl(apex_mail.get_instance_url(), '') ||
                 '|' ||
                 sys_context('USERENV', 'SESSION_USER') ||
                 '|' ||
                 l_workspace,
                 'SHA256'
             )
         ))
    into l_client_token
    from dual;

  dbms_output.put_line('# put the following lines into apply.env and modify URL if needed');
  dbms_output.put_line('REST_SQL_URL="'||apex_mail.get_instance_url||lower(l_workspace)||'/dbflow/deploy"');
  dbms_output.put_line('REST_CLIENT_TOKEN="'||l_client_token||'"');
  dbms_output.put_line('REST_USES_OAUTH=FALSE');
end;
/
