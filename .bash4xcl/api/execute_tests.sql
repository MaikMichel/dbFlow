set define '^'
set concat on
set concat .
set verify off
define SPOOLFILE = '^1'
define VERSION = '^2'
set timing on;
set serveroutput on;
spool ^SPOOLFILE append;
prompt ............................................................................
prompt ............................................................................
prompt ..                                                                        ..
prompt ..      utPLSQL - TESTs                                                   ..
prompt ..                                                                        ..
prompt ............................................................................
prompt ............................................................................
prompt
prompt
prompt compiling schema
exec dbms_utility.compile_schema(schema => USER, compile_all => false);
exec dbms_session.reset_package;

prompt executing Tests
set serveroutput on
exec ut.run(a_color_console => true);
