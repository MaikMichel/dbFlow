create or replace package rest_compile is
    type r_statement is record (
        stmt_type      varchar2(30),
        stmt_text      clob
    );

    type t_array is table of varchar2(32767) index by binary_integer;
    type t_statement_list is table of r_statement index by binary_integer;
    type t_file_list is table of varchar2(32767) index by binary_integer;


    function run_payload(p_request_name in varchar2,
                         p_payload      in blob,
                         p_content_type in varchar2) return json_object_t;
    procedure run_payload_rest(p_request_name in varchar2,
                               p_payload      in blob,
                               p_content_type in varchar2);
    procedure run_content_rest(p_fname          in varchar2,
                               p_script_content in clob);

    function normalize_input(p_script in clob) return clob;
    function clob_to_lines(p_clob in clob) return t_array;
    function is_sqlplus_command(p_line in varchar2) return boolean;
    procedure clob_append_line(p_target in out nocopy clob, p_line in varchar2);

    function split_into_statements(p_script in clob)
        return t_statement_list;


    -- function split_script(p_script in clob) return t_statement_list;
    -- function classify_statement(p_text in clob) return varchar2;
    procedure execute_statement(p_fname in varchar2,
                                p_stmt in r_statement);
    function run_content(p_fname          in varchar2,
                         p_script_content in clob) return json_object_t;

    procedure import_app_rest( p_app_file_content   in clob,
                                p_to_workspace       in varchar2,
                                p_to_schema          in varchar2,
                                p_application_id     in number);
end;
/
