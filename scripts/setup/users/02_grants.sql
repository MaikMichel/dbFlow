-- 2 tablespace quotas for ^schema_name
alter user ^schema_name quota unlimited on ^deftablespace;


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


prompt **********************************************************************
prompt
prompt