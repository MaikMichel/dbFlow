set define '^'
set concat on
set concat .
set verify off
define VERSION = '^1'
set timing on;
set serveroutput on;

prompt
prompt ............................................................................
prompt ............................................................................
prompt ..                                                                        ..
prompt ..      Compiling Schema...                                               ..
prompt ..                                                                        ..
prompt ............................................................................
prompt ............................................................................
prompt
prompt compiling schema
exec dbms_utility.compile_schema(schema => user, compile_all => false);
exec dbms_session.reset_package

prompt list of invalid objects
select lower(object_type) as object_type, lower(object_name) as object_name
  from user_objects
 where status <> 'VALID'
order by 1, 2;