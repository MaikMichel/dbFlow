set define '^'
set verify off

@../env.sql

prompt
prompt
prompt **********************************************************************
prompt ***  SCHEMA CREATION: ^schema_name
prompt **********************************************************************
prompt
prompt


prompt ^schema_name droppen
declare
  v_check number(1) := 0;
begin
  select 1
    into v_check
    from all_users
   where username = upper('^schema_name');
  dbms_output.put_line('drop user ^schema_name cascade');
  execute immediate 'drop user ^schema_name cascade';
exception
  when no_data_found then
    null; -- ok, nothing to drop  ´
end;
/

prompt create user ^schema_name default tablespace ^deftablespace
create user ^schema_name NO AUTHENTICATION
  default tablespace ^deftablespace
  temporary tablespace temp
  profile default
  account unlock;


-- 2 tablespace quotas for ^schema_name
alter user ^schema_name quota unlimited on ^deftablespace;

-- 2 roles for ^schema_name
alter user ^schema_name default role all;

-- 11 system privileges for ^schema_name
grant create any context to ^schema_name;
grant create any directory to ^schema_name;
grant create any procedure to ^schema_name;
grant create job to ^schema_name;
grant create procedure to ^schema_name;
grant create sequence to ^schema_name;
grant create synonym to ^schema_name;
grant create public synonym to ^schema_name;
grant create table to ^schema_name;
grant create trigger to ^schema_name;
grant create type to ^schema_name;
grant create view to ^schema_name;
grant create session to ^schema_name;

-- 5 object privileges for ^schema_name
grant execute on sys.dbms_crypto to ^schema_name;
grant execute on sys.utl_file to ^schema_name;
grant execute on sys.utl_http to ^schema_name;
grant execute on sys.dbms_rls to ^schema_name;

grant create any context to ^schema_name;

alter user ^schema_name
  grant connect through ^db_app_user;

prompt **********************************************************************
prompt
prompt