set define '^'
set concat on
set concat .
set verify off
define VERSION = '^1'
set timing on;
set serveroutput on;

prompt dropping jobs
Declare
  v_cnt pls_integer := 0;
Begin
  for cur in (
    select 'begin dbms_scheduler.drop_job(job_name => '''||job_creator||'.'||job_name||''', force => true); end;' stmt,
            job_name
      from user_scheduler_jobs j
  )
  loop
    dbms_output.put_line('drop job: '||cur.job_name);
    execute immediate cur.stmt;
    v_cnt := v_cnt + 1;
  end loop;
  dbms_output.put_line('.. ' || v_cnt || ' jobs(s) dropped');
End;
/
prompt dropping objects
begin
  for cur in (

      with base as (
          select
                object_type,
                object_name
          from user_objects
          where object_type in ( 'TABLE', 'VIEW','MATERIALIZED VIEW', 'PACKAGE', 'TYPE', 'PROCEDURE', 'FUNCTION', 'TRIGGER', 'SEQUENCE', 'SYNONYM' )
          and object_name not like 'SYS_PLSQL_%'
          and object_name not like 'ISEQ$$_%'
          minus -- we have to remove the drop table command for materialized views as they appear twice above
          select
              'TABLE',
              object_name
          from user_objects
          where object_type = 'MATERIALIZED VIEW'
          and object_name not like 'SYS_PLSQL_%'
          and object_name not like 'ISEQ$$_%'
      )
      select 'DROP ' || object_type || ' ' || object_name || decode ( object_type, 'TABLE', ' CASCADE CONSTRAINTS PURGE', 'TYPE', ' force' ) as v_sql
      from base
      order by decode( object_type, 'TRIGGER', 'AAA', object_type ), object_name


  ) loop
    execute immediate cur.v_sql;
  end loop;
end;
/

purge recyclebin;

prompt
prompt objects left in schema
select lower(object_type) as object_type, lower(object_name) as object_name
  from user_objects
 order by object_type, object_name;
