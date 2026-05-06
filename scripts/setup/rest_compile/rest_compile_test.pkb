create or replace package body rest_compile_test is
    --%suite(Tests for rest_compile package)

    g_fixtures constant clob := q'~[
      {
        "name": "collects_plsql_block",
        "expectedCount": 1,
        "lines": [
          "declare",
          "  l_test number := 1;",
          "begin",
          "  null;",
          "end;"
        ]
      },
      {
        "name": "collects_nested_anonymous_block",
        "expectedCount": 1,
        "lines": [
          "declare",
          "  l_file_name varchar2(2000) := 'changelog_patch_0.3.0.md';",
          "begin",
          "  declare",
          "    l_version varchar2(100);",
          "  begin",
          "    l_version := substr(l_file_name, instr(l_file_name, '_', 1, 2)+1);",
          "    begin",
          "      null;",
          "    exception",
          "      when dup_val_on_index then",
          "        null;",
          "    end;",
          "  exception",
          "    when others then",
          "      raise;",
          "  end;",
          "  commit;",
          "exception",
          "  when others then",
          "    raise;",
          "end;",
          "/"
        ]
      },
      {
        "name": "collects_cor_terminated_by_slash",
        "expectedCount": 1,
        "lines": [
          "create or replace package p1 is",
          "  procedure x;",
          "end;",
          "/"
        ]
      },
      {
        "name": "only_some_sqlplus",
        "expectedCount": 0,
        "lines": [
          "set define '^'",
          "set concat on",
          "set concat .",
          "set verify off",
          "WHENEVER SQLERROR EXIT SQL.SQLCODE"
        ]
      },
      {
        "name": "two_tables_with_sqlplus_lines",
        "expectedCount": 2,
        "lines": [
          "set define '^'",
          "set concat on",
          "set concat .",
          "set verify off",
          "WHENEVER SQLERROR EXIT SQL.SQLCODE",
          "",
          "define VERSION = '^1'",
          "define MODE = '^2'",
          "set timing on",
          "set trim on",
          "set linesize 2000",
          "set sqlblanklines on",
          "set tab off",
          "set pagesize 9999",
          "set trimspool on",
          "",
          "Prompt .............................................................................. ",
          "Prompt .............................................................................. ",
          "Prompt .. Start Installation for schema: ati ",
          "Prompt ..                       Version: init 0.0.0 ",
          "Prompt .............................................................................. ",
          "set serveroutput on",
          "set scan off",
          "",
          "set scan on",
          "set scan off",
          "Prompt Installing tables ...",
          "Prompt",
          "set define off",
          "Prompt >>> db/ati/tables/test_cases.sql",
          "create table test_cases (",
          "    tca_id              number              not null, -- PK",
          "    tca_tsu_id          number              not null, -- FK to test_suites",
          "    tca_id_attr         number,      -- id attribute from testcase",
          "    tca_id_run          number,      -- id generated per testrun",
          "    tca_name            varchar2(255 char),",
          "    tca_fullname       varchar2(4000 char),",
          "    tca_time            number              default 0,",
          "    tca_status          varchar2(20)        default 'PASS' not null, -- PASS, FAIL, SKIP, TODO",
          "    tca_filename        varchar2(4000 char),",
          "    tca_line            number,",
          "    tca_column          number,",
          "    tca_diag         clob,",
          "    tca_created_at      timestamp                       not null,",
          "    tca_modified_at     timestamp                       not null,",
          "    tca_created_by      varchar2(255)                   not null,",
          "    tca_modified_by     varchar2(255)                   not null",
          ");",
          "",
          "-- File: indexes/primaries/test_cases_tca_id_pk.sql",
          "-- File: constraints/primaries/test_cases_tca_id_pk.sql",
          "-- File: constraints/foreigns/test_cases_tca_tsu_id_fk.sql",
          "-- File: indexes/defaults/test_cases_tca_tsu_id_df.sql",
          "-- File: sources/triggers/test_cases_biu.sql",
          "",
          "Prompt <<< db/ati/tables/test_cases.sql",
          "Prompt >>> db/ati/tables/test_runs.sql",
          "-- drop table test_runs;",
          "",
          "create table test_runs (",
          "    tru_id              number              not null, -- PK",
          "    tru_name            varchar2(255),",
          "    tru_date            timestamp with time zone not null,",
          "    tru_user            varchar2(255),",
          "    tru_machine         varchar2(255),",
          "    tru_os              varchar2(255),",
          "    tru_db_version      varchar2(255),",
          "    tru_apex_version    varchar2(255),",
          "    tru_branch_name     varchar2(255),",
          "    tru_report          clob,",
          "    -- comming from the original reporter",
          "    tru_tests           number          default 0       not null,",
          "    tru_failures        number          default 0       not null,",
          "    tru_assertions      number          default 0       not null,",
          "    tru_skipped         number          default 0       not null,",
          "    -- commint from APEX dev CLI",
          "    tru_asserts_total   number          default 0       not null,",
          "    tru_asserts_passed  number          default 0       not null,",
          "    tru_asserts_failed  number          default 0       not null,",
          "    tru_asserts_skipped number          default 0       not null,",
          "    tru_asserts_todo    number          default 0       not null,",
          "",
          "    tru_direct_suites_total     number          default 0       not null,",
          "    tru_direct_suites_passed    number          default 0       not null,",
          "    tru_direct_suites_failed    number          default 0       not null,",
          "    tru_direct_suites_skipped   number          default 0       not null,",
          "    --tru_direct_suites_todo   number          default 0       not null,",
          "",
          "    tru_time_tests_ms   number          default 0       not null,",
          "    tru_time_overall_ms number          default 0       not null,",
          "    tru_created_at      timestamp                       not null,",
          "    tru_modified_at     timestamp                       not null,",
          "    tru_created_by      varchar2(255)                   not null,",
          "    tru_modified_by     varchar2(255)                   not null",
          ");",
          "",
        ]
      },{
        "name": "two_tables_with_sqlplus_lines_and_a_drop",
        "expectedCount": 3,
        "lines": [
          "set define '^'",
          "set concat on",
          "set concat .",
          "set verify off",
          "WHENEVER SQLERROR EXIT SQL.SQLCODE",
          "",
          "define VERSION = '^1'",
          "define MODE = '^2'",
          "set timing on",
          "set trim on",
          "set linesize 2000",
          "set sqlblanklines on",
          "set tab off",
          "set pagesize 9999",
          "set trimspool on",
          "",
          "Prompt .............................................................................. ",
          "Prompt .............................................................................. ",
          "Prompt .. Start Installation for schema: ati ",
          "Prompt ..                       Version: init 0.0.0 ",
          "Prompt .............................................................................. ",
          "set serveroutput on",
          "set scan off",
          "",
          "set scan on",
          "set scan off",
          "Prompt Installing tables ...",
          "Prompt",
          "set define off",
          "Prompt >>> db/ati/tables/test_cases.sql",
          "create table test_cases (",
          "    tca_id              number              not null, -- PK",
          "    tca_tsu_id          number              not null, -- FK to test_suites",
          "    tca_id_attr         number,      -- id attribute from testcase",
          "    tca_id_run          number,      -- id generated per testrun",
          "    tca_name            varchar2(255 char),",
          "    tca_fullname       varchar2(4000 char),",
          "    tca_time            number              default 0,",
          "    tca_status          varchar2(20)        default 'PASS' not null, -- PASS, FAIL, SKIP, TODO",
          "    tca_filename        varchar2(4000 char),",
          "    tca_line            number,",
          "    tca_column          number,",
          "    tca_diag         clob,",
          "    tca_created_at      timestamp                       not null,",
          "    tca_modified_at     timestamp                       not null,",
          "    tca_created_by      varchar2(255)                   not null,",
          "    tca_modified_by     varchar2(255)                   not null",
          ");",
          "",
          "-- File: indexes/primaries/test_cases_tca_id_pk.sql",
          "-- File: constraints/primaries/test_cases_tca_id_pk.sql",
          "-- File: constraints/foreigns/test_cases_tca_tsu_id_fk.sql",
          "-- File: indexes/defaults/test_cases_tca_tsu_id_df.sql",
          "-- File: sources/triggers/test_cases_biu.sql",
          "",
          "Prompt <<< db/ati/tables/test_cases.sql",
          "Prompt >>> db/ati/tables/test_runs.sql",
          "drop table test_runs;",
          "",
          "create table test_runs (",
          "    tru_id              number              not null, -- PK",
          "    tru_name            varchar2(255),",
          "    tru_date            timestamp with time zone not null,",
          "    tru_user            varchar2(255),",
          "    tru_machine         varchar2(255),",
          "    tru_os              varchar2(255),",
          "    tru_db_version      varchar2(255),",
          "    tru_apex_version    varchar2(255),",
          "    tru_branch_name     varchar2(255),",
          "    tru_report          clob,",
          "    -- comming from the original reporter",
          "    tru_tests           number          default 0       not null,",
          "    tru_failures        number          default 0       not null,",
          "    tru_assertions      number          default 0       not null,",
          "    tru_skipped         number          default 0       not null,",
          "    -- commint from APEX dev CLI",
          "    tru_asserts_total   number          default 0       not null,",
          "    tru_asserts_passed  number          default 0       not null,",
          "    tru_asserts_failed  number          default 0       not null,",
          "    tru_asserts_skipped number          default 0       not null,",
          "    tru_asserts_todo    number          default 0       not null,",
          "",
          "    tru_direct_suites_total     number          default 0       not null,",
          "    tru_direct_suites_passed    number          default 0       not null,",
          "    tru_direct_suites_failed    number          default 0       not null,",
          "    tru_direct_suites_skipped   number          default 0       not null,",
          "    --tru_direct_suites_todo   number          default 0       not null,",
          "",
          "    tru_time_tests_ms   number          default 0       not null,",
          "    tru_time_overall_ms number          default 0       not null,",
          "    tru_created_at      timestamp                       not null,",
          "    tru_modified_at     timestamp                       not null,",
          "    tru_created_by      varchar2(255)                   not null,",
          "    tru_modified_by     varchar2(255)                   not null",
          ");",
          "",
        ]
      },
      {
        "name": "two_alter_tables",
        "expectedCount": 2,
        "lines": [
          "Prompt >>> db/ati/constraints/primaries/test_suites_tsu_id_pk.sql",
          "alter table test_suites add (",
          "  constraint tsu_id_pk",
          "  primary key (tsu_id)",
          "  using index test_suites_tsu_id_pk",
          "  enable validate",
          ");",
          "Prompt <<< db/ati/constraints/primaries/test_suites_tsu_id_pk.sql",
          "set define '^'",
          "Prompt",
          "Prompt",
          "",
          "Prompt Installing constraints/foreigns ...",
          "Prompt",
          "set define off",
          "Prompt >>> db/ati/constraints/foreigns/test_cases_tca_tsu_id_fk.sql",
          "alter table test_cases add (",
          "  constraint test_cases_tca_tsu_id_fk",
          "  foreign key (tca_tsu_id)",
          "  references test_suites (tsu_id)",
          "  on delete cascade",
          "  enable validate",
          ");"
        ]
      },
      {
        "name": "two_specs",
        "expectedCount": 2,
        "lines": [
          "Prompt Installing sources/packages ...",
          "Prompt",
          "set define off",
          "Prompt >>> db/ati/sources/packages/app_interface.pks",
          "create or replace package app_interface is",
          "  function generate_page_link ( p_app_page_id      in number,",
          "                                  p_app_user         in varchar2 default sys_context('apex$session','app_user'),",
          "                                  p_checksum_type    in varchar2 default 'SESSION',",
          "                                  p_page_item_names  in APEX_T_VARCHAR2 default null,",
          "                                  p_page_item_values in APEX_T_VARCHAR2 default null) return varchar2;",
          "",
          "  function get_diagnostic_info_md(p_tca_id in test_cases.tca_id%type) return clob;",
          "  function get_lang_from_file(p_file_name in varchar2) return varchar2;",
          "  function get_skip_info_md(p_tsu_id in test_suites.tsu_id%type) return clob;",
          "",
          "  procedure clear_region_sort_preferences(p_app_id           in number,",
          "                                          p_page_id          in number,",
          "                                          p_region_static_id in varchar2);",
          "end;",
          "/",
          "",
          "Prompt <<< db/ati/sources/packages/app_interface.pks",
          "Prompt >>> db/ati/sources/packages/ati_page_helpers.pks",
          "create or replace package ati_page_helpers is",
          "    type t_numbers is table of number;",
          "",
          "    function selected_pk_num(p_app_id           in number,",
          "                            p_page_id          in number,",
          "                            p_region_static_id in varchar2,",
          "                            p_pk_column        in varchar2)",
          "                            return                t_numbers pipelined;",
          "",
          "    function region_has_rows(p_app_id           in number,",
          "                            p_page_id          in number,",
          "                            p_region_static_id in varchar2)",
          "                            return                boolean;",
          "end;",
          "/",
        ]
      },
      {
        "name": "three_anonymous_blocks",
        "expectedCount": 3,
        "lines": [
          "begin",
          "  null;",
          "end;",
          "/",
          "",
          "begin",
          "  if 1/2 > 0 then null; end if;",
          "end;",
          "/",
          "",
          "begin",
          "  if 1/0 > 0 then null; end if;",
          "end;",
          "/",
        ]
      },
      {
        "name": "multiple_procedures_in_declare_block",
        "expectedCount": 1,
        "lines": [
          "declare",
          "  l_cnt pls_integer := 0;",
          "",
          "  procedure drop_object(p_type in varchar2, p_name in varchar2, p_extra in varchar2 default null) is",
          "    l_exists pls_integer := 0;",
          "  begin",
          "    select count(*)",
          "      into l_exists",
          "      from user_objects",
          "     where object_type = p_type",
          "       and object_name = upper(p_name);",
          "",
          "    if l_exists > 0 then",
          "      dbms_output.put_line('drop ' || lower(p_type) || ': ' || lower(p_name));",
          "      execute immediate 'drop ' || p_type || ' ' || p_name || nvl(p_extra, '');",
          "      l_cnt := l_cnt + 1;",
          "    else",
          "      dbms_output.put_line('skip ' || lower(p_type) || ': ' || lower(p_name));",
          "    end if;",
          " end;",
          "",
          "    procedure drop_job(p_job_name in varchar2) is",
          "        l_exists pls_integer := 0;",
          "    begin",
          "        select count(*)",
          "          into l_exists",
          "          from user_scheduler_jobs",
          "         where upper(job_name) = upper(p_job_name);",
          "",
          "        if l_exists > 0 then",
          "            dbms_output.put_line('drop job: '||user||'.'||p_job_name);",
          "            execute immediate 'begin dbms_scheduler.drop_job(job_name => '''||user||'.'||p_job_name||''', force => true); end;';",
          "            l_cnt := l_cnt + 1;",
          "        else",
          "            dbms_output.put_line('skip job: '||user||'.'||p_job_name);",
          "        end if;",
          "    end;",
          "begin",
          "    -- views",
          "    drop_object('VIEW', 'v_test');",
          "",
          "    dbms_output.put_line('.. ' || l_cnt || ' object(s) dropped');",
          "end;",
          "/",
        ]
      },
      {
        "name": "package_body",
        "expectedCount": 1,
        "lines": [
            "create or replace package body this_is_my_test is",
            "  function get_some(p_p1 in vachar2,",
            "                    p_p2 in number)",
            "                    return number is",
            "     l_local_var number;",
            "     function nested_one return_number is",
            "     begin",
            "       return 123;",
            "     end;",
            "  begin",
            "     return 1;",
            "  end;",
            "  procedure set_some(p_p1 in vachar2,",
            "                    p_p2 in number)",
            "     l_local_var number;",
            "     function nested_one return_number is",
            "     begin",
            "       return 123;",
            "     end;",
            "  begin",
            "     null",
            "  end;",
            "begin",
            "  call_my_proc;",
            "  begin",
            "    null;",
            "  end;",
            "end;",
            "/",
        ]
      },
      {
        "name": "package_body_nested_named_end",
        "expectedCount": 1,
        "lines": [
          "create or replace package body this_is_my_test is",
          "  procedure p is",
          "    function local_fn return number is",
          "    begin",
          "      return 1;",
          "    end local_fn;",
          "  begin",
          "    null;",
          "  end p;",
          "begin",
          "  p;",
          "end this_is_my_test;",
          "/"
        ]
      },
      {
        "name": "package_body_local_if_loop",
        "expectedCount": 1,
        "lines": [
          "create or replace package body this_is_my_test is",
          "  procedure p is",
          "  begin",
          "    for i in 1 .. 2 loop",
          "      if i > 0 then",
          "        null;",
          "      end if;",
          "    end loop;",
          "  end p;",
          "begin",
          "  p;",
          "end this_is_my_test;",
          "/"
        ]
      },
      {
        "name": "exec_lines_as_plsql_blocks",
        "expectedCount": 2,
        "lines": [
          "exec dbms_utility.compile_schema(schema => user, compile_all => false);",
          "exec dbms_session.reset_package"
        ]
      },
      {
        "name": "parse_not_trimmed_lines",
        "expectedCount": 1,
        "lines": [
            "      set serveroutput on;",
            "      set define off;",
            "      Declare",
            "        v_application_id  apex_application_build_options.application_id%type := 12120 + 0;",
            "        v_workspace_id    apex_workspaces.workspace_id%type;",
            "      Begin",
            "        select workspace_id",
            "          into v_workspace_id",
            "          from apex_workspaces",
            "          where workspace = upper('APEX_DX');",
            "",
            "        apex_application_install.set_workspace_id(v_workspace_id);",
            "        apex_util.set_security_group_id(p_security_group_id => apex_application_install.get_workspace_id);",
            "",
            "        apex_util.set_application_status(p_application_id     => v_application_id,",
            "                                          p_application_status => 'UNAVAILABLE',",
            "                                          p_unavailable_value  => 'under maintence' );",
            "",
            "        dbms_output.put_line('.. APP: '|| v_application_id || ' has been disabled');",
            "",
            "        -- check translated Applications additionally",
            "        for cur in ( select translated_application_id, translated_app_language",
            "                       from apex_application_trans_map",
            "                      where primary_application_id = v_application_id",
            "                      order by translated_application_id)",
            "        loop",
            "          begin",
            "            apex_util.set_application_status(p_application_id     => cur.translated_application_id,",
            "                                             p_application_status => 'UNAVAILABLE',",
            "                                             p_unavailable_value  => 'under maintence' );",
            "            dbms_output.put_line('.... Translated APP: '|| cur.translated_application_id || ' (' || cur.translated_app_language || ') has been disabled');",
            "          exception",
            "            when others then",
            "              if sqlerrm like '%Application not found%' then",
            "                dbms_output.put_line( 'Application: '||upper(cur.translated_application_id)||' probably not published!');",
            "              else",
            "                raise;",
            "              end if;",
            "          end;",
            "        end loop;",
            "      Exception",
            "        when no_data_found then",
            "          dbms_output.put_line('Workspace: '||upper('APEX_DX')||' not found!');",
            "        when others then",
            "          if sqlerrm like '%Application not found%' then",
            "            dbms_output.put_line('Application: '||upper(v_application_id)||' not found!');",
            "          else",
            "            raise;",
            "          end if;",
            "End;",
            "/"

        ]
      },
    ]~';

    function join_json_lines(p_json clob, p_name varchar2) return clob is
  l_script clob;
