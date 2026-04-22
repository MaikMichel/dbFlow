drop table if exists rest_compile_logs;
create table rest_compile_logs (
    rcl_id         number generated always as identity,
    rcl_fname      varchar2(4000 char),
    rcl_content    clob,
    rcl_payload    blob,
    rcl_content_type varchar2(255 char),
    rcl_is_zip     varchar2(1 char)
);
