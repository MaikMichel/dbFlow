create or replace package export_schema is
  
  function get_zip return blob;

  function get_table(p_table_name   in varchar) return clob;
end;
/