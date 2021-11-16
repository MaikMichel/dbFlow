create or replace package dbflow$exp_schema is

  function get_zip(p_object in varchar2 default 'ALL') return blob;

  function get_table(p_table_name   in varchar) return clob;
end;
/