begin
  dbms_lob.createtemporary(l_script, true);

  for r in (
    select jt.line_no, jt.line_txt
    from json_table(
           p_json format json,
           '$[*]'
           columns
             name varchar2(200) path '$.name',
             nested path '$.lines[*]'
               columns (
                 line_no  for ordinality,
                 line_txt varchar2(4000) path '$'
               )
         ) jt
    where jt.name = p_name
    order by jt.line_no
  ) loop
    dbms_lob.append(l_script, to_clob(r.line_txt || chr(10)));
  end loop;

  return l_script;
end;

    function clob_to_blob_utf8(p_clob in clob) return blob is
      l_blob         blob;
      l_dest_offset  integer := 1;
      l_src_offset   integer := 1;
      l_lang_context integer := dbms_lob.default_lang_ctx;
      l_warning      integer;
    begin
      dbms_lob.createtemporary(l_blob, true);

      if p_clob is not null and dbms_lob.getlength(p_clob) > 0 then
        dbms_lob.converttoblob(dest_lob     => l_blob,
                               src_clob     => p_clob,
                               amount       => dbms_lob.lobmaxsize,
                               dest_offset  => l_dest_offset,
                               src_offset   => l_src_offset,
                               blob_csid    => nls_charset_id('AL32UTF8'),
                               lang_context => l_lang_context,
                               warning      => l_warning);
      end if;

      return l_blob;
    end;

    function create_zip_payload(p_file_name          in varchar2,
                                p_file_content       in clob,
                                p_second_file_name   in varchar2 default null,
                                p_second_file_content in clob default null) return blob is
      l_zip_blob blob;
    begin
      dbms_lob.createtemporary(l_zip_blob, true);

      apex_zip.add_file(p_zipped_blob => l_zip_blob,
                        p_file_name   => p_file_name,
                        p_content     => clob_to_blob_utf8(p_file_content));

      if p_second_file_name is not null then
        apex_zip.add_file(p_zipped_blob => l_zip_blob,
                          p_file_name   => p_second_file_name,
                          p_content     => clob_to_blob_utf8(p_second_file_content));
      end if;

      apex_zip.finish(p_zipped_blob => l_zip_blob);
      return l_zip_blob;
    end;

    function json_value_varchar2(p_json in json_object_t,
                                 p_path in varchar2) return varchar2 is
      l_info json_object_t;
    begin
      case p_path
        when '$.success' then
          if p_json.get_boolean('success') then
            return 'true';
          end if;
          return 'false';
        when '$.file_name' then
          return p_json.get_string('file_name');
        when '$.is_zip' then
          if p_json.get_boolean('is_zip') then
            return 'true';
          end if;
          return 'false';
        when '$.message' then
          return p_json.get_string('message');
        when '$.info.total_statements' then
          l_info := treat(p_json.get_object('info') as json_object_t);
          return to_char(l_info.get_number('total_statements'));
        else
          raise_application_error(-20020, 'Unsupported JSON path in test helper: ' || p_path);
      end case;
    end;

    --%test(runs json fixtures)
  procedure run_all is
