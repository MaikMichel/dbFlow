declare
  C_CLIENT_NAME   varchar2(100) := 'DBFLOW_REST_COMPILE_API_CLIENT';
  l_client_row    user_ords_clients%rowtype;
  l_exists        number;
  l_workspace     varchar2(200);
  l_basic_plain   varchar2(4000);
  l_basic_b64     varchar2(4000);
  l_client_token  varchar2(64);
begin
  select count(*)
    into l_exists
    from user_ords_clients
   where name = C_CLIENT_NAME;

  if l_exists = 0 then 
    oauth.create_client(
      p_name            => C_CLIENT_NAME,
      p_grant_type      => 'client_credentials',      
      p_description     => 'Internal API client to use with dbFlow',
      p_support_email   => v('APP_USER'),        
      p_privilege_names => 'DBFLOW_REST_COMPILE_API_PRIV'
    );

    oauth.grant_client_role(
      p_client_name => C_CLIENT_NAME,
      p_role_name   => 'DBFLOW_REST_COMPILE_API_ROLE'
    );

    commit;
  end if;

  select *
    into l_client_row
    from user_ords_clients 
   where name = C_CLIENT_NAME; 

  select workspace 
    into l_workspace
    from APEX_WORKSPACES 
   where rownum = 1; 

  l_basic_plain := l_client_row.client_id || ':' || l_client_row.client_secret;
  l_basic_b64 := utl_raw.cast_to_varchar2(
    utl_encode.base64_encode(
      utl_i18n.string_to_raw(l_basic_plain, 'AL32UTF8')
    )
  );
  l_basic_b64 := replace(replace(l_basic_b64, chr(10), ''), chr(13), '');

  -- Compute client token using the same formula as the package body initialisation.
  -- This value must be set as REST_CLIENT_TOKEN in apply.env.
  select lower(rawtohex(
             standard_hash(
                 sys_context('USERENV', 'CURRENT_USER') ||
                 '|' ||
                 l_workspace,
                 'SHA256'
             )
         ))
    into l_client_token
    from dual;

  dbms_output.put_line('# put the following lines into apply.env and modify URL if needed');
  dbms_output.put_line('REST_SQL_URL="'||apex_mail.get_instance_url||lower(l_workspace)||'/dbflow/deploy"');
  dbms_output.put_line('REST_OAUTH_TOKEN_URL="'||apex_mail.get_instance_url||lower(l_workspace)||'/oauth/token"');
  dbms_output.put_line('REST_OAUTH_BASIC_B64="'||l_basic_b64||'"');
  dbms_output.put_line('REST_CLIENT_TOKEN="'||l_client_token||'"');
  dbms_output.put_line('REST_USES_OAUTH=TRUE');
end;
/

