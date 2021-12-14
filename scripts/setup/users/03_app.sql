set define '^'
set verify off

@../env.sql

prompt
prompt
prompt **********************************************************************
prompt ***  SCHEMA CREATION: ^app_schema
prompt **********************************************************************
prompt
prompt

prompt ^app_schema droppen
declare
  v_check number(1) := 0;
begin
  select 1
    into v_check
    from all_users
   where username = upper('^app_schema');
  dbms_output.put_line('drop user ^app_schema cascade');
  execute immediate 'drop user ^app_schema cascade';
exception
  when no_data_found then
    null; -- ok, nothing to drop  ´
end;
/

prompt create user ^app_schema identified by "^db_app_pwd" default tablespace ^deftablespace
create user ^app_schema
  identified by "^db_app_pwd"
  default tablespace ^deftablespace
  temporary tablespace temp
  profile default
  account unlock;


-- 2 tablespace quotas for ^app_schema
alter user ^app_schema quota unlimited on ^deftablespace;

-- 2 roles for ^app_schema
alter user ^app_schema default role all;

-- 11 system privileges for ^app_schema
grant create any context to ^app_schema;
grant create any directory to ^app_schema;
grant create any procedure to ^app_schema;
grant create job to ^app_schema;
grant create procedure to ^app_schema;
grant create sequence to ^app_schema;
grant create synonym to ^app_schema;
grant create public synonym to ^app_schema;
grant create table to ^app_schema;
grant create trigger to ^app_schema;
grant create type to ^app_schema;
grant create view to ^app_schema;
grant create session to ^app_schema;

-- 5 object privileges for ^app_schema
grant execute on sys.dbms_crypto to ^app_schema;
grant execute on sys.utl_file to ^app_schema;
grant execute on sys.utl_http to ^app_schema;
grant execute on sys.dbms_rls to ^app_schema;

grant create any context to ^app_schema;

prompt **********************************************************************
prompt
prompt