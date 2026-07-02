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

    -- Security token: SHA-256 hash of instance_url|schema|workspace, computed at
    -- package initialisation. Every _rest endpoint validates the x-dbflow-token
    -- request header against this value when it is not null.
    g_client_token varchar2(64);
    function check_client_token return boolean;

    -- Set the client token for the current request. Each ORDS handler binds the
    -- x-dbflow-token request header to a parameter and passes it here, because an
    -- undeclared custom header is not exposed via owa_util.get_cgi_env.
    procedure set_request_token(p_token in varchar2);

    -- API versioning: api_level is increased whenever new endpoints are added
    -- or the request contract changes. Clients (dbFlux/dbFlow) read it via
    -- GET /compile and refuse to call endpoints the installed package does
    -- not provide yet.
    -- Level 3: header parameters are also accepted in hyphen form (app-id,
    -- file-name, ...) because proxies like Akamai or nginx drop request
    -- headers whose names contain underscores.
    c_version   constant varchar2(20) := '1.3.1';
    c_api_level constant pls_integer  := 3;

    function get_version return varchar2;
    function get_api_level return number;
    procedure get_info_rest;

    -- schema compilation (response: JSON with errors in user_errors shape)
    procedure compile_schema_rest(p_compile_all      in varchar2,
                                  p_db_folder        in varchar2,
                                  p_enable_warnings  in varchar2,
                                  p_warning_string   in varchar2,
                                  p_warning_excludes in varchar2);

    -- exports: respond with application/zip on success, error JSON otherwise
    procedure export_app_rest         (p_app_id in varchar2, p_export_options in varchar2);
    procedure export_plugin_rest      (p_app_id in varchar2, p_plugin_name in varchar2);
    procedure export_static_files_rest(p_app_id in varchar2, p_file_name in varchar2);
    procedure export_plugin_files_rest(p_app_id in varchar2, p_plugin_name in varchar2, p_file_name in varchar2);
    procedure export_schema_rest      (p_folder in varchar2, p_file_name in varchar2, p_grants_with_object in varchar2);
    procedure export_rest_module_rest (p_module_name in varchar2);

    -- remove an APEX static file (response: JSON {success, found, removed[]})
    procedure remove_static_file_rest (p_app_id in varchar2, p_file_name in varchar2, p_file_ext in varchar2);
end;
/
