set define '^'
set concat on
set concat .
set verify off
define SPOOLFILE = '^1'
define VERSION = '^2'
set timing on;
set serveroutput on;
set termout off
set echo off
set feedback off
REM Special case, cause we spool testoutput to xml - spool ^SPOOLFILE append;
prompt ............................................................................
prompt ............................................................................
prompt ..                                                                        ..
prompt ..      utPLSQL - TESTs XML                                               ..
prompt ..                                                                        ..
prompt ............................................................................
prompt ............................................................................
prompt
prompt compiling schema
exec dbms_utility.compile_schema(schema => user, compile_all => false);
exec dbms_session.reset_package;

prompt executing Tests
spool ^SPOOLFILE
begin
  execute immediate 'select ut.version from dual';
  ut.run(ut_junit_reporter());
exception
  when others then
    dbms_output.put_line('utPLSQL not installed. No tests will run.');
end;
/
spool off
