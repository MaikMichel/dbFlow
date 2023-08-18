set termout off
column filename new_val filename
select 'testoutput_^^MODE._^^VERSION._on_'||SYS_CONTEXT('USERENV', 'SESSION_USER')||'.xml' filename
  from dual;
set termout on
prompt
prompt
prompt ............................................................................
prompt ............................................................................
prompt ..
prompt ..      utPLSQL - TESTs - ^^filename
prompt ..
prompt ............................................................................
prompt ............................................................................
prompt
prompt compiling schema
exec dbms_utility.compile_schema(schema => USER, compile_all => false);
exec dbms_session.reset_package;

prompt executing Tests
set serveroutput on
set echo off
set feedback off
set termout off
spool ^^filename
exec ut.run(ut_junit_reporter());
spool off
set termout on
exec ut.run(a_color_console => true);

