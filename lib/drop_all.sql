set define '^'
set concat on
set concat .
set verify off
define SPOOLFILE = '^1'
define VERSION = '^2'
set timing on;
set serveroutput on;
spool ^SPOOLFILE append;
begin
  for cur in (
    
      with base as (
          select 
                object_type,
                object_name
          from user_objects
          where object_type in ( 'TABLE', 'VIEW','MATERIALIZED VIEW', 'PACKAGE', 'TYPE', 'PROCEDURE', 'FUNCTION', 'TRIGGER', 'SEQUENCE' )
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
select lower(object_type) as object_type, lower(object_name) as object_name from user_objects order by object_type, object_name;