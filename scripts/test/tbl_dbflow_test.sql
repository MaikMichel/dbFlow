Declare
  l_check number(1);
begin
  select 1
    into l_check
    from user_tables
   where table_name = 'DBFLOW_TEST';


  execute immediate 'drop table DBFLOW_TEST';
exception
  when no_data_found then
    null;
end;
/

create table dbflow_test (
  dft_id         number generated always as identity,
  dft_mode       varchar2(2000 char) not null,
  dft_mainfolder varchar2(2000 char) not null,
  dft_schema     varchar2(2000 char) not null,
  dft_file       varchar2(2000 char) not null
);