begin
  for c in (
    select name, expectedCount
    from json_table(
           g_fixtures format json,
           '$[*]'
           columns
             name          varchar2(200) path '$.name',
             expectedCount number        path '$.expectedCount'
         )
  ) loop
    declare
      l_script clob := join_json_lines(g_fixtures, c.name);
      l_stmts  rest_compile.t_statement_list;
    begin
      l_stmts := rest_compile.split_into_statements(l_script);

      ut.expect(l_stmts.count).to_equal(c.expectedCount);
      if l_stmts.count != c.expectedCount then
        ut.fail('Case "'||c.name||'": expected '||c.expectedCount||' statements, got '||l_stmts.count);
        if l_stmts.count > 0 then
          for i in l_stmts.first .. l_stmts.last loop
            dbms_output.put_line('AAA('||i||': ' || l_stmts(i).stmt_text);
          end loop;
        end if;
      end if;
    end;
  end loop;
end;

    procedure setup_suite is
    begin
        null;
    end;

    procedure teardown_test is
    begin
        delete from rest_compile_logs;
        commit;
    end;

    procedure null_returns_empty_clob is
        l_result clob;
    begin
        l_result := rest_compile.normalize_input(null);

        -- empty_clob() => Länge 0
        ut.expect(dbms_lob.getlength(l_result)).to_equal(0);
    end;


    procedure normalizes_newlines is
        l_in     clob;
        l_expect clob;
        l_result clob;
    begin
        -- CRLF und CR werden zu LF normalisiert; am Ende genau ein LF
        l_in     := to_clob('a' || chr(13)||chr(10) || 'b' || chr(13) || 'c');
        l_expect := to_clob('a' || chr(10) || 'b' || chr(10) || 'c' || chr(10));

        l_result := rest_compile.normalize_input(l_in);

        ut.expect(l_result).to_equal(l_expect);
    end;


    procedure trims_and_appends_one_lf is
        l_in     clob;
        l_expect clob;
        l_result clob;
    begin
        -- trailing LF + spaces + tab + LF werden entfernt,
        -- danach wird genau ein LF angehängt
        l_in     := to_clob('x' || chr(10) || 'y' || chr(10) || ' ' || chr(9) || chr(10));
        l_expect := to_clob('x' || chr(10) || 'y' || chr(10));

        l_result := rest_compile.normalize_input(l_in);

        ut.expect(l_result).to_equal(l_expect);
    end;


    -------------


    procedure null_returns_empty is
        l_lines rest_compile.t_array;
    begin
        l_lines := rest_compile.clob_to_lines(null);

        ut.expect(l_lines.count).to_equal(0);
    end;


    procedure single_line_no_lf is
        l_lines rest_compile.t_array;
    begin
        l_lines := rest_compile.clob_to_lines(to_clob('abc'));

        ut.expect(l_lines.count).to_equal(1);
        ut.expect(l_lines(1)).to_equal('abc');
    end;


    procedure two_lines_with_lf is
        l_lines rest_compile.t_array;
    begin
        l_lines := rest_compile.clob_to_lines(to_clob('a' || chr(10) || 'b'));

        ut.expect(l_lines.count).to_equal(2);
        ut.expect(l_lines(1)).to_equal('a');
        ut.expect(l_lines(2)).to_equal('b');
    end;


    procedure empty_line_in_between is
        l_lines rest_compile.t_array;
    begin
        l_lines := rest_compile.clob_to_lines(to_clob('a' || chr(10) || chr(10) || 'b'));

        ut.expect(l_lines.count).to_equal(3);
        ut.expect(l_lines(1)).to_equal('a');
        ut.expect(l_lines(2)).to_equal('');
        ut.expect(l_lines(3)).to_equal('b');
    end;




    ------

    procedure null_and_blank is
  begin
    ut.expect( rest_compile.is_sqlplus_command(null) ).to_be_true;
    ut.expect( rest_compile.is_sqlplus_command('') ).to_be_true;
    ut.expect( rest_compile.is_sqlplus_command('   ') ).to_be_true;
  end;

  procedure directives_are_true is
  begin
    -- PROMPT
    ut.expect( rest_compile.is_sqlplus_command('prompt hello') ).to_be_true;
    ut.expect( rest_compile.is_sqlplus_command('  ProMpT hello') ).to_be_true;

    -- SET
    ut.expect( rest_compile.is_sqlplus_command('set echo on') ).to_be_true;
    ut.expect( rest_compile.is_sqlplus_command('   SET serveroutput on') ).to_be_true;

    -- DEFINE / UNDEFINE
    ut.expect( rest_compile.is_sqlplus_command('define x=1') ).to_be_true;
    ut.expect( rest_compile.is_sqlplus_command('undefine x') ).to_be_true;

    -- WHENEVER
    ut.expect( rest_compile.is_sqlplus_command('whenever sqlerror exit failure') ).to_be_true;

    -- SPOOL
    ut.expect( rest_compile.is_sqlplus_command('spool out.log') ).to_be_true;

    -- COLUMN / COL
    ut.expect( rest_compile.is_sqlplus_command('column col1 format a10') ).to_be_true;
    ut.expect( rest_compile.is_sqlplus_command('col col1 for a10') ).to_be_true;

    -- ACCEPT
    ut.expect( rest_compile.is_sqlplus_command('accept p_x prompt ''x:''') ).to_be_true;

    -- HOST
    ut.expect( rest_compile.is_sqlplus_command('host dir') ).to_be_true;

    -- REM / REMARK
    ut.expect( rest_compile.is_sqlplus_command('rem this is a comment') ).to_be_true;
    ut.expect( rest_compile.is_sqlplus_command('remark this is a comment') ).to_be_true;
  end;

  procedure non_directives_are_false is
  begin
    -- regular SQL should not be ignored
    ut.expect( rest_compile.is_sqlplus_command('select 1 from dual;') ).to_be_false;
    ut.expect( rest_compile.is_sqlplus_command('  insert into t(x) values (1);') ).to_be_false;

    -- slash line should NOT be ignored by this function per your comment
    ut.expect( rest_compile.is_sqlplus_command('/') ).to_be_false;
    ut.expect( rest_compile.is_sqlplus_command('   /') ).to_be_false;

    -- tricky: starts with keyword but not the pattern "KEYWORD<space>"
    ut.expect( rest_compile.is_sqlplus_command('promptx') ).to_be_false; -- no trailing space => does not match 'PROMPT %'
    ut.expect( rest_compile.is_sqlplus_command('setx') ).to_be_false;    -- no trailing space => does not match 'SET %'
  end;

  procedure prefix_boundary_cases is
  begin
    -- Ensure "SET " doesn't accidentally match other tokens
    ut.expect( rest_compile.is_sqlplus_command('setx echo on') ).to_be_false;
    ut.expect( rest_compile.is_sqlplus_command('setup something') ).to_be_false;

    -- Ensure "COL " doesn't match "COLUMN" unless explicitly handled (it is handled via COLUMN %)
    ut.expect( rest_compile.is_sqlplus_command('color red') ).to_be_false;

    -- Ensure leading spaces are ok (ltrim)
    ut.expect( rest_compile.is_sqlplus_command('   rem comment') ).to_be_true;
  end;

    ------
      procedure creates_and_appends_first_line is
    l_clob clob;
  begin
    rest_compile.clob_append_line(l_clob, 'abc');

    ut.expect(l_clob).to_be_not_null;
    ut.expect(dbms_lob.istemporary(l_clob)).to_equal(1);
    ut.expect(dbms_lob.substr(l_clob, 32767, 1)).to_equal('abc' || chr(10));

    -- cleanup
    if dbms_lob.istemporary(l_clob) = 1 then
      dbms_lob.freetemporary(l_clob);
    end if;
  end;

  procedure appends_multiple_lines is
    l_clob clob;
  begin
    rest_compile.clob_append_line(l_clob, 'line1');
    rest_compile.clob_append_line(l_clob, 'line2');
    rest_compile.clob_append_line(l_clob, 'line3');

    ut.expect(dbms_lob.substr(l_clob, 32767, 1))
      .to_equal('line1' || chr(10) || 'line2' || chr(10) || 'line3' || chr(10));

    -- cleanup
    if dbms_lob.istemporary(l_clob) = 1 then
      dbms_lob.freetemporary(l_clob);
    end if;
  end;

  procedure appends_empty_line is
    l_clob clob;
  begin
    rest_compile.clob_append_line(l_clob, '');

    ut.expect(dbms_lob.substr(l_clob, 32767, 1)).to_equal(chr(10));

    -- cleanup
    if dbms_lob.istemporary(l_clob) = 1 then
      dbms_lob.freetemporary(l_clob);
    end if;
  end;

  procedure appends_null_line_as_newline is
    l_clob clob;
  begin
    -- In PL/SQL, NULL || 'x' yields 'x', so p_line||chr(10) becomes chr(10)
    rest_compile.clob_append_line(l_clob, null);

    ut.expect(dbms_lob.substr(l_clob, 32767, 1)).to_equal(chr(10));

    -- cleanup
    if dbms_lob.istemporary(l_clob) = 1 then
      dbms_lob.freetemporary(l_clob);
    end if;
  end;

    ------
  procedure ignores_sqlplus_directives is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
         to_clob('PROMPT hello' || chr(10) ||
                 'SET DEFINE OFF' || chr(10) ||
                 'DEFINE X = 1' || chr(10) ||
                 'create table t1 (c number);' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'create table t1', 1, 1)).to_be_greater_than(0);
  end;


  procedure splits_simple_ddl is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('create table t1 (c number);' || chr(10) ||
              'alter table t1 add (c2 varchar2(10));' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(2);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'create table t1', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(2).stmt_text, 'alter table t1', 1, 1)).to_be_greater_than(0);
  end;


  procedure collects_plsql_block is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('declare' || chr(10) ||
              '  l_test number := 1;' || chr(10) ||
              'begin' || chr(10) ||
              '  dbms_output.put_line(l_test);' || chr(10) ||
              'end;' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);
    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'declare', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'end;', 1, 1)).to_be_greater_than(0);
  end;

  procedure collects_nested_anonymous_block is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('declare' || chr(10) ||
              '  l_file_name varchar2(2000) := ''changelog_patch_0.3.0.md'';' || chr(10) ||
              'begin' || chr(10) ||
              '  declare' || chr(10) ||
              '    l_version varchar2(100);' || chr(10) ||
              '  begin' || chr(10) ||
              '    l_version := substr(l_file_name, instr(l_file_name, ''_'', 1, 2)+1);' || chr(10) ||
              '    begin' || chr(10) ||
              '      null;' || chr(10) ||
              '    exception' || chr(10) ||
              '      when dup_val_on_index then' || chr(10) ||
              '        null;' || chr(10) ||
              '    end;' || chr(10) ||
              '  exception' || chr(10) ||
              '    when others then' || chr(10) ||
              '      raise;' || chr(10) ||
              '  end;' || chr(10) ||
              '  commit;' || chr(10) ||
              'exception' || chr(10) ||
              '  when others then' || chr(10) ||
              '    raise;' || chr(10) ||
              'end;' || chr(10) ||
              '/' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'when dup_val_on_index then', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'commit;', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'exception', 1, 2)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, chr(10) || '/' || chr(10), 1, 1)).to_equal(0);
  end;


  procedure collects_cor_terminated_by_slash is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('create or replace package p1 is' || chr(10) ||
              '  procedure x;' || chr(10) ||
              'end;' || chr(10) ||
              '/' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'create or replace package p1', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'end;', 1, 1)).to_be_greater_than(0);

    -- Ensure "/" itself is not part of the statement text
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, chr(10) || '/' || chr(10), 1, 1)).to_equal(0);
  end;

  procedure collects_simple_ddl_terminated_by_slash is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('create unique index rc_simple_ddl_slash_i1 on rc_simple_ddl_slash_t' || chr(10) ||
              '  (id)' || chr(10) ||
              '/' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'create unique index rc_simple_ddl_slash_i1', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, chr(10) || '/' || chr(10), 1, 1)).to_equal(0);
  end;


  procedure ignores_semicolon_in_string is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('declare' || chr(10) ||
              'begin' || chr(10) ||
              '  dbms_output.put_line(''a;b;c'');' || chr(10) ||
              'end;' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, '''a;b;c''', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'end;', 1, 1)).to_be_greater_than(0);
  end;

  procedure ignores_semicolon_in_quoted_string is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob(q'~declare
              begin
                dbms_output.put_line('a;b;c');
                dbms_output.put_line('a;b;c');
              end;~');

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, '''a;b;c''', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'end;', 1, 1)).to_be_greater_than(0);
  end;

  procedure ignores_semicolon_in_block_comment is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('create table t2 (' || chr(10) ||
              '  c number /* this ; is inside comment */' || chr(10) ||
              ');' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'create table t2', 1, 1)).to_be_greater_than(0);
  end;

  procedure ignores_semicolon_in_line_comment is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('create table t2 (' || chr(10) ||
              '  c number -- this ; is inside comment' || chr(10) ||
              ');' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'create table t2', 1, 1)).to_be_greater_than(0);
  end;

  procedure collects_anonymous_block_with_multiline_comment is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('declare' || chr(10) ||
              '  l_value number := 1;' || chr(10) ||
              'begin' || chr(10) ||
              '  /*' || chr(10) ||
              '    ------- TEMPLATE END -------' || chr(10) ||
              '    keep this text inside the comment block' || chr(10) ||
              '  */' || chr(10) ||
              '  l_value := l_value + 1;' || chr(10) ||
              '  commit;' || chr(10) ||
              'exception' || chr(10) ||
              '  when others then' || chr(10) ||
              '    raise;' || chr(10) ||
              'end;' || chr(10) ||
              '/' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'TEMPLATE END', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'commit;', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'exception', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, chr(10) || '/' || chr(10), 1, 1)).to_equal(0);
  end;

  procedure collects_nested_block_after_line_comment is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('declare' || chr(10) ||
              '  l_file_name varchar2(2000) := ''changelog_patch_0.3.0.md'';' || chr(10) ||
              'begin' || chr(10) ||
              '  declare' || chr(10) ||
              '    l_version varchar2(100);' || chr(10) ||
              '  begin' || chr(10) ||
              '    l_version := substr(l_file_name, instr(l_file_name, ''_'', 1, 2)+1);' || chr(10) ||
              '    -- simulate changelog upload block' || chr(10) ||
              '    begin' || chr(10) ||
              '      null;' || chr(10) ||
              '    exception' || chr(10) ||
              '      when dup_val_on_index then' || chr(10) ||
              '        null;' || chr(10) ||
              '    end;' || chr(10) ||
              '  exception' || chr(10) ||
              '    when others then' || chr(10) ||
              '      raise;' || chr(10) ||
              '  end;' || chr(10) ||
              '  commit;' || chr(10) ||
              'exception' || chr(10) ||
              '  when others then' || chr(10) ||
              '    raise;' || chr(10) ||
              'end;' || chr(10) ||
              '/' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'simulate changelog upload block', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'commit;', 1, 1)).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'exception', 1, 2)).to_be_greater_than(0);
  end;

  procedure skips_leading_multiline_comment_before_statement is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('/*' || chr(10) ||
              '  ------- TEMPLATE END -------' || chr(10) ||
              '  comment before the first statement' || chr(10) ||
              '*/' || chr(10) ||
              'create table t_leading_comment (c number);' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);
    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, 'create table t_leading_comment', 1, 1)).to_be_greater_than(0);
  end;

  procedure runs_nested_anonymous_block is
    l_script  clob;
    l_result  json_object_t;
  begin
    l_script :=
      to_clob('declare' || chr(10) ||
              '  l_outer number := 0;' || chr(10) ||
              'begin' || chr(10) ||
              '  declare' || chr(10) ||
              '    l_inner number := 1;' || chr(10) ||
              '  begin' || chr(10) ||
              '    l_outer := l_outer + l_inner;' || chr(10) ||
              '  exception' || chr(10) ||
              '    when others then' || chr(10) ||
              '      raise;' || chr(10) ||
              '  end;' || chr(10) ||
              '  if l_outer != 1 then' || chr(10) ||
              '    raise_application_error(-20001, ''unexpected value'');' || chr(10) ||
              '  end if;' || chr(10) ||
              'exception' || chr(10) ||
              '  when others then' || chr(10) ||
              '    raise;' || chr(10) ||
              'end;' || chr(10) ||
              '/' || chr(10));

    l_result := rest_compile.run_content(p_fname => 'nested_block_test.sql',
                                         p_script_content => l_script);

    ut.expect(l_result.get_number('total_statements')).to_equal(1);
    ut.expect(l_result.get_number('executed_count')).to_equal(1);
  end;

  procedure runs_anonymous_block_with_multiline_comment is
    l_script  clob;
    l_result  json_object_t;
  begin
    l_script :=
      to_clob('declare' || chr(10) ||
              '  l_value number := 1;' || chr(10) ||
              'begin' || chr(10) ||
              '  /*' || chr(10) ||
              '    ------- TEMPLATE END -------' || chr(10) ||
              '    keep this text inside the comment block' || chr(10) ||
              '  */' || chr(10) ||
              '  l_value := l_value + 1;' || chr(10) ||
              '  if l_value != 2 then' || chr(10) ||
              '    raise_application_error(-20002, ''unexpected value'');' || chr(10) ||
              '  end if;' || chr(10) ||
              'exception' || chr(10) ||
              '  when others then' || chr(10) ||
              '    raise;' || chr(10) ||
              'end;' || chr(10) ||
              '/' || chr(10));

    l_result := rest_compile.run_content(p_fname => 'comment_block_test.sql',
                                         p_script_content => l_script);

    ut.expect(l_result.get_number('total_statements')).to_equal(1);
    ut.expect(l_result.get_number('executed_count')).to_equal(1);
  end;

  procedure runs_simple_ddl_with_trailing_semicolons is
    l_script clob;
    l_result json_object_t;
  begin
    l_script :=
      to_clob('begin' || chr(10) ||
              '  execute immediate ''drop table rc_semicolon_ddl_t purge'';' || chr(10) ||
              'exception' || chr(10) ||
              '  when others then' || chr(10) ||
              '    if sqlcode != -942 then' || chr(10) ||
              '      raise;' || chr(10) ||
              '    end if;' || chr(10) ||
              'end;' || chr(10) ||
              '/' || chr(10) ||
              'create table rc_semicolon_ddl_t (' || chr(10) ||
              '  id number not null' || chr(10) ||
              ');' || chr(10) ||
              'create unique index rc_semicolon_ddl_i1 on rc_semicolon_ddl_t' || chr(10) ||
              '  (id)' || chr(10) ||
              '  logging' || chr(10) ||
              ';' || chr(10) ||
              'drop table rc_semicolon_ddl_t purge;' || chr(10));

    l_result := rest_compile.run_content(p_fname => 'simple_ddl_semicolon_test.sql',
                                         p_script_content => l_script);

    ut.expect(l_result.get_number('total_statements')).to_equal(4);
    ut.expect(l_result.get_number('executed_count')).to_equal(4);
  end;

  procedure runs_simple_ddl_with_slash_terminator is
    l_script clob;
    l_result json_object_t;
  begin
    l_script :=
      to_clob('begin' || chr(10) ||
              '  execute immediate ''drop table rc_slash_ddl_t purge'';' || chr(10) ||
              'exception' || chr(10) ||
              '  when others then' || chr(10) ||
              '    if sqlcode != -942 then' || chr(10) ||
              '      raise;' || chr(10) ||
              '    end if;' || chr(10) ||
              'end;' || chr(10) ||
              '/' || chr(10) ||
              'create table rc_slash_ddl_t (' || chr(10) ||
              '  id number not null' || chr(10) ||
              ');' || chr(10) ||
              'create unique index rc_slash_ddl_i1 on rc_slash_ddl_t' || chr(10) ||
              '  (id)' || chr(10) ||
              '/' || chr(10) ||
              'drop table rc_slash_ddl_t purge;' || chr(10));

    l_result := rest_compile.run_content(p_fname => 'simple_ddl_slash_test.sql',
                                         p_script_content => l_script);

    ut.expect(l_result.get_number('total_statements')).to_equal(4);
    ut.expect(l_result.get_number('executed_count')).to_equal(4);
  end;

  procedure runs_plain_blob_payload is
    l_payload   blob;
    l_result    json_object_t;
    l_log_count number;
  begin
    l_payload := clob_to_blob_utf8(to_clob('begin null; end;' || chr(10) || '/' || chr(10)));

    l_result := rest_compile.run_payload(p_request_name => 'plain_payload_test.sql',
                                         p_payload      => l_payload,
                                         p_content_type => 'text/plain');

    ut.expect(json_value_varchar2(l_result, '$.success')).to_equal('true');
    ut.expect(json_value_varchar2(l_result, '$.file_name')).to_equal('plain_payload_test.sql');
    ut.expect(json_value_varchar2(l_result, '$.is_zip')).to_equal('false');
    ut.expect(json_value_varchar2(l_result, '$.info.total_statements')).to_equal('1');

    select count(*)
      into l_log_count
      from rest_compile_logs
     where rcl_fname = 'plain_payload_test.sql'
       and rcl_is_zip = 'N'
       and rcl_content_type = 'text/plain';

    ut.expect(l_log_count).to_equal(1);
  end;

  procedure runs_single_file_zip_payload is
    l_payload   blob;
    l_result    json_object_t;
    l_log_count number;
  begin
    l_payload := create_zip_payload(p_file_name    => 'db/ati/demo_zip_payload.sql',
                                    p_file_content => to_clob('begin null; end;' || chr(10) || '/' || chr(10)));

    l_result := rest_compile.run_payload(p_request_name => 'compile_request.zip',
                                         p_payload      => l_payload,
                                         p_content_type => 'application/zip');

    ut.expect(json_value_varchar2(l_result, '$.success')).to_equal('true');
    ut.expect(json_value_varchar2(l_result, '$.file_name')).to_equal('db/ati/demo_zip_payload.sql');
    ut.expect(json_value_varchar2(l_result, '$.is_zip')).to_equal('true');
    ut.expect(json_value_varchar2(l_result, '$.info.total_statements')).to_equal('1');

    select count(*)
      into l_log_count
      from rest_compile_logs
     where rcl_fname = 'db/ati/demo_zip_payload.sql'
       and rcl_is_zip = 'Y'
       and rcl_content_type = 'application/zip';

    ut.expect(l_log_count).to_equal(1);
  end;

  procedure rejects_multi_file_zip_payload is
    l_payload blob;
    l_result  json_object_t;
  begin
    l_payload := create_zip_payload(p_file_name           => 'db/ati/demo_zip_payload.sql',
                                    p_file_content        => to_clob('begin null; end;' || chr(10) || '/' || chr(10)),
                                    p_second_file_name    => 'db/ati/demo_zip_payload_2.sql',
                                    p_second_file_content => to_clob('begin null; end;' || chr(10) || '/' || chr(10)));

    l_result := rest_compile.run_payload(p_request_name => 'compile_request.zip',
                                         p_payload      => l_payload,
                                         p_content_type => 'application/zip');

    ut.expect(json_value_varchar2(l_result, '$.success')).to_equal('false');
    ut.expect(instr(json_value_varchar2(l_result, '$.message'), 'exactly one file')).to_be_greater_than(0);
  end;

  procedure rejects_invalid_zip_payload is
    l_payload blob;
    l_result  json_object_t;
  begin
    l_payload := clob_to_blob_utf8(to_clob('not a zip payload'));

    l_result := rest_compile.run_payload(p_request_name => 'compile_request.zip',
                                         p_payload      => l_payload,
                                         p_content_type => 'application/zip');

    ut.expect(json_value_varchar2(l_result, '$.success')).to_equal('false');
    ut.expect(json_value_varchar2(l_result, '$.message')).to_be_not_null;
  end;
    ------

   procedure test_multiline_comment_slashs is
    l_script clob;
    l_stmts  rest_compile.t_statement_list;
  begin
    l_script :=
      to_clob('create or replace package p1 is' || chr(10) ||
              '  /**' || chr(10) ||
              '  * This is a comment' || chr(10) ||
              '  */' || chr(10) ||
              '  procedure x;' || chr(10) ||
              'end;' || chr(10) ||
              '/' || chr(10));

    l_stmts := rest_compile.split_into_statements(l_script);

    ut.expect(l_stmts.count).to_equal(1);


    ut.expect(dbms_lob.instr(l_stmts(1).stmt_text, '/*', 1, 1)).to_be_greater_than(0);
  end;

end;
/
