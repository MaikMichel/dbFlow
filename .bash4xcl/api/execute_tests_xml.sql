prompt
prompt
prompt ............................................................................
prompt ............................................................................
prompt ..                                                                        ..
prompt ..      utPLSQL - TESTs XML                                               ..
prompt ..                                                                        ..
prompt ............................................................................
prompt ............................................................................
prompt
set define '^'
set concat on
set concat .
set verify off

prompt compiling schema
exec dbms_utility.compile_schema(schema => user, compile_all => false);
exec dbms_session.reset_package;

prompt executing Tests
spool ^1
set serveroutput on
set termout off
set echo off
set feedback off
begin
  execute immediate 'select ut.version from dual';  
  ut.run(ut_junit_reporter());
exception 
  when others then
    dbms_output.put_line('utPLSQL not installed. No tests will run.');   
end;
/
spool off



