declare
  C_CLIENT_NAME   varchar2(100) := 'DBFLOW_REST_COMPILE_API_CLIENT';
  l_client_row    user_ords_clients%rowtype;
  
  l_client_id     varchar2(200);
  l_client_secret varchar2(200);
  l_exists        number;

begin
  select count(*)
    into l_exists
    from user_ords_clients
   where name = C_CLIENT_NAME;

  if l_exists = 0 then 
    oauth.create_client(
      p_name            => C_CLIENT_NAME,
      p_grant_type      => 'client_credentials',
      p_owner           => 'Maik',
      p_description     => 'Internal API client to use with dbFlow',
      p_support_email   => 'maik.michel@oracle.com',
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

  dbms_output.put_line('# put the following lines into apply.env and modify URL accordingly');
  dbms_output.put_line('REST_OAUTH_TOKEN_URL="<< HOST to ORDS (https://localhost:8080/ords/) >> '||lower(user)||'/oauth/token"');
  dbms_output.put_line('REST_OAUTH_CLIENT_ID="'||l_client_row.client_id||'"');
  dbms_output.put_line('REST_OAUTH_CLIENT_SECRET="'||l_client_row.client_secret||'"');
end;
/

-- select client_id, client_secret
--   from   user_ords_clients
--  where name = 'DBFLOW_REST_COMPILE_API_CLIENT';

--  curl -i -k --user xIGpIqNAq6p6KVGnC92bJA..:IU5EFPWsi2mQbciHyd_fxg.. --data "grant_type=client_credentials" https://localhost:8006/ords/ati/oauth/token