set define '^'
set concat on
set concat .
set verify off

@../env.sql

-------------------------------------------------------------------------------------

PROMPT  =============================================================================
PROMPT  ==   CREATE APEX User wsadmin
PROMPT  =============================================================================
PROMPT


PROMPT Change session to APEX_USER
ALTER SESSION SET CURRENT_SCHEMA = ^apex_user;
set serveroutput on

Declare
  v_workspace_id number;
Begin
  select to_char(workspace_id)
    into v_workspace_id
    from apex_workspaces
   where workspace = upper('^workspace');

  apex_util.set_security_group_id (p_security_group_id => v_workspace_id);
  if apex_util.is_username_unique(p_username => 'wsadmin') then
    apex_util.create_user(p_user_name                     => 'wsadmin',
                          p_first_name                    => '',
                          p_last_name                     => '',
                          p_description                   => '',
                          p_email_address                 => '',
                          p_web_password                  => 'wsadmin',
                          p_developer_privs               => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
                          p_default_schema                => upper('^app_schema'),
                          p_allow_access_to_schemas       => NULL,
                          p_change_password_on_first_use  => 'Y');
    commit;
  else
    dbms_output.put_line('User wsadmin allready exists in workspace');
  end if;

End;
/