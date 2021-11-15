set define '^'
set concat on
set concat .
set verify off

@../env.sql

-------------------------------------------------------------------------------------
PROMPT  =============================================================================
PROMPT  ==   Configure instance settings
PROMPT  =============================================================================
PROMPT

begin
  apex_instance_admin.set_parameter('MAX_SESSION_IDLE_SEC', '28800');
  apex_instance_admin.set_parameter('MAX_SESSION_LENGTH_SEC', '28800');
  apex_instance_admin.set_parameter('SESSION_TIMEOUT_WARNING_SEC', '180');

  commit;
end;
/
