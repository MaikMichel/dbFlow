begin
  for cur in ( select 'DROP ' || object_type || ' ' || object_name ||
                      decode ( object_type, 'TABLE', ' CASCADE CONSTRAINTS PURGE',
                                            'TYPE', ' force' ) as v_sql
                from user_objects
               where object_type in ( 'TABLE', 'VIEW', 'PACKAGE', 'TYPE', 'PROCEDURE', 'FUNCTION', 'TRIGGER', 'SEQUENCE' )
                 and object_name not like 'SYS_PLSQL_%'
               order by decode ( object_type, 'TRIGGER', 'AAA', object_type ), object_name) 
  loop
    execute immediate cur.v_sql;
  end loop;
end;
/