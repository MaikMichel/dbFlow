set define '^'
set concat on
set concat .
set verify off

@../env.sql

-------------------------------------------------------------------------------------
PROMPT  =============================================================================
PROMPT  ==   CREATE SMTP ACL
PROMPT  =============================================================================
PROMPT


begin
  sys.dbms_network_acl_admin.append_host_ace(
    host        => '*'
   ,lower_port  => 25
   ,upper_port  => 25
   ,ace         => xs$ace_type(
      privilege_list     => xs$name_list('CONNECT')
     ,granted            => true
     ,principal_name     => '^apex_user'
     ,principal_type     => XS_ACL.PTYPE_DB
    )
  );
end;
/