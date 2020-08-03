set define '^'
set concat on
set concat .
set verify off
prompt ^1 droppen

drop user ^1 cascade;

create user ^1
  identified by ^2
  default tablespace users
  temporary tablespace temp
  profile default
  account unlock;



-- 2 roles for ^1
grant connect to ^1;
alter user ^1 default role all;
grant create any context to ^1;


alter user ^3
  grant connect through ^1;

alter user ^4
  grant connect through ^1;

grant execute on sys.dbms_session to ^4;

alter user ^5
  grant connect through ^1;
