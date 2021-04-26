set define '^'
set concat on
set concat .
set verify off

@../env.sql

prompt
prompt
prompt **********************************************************************
prompt ***  USER CREATION: ^depl_schema
prompt **********************************************************************
prompt
prompt

prompt ^db_app_user droppen

drop user ^db_app_user cascade;

create user ^db_app_user
  identified by ^db_app_pwd
  default tablespace ^deftablespace
  temporary tablespace temp
  profile default
  account unlock;



-- 2 roles for ^db_app_user
grant connect to ^db_app_user;
alter user ^db_app_user default role all;
grant create any context to ^db_app_user;

alter user ^data_schema
  grant connect through ^db_app_user;

alter user ^logic_schema
  grant connect through ^db_app_user;

alter user ^app_schema
  grant connect through ^app_schema;


prompt **********************************************************************
prompt
prompt