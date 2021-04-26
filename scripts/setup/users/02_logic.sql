set define '^'
set verify off

@../env.sql

prompt
prompt
prompt **********************************************************************
prompt ***  SCHEMA CREATION: ^logic_schema
prompt **********************************************************************
prompt
prompt


prompt ^logic_schema droppen
declare
  v_check number(1) := 0;
begin
  select 1
    into v_check
    from all_users
   where username = upper('^logic_schema');
  dbms_output.put_line('drop user ^logic_schema cascade');
  execute immediate 'drop user ^logic_schema cascade';
exception
  when no_data_found then
    null; -- ok, nothing to drop  ´
end;
/

prompt create user ^logic_schema identified by ^db_app_pwd default tablespace ^deftablespace
create user ^logic_schema
  identified by ^db_app_pwd
  default tablespace ^deftablespace
  temporary tablespace temp
  profile default
  account unlock;


-- 2 tablespace quotas for ^logic_schema
alter user ^logic_schema quota unlimited on ^deftablespace;

-- 2 roles for ^logic_schema
alter user ^logic_schema default role all;

-- 11 system privileges for ^logic_schema
grant create any context to ^logic_schema;
grant create any directory to ^logic_schema;
grant create any procedure to ^logic_schema;
grant create job to ^logic_schema;
grant create procedure to ^logic_schema;
grant create sequence to ^logic_schema;
grant create synonym to ^logic_schema;
grant create public synonym to ^logic_schema;
grant create table to ^logic_schema;
grant create trigger to ^logic_schema;
grant create type to ^logic_schema;
grant create view to ^logic_schema;
grant create session to ^logic_schema;

-- 5 object privileges for ^logic_schema
grant execute on sys.dbms_crypto to ^logic_schema;
grant execute on sys.utl_file to ^logic_schema;
grant execute on sys.utl_http to ^logic_schema;
grant execute on sys.dbms_rls to ^logic_schema;
grant execute on sys.dbms_session to ^logic_schema;

grant create any context to ^logic_schema;

prompt **********************************************************************
prompt
prompt