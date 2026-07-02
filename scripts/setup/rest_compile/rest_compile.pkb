create or replace package body rest_compile is


    g_logs        t_array;
    g_log_entries json_array_t := json_array_t();

    -- client security token of the current request, set by each ORDS handler
    -- from the bound x-dbflow-token header (see set_request_token)
    g_request_token varchar2(64);

    -- state for the schema DDL export helpers (see export_schema_rest)
    c_exp_crlf          constant varchar2(10) := chr(13)||chr(10);
    g_exp_objects_found boolean := false;
    g_exp_files         t_array;

    /*
    * ANSI color codes for optional debug output.
    *
    * Note:
    * - Debug helper procedures are intentionally kept for ad-hoc troubleshooting.
    * - Not every color constant is used in the current runtime path.
    */
    gc_red           varchar2(7) := chr(27) || '[31m';
    gc_green         varchar2(7) := chr(27) || '[32m';
    gc_yellow        varchar2(7) := chr(27) || '[33m';
    gc_blue          varchar2(7) := chr(27) || '[34m';
    gc_cyan          varchar2(7) := chr(27) || '[36m';
    gc_reset         varchar2(7) := chr(27) || '[0m';

    /*
    * Reset and clear internal logs.
    */
    procedure reset_logs is
    begin
        g_logs.delete;
        g_log_entries := json_array_t();
    end reset_logs;

    procedure set_request_token(p_token in varchar2) is
    begin
        g_request_token := lower(trim(p_token));
    end set_request_token;

    function check_client_token return boolean is
        l_token varchar2(64);
    begin
        if g_client_token is not null then
            l_token := g_request_token;
            if l_token is null or l_token <> g_client_token then
                owa_util.status_line(401, 'Unauthorized', false);
                owa_util.mime_header('application/json', false);
                owa_util.http_header_close;
                sys.htp.p('{"success":false,"error":"Unauthorized","message":"Invalid or missing x-dbflow-token header"}');
                return false;
            end if;
        end if;
        return true;
    end check_client_token;

    /*
    * Append one line to the in-memory log buffer.
    *
    * This helper is intentionally kept for debug/troubleshooting scenarios.
    */
    procedure log(p_line in varchar2) is
    begin
        g_logs(g_logs.count + 1) := p_line;
    end log;

    /**
    * Print a formatted debug message to DBMS_OUTPUT.
    *
    * This helper is intentionally kept for ad-hoc diagnostics.
    */
    procedure print(p_message    in varchar2,
                    p_color      in varchar2    default null,
                    p0           in varchar2    default null,
                    p1           in varchar2    default null,
                    p2           in varchar2    default null,
                    p3           in varchar2    default null,
                    p4           in varchar2    default null,
                    p5           in varchar2    default null,
                    p6           in varchar2    default null,
                    p7           in varchar2    default null,
                    p8           in varchar2    default null,
                    p9           in varchar2    default null) is

        l_message varchar2(32767);
    begin
      l_message := apex_string.format(p_message, p0, p1, p2, p3, p4, p5, p6, p7, p8, p9);
      dbms_output.put_line(case when p_color is not null then p_color end
                             || l_message ||
                             case when p_color is not null then gc_reset end);
    end;

    procedure debug(p_message    in varchar2,
                    p0           in varchar2    default null,
                    p1           in varchar2    default null,
                    p2           in varchar2    default null,
                    p3           in varchar2    default null,
                    p4           in varchar2    default null,
                    p5           in varchar2    default null,
                    p6           in varchar2    default null,
                    p7           in varchar2    default null,
                    p8           in varchar2    default null,
                    p9           in varchar2    default null) is
    begin
      print(p_message, gc_cyan, p0, p1, p2, p3, p4, p5, p6, p7, p8, p9);
    end;

    function to_json_array_t(p_string in clob) return json_array_t is
        l_array    json_array_t := json_array_t();
        l_line     varchar2(4000 char);
        l_pos      number := 1;
        l_next_pos number;
    begin
        loop
            l_next_pos := instr(p_string, chr(10), l_pos);
            if l_next_pos = 0 then
                l_line := trim(substr(p_string, l_pos));
                if length(l_line) > 0 then
                    l_array.append(l_line);
                end if;
                exit;
            else
                l_line := trim(substr(p_string, l_pos, l_next_pos - l_pos));
                if length(l_line) > 0 then
                    l_array.append(l_line);
                end if;
                l_pos := l_next_pos + 1;
            end if;
        end loop;
        return l_array;
    end to_json_array_t;

    function get_user_errors(p_file_name in varchar2) return json_array_t is
        l_finding json_object_t := json_object_t(); 
        l_return  json_array_t  := json_array_t;
        l_extension varchar2(100 char);
        l_base_file varchar2(1000 char);
    begin
        l_extension := regexp_substr(p_file_name, '[^.]+$');
        l_base_file := regexp_substr(p_file_name, '[^/\\]+$');
        for cur in (with errms as (select attribute, line||':'||position lpos, name, type,
                                            replace(substr(text, 1, instr(text, ':', 1, 1) -1), ' ') errtype,
                                            replace(substr(text, instr(text, ': ', 1, 1) + 2), chr(10), ' ') errtext
                                    from user_errors
                                    where attribute in ('ERROR', 'WARNING')
                                        and lower(name||decode(type, 'PACKAGE', '.pks',
                                                    'PACKAGE BODY', '.pkb',
                                                    'TYPE', '.tps',
                                                    'TYPE BODY', '.tpb',
                                                    '.'||l_extension)) = lower(l_base_file))
                        select attribute, lpos, name, errtype, errtext, max(length(errtype)) over () mlen, max(length(lpos)) over () mlpos
                            from errms
                    order by type, name, lpos)
        loop            
            l_finding.put('attribute', cur.attribute);
            l_finding.put('typeid',    rpad(cur.errtype, cur.mlen, ' '));
            l_finding.put('fileinfo',  p_file_name|| ':' || rpad(cur.lpos, cur.mlpos , ' '));
            l_finding.put('errtext',   cur.errtext);            
            l_return.append(l_finding);
        end loop;

        return l_return;        
    end;
    procedure log_result(p_type        in varchar2,
                         p_status      in varchar2,
                         p_msg         in varchar2,
                         p_stmt        in clob,
                         p_user_errors in json_array_t default null,
                         p_duration_ms in number) is
        l_entry json_object_t := json_object_t();
    begin

        l_entry.put('statement_type', p_type);
        l_entry.put('status', p_status);
        l_entry.put('error_message', p_msg);
        l_entry.put('duration_ms', p_duration_ms);

        if p_stmt is not null then
            l_entry.put('statement_preview', to_json_array_t(p_stmt));
        end if;
        if p_user_errors is not null then
            l_entry.put('user_errors', p_user_errors);
        end if;
        g_log_entries.append(l_entry);
    end log_result;

    procedure append_runtime_logs(p_response in out nocopy json_object_t) is
        l_logs json_array_t := json_array_t();
    begin
        if g_logs.count > 0 then
            for i in g_logs.first .. g_logs.last loop
                l_logs.append(g_logs(i));
            end loop;
            p_response.put('logs', l_logs);
        end if;

        p_response.put('log_results', g_log_entries);
    end append_runtime_logs;

    procedure emit_json_response(p_response in json_object_t) is
        l_clob clob := p_response.to_clob;
        l_pos  pls_integer := 1;
    begin
        while l_pos <= dbms_lob.getlength(l_clob) loop
            sys.htp.prn(dbms_lob.substr(l_clob, 32767, l_pos));
            l_pos := l_pos + 32767;
        end loop;
    end emit_json_response;

    function build_error_response return json_object_t is
        l_response json_object_t := json_object_t();
    begin
        l_response.put('success', false);
        l_response.put('error', true);
        l_response.put('code', sqlcode);
        l_response.put('message', sqlerrm);
        l_response.put('stackTrace', to_json_array_t(dbms_utility.format_error_backtrace));
        l_response.put('timestamp', current_timestamp);
        append_runtime_logs(l_response);
        return l_response;
    end build_error_response;

    function blob_to_clob_utf8(p_blob in blob) return clob is
        l_clob         clob;
        l_dest_offset  integer := 1;
        l_src_offset   integer := 1;
        l_lang_context integer := dbms_lob.default_lang_ctx;
        l_warning      integer;
    begin
        if p_blob is null or dbms_lob.getlength(p_blob) = 0 then
            return empty_clob();
        end if;

        dbms_lob.createtemporary(l_clob, true);
        dbms_lob.converttoclob(dest_lob     => l_clob,
                               src_blob     => p_blob,
                               amount       => dbms_lob.lobmaxsize,
                               dest_offset  => l_dest_offset,
                               src_offset   => l_src_offset,
                               blob_csid    => nls_charset_id('AL32UTF8'),
                               lang_context => l_lang_context,
                               warning      => l_warning);

        if l_warning != dbms_lob.no_warning then
            raise_application_error(-20001, 'Payload could not be converted from UTF-8.');
        end if;

        return l_clob;
    end blob_to_clob_utf8;

    function is_zip_payload(p_payload      in blob,
                            p_content_type in varchar2) return boolean is
        l_content_type varchar2(255 char) := lower(nvl(trim(p_content_type), ''));
        l_magic        raw(2);
    begin
        if l_content_type like '%zip%' then
            return true;
        end if;

        if p_payload is null or dbms_lob.getlength(p_payload) < 2 then
            return false;
        end if;

        l_magic := dbms_lob.substr(p_payload, 2, 1);
        return l_magic = hextoraw('504B');
    end is_zip_payload;

    procedure extract_single_file_from_zip(p_zip_blob         in blob,
                                           p_request_name     in varchar2,
                                           p_out_file_name    out varchar2,
                                           p_out_file_content out clob) is
        l_files        apex_zip.t_files;
        l_file_name    varchar2(32767);
        l_file_count   pls_integer := 0;
        l_file_content blob;
    begin
        l_files := apex_zip.get_files(p_zipped_blob => p_zip_blob);

        for i in 1 .. l_files.count loop
            if l_files(i) is not null and not regexp_like(l_files(i), '/$') then
                l_file_count := l_file_count + 1;
                l_file_name := l_files(i);
            end if;
        end loop;

        if l_file_count = 0 then
            raise_application_error(-20002, 'ZIP payload does not contain a file.');
        end if;

        if l_file_count > 1 then
            raise_application_error(-20003, 'ZIP payload must contain exactly one file.');
        end if;

        l_file_content := apex_zip.get_file_content(p_zipped_blob => p_zip_blob,
                                                    p_file_name   => l_file_name);

        p_out_file_name := coalesce(l_file_name, p_request_name);
        p_out_file_content := blob_to_clob_utf8(l_file_content);
    end extract_single_file_from_zip;

    procedure log_request_payload(p_fname        in varchar2,
                                  p_content      in clob,
                                  p_payload      in blob,
                                  p_content_type in varchar2,
                                  p_is_zip       in boolean) is
    begin
        insert into rest_compile_logs (
            rcl_fname,
            rcl_content,
            rcl_payload,
            rcl_content_type,
            rcl_is_zip
        ) values (
            p_fname,
            p_content,
            p_payload,
            p_content_type,
            case when p_is_zip then 'Y' else 'N' end
        );
        commit;
    end log_request_payload;

    function normalize_input(p_script in clob) return clob is
        l_clean clob := p_script;
    begin
        if l_clean is null then
            return empty_clob();
        end if;

        l_clean := replace(l_clean, chr(13) || chr(10), chr(10));
        l_clean := replace(l_clean, chr(13), chr(10));
        l_clean := rtrim(l_clean, chr(10) || ' ' || chr(9));

        return l_clean || chr(10);
    end normalize_input;

    function clob_to_lines(p_clob in clob)
        return t_array
    is
        l_lines     t_array;
        l_pos       pls_integer := 1;
        l_nl_pos    pls_integer;
        l_len       pls_integer;
        l_line_len  pls_integer;
    begin
        if p_clob is null then
        return l_lines; -- empty associative array
        end if;

        l_len := dbms_lob.getlength(p_clob);

        while l_pos <= l_len loop
            -- Find next LF starting from l_pos
            l_nl_pos := dbms_lob.instr(p_clob, chr(10), l_pos);

            if l_nl_pos = 0 then
                -- Last line without LF at the end
                l_line_len := l_len - l_pos + 1;
            else
                -- Line ends right before LF
                l_line_len := l_nl_pos - l_pos;
            end if;

            if l_line_len > 32767 then
                raise_application_error(
                -20000,
                'Line too long for VARCHAR2(32767): ' || l_line_len || ' characters.'
                );
            end if;

            if l_line_len = 0 then
                l_lines(nvl(l_lines.last, 0) + 1) := '';
            else
                l_lines(nvl(l_lines.last, 0) + 1) := dbms_lob.substr(p_clob, l_line_len, l_pos);
            end if;

            exit when l_nl_pos = 0;  -- no more newlines
            l_pos := l_nl_pos + 1;   -- continue after LF
        end loop;

        return l_lines;
    end clob_to_lines;

    function is_comment_only_line(p_line varchar2) return boolean is
        l_trimmed_line varchar2(32767) := ltrim(p_line);
    begin
        if l_trimmed_line is null then
            return true; -- treat empty as ignorable
        end if;

        if substr(l_trimmed_line, 1, 2) = '--' then
            return true;
        end if;

        return false;
    end;

    function is_sqlplus_command(p_line in varchar2) return boolean is
        l_trimmed_line varchar2(32767) := ltrim(p_line);
        l_upper_line   varchar2(32767);
    begin
        if l_trimmed_line is null then
            return true; -- ignore empty lines
        end if;

        if substr(ltrim(p_line), 1, 2) = '--' then return true; end if;
        l_upper_line := upper(l_trimmed_line);

         -- PROMPT with or without payload
        if regexp_like(l_upper_line, '^PROMPT([[:space:]].*)?$') then
            return true;
        end if;

        -- other directives (keep your existing ones)
        if regexp_like(l_upper_line, '^SET([[:space:]].*)?$') then return true; end if;
        if regexp_like(l_upper_line, '^DEFINE([[:space:]].*)?$') then return true; end if;
        if regexp_like(l_upper_line, '^UNDEFINE([[:space:]].*)?$') then return true; end if;
        if regexp_like(l_upper_line, '^WHENEVER([[:space:]].*)?$') then return true; end if;
        if regexp_like(l_upper_line, '^SPOOL([[:space:]].*)?$') then return true; end if;
        if regexp_like(l_upper_line, '^(COLUMN|COL)([[:space:]].*)?$') then return true; end if;
        if regexp_like(l_upper_line, '^ACCEPT([[:space:]].*)?$') then return true; end if;
        if regexp_like(l_upper_line, '^HOST([[:space:]].*)?$') then return true; end if;
        if regexp_like(l_upper_line, '^(REM|REMARK)([[:space:]].*)?$') then return true; end if;

        return false;
    end;

    procedure clob_append_line(p_target in out nocopy clob, p_line in varchar2) is
    begin
        if p_target is null then
        dbms_lob.createtemporary(p_target, true);
        end if;
        dbms_lob.append(p_target, to_clob(p_line || chr(10)));
    end;


    function split_into_statements(p_script in clob) return t_statement_list is
        -- Stateful SQL/PLSQL parser that splits one deployment script into executable
        -- statements while preserving statement text. Terminator handling:
        --   * simple DDL: finalize on ';'
        --   * CREATE OR REPLACE units: finalize on slash line '/'
        -- Parsing guards ensure ';' in strings/comments and END IF/LOOP/CASE do not
        -- prematurely terminate outer blocks.
        l_lines      t_array;
        l_result     t_statement_list;

        -- Current statement buffer
        l_stmt       r_statement;

        -- Stack of expected closing tokens for comments, grouping chars and
        -- simple DDL semicolon-terminated statements.
        type t_stack is table of varchar2(200) index by pls_integer;
        l_stack      t_stack;
        l_stack_top  pls_integer := 0;

        -- States for parsing
        l_in_squote          boolean := false;  -- inside '...'
        l_in_line_comment    boolean := false;  -- inside -- ...
        l_in_block_comment   boolean := false;  -- inside /* ... */
        l_expect_slash_end   boolean := false;  -- CREATE OR REPLACE requires '/' line to finish
        l_end_keyword_seen   boolean := false;  -- saw END keyword; close a PL/SQL scope on ';'
        l_plsql_block_depth  pls_integer := 0;  -- active PL/SQL scopes closed by END;
        l_pending_header_debt pls_integer := 0; -- headers that still need their matching BEGIN

        procedure push(p_token varchar2) is
        begin
            l_stack_top := l_stack_top + 1;
            l_stack(l_stack_top) := p_token;
        end;

        function top return varchar2 is
        begin
            return case when l_stack_top > 0 then l_stack(l_stack_top) end;
        end;

        procedure pop_expected(p_token varchar2) is
        begin
            if l_stack_top > 0 and l_stack(l_stack_top) = p_token then
                l_stack.delete(l_stack_top);
                l_stack_top := l_stack_top - 1;
            end if;
        end;

        function stack_empty return boolean is
        begin
            return l_stack_top = 0;
        end;

        function only_semicolon_pending return boolean is
        begin
            return l_stack_top = 1 and l_stack(1) = 'SEMICOLON';
        end;

        procedure skip_leading_block_comments(p_line         in out nocopy varchar2,
                                              p_line_skipped out boolean) is
            l_close_pos pls_integer;
            l_work      varchar2(32767) := p_line;
        begin
            p_line_skipped := false;

            loop
                if l_in_block_comment then
                    l_close_pos := instr(l_work, '*/');

                    if l_close_pos = 0 then
                        p_line := null;
                        p_line_skipped := true;
                        return;
                    end if;

                    l_work := ltrim(substr(l_work, l_close_pos + 2));
                    l_in_block_comment := false;

                    if l_work is null then
                        p_line := null;
                        p_line_skipped := true;
                        return;
                    end if;
                elsif regexp_like(ltrim(l_work), '^/\*') then
                    l_work := ltrim(l_work);
                    l_close_pos := instr(l_work, '*/');

                    if l_close_pos = 0 then
                        l_in_block_comment := true;
                        p_line := null;
                        p_line_skipped := true;
                        return;
                    end if;

                    l_work := ltrim(substr(l_work, l_close_pos + 2));

                    if l_work is null then
                        p_line := null;
                        p_line_skipped := true;
                        return;
                    end if;
                else
                    exit;
                end if;
            end loop;

            p_line := l_work;
        end skip_leading_block_comments;

        procedure open_plsql_scope(p_requires_begin in boolean default false) is
        begin
            l_plsql_block_depth := l_plsql_block_depth + 1;

            if p_requires_begin then
                l_pending_header_debt := l_pending_header_debt + 1;
            end if;
        end open_plsql_scope;

        procedure handle_begin_keyword is
        begin
            if l_pending_header_debt > 0 then
                l_pending_header_debt := l_pending_header_debt - 1;
            else
                open_plsql_scope;
            end if;
        end handle_begin_keyword;

        function next_word(p_line varchar2, p_pos pls_integer) return varchar2 is
            l_j pls_integer := p_pos;
            l_len pls_integer := length(p_line);
        begin
            -- skip spaces
            while l_j <= l_len and substr(p_line, l_j, 1) in (' ', chr(9)) loop
                l_j := l_j + 1;
            end loop;

            -- if next is ';' then treat as no word
            if l_j > l_len or substr(p_line, l_j, 1) = ';' then
                return null;
            end if;

            -- read identifier-ish word
            declare
                l_k pls_integer := l_j;
            begin
                while l_k <= l_len and regexp_like(substr(p_line, l_k, 1), '[A-Za-z_0-9$#]') loop
                    l_k := l_k + 1;
                end loop;
                return upper(substr(p_line, l_j, l_k - l_j));
            end;
        end;

        -- Detect openers based on keywords (outside comments/strings)
        procedure handle_keyword_openers(p_line varchar2) is
            l_up varchar2(32767) := upper(p_line);
        begin
            if regexp_like(l_up, '^[[:space:]]*CREATE[[:space:]]+OR[[:space:]]+REPLACE([[:space:]]|$)') then
                l_expect_slash_end := true;
                open_plsql_scope(p_requires_begin => true);

                if regexp_like(l_up, 'CREATE[[:space:]]+OR[[:space:]]+REPLACE[[:space:]]+PACKAGE[[:space:]]+BODY([[:space:]]|$)') then
                    l_stmt.stmt_type := 'PACKAGE_BODY';
                elsif regexp_like(l_up, 'CREATE[[:space:]]+OR[[:space:]]+REPLACE[[:space:]]+PACKAGE([[:space:]]|$)') then
                    l_stmt.stmt_type := 'PACKAGE';
                elsif regexp_like(l_up, 'CREATE[[:space:]]+OR[[:space:]]+REPLACE[[:space:]]+PROCEDURE([[:space:]]|$)') then
                    l_stmt.stmt_type := 'PROCEDURE';
                elsif regexp_like(l_up, 'CREATE[[:space:]]+OR[[:space:]]+REPLACE[[:space:]]+FUNCTION([[:space:]]|$)') then
                    l_stmt.stmt_type := 'FUNCTION';
                else
                    l_stmt.stmt_type := 'OTHER';
                end if;

            elsif regexp_like(l_up, '^[[:space:]]*CREATE([[:space:]]|$)') then
                push('SEMICOLON'); -- ends with ;

            elsif regexp_like(l_up, '^[[:space:]]*ALTER([[:space:]]|$)') then
                push('SEMICOLON'); -- ends with ;

            elsif regexp_like(l_up, '^[[:space:]]*DECLARE([[:space:]]|$)') then
                open_plsql_scope(p_requires_begin => true);
                l_stmt.stmt_type := nvl(l_stmt.stmt_type, 'PLSQL');

            elsif regexp_like(l_up, '^[[:space:]]*BEGIN([[:space:]]|$)') then
                -- Header BEGIN for DECLARE/CREATE/local subprogram consumes the
                -- pending header debt. Additional BEGIN starts a nested block.
                handle_begin_keyword;
                l_stmt.stmt_type := nvl(l_stmt.stmt_type, 'PLSQL');

            elsif regexp_like(l_up,
                              '^[[:space:]]*(PROCEDURE|FUNCTION)[[:space:]]+[A-Z_0-9$#]+.*[[:space:]](IS|AS)([[:space:]]|$)') then
                -- Local subprogram declaration inside DECLARE/BEGIN blocks.
                -- Example:
                --   declare
                --     procedure p is
                --     begin
                --       null;
                --     end;
                --   begin
                --     p;
                --   end;
                --
                -- Without this, END; from local subprograms could close the outer block
                -- too early and split one statement into multiple fragments.
                if l_plsql_block_depth > 0 then
                    open_plsql_scope(p_requires_begin => true);
                end if;
            end if;
        end;

        procedure finalize_statement is
            l_idx pls_integer;
        begin
            if l_stmt.stmt_text is null then
                return;
            end if;

            l_idx := nvl(l_result.last, 0) + 1;
            l_result(l_idx) := l_stmt;

            -- reset state for next statement
            l_stmt := null;
            l_stack.delete;
            l_stack_top := 0;

            l_in_squote           := false;
            l_in_line_comment     := false;
            l_in_block_comment    := false;
            l_expect_slash_end    := false;
            l_end_keyword_seen    := false;
            l_plsql_block_depth   := 0;
            l_pending_header_debt := 0;
        end;

    begin -- split_into_statements
        if p_script is null then
            return l_result;
        end if;

        l_lines := clob_to_lines(p_script);

        for ln in 1 .. l_lines.count loop
            declare
                l_line               varchar2(32767) := l_lines(ln);
                l_upper_trimmed_line varchar2(32767) := upper(ltrim(l_line));
                l_trimmed_line       varchar2(32767) := ltrim(l_line);
                l_i                  pls_integer;
                l_ch                 varchar2(1 char);
                l_next2              varchar2(2 char);
                l_prev               varchar2(1 char);
                l_line_skipped       boolean := false;
                l_is_slash_line boolean;
            begin
                if l_stmt.stmt_text is null then
                    skip_leading_block_comments(p_line => l_line,
                                                p_line_skipped => l_line_skipped);
                    if l_line_skipped then
                        continue;
                    end if;
                end if;

                l_trimmed_line := ltrim(l_line);
                l_upper_trimmed_line := upper(l_trimmed_line);
                l_is_slash_line := regexp_like(l_upper_trimmed_line, '^/[[:space:]]*$');
                l_in_line_comment := false;

                -- SQL*Plus EXEC/EXECUTE: convert to executable anonymous PL/SQL block
                --   exec dbms_session.reset_package
                -- -> begin dbms_session.reset_package; end;
                if l_stmt.stmt_text is null and regexp_like(l_upper_trimmed_line, '^(EXEC|EXECUTE)([[:space:]]|$)') then
                    declare
                        l_exec_call varchar2(32767);
                    begin
                        l_exec_call := regexp_replace(l_trimmed_line,
                                                      '^(EXEC|EXECUTE)[[:space:]]+',
                                                      '',
                                                      1,
                                                      1,
                                                      'i');
                        l_exec_call := rtrim(l_exec_call);

                        if l_exec_call is not null then
                            if substr(l_exec_call, -1) != ';' then
                                l_exec_call := l_exec_call || ';';
                            end if;

                            dbms_lob.createtemporary(l_stmt.stmt_text, true);
                            l_stmt.stmt_type := 'PLSQL';
                            clob_append_line(l_stmt.stmt_text, 'begin ' || l_exec_call || ' end;');
                            finalize_statement;
                        end if;
                    end;
                    continue;
                end if;

                -- Ignore SQL*Plus directives (but not "/" because we use it as terminator)
                if l_stmt.stmt_text is null and not l_is_slash_line and is_sqlplus_command(l_line) then
                    continue;
                end if;

                -- Slash lines terminate CREATE OR REPLACE units and simple SQL/DDL
                -- statements that are otherwise only waiting for their SQL*Plus
                -- script terminator.
                if l_is_slash_line and not l_in_squote and not l_in_line_comment and not l_in_block_comment then
                    -- SQL*Plus/SQLcl delimiter: never part of the statement text.
                    -- For simple DDL we only accept slash when no grouping remains
                    -- open and the pending stack entry is the synthetic SEMICOLON token.
                    if l_stmt.stmt_text is not null
                       and ((l_expect_slash_end and stack_empty)
                         or (only_semicolon_pending and l_plsql_block_depth = 0)) then
                        finalize_statement;
                    end if;
                    continue;
                end if;

                -- If we are not currently building a statement, ignore pure comment lines
                if l_stmt.stmt_text is null and is_comment_only_line(l_line) then
                    continue;
                end if;

                -- Start statement buffer if needed
                if l_stmt.stmt_text is null then
                    dbms_lob.createtemporary(l_stmt.stmt_text, true);
                end if;

                -- Only check keyword-openers at line start when not inside string/comment
                if (not l_in_squote) and (not l_in_line_comment) and (not l_in_block_comment) then
                    handle_keyword_openers(l_line);
                end if;

                -- Append original line to statement text
                clob_append_line(l_stmt.stmt_text, l_line);

                -- Parse characters to maintain stack and detect completion
                l_i := 1;

                while l_i <= length(l_line) loop
                    l_ch    := substr(l_line, l_i, 1);
                    l_next2 := substr(l_line, l_i, 2);
                    l_prev  := case when l_i > 1 then substr(l_line, l_i - 1, 1) end;

                    -- Line comment start: -- (only when not in string and not in block comment)
                    if (not l_in_squote) and (not l_in_block_comment) and l_next2 = '--' then
                        l_in_line_comment := true;
                        exit;
                    end if;

                    -- Block comment open/close
                    if (not l_in_squote) then
                        if (not l_in_block_comment) and l_next2 = '/*' then
                            l_in_block_comment := true;
                            l_i := l_i + 2;
                            continue;
                        elsif l_in_block_comment and l_next2 = '*/' then
                            l_in_block_comment := false;
                            l_i := l_i + 2;
                            continue;
                        end if;
                    end if;

                    -- If inside block comment, ignore everything else
                    if l_in_block_comment then
                        l_i := l_i + 1;
                        continue;
                    end if;

                    -- String literal handling for '
                    if l_ch = '''' then
                        if l_in_squote then
                            -- handle escaped quote ''
                            if substr(l_line, l_i + 1, 1) = '''' then
                                l_i := l_i + 2;
                                continue;
                            else
                                l_in_squote := false;
                                l_i := l_i + 1;
                                continue;
                            end if;
                        else
                            l_in_squote := true;
                            l_i := l_i + 1;
                            continue;
                        end if;
                    end if;

                    -- If inside string, do not treat tokens/semicolons as terminators
                    if l_in_squote then
                        l_i := l_i + 1;
                        continue;
                    end if;

                    -- Bracket/paren openers/closers
                    if l_ch = '(' then
                        push(')');
                    elsif l_ch = '[' then
                        push(']');
                    elsif l_ch = '{' then
                        push('}');
                    elsif l_ch = ')' then
                        pop_expected(')');
                    elsif l_ch = ']' then
                        pop_expected(']');
                    elsif l_ch = '}' then
                        pop_expected('}');
                    end if;

                    -- Detect END keyword (very simplified)
                    -- We only use it to satisfy "DECLARE/BEGIN ends with END;"
                    -- if regexp_like(upper(substr(line, i)), '^END([^[:alnum:]_$#]|$)') then
                    --     l_end_keyword_seen := true;
                    -- end if;
                    -- Detect END keyword (only treat END; / END <label>; as block end, not END IF/LOOP/CASE)
                    if regexp_like(l_ch, '[A-Za-z_]') then
                        declare
                            l_j pls_integer := l_i;
                            l_word varchar2(300);
                            l_word_after varchar2(300);
                        begin
                            while l_j <= length(l_line) and regexp_like(substr(l_line, l_j, 1), '[A-Za-z_0-9$#]') loop
                                l_j := l_j + 1;
                            end loop;

                            l_word := upper(substr(l_line, l_i, l_j - l_i));

                            if l_word = 'END' then
                                l_word_after := next_word(l_line, l_j);  -- word after END

                                if l_word_after is null or l_word_after not in ('IF', 'LOOP', 'CASE') then
                                    l_end_keyword_seen := true;
                                end if;
                            end if;

                            l_i := l_j - 1; -- advance past the word
                        end;
                    end if;

                    -- Statement terminator ;
                    if l_ch = ';' then
                        if l_end_keyword_seen and l_plsql_block_depth > 0 then
                            l_plsql_block_depth := l_plsql_block_depth - 1;
                            l_end_keyword_seen := false;
                        end if;

                        -- Pop SEMICOLON expectation for simple DDL
                        if top = 'SEMICOLON' then
                            pop_expected('SEMICOLON');
                        end if;

                        -- If everything is closed and we do NOT require slash termination, finalize now
                        if stack_empty and l_plsql_block_depth = 0 and not l_expect_slash_end then
                            finalize_statement;
                        end if;
                    end if;

                    l_i := l_i + 1;
                end loop;

                -- If CREATE OR REPLACE and stack empty, we still wait for "/" line
                if stack_empty and l_expect_slash_end then
                    -- do nothing here; slash line will finalize
                    null;
                end if;

            end;
        end loop;

        -- If something remains without terminator, return it as "incomplete"?
        -- Here: we only return complete statements; leftover is ignored.
        return l_result;
    end split_into_statements;

    function strip_trailing_sql_terminator(p_stmt_text in clob) return clob is
        l_stmt clob;
        l_len  pls_integer;
        l_ch   varchar2(1 char);
    begin
        if p_stmt_text is null then
            return null;
        end if;

        dbms_lob.createtemporary(l_stmt, true);
        dbms_lob.append(l_stmt, p_stmt_text);

        l_len := dbms_lob.getlength(l_stmt);
        while l_len > 0 loop
            l_ch := dbms_lob.substr(l_stmt, 1, l_len);
            exit when l_ch not in (' ', chr(9), chr(10), chr(13));
            l_len := l_len - 1;
        end loop;

        if l_len < dbms_lob.getlength(l_stmt) then
            dbms_lob.trim(l_stmt, l_len);
        end if;

        if l_len > 0 and dbms_lob.substr(l_stmt, 1, l_len) = ';' then
            dbms_lob.trim(l_stmt, l_len - 1);
        end if;

        return l_stmt;
    end strip_trailing_sql_terminator;

    procedure execute_statement(p_fname in varchar2,
                                p_stmt in r_statement) is
        l_start     number := dbms_utility.get_time;
        l_stmt_text clob := p_stmt.stmt_text;
    begin
        if p_stmt.stmt_type is null then
            l_stmt_text := strip_trailing_sql_terminator(p_stmt.stmt_text);
        end if;

        execute immediate l_stmt_text;
        log_result(p_type => p_stmt.stmt_type,
                   p_status => 'SUCCESS',
                   p_msg => null,
                   p_stmt => null,
                   p_duration_ms => (dbms_utility.get_time - l_start) * 10); 
    exception
        when others then
            log_result(p_type => p_stmt.stmt_type,
                       p_status => 'ERROR',
                       p_msg => sqlerrm,
                       p_stmt => p_stmt.stmt_text,
                       p_user_errors => get_user_errors(p_file_name => p_fname),
                       p_duration_ms => (dbms_utility.get_time - l_start) * 10);
            raise;
    end execute_statement;

    function build_response_info(p_total        in number,
                                 p_executed     in number,
                                 p_duration_ms  in number) return json_object_t is
        l_obj json_object_t := json_object_t();
    begin
        l_obj.put('total_statements', p_total);
        l_obj.put('executed_count', p_executed);
        l_obj.put('duration_ms', p_duration_ms);
        return l_obj;
    end build_response_info;

    function run_content(p_fname          in varchar2,
                         p_script_content in clob) return json_object_t is
        l_normalized clob;
        l_statements t_statement_list;
        l_total      number := 0;
        l_executed   number := 0;

        l_start number := dbms_utility.get_time;
    begin
        reset_logs;
        -- savepoint rest_compile_run;

        l_normalized := normalize_input(p_script_content);

        l_statements := split_into_statements(l_normalized);
        l_total      := l_statements.count;

        for i in 1 .. l_statements.count loop
            execute_statement(p_fname, l_statements(i));
            l_executed := l_executed + 1;
        end loop;

        return build_response_info(l_total,
                                   l_executed,
                                   (dbms_utility.get_time - l_start) * 10);
    end run_content;

    function run_payload(p_request_name in varchar2,
                         p_payload      in blob,
                         p_content_type in varchar2) return json_object_t is
        l_response       json_object_t := json_object_t();
        l_info           json_object_t;
        l_effective_name varchar2(4000 char) := p_request_name;
        l_script_content clob;
        l_is_zip         boolean := is_zip_payload(p_payload      => p_payload,
                                                   p_content_type => p_content_type);
    begin
        reset_logs;

        if l_is_zip then
            extract_single_file_from_zip(p_zip_blob         => p_payload,
                                         p_request_name     => p_request_name,
                                         p_out_file_name    => l_effective_name,
                                         p_out_file_content => l_script_content);
        else
            l_script_content := blob_to_clob_utf8(p_payload);
        end if;

        if l_effective_name is null then
            l_effective_name := p_request_name;
        end if;

        log_request_payload(p_fname        => l_effective_name,
                            p_content      => l_script_content,
                            p_payload      => p_payload,
                            p_content_type => p_content_type,
                            p_is_zip       => l_is_zip);

        l_info := run_content(p_fname          => l_effective_name,
                              p_script_content => l_script_content);

        l_response.put('success', true);
        l_response.put('file_name', l_effective_name);
        l_response.put('is_zip', l_is_zip);
        l_response.put('info', l_info);
        append_runtime_logs(l_response);

        return l_response;
    exception
        when others then
            return build_error_response;
    end run_payload;

    procedure run_payload_rest(p_request_name in varchar2,
                               p_payload      in blob,
                               p_content_type in varchar2) is
        l_response json_object_t;
    begin
        if not check_client_token then
            return;
        end if;
        owa_util.mime_header('application/json', false);
        sys.htp.p('Cache-Control: no-cache');
        owa_util.http_header_close;

        l_response := run_payload(p_request_name => p_request_name,
                                  p_payload      => p_payload,
                                  p_content_type => p_content_type);
        emit_json_response(l_response);
    end run_payload_rest;

    procedure run_content_rest(p_fname          in varchar2,
                               p_script_content in clob) is
        l_response json_object_t := json_object_t();
        l_info     json_object_t;
    begin
        if not check_client_token then
            return;
        end if;
        owa_util.mime_header('application/json', false);
        sys.htp.p('Cache-Control: no-cache');
        owa_util.http_header_close;

        l_info := run_content(p_fname           => p_fname, 
                              p_script_content  => p_script_content);

        l_response.put('info', l_info);
        l_response.put('success', true);
        append_runtime_logs(l_response);
        emit_json_response(l_response);
    exception
        when others then
            emit_json_response(build_error_response);
    end run_content_rest;



    procedure import_app( p_app_file_content   in clob,
                         p_to_workspace       in varchar2,
                         p_to_schema          in varchar2,
                         p_application_id     in number )  is
        l_files         apex_t_export_files := apex_t_export_files();
        l_workspace_id	apex_workspaces.workspace_id%type;
    begin

        l_files.extend(1);
        l_files( 1 ) := apex_t_export_file( 'import-app.sql', p_app_file_content );

        log('Workspace: ' || p_to_workspace);
        log('Schema: ' || p_to_schema);
        log('Application ID: ' || p_application_id);

        -- select workspace_id
        --   into l_workspace_id
        --   from apex_workspaces
        --  where workspace = p_to_workspace;

        -- apex_application_install.set_workspace_id(l_workspace_id);

        apex_util.set_workspace(p_to_workspace);
        -- apex_application_install.generate_offset;
        apex_application_install.set_schema( p_to_schema );
        apex_application_install.set_application_id(p_application_id );

        apex_application_install.install(p_source             => l_files,
                                         p_overwrite_existing => true );

    end import_app;

     procedure import_app_rest( p_app_file_content   in clob,
                                p_to_workspace       in varchar2,
                                p_to_schema          in varchar2,
                                p_application_id     in number) is
        l_response json_object_t := json_object_t();
    begin
        if not check_client_token then
            return;
        end if;
        reset_logs;

        owa_util.mime_header('application/json', false);
        sys.htp.p('Cache-Control: no-cache');
        owa_util.http_header_close;

        import_app(p_app_file_content => p_app_file_content,
                   p_to_workspace     => upper(p_to_workspace),
                   p_to_schema        => upper(p_to_schema),
                   p_application_id   => p_application_id);

        l_response.put('success', true);
        append_runtime_logs(l_response);
        emit_json_response(l_response);
    exception
        when others then
            emit_json_response(build_error_response);
    end import_app_rest;

    -- #####################################################################
    -- API info / versioning
    -- #####################################################################

    function get_version return varchar2 is
    begin
        return c_version;
    end get_version;

    function get_api_level return number is
    begin
        return c_api_level;
    end get_api_level;

    procedure get_info_rest is
        l_response json_object_t := json_object_t();
    begin
        if not check_client_token then
            return;
        end if;
        owa_util.mime_header('application/json', false);
        sys.htp.p('Cache-Control: no-cache');
        owa_util.http_header_close;

        l_response.put('success', true);
        l_response.put('version', c_version);
        l_response.put('api_level', c_api_level);
        emit_json_response(l_response);
    end get_info_rest;

    -- #####################################################################
    -- shared helpers for the export endpoints
    -- #####################################################################

    procedure emit_json_header is
    begin
        owa_util.mime_header('application/json', false);
        sys.htp.p('Cache-Control: no-cache');
        owa_util.http_header_close;
    end emit_json_header;

    -- exports compute their payload first; nothing is written to the
    -- response before this point, so the error path can still emit JSON.
    procedure emit_zip_response(p_zip       in blob,
                                p_file_name in varchar2) is
        -- wpg_docload.download_file requires an in out parameter
        l_zip blob := p_zip;
    begin
        owa_util.mime_header('application/zip', false);
        sys.htp.p('Content-Disposition: attachment; filename="' || p_file_name || '"');
        sys.htp.p('Cache-Control: no-cache');
        owa_util.http_header_close;
        wpg_docload.download_file(l_zip);
    end emit_zip_response;

    procedure emit_json_error_response is
        l_response json_object_t := build_error_response;
    begin
        emit_json_header;
        emit_json_response(l_response);
    end emit_json_error_response;

    function clob_to_blob(p_clob in clob) return blob is
        l_blob         blob;
        l_lang_context integer := dbms_lob.default_lang_ctx;
        l_warning      integer := dbms_lob.warn_inconvertible_char;
        l_dest_offset  integer := 1;
        l_src_offset   integer := 1;
    begin
        if p_clob is not null then
            dbms_lob.createtemporary(l_blob, true);
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
    end clob_to_blob;

    -- resolves the application (by id or alias) and sets the APEX security
    -- group so that apex_export / wwv_flow_api work inside the ORDS call
    procedure init_apex_context(p_app_id     in  varchar2,
                                p_app_id_out out number) is
        l_workspace_id apex_applications.workspace_id%type;
    begin
        select application_id, workspace_id
          into p_app_id_out, l_workspace_id
          from apex_applications
         where to_char(application_id) = p_app_id
            or upper(alias) = upper(p_app_id);

        apex_util.set_security_group_id(p_security_group_id => l_workspace_id);
    end init_apex_context;

    -- #####################################################################
    -- compile schema (port of dbFlux compile.sh)
    -- #####################################################################

    function get_schema_errors(p_db_folder        in varchar2,
                               p_warning_string   in varchar2,
                               p_warning_excludes in varchar2) return json_array_t is
        l_return    json_array_t := json_array_t();
        l_db_folder varchar2(255 char) := nvl(p_db_folder, 'db');
    begin
        for cur in (with excl as (select to_number(trim(column_value)) excl_no
                                    from table(apex_string.split(nvl(p_warning_excludes, '-1'), ','))),
                         errms as (select attribute, line||':'||position lpos, name, type,
                                          replace(substr(text, 1, instr(text, ':', 1, 1) -1), ' ') errtype,
                                          replace(substr(text, instr(text, ': ', 1, 1) + 2), chr(10), ' ') errtext,
                                          case
                                            when type = 'PACKAGE BODY' and exists(select 1 from user_source s where s.name = ue.name and s.type = 'PACKAGE' and instr(replace(lower(s.text), ' '), '--%suite') > 0) then l_db_folder||'/'||lower(user)||'/tests/packages/'||lower(name)||'.pkb'
                                            when type = 'PACKAGE'      and exists(select 1 from user_source s where s.name = ue.name and s.type = 'PACKAGE' and instr(replace(lower(s.text), ' '), '--%suite') > 0) then l_db_folder||'/'||lower(user)||'/tests/packages/'||lower(name)||'.pks'
                                            when type = 'PACKAGE BODY' then l_db_folder||'/'||lower(user)||'/sources/packages/'||lower(name)||'.pkb'
                                            when type = 'PACKAGE'      then l_db_folder||'/'||lower(user)||'/sources/packages/'||lower(name)||'.pks'
                                            when type = 'TYPE BODY'    then l_db_folder||'/'||lower(user)||'/sources/types/'||lower(name)||'.tpb'
                                            when type = 'TYPE'         then l_db_folder||'/'||lower(user)||'/sources/types/'||lower(name)||'.tps'
                                            when type = 'FUNCTION'     then l_db_folder||'/'||lower(user)||'/sources/functions/'||lower(name)||'.sql'
                                            when type = 'PROCEDURE'    then l_db_folder||'/'||lower(user)||'/sources/procedures/'||lower(name)||'.sql'
                                            when type = 'VIEW'         then l_db_folder||'/'||lower(user)||'/views/'||lower(name)||'.sql'
                                            when type = 'TRIGGER'      then l_db_folder||'/'||lower(user)||'/sources/triggers/'||lower(name)||'.sql'
                                          end wsfile
                                     from user_errors ue
                                    where attribute in ('ERROR', nvl(p_warning_string, 'NIX'))
                                      and message_number not in (select excl_no from excl)
                                      and name not like 'BIN$%' -- exclude trash
                                      )
                    select attribute, lpos, name, errtype, errtext, wsfile,
                           max(length(errtype)) over () mlen, max(length(lpos)) over () mlpos
                      from errms
                     order by type, name, lpos)
        loop
            declare
                l_finding json_object_t := json_object_t();
            begin
                l_finding.put('attribute', cur.attribute);
                l_finding.put('typeid',    rpad(cur.errtype, cur.mlen, ' '));
                l_finding.put('fileinfo',  cur.wsfile || ':' || rpad(cur.lpos, cur.mlpos, ' '));
                l_finding.put('errtext',   cur.errtext);
                l_return.append(l_finding);
            end;
        end loop;

        return l_return;
    end get_schema_errors;

    procedure compile_schema_rest(p_compile_all      in varchar2,
                                  p_db_folder        in varchar2,
                                  p_enable_warnings  in varchar2,
                                  p_warning_string   in varchar2,
                                  p_warning_excludes in varchar2) is
        l_response    json_object_t := json_object_t();
        l_info        json_object_t := json_object_t();
        l_errors      json_array_t;
        l_compile_all boolean := upper(nvl(p_compile_all, 'FALSE')) = 'TRUE';
        l_start       number  := dbms_utility.get_time;
    begin
        if not check_client_token then
            return;
        end if;
        reset_logs;
        emit_json_header;

        if trim(p_enable_warnings) is not null then
            execute immediate rtrim(trim(p_enable_warnings), ';');
        end if;

        -- Never call dbms_session.reset_package here: its deferred reset fires
        -- when the ORDS handler call ends and wipes ALL package state of the
        -- pooled session — including the htp/OWA page buffer holding the JSON
        -- response — before ORDS fetches it (client sees HTTP 555). Stale state
        -- of recompiled packages is handled by Oracle itself: the next call
        -- raises ORA-04068 once and reinitializes automatically.
        dbms_utility.compile_schema(schema => user, compile_all => l_compile_all);

        l_errors := get_schema_errors(p_db_folder        => p_db_folder,
                                      p_warning_string   => p_warning_string,
                                      p_warning_excludes => p_warning_excludes);

        l_info.put('compile_all', l_compile_all);
        l_info.put('error_count', l_errors.get_size);
        l_info.put('duration_ms', (dbms_utility.get_time - l_start) * 10);

        l_response.put('success', true);
        l_response.put('schema', user);
        l_response.put('errors', l_errors);
        l_response.put('info', l_info);
        append_runtime_logs(l_response);
        emit_json_response(l_response);
    exception
        when others then
            emit_json_response(build_error_response);
    end compile_schema_rest;

    -- #####################################################################
    -- APEX application / plugin export (apex_export)
    -- #####################################################################

    function files_to_zip(p_files in apex_t_export_files) return blob is
        l_zip blob;
    begin
        dbms_lob.createtemporary(l_zip, true);
        for i in 1 .. p_files.count loop
            apex_zip.add_file(p_zipped_blob => l_zip,
                              p_file_name   => p_files(i).name,
                              p_content     => clob_to_blob(p_files(i).contents));
        end loop;

        if p_files.count = 0 then
            raise_application_error(-20002, 'Nothing found to export');
        end if;

        apex_zip.finish(p_zipped_blob => l_zip);
        return l_zip;
    end files_to_zip;

    procedure export_app_rest(p_app_id         in varchar2,
                              p_export_options in varchar2) is
        l_app_id                  number;
        l_files                   apex_t_export_files;
        l_tokens                  apex_t_varchar2;
        l_token                   varchar2(255 char);
        l_idx                     pls_integer;
        -- SQLcl "apex export" includes the export date unless -skipExportDate is set
        l_with_date               boolean := true;
        l_with_original_ids       boolean := false;
        l_with_translations       boolean := false;
        l_with_comments           boolean := false;
        l_with_acl_assignments    boolean := false;
        l_with_supporting_objects varchar2(1 char);
    begin
        if not check_client_token then
            return;
        end if;
        reset_logs;
        init_apex_context(p_app_id, l_app_id);

        -- map SQLcl "apex export" flags onto apex_export parameters,
        -- tolerating (and logging) unknown flags
        l_tokens := apex_string.split(regexp_replace(trim(p_export_options), '[[:space:]]+', ' '), ' ');
        l_idx := 1;
        while l_idx <= l_tokens.count loop
            l_token := lower(l_tokens(l_idx));
            case
                when l_token is null or l_token = '-split' then null;
                when l_token = '-skipexportdate'       then l_with_date := false;
                when l_token = '-exporiginalids'       then l_with_original_ids := true;
                when l_token = '-exptranslations'      then l_with_translations := true;
                when l_token = '-expcomments'          then l_with_comments := true;
                when l_token = '-expaclassignments'    then l_with_acl_assignments := true;
                when l_token = '-expsupportingobjects' then
                    if l_idx < l_tokens.count then
                        l_idx := l_idx + 1;
                        l_with_supporting_objects := upper(substr(l_tokens(l_idx), 1, 1));
                    end if;
                else
                    log('Ignoring unknown export option: ' || l_tokens(l_idx));
            end case;
            l_idx := l_idx + 1;
        end loop;

        l_files := apex_export.get_application(p_application_id          => l_app_id,
                                               p_split                   => true,
                                               p_with_date               => l_with_date,
                                               p_with_original_ids       => l_with_original_ids,
                                               p_with_translations       => l_with_translations,
                                               p_with_comments           => l_with_comments,
                                               p_with_acl_assignments    => l_with_acl_assignments,
                                               p_with_supporting_objects => l_with_supporting_objects);

        emit_zip_response(files_to_zip(l_files), 'f' || l_app_id || '.zip');
    exception
        when others then
            emit_json_error_response;
    end export_app_rest;

    procedure export_plugin_rest(p_app_id      in varchar2,
                                 p_plugin_name in varchar2) is
        l_app_id    number;
        l_plugin_id apex_appl_plugins.plugin_id%type;
        l_files     apex_t_export_files;
    begin
        if not check_client_token then
            return;
        end if;
        reset_logs;
        init_apex_context(p_app_id, l_app_id);

        begin
            select plugin_id
              into l_plugin_id
              from apex_appl_plugins
             where application_id = l_app_id
               and name = p_plugin_name;
        exception
            when no_data_found then
                raise_application_error(-20002, 'Plugin not found (' || p_app_id || '/' || p_plugin_name || ')');
        end;

        l_files := apex_export.get_application(p_application_id => l_app_id,
                                               p_split          => false,
                                               p_components     => apex_t_varchar2('PLUGIN:' || l_plugin_id));

        emit_zip_response(files_to_zip(l_files), 'f' || l_app_id || '.zip');
    exception
        when others then
            emit_json_error_response;
    end export_plugin_rest;

    -- #####################################################################
    -- APEX static / plugin files (port of dbFlux export_app_static_function.sql)
    -- #####################################################################

    procedure export_static_files_rest(p_app_id    in varchar2,
                                       p_file_name in varchar2) is
        l_app_id number;
        l_zip    blob;
        l_found  boolean := false;
    begin
        if not check_client_token then
            return;
        end if;
        reset_logs;
        init_apex_context(p_app_id, l_app_id);

        dbms_lob.createtemporary(l_zip, true);
        for cur in (select file_name, file_content
                      from apex_application_static_files
                     where application_id = l_app_id
                       and (file_name = p_file_name or p_file_name is null)
                       and file_name not like '%.min.css'
                       and file_name not like '%.min.js'
                       and file_name not like '%.js.map')
        loop
            l_found := true;
            apex_zip.add_file(p_zipped_blob => l_zip,
                              p_file_name   => cur.file_name,
                              p_content     => cur.file_content);
        end loop;

        if not l_found then
            raise_application_error(-20002, 'Nothing found to export (' || p_app_id || '/' || p_file_name || ')');
        end if;

        apex_zip.finish(p_zipped_blob => l_zip);
        emit_zip_response(l_zip, 'f' || l_app_id || '_static.zip');
    exception
        when others then
            emit_json_error_response;
    end export_static_files_rest;

    procedure export_plugin_files_rest(p_app_id      in varchar2,
                                       p_plugin_name in varchar2,
                                       p_file_name   in varchar2) is
        l_app_id number;
        l_zip    blob;
        l_found  boolean := false;
    begin
        if not check_client_token then
            return;
        end if;
        reset_logs;
        init_apex_context(p_app_id, l_app_id);

        dbms_lob.createtemporary(l_zip, true);
        for cur in (select file_name, file_content
                      from apex_appl_plugin_files
                     where application_id = l_app_id
                       and plugin_name = upper(p_plugin_name)
                       and (file_name = p_file_name or p_file_name is null)
                       and file_name not like '%.min.css'
                       and file_name not like '%.min.js'
                       and file_name not like '%.js.map')
        loop
            l_found := true;
            apex_zip.add_file(p_zipped_blob => l_zip,
                              p_file_name   => cur.file_name,
                              p_content     => cur.file_content);
        end loop;

        if not l_found then
            raise_application_error(-20002, 'Nothing found to export (' || p_app_id || '/' || p_plugin_name || '/' || p_file_name || ')');
        end if;

        apex_zip.finish(p_zipped_blob => l_zip);
        emit_zip_response(l_zip, 'f' || l_app_id || '_plugin.zip');
    exception
        when others then
            emit_json_error_response;
    end export_plugin_files_rest;

    procedure remove_static_file_rest(p_app_id    in varchar2,
                                      p_file_name in varchar2,
                                      p_file_ext  in varchar2) is
        l_response    json_object_t := json_object_t();
        l_removed     json_array_t  := json_array_t();
        l_app_id      number;
        l_found       boolean := false;
        -- ORDS pools sessions: current_schema must be restored in any case
        l_prev_schema varchar2(128 char) := sys_context('userenv', 'current_schema');

        procedure restore_schema is
        begin
            execute immediate 'alter session set current_schema = '
                || sys.dbms_assert.enquote_name(l_prev_schema, false);
        exception
            when others then
                null;
        end restore_schema;
    begin
        if not check_client_token then
            return;
        end if;
        reset_logs;
        emit_json_header;

        init_apex_context(p_app_id, l_app_id);

        execute immediate 'alter session set current_schema = '
            || sys.dbms_assert.enquote_name(apex_application.g_flow_schema_owner, false);

        for cur in (select application_file_id, application_id, file_name
                      from apex_application_static_files
                     where application_id = l_app_id
                       and replace(file_name, replace(p_file_name, '.' || p_file_ext))
                           in ('.' || p_file_ext, '.' || p_file_ext || '.map', '.min.' || p_file_ext))
        loop
            l_found := true;
            wwv_flow_api.remove_app_static_file(p_id => cur.application_file_id, p_flow_id => cur.application_id);
            l_removed.append(cur.file_name);
        end loop;

        restore_schema;

        l_response.put('success', true);
        l_response.put('found', l_found);
        l_response.put('removed', l_removed);
        append_runtime_logs(l_response);
        emit_json_response(l_response);
    exception
        when others then
            declare
                l_error json_object_t := build_error_response;
            begin
                restore_schema;
                emit_json_response(l_error);
            end;
    end remove_static_file_rest;

    -- #####################################################################
    -- schema / object DDL export
    -- (port of dbFlux export_anonymous_function.sql, zip writing on apex_zip)
    -- #####################################################################

    procedure exp_zip_add_file(p_zipped_blob in out nocopy blob,
                               p_name        in varchar2,
                               p_content     in blob) is
    begin
        g_exp_objects_found := true;
        apex_zip.add_file(p_zipped_blob => p_zipped_blob,
                          p_file_name   => p_name,
                          p_content     => p_content);
        g_exp_files(g_exp_files.count + 1) := p_name;
    end exp_zip_add_file;

    -- inspired and copyright by https://github.com/connormcd/misc-scripts/blob/master/ddl_cleanup.sql
    function to_lowercase(p_content in clob) return clob is
        l_in_double   boolean := false;
        l_in_string   boolean := false;
        l_need_quotes boolean := false;

        l_res         clob;
        l_content     clob := regexp_replace(p_content,'"([A-Z0-9_$#]+)"','\1');
        l_idx         int := 0;
        l_thischar    varchar2(1 char);
        l_prevchar    varchar2(1 char);
        l_nextchar    varchar2(1 char);
        l_sqt         varchar2(1 char) := '''';
        l_dqt         varchar2(1 char) := '"';
        l_last_l_dqt  int;

        procedure append is
        begin
            if not l_need_quotes and not l_in_string and not l_in_double then
                l_res := l_res || lower(l_thischar);
            else
                l_res := l_res || l_thischar;
            end if;
        end;
    begin
        dbms_lob.createtemporary(l_res, true);

        loop
            l_idx := l_idx + 1;
            if l_idx > 1 then
                l_prevchar := l_thischar;
            end if;
            l_thischar := substr(l_content, l_idx, 1);
            exit when l_thischar is null;
            l_nextchar := substr(l_content, l_idx+1, 1);

            if l_thischar not in (l_dqt,l_sqt) then
                append;
                if l_in_double then
                    if l_thischar not between 'A' and 'Z' and l_thischar not between '0' and '9' and l_thischar not in ('$','#','_') or
                    ( l_prevchar = l_dqt  and ( l_thischar in ('$','#','_') or l_thischar between '0' and '9' ) )
                    then
                        l_need_quotes := true;
                    end if;
                end if;
            elsif l_thischar = l_dqt and not l_in_double and not l_in_string then
                append;
                l_in_double := true;
                l_need_quotes := false;
            elsif l_thischar = l_dqt and l_in_double and not l_in_string then
                l_last_l_dqt := instr(l_res,l_dqt,-1);
                if l_last_l_dqt = 0 then
                    raise_application_error(-20000,'l_last_l_dqt died');
                else
                    if not l_need_quotes then
                        l_res := substr(l_res,1,l_last_l_dqt-1)||lower(substr(l_res,l_last_l_dqt+1));
                    else
                        append;
                    end if;
                    l_need_quotes := false;
                end if;
                l_in_double := false;
            elsif l_thischar = l_sqt then
                append;
                if not l_in_double then
                    if not l_in_string then
                        l_in_string := true;
                    else
                        if l_nextchar = l_sqt then
                            l_in_string := true;
                            l_res := l_res ||  l_nextchar;
                            l_idx := l_idx + 1;
                        else
                            l_in_string := false;
                        end if;
                    end if;
                end if;
            else
                append;
            end if;

        end loop;
        return l_res;
    end to_lowercase;

    function get_lowercase_ddl(p_type varchar2,
                               p_name varchar2) return clob is
    begin
        return to_lowercase('-- Exported with dbms_metadata.get_ddl' || chr(10) || ltrim(dbms_metadata.get_ddl(p_type, p_name), c_exp_crlf||' '));
    end get_lowercase_ddl;

    function get_grants(p_object_name in varchar2) return clob is
        l_content clob;
    begin
        l_content := 'Prompt Revoke all grants found in user_tab_privs_made of object: '||p_object_name||chr(10)
                || 'begin'||chr(10)
                || '  for revoke_rec in (select privilege, table_name, grantee'||chr(10)
                || '                       from user_tab_privs_made'||chr(10)
                || '                      where table_name = '''||upper(p_object_name)||'''  )'||chr(10)
                || '  loop'||chr(10)
                || '    execute immediate ''revoke '' || revoke_rec.privilege || '' on '' || revoke_rec.table_name || '' from '' || revoke_rec.grantee;'||chr(10)
                || '  end loop;'||chr(10)
                || 'end;'||chr(10)
                || '/'||chr(10)
                || ''||chr(10)
                || ''||chr(10)
                || 'Prompt Grants to object: '||p_object_name;

        for cur in (select 'grant ' || privilege || ' on ' || table_name || ' to ' || grantee ||
                        case when grantable = 'YES' then ' with grant option;' else ';' end as grant_script
                    from user_tab_privs_made
                    where table_name = p_object_name
                    order by grantee)
        loop
            l_content := concat(l_content, chr(10) || cur.grant_script);
        end loop;
        l_content := concat(l_content, chr(10)||chr(10));
        return l_content;
    end get_grants;

    function get_table(p_table_name     in varchar,
                       p_include_flinks in boolean default false) return clob is
        l_script    clob;
        l_comments  clob;
    begin
        l_script := get_lowercase_ddl('TABLE', upper(p_table_name));

        -- all we need is before the first ";"
        l_script := substr(l_script, 1, instr(l_script, ';', 1, 1));

        -- replace double_quotes
        l_script := replace(l_script, '"', '');

        -- additionally get comments
        begin
            l_comments := to_lowercase(dbms_metadata.get_dependent_ddl( 'COMMENT', upper(p_table_name)));

            -- replace schema name and double_quotes
            l_comments := replace(l_comments, '"', '');

            dbms_lob.append(l_script, chr(10)||chr(10)||l_comments);
        exception
            when others then
                null; -- ORA-31608: specified object of type COMMENT not found
        end;

        if p_include_flinks and g_exp_files.count > 0 then
            dbms_lob.append(l_script, chr(10)||chr(10));
            for i in 1 .. g_exp_files.count loop
                dbms_lob.append(l_script, '-- File: '||g_exp_files(i)||chr(10));
            end loop;
        end if;
        return l_script;
    end get_table;

    procedure add_tables(p_zip_file in out nocopy blob,
                         p_table_name varchar2 default null) is
    begin
        for cur in (select table_name, 'tables/'||lower(table_name)||'.sql' filename
                      from user_tables
                     where p_table_name is null or upper(table_name) = upper(p_table_name))
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_table(p_table_name     => cur.table_name,
                                                                     p_include_flinks => (p_table_name is not null))));
        end loop;
    end add_tables;

    function get_constraint(p_constraint_name   in varchar,
                            p_constraint_type   in varchar2) return clob is
        l_script clob;
    begin
        l_script := get_lowercase_ddl(case
                                        when p_constraint_type = 'R' then
                                            'REF_CONSTRAINT'
                                        else
                                            'CONSTRAINT'
                                      end,
                                      upper(p_constraint_name)
                                      );

        -- all we need is before the first ";"
        l_script := substr(l_script, 1, instr(l_script, ';', 1, 1));

        return l_script;
    end get_constraint;

    procedure add_constraints(p_zip_file     in out nocopy blob,
                              p_object_name  in            varchar2 default null,
                              p_object_type  in            varchar2 default null) is
    begin
        for cur in (select constraint_name, 'constraints/' ||
                           case
                             when constraint_type = 'P' then 'primaries'
                             when constraint_type = 'U' then 'uniques'
                             when constraint_type = 'R' then 'foreigns'
                             when constraint_type = 'C' then 'checks'
                           end || '/' ||lower(constraint_name)||'.sql' filename,
                           constraint_type
                      from user_constraints
                     where generated != 'GENERATED NAME'
                       and constraint_name not like 'BIN$%'
                       and (   p_object_name     is null
                            or upper(constraint_name) = upper(p_object_name)
                            or upper(table_name||'_'||constraint_name) = upper(p_object_name)
                            or upper(table_name)      = upper(p_object_name)
                           )
                       and (
                                p_object_type is null
                             or p_object_type = 'TABLES'
                             or 'constraints/' || case
                                                    when constraint_type = 'P' then 'primaries'
                                                    when constraint_type = 'U' then 'uniques'
                                                    when constraint_type = 'R' then 'foreigns'
                                                    when constraint_type = 'C' then 'checks'
                                                  end = lower(p_object_type)
                             )
                    order by case
                                when constraint_type = 'P' then 'aaa'
                                when constraint_type = 'U' then 'bbb'
                                when constraint_type = 'R' then 'ccc'
                                when constraint_type = 'C' then 'ddd'
                              end, constraint_name
                    )
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_constraint(cur.constraint_name, cur.constraint_type)));
        end loop;
    end add_constraints;

    function get_index(p_index_name   in varchar) return clob is
        l_script clob;
    begin
        l_script := get_lowercase_ddl('INDEX', upper(p_index_name));

        -- only to the first occurence of ;
        l_script := substr(l_script, 1, instr(l_script, ';', 1, 1));

        return l_script;
    end get_index;

    procedure add_indexes(p_zip_file     in out nocopy blob,
                          p_object_name  in            varchar2 default null,
                          p_object_type  in            varchar2 default null) is
    begin
        for cur in (select i.index_name index_name, 'indexes/'||
                           case
                             when c.constraint_type = 'P' then 'primaries'
                             when i.uniqueness = 'UNIQUE' then 'uniques'
                             else 'defaults'
                           end ||'/' ||lower(i.index_name)||'.sql' filename
                      from user_indexes i left join user_constraints c on i.index_name = c.index_name
                     where index_type != 'LOB'
                       and (   p_object_name    is null
                            or upper(i.index_name)  = upper(p_object_name)
                            or upper(i.table_name||'_'||i.index_name)  = upper(p_object_name)
                            or upper(i.table_name)  = upper(p_object_name)
                           )
                       and (
                                p_object_type is null
                             or p_object_type in ('TABLES')
                             or 'indexes/' || case
                                                    when constraint_type = 'P' then 'primaries'
                                                    when i.uniqueness = 'UNIQUE' then 'uniques'
                                                    else 'defaults'
                                                  end = lower(p_object_type)
                             )
                    order by case
                               when constraint_type = 'P' then 'aaa'
                               when i.uniqueness = 'UNIQUE' then 'bbb'
                               else 'ccc'
                             end, i.index_name
                    )
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_index(p_index_name   => cur.index_name)));
        end loop;
    end add_indexes;

    function get_source(p_source_name        in varchar2,
                        p_source_type        in varchar2,
                        p_grant_with_object  in boolean  default false)
                        return clob is
        l_script clob;
    begin
        -- add target version to ddl to ommit "editionable" clause
        l_script := ltrim(dbms_metadata.get_ddl(p_source_type, upper(p_source_name), user, '11.2.0'), c_exp_crlf||' ');

        -- remove double quotes
        l_script := replace(l_script, '"'||upper(p_source_name)||'"', lower(p_source_name));

        -- change the first line of the content to lowercase
        l_script := lower(substr(l_script, 1, instr(l_script, chr(10)) - 1)) || substr(l_script, instr(l_script, chr(10)));

        if p_grant_with_object and p_source_type not in ('PACKAGE_BODY', 'TYPE_BODY', 'TRIGGER') then
            l_script := concat(l_script, chr(10) || get_grants(p_source_name));
        end if;

        return l_script;
    end get_source;

    procedure add_sources(p_zip_file           in out nocopy blob,
                          p_object_name        in            varchar2 default null,
                          p_object_type        in            varchar2 default null,
                          p_grant_with_object  in            boolean  default false) is
    begin
        for cur in (select object_name,
                            case
                              when object_type = 'PACKAGE BODY' then 'PACKAGE_BODY'
                              when object_type = 'PACKAGE' then 'PACKAGE_SPEC'
                              when object_type = 'TYPE BODY' then 'TYPE_BODY'
                              when object_type = 'TYPE' then 'TYPE_SPEC'
                              else object_type
                            end source_type,
                            'sources/'||
                            case
                              when object_type in ('PACKAGE', 'PACKAGE BODY') then 'packages'
                              when object_type in ('TYPE', 'TYPE BODY') then 'types'
                              else lower(object_type)||'s' -- plural
                            end||'/'||lower(object_name)||'.'||
                            case
                              when object_type = 'PACKAGE BODY' then 'pkb'
                              when object_type = 'PACKAGE' then 'pks'
                              when object_type = 'TYPE BODY' then 'tpb'
                              when object_type = 'TYPE' then 'tps'
                              else 'sql'
                            end filename
                      from user_objects
                     where object_type in ('TYPE', 'TYPE BODY', 'PACKAGE BODY', 'PACKAGE', 'FUNCTION', 'PROCEDURE', 'TRIGGER')
                       and object_name not in (select name
                                                 from user_source
                                                where name = object_name
                                                  and type = 'PACKAGE'
                                                  and instr(replace(lower(text), ' '), '--%suite(') > 0) -- exclude test suites
                       and object_name not like 'SYS\_PLSQL\_%' escape '\'
                       and (    p_object_name is null
                             or (    upper(object_name) = upper(p_object_name)
                                 and object_type like case lower(p_object_type)
                                                              when 'sources/packages'   then 'PACKAGE%'
                                                              when 'sources/types'      then 'TYPE%'
                                                              when 'sources/procedures' then 'PROCEDURE%'
                                                              when 'sources/functions'  then 'FUNCTION%'
                                                              when 'sources/triggers'   then 'TRIGGER%'
                                                       end
                                )
                           )
                    )
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_source(p_source_name       => cur.object_name,
                                                                      p_source_type       => cur.source_type,
                                                                      p_grant_with_object => p_grant_with_object)));
        end loop;
    end add_sources;

    /* just like source but another folder and names start with TEST_*/
    procedure add_tests(p_zip_file     in out nocopy blob,
                        p_object_name  in            varchar2 default null,
                        p_object_type  in            varchar2 default null) is
    begin
        for cur in (select object_name,
                            case
                              when object_type = 'PACKAGE BODY' then 'PACKAGE_BODY'
                              when object_type = 'PACKAGE' then 'PACKAGE_SPEC'
                              when object_type = 'TYPE BODY' then 'TYPE_BODY'
                              when object_type = 'TYPE' then 'TYPE_SPEC'
                              else object_type
                            end source_type,
                            'tests/'||
                            case
                              when object_type in ('PACKAGE', 'PACKAGE BODY') then 'packages'
                              when object_type in ('TYPE', 'TYPE BODY') then 'types'
                              else lower(object_type)||'s' -- plural
                            end||'/'||lower(object_name)||'.'||
                            case
                              when object_type = 'PACKAGE BODY' then 'pkb'
                              when object_type = 'PACKAGE' then 'pks'
                              when object_type = 'TYPE BODY' then 'tpb'
                              when object_type = 'TYPE' then 'tps'
                              else 'sql'
                            end filename
                      from user_objects
                     where object_type in ('TYPE', 'TYPE BODY', 'PACKAGE BODY', 'PACKAGE', 'FUNCTION', 'PROCEDURE')
                       and object_name in (select name
                                              from user_source
                                             where name = object_name
                                               and type = 'PACKAGE'
                                               and instr(replace(lower(text), ' '), '--%suite(') > 0) -- include test suites
                       and (    p_object_name is null
                             or (    upper(object_name) = upper(p_object_name)
                                 and object_type like case lower(p_object_type)
                                                              when 'tests/packages'   then 'PACKAGE%'
                                                              when 'tests/types'      then 'TYPE%'
                                                              when 'tests/procedures' then 'PROCEDURE%'
                                                              when 'tests/functions'  then 'FUNCTION%'
                                                       end
                                )
                           )
                    )
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_source(p_source_name => cur.object_name,
                                                                      p_source_type => cur.source_type)));
        end loop;
    end add_tests;

    function get_sequence(p_sequence_name in varchar2)
                        return clob is
        l_script clob;
    begin
        l_script := get_lowercase_ddl('SEQUENCE', upper(p_sequence_name));

        -- remove double quotes
        l_script := replace(l_script, '"'||upper(p_sequence_name)||'"', lower(p_sequence_name));

        return l_script;
    end get_sequence;

    procedure add_sequences(p_zip_file     in out nocopy blob,
                            p_object_name  in            varchar2 default null,
                            p_object_type  in            varchar2 default null)  is
    begin
        for cur in (select sequence_name, 'sequences/'||lower(sequence_name)||'.sql' filename
                      from user_sequences
                     where sequence_name not like 'ISEQ%'
                       and (    p_object_name is null
                             or (    upper(sequence_name) = upper(p_object_name)
                                 and p_object_type = 'SEQUENCES')) )
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_sequence(p_sequence_name   => cur.sequence_name)));
        end loop;
    end add_sequences;

    function get_view(p_view_name         in varchar2,
                      p_grant_with_object in boolean  default false)
                        return clob is
        l_script clob;
    begin
        -- special workaround to be able to grant on invalid views
        if p_grant_with_object then
            -- first create a dummy view
            l_script := 'create or replace force view '||lower(p_view_name)||' as '||chr(10)||
                        'select * from json_table(''{dummy:"a"}'', ''$'' columns(dummy varchar2(10) path ''$.dummy''));'||chr(10)||chr(10);

            -- gen grants
            l_script := concat(l_script, get_grants(upper(p_view_name)));

            -- grants will be kept when underlying object is recreated ...
        end if;

        l_script := concat(l_script, get_lowercase_ddl('VIEW', upper(p_view_name)));

        return l_script;
    end get_view;

    procedure add_views(p_zip_file           in out nocopy blob,
                        p_object_name        in            varchar2 default null,
                        p_object_type        in            varchar2 default null,
                        p_grant_with_object  in            boolean  default false) is
    begin
        for cur in (select view_name, 'views/'||lower(view_name)||'.sql' filename
                      from user_views
                     where (   p_object_name is null
                            or (     upper(view_name) = upper(p_object_name)
                                 and p_object_type = 'VIEWS')))
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_view(p_view_name         => cur.view_name,
                                                                    p_grant_with_object => p_grant_with_object)));
        end loop;
    end add_views;

    function get_mview(p_mview_name in varchar2)
                        return clob is
        l_script clob;
    begin
        l_script := get_lowercase_ddl('MATERIALIZED_VIEW', upper(p_mview_name));

        return l_script;
    end get_mview;

    procedure add_mviews(p_zip_file     in out nocopy blob,
                         p_object_name  in            varchar2 default null,
                         p_object_type  in            varchar2 default null) is
    begin
        for cur in (select mview_name, 'mviews/'||lower(mview_name)||'.sql' filename
                      from user_mviews
                     where (   p_object_name is null
                            or (     upper(mview_name) = upper(p_object_name)
                                 and p_object_type = 'MVIEWS')))
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_mview(p_mview_name   => cur.mview_name)));
        end loop;
    end add_mviews;

    function get_job(p_job_name in varchar2)
                        return clob is
        l_script clob;
    begin
        l_script := ltrim(dbms_metadata.get_ddl('PROCOBJ', upper(p_job_name)), c_exp_crlf||' ');

        return l_script;
    end get_job;

    procedure add_jobs(p_zip_file     in out nocopy blob,
                       p_object_name  in            varchar2 default null,
                       p_object_type  in            varchar2 default null) is
    begin
        for cur in (select job_name, 'jobs/'||lower(job_name)||'.sql' filename
                      from user_scheduler_jobs
                      where (   p_object_name is null
                            or (     upper(job_name) = upper(p_object_name)
                                 and p_object_type = 'JOBS')))
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_job(p_job_name   => cur.job_name)));
        end loop;
    end add_jobs;

    function get_synonym(p_synonym_name in varchar2,
                         p_owner        in varchar2)
                        return clob is
        l_script clob;
    begin
        l_script := to_lowercase('-- Exported with dbms_metadata.get_ddl' || chr(10) ||  ltrim(dbms_metadata.get_ddl('SYNONYM', upper(p_synonym_name), p_owner), c_exp_crlf||' '));

        return l_script;
    end get_synonym;

    procedure add_synonyms(p_zip_file     in out nocopy blob,
                           p_object_name  in            varchar2 default null,
                           p_object_type  in            varchar2 default null) is
    begin
        for cur in (select synonym_name,  owner, 'synonyms/public/'||lower(synonym_name)||'.sql' filename
                      from all_synonyms
                     where owner in 'public'
                       and table_owner = user
                       and (   p_object_name is null
                            or (     synonym_name = upper(p_object_name)
                                 and p_object_type = 'SYNONYMS'))
                    union
                    select synonym_name,  user, 'synonyms/private/'||lower(synonym_name)||'.sql' filename
                      from user_synonyms
                    where (   p_object_name is null
                            or (     synonym_name = upper(p_object_name)
                                 and p_object_type = 'SYNONYMS')) )
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_synonym(p_synonym_name   => cur.synonym_name,
                                                                       p_owner => cur.owner)));
        end loop;
    end add_synonyms;

    function get_policy(p_object_name in varchar2)
                        return clob is
        l_script clob;
    begin
        l_script := to_lowercase('-- Exported with dbms_metadata.get_dependent_ddl' || chr(10) ||  ltrim(dbms_metadata.get_dependent_ddl('RLS_POLICY', upper(p_object_name), user), c_exp_crlf||' '));

        return l_script;
    end get_policy;

    procedure add_policies(p_zip_file     in out nocopy blob,
                           p_object_name  in            varchar2 default null,
                           p_object_type  in            varchar2 default null) is
    begin
        for cur in (select policy_name, object_name, 'policies/'||lower(object_name)||'.sql' filename
                      from user_policies
                    where (   p_object_name is null
                            or (     object_name = upper(p_object_name)
                                 and p_object_type = 'POLICIES')))
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_policy(p_object_name   => cur.object_name)));
        end loop;
    end add_policies;

    function get_context(p_namespace in varchar2)
                        return clob is
        l_script clob;
    begin
        l_script := to_lowercase('-- Exported with dbms_metadata.get_ddl' || chr(10) ||  ltrim(dbms_metadata.get_ddl('CONTEXT', upper(p_namespace)), c_exp_crlf||' '));

        return l_script;
    end get_context;

    procedure add_contexts(p_zip_file     in out nocopy blob,
                           p_object_name  in            varchar2 default null,
                           p_object_type  in            varchar2 default null) is
    begin
        for cur in (select namespace, 'contexts/'||lower(namespace)||'.sql' filename
                      from all_context
                     where schema = user
                       and (   p_object_name is null
                            or (     namespace = upper(p_object_name)
                                 and p_object_type = 'CONTEXTS'))
                     union
                    select p_object_name, 'contexts/'||lower(p_object_name)||'.sql' filename
                      from dual
                     where p_object_name is not null
                       and p_object_type = 'CONTEXTS')
        loop
            exp_zip_add_file(p_zipped_blob => p_zip_file
                            ,p_name        => cur.filename
                            ,p_content     => clob_to_blob(get_context(p_namespace  => cur.namespace)));
        end loop;
    end add_contexts;

    procedure add_grants(p_zip_file           in out nocopy blob,
                         p_grant_with_object  in            boolean  default false) is
        l_content clob;
        l_grant_with_object varchar(1) := case when p_grant_with_object then 'Y' else 'N' end;
    begin
        l_content := 'Prompt Revoke all grants found in user_tab_privs_made'||chr(10)
                || 'begin'||chr(10)
                || '  for revoke_rec in (select privilege, table_name, grantee'||chr(10)
                || '                       from user_tab_privs_made'||chr(10)
                || '                      where ('''||l_grant_with_object||''' = ''N'' or type not in (''VIEW'', ''PACKAGE''))'||chr(10)
                || '                        and table_name != user -- not INHERIT PRIVILEGES'||chr(10)
                || '                      )'||chr(10)
                || '  loop'||chr(10)
                || '    dbms_output.put_line(''revoke '' || revoke_rec.privilege || '' on '' || revoke_rec.table_name || '' from '' || revoke_rec.grantee);'||chr(10)
                || '    execute immediate ''revoke '' || revoke_rec.privilege || '' on '' || revoke_rec.table_name || '' from '' || revoke_rec.grantee;'||chr(10)
                || '  end loop;'||chr(10)
                || 'end;'||chr(10)
                || '/'||chr(10)
                || ''||chr(10)
                || ''||chr(10)
                || 'Prompt Grants to all known objects';

        for cur in (select 'grant ' || privilege || ' on ' || table_name || ' to ' || grantee ||
                        case when grantable = 'YES' then ' with grant option;' else ';' end as grant_script
                      from user_tab_privs_made
                    where not exists (select 1 from user_recyclebin where object_name = table_name )
                      and table_name != user -- not INHERIT PRIVILEGES
                      and (l_grant_with_object = 'N' or type not in ('VIEW', 'PACKAGE'))
                    order by grantee, table_name)
        loop
            l_content := concat(l_content, chr(10) || cur.grant_script);
        end loop;
        l_content := concat(l_content, chr(10));


        exp_zip_add_file(p_zipped_blob => p_zip_file
                        ,p_name        => 'ddl/base/010_grants.sql'
                        ,p_content     => clob_to_blob(l_content));
    end add_grants;

    function get_schema_zip(p_folder             in varchar2 default null,
                            p_file_name          in varchar2 default null,
                            p_grant_with_object  in boolean default false)
                            return blob is
        l_zip_file    blob;
        l_object_name varchar2(250) := upper(substr(p_file_name, 1, instr(p_file_name, '.')-1));
        l_object_type varchar2(250) := upper(p_folder);
    begin

        -- init boolean to validate, that something was exported, later
        g_exp_objects_found := false;

        -- init global files array
        g_exp_files.delete;


        dbms_lob.createtemporary(l_zip_file, true);

        --
        if (l_object_type is null or l_object_type in ('TABLES', 'INDEXES/PRIMARIES', 'INDEXES/UNIQUES', 'INDEXES/DEFAULTS')) then
            add_indexes(p_zip_file     => l_zip_file,
                        p_object_name  => l_object_name,
                        p_object_type  => l_object_type);
        end if;

        if (l_object_type is null or l_object_type in ('TABLES', 'CONSTRAINTS/PRIMARIES', 'CONSTRAINTS/FOREIGNS', 'CONSTRAINTS/CHECKS', 'CONSTRAINTS/UNIQUES')) then
            add_constraints(p_zip_file     => l_zip_file,
                            p_object_name  => l_object_name,
                            p_object_type  => l_object_type);
        end if;

        if (l_object_type is null or l_object_type = 'TABLES') then
            add_tables(p_zip_file   => l_zip_file,
                       p_table_name => l_object_name);
        end if;

        if (l_object_type is null or l_object_type in ('SOURCES/PACKAGES', 'SOURCES/TYPES', 'SOURCES/FUNCTIONS', 'SOURCES/PROCEDURES', 'SOURCES/TRIGGERS')) then
            add_sources(p_zip_file          => l_zip_file,
                        p_object_name       => l_object_name,
                        p_object_type       => l_object_type,
                        p_grant_with_object => p_grant_with_object);
        end if;

        if (l_object_type is null or l_object_type in ('TESTS/PACKAGES', 'TESTS/TYPES', 'TESTS/FUNCTIONS', 'TESTS/PROCEDURES')) then
            add_tests(p_zip_file      => l_zip_file,
                      p_object_name   => l_object_name,
                      p_object_type   => l_object_type);
        end if;

        if (l_object_type is null or l_object_type in ('SEQUENCES')) then
            add_sequences(p_zip_file      => l_zip_file,
                          p_object_name   => l_object_name,
                          p_object_type   => l_object_type);
        end if;

        if (l_object_type is null or l_object_type in ('VIEWS')) then
            add_views(p_zip_file          => l_zip_file,
                      p_object_name       => l_object_name,
                      p_object_type       => l_object_type,
                      p_grant_with_object => p_grant_with_object);
        end if;

        if (l_object_type is null or l_object_type in ('MVIEWS')) then
            add_mviews(p_zip_file      => l_zip_file,
                       p_object_name   => l_object_name,
                       p_object_type   => l_object_type);
        end if;

        if (l_object_type is null or l_object_type in ('JOBS')) then
            add_jobs(p_zip_file      => l_zip_file,
                     p_object_name   => l_object_name,
                     p_object_type   => l_object_type);
        end if;

        if (l_object_type is null or l_object_type in ('SYNONYMS/PUBLIC', 'SYNONYMS/PRIVATE')) then
            add_synonyms(p_zip_file      => l_zip_file,
                         p_object_name   => l_object_name,
                         p_object_type   => l_object_type);
        end if;

        if (l_object_type is null or l_object_type in ('POLICIES')) then
            add_policies(p_zip_file      => l_zip_file,
                         p_object_name   => l_object_name,
                         p_object_type   => l_object_type);
        end if;

        if (l_object_type is null or l_object_type in ('CONTEXTS')) then
            add_contexts(p_zip_file      => l_zip_file,
                         p_object_name   => l_object_name,
                         p_object_type   => l_object_type);
        end if;

        if (l_object_type is null) then
            add_grants(p_zip_file           => l_zip_file,
                       p_grant_with_object  => p_grant_with_object);
        end if;

        if not g_exp_objects_found then
            raise_application_error(-20002, 'Nothing found to export');
        end if;

        apex_zip.finish(p_zipped_blob => l_zip_file);
        return l_zip_file;
    end get_schema_zip;

    procedure export_schema_rest(p_folder             in varchar2,
                                 p_file_name          in varchar2,
                                 p_grants_with_object in varchar2) is
        l_zip blob;
    begin
        if not check_client_token then
            return;
        end if;
        reset_logs;

        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR',        true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY',               true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'STORAGE',              false);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SEGMENT_ATTRIBUTES',   false);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS',          true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'REF_CONSTRAINTS',      true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS_AS_ALTER', true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'EMIT_SCHEMA',          false);

        l_zip := get_schema_zip(p_folder            => p_folder,
                                p_file_name         => p_file_name,
                                p_grant_with_object => lower(nvl(p_grants_with_object, 'false')) = 'true');

        emit_zip_response(l_zip, lower(user) || '.zip');
    exception
        when others then
            emit_json_error_response;
    end export_schema_rest;

    -- #####################################################################
    -- ORDS REST module export
    -- #####################################################################

    procedure export_rest_module_rest(p_module_name in varchar2) is
        l_zip    blob;
        l_export clob;
    begin
        if not check_client_token then
            return;
        end if;
        reset_logs;

        -- dynamic call: ORDS_EXPORT availability differs between installations
        -- and a static reference would break package compilation
        begin
            execute immediate 'begin :l := ords_export.export_module(p_module_name => :m); end;'
                using out l_export, in p_module_name;
        exception
            when others then
                raise_application_error(-20004,
                    'ORDS module export failed or ORDS_EXPORT is not available for this schema: ' || sqlerrm);
        end;

        if l_export is null or dbms_lob.getlength(l_export) = 0 then
            raise_application_error(-20002, 'Nothing found to export (' || p_module_name || ')');
        end if;

        -- matches "prompt /" appended by the SQLNET based export
        l_export := l_export || chr(10) || '/' || chr(10);

        dbms_lob.createtemporary(l_zip, true);
        apex_zip.add_file(p_zipped_blob => l_zip,
                          p_file_name   => lower(p_module_name) || '.module.sql',
                          p_content     => clob_to_blob(l_export));
        apex_zip.finish(p_zipped_blob => l_zip);

        emit_zip_response(l_zip, lower(p_module_name) || '.zip');
    exception
        when others then
            emit_json_error_response;
    end export_rest_module_rest;

begin
    -- Compute the security token once at package load time.
    -- The same formula is used in rest_compile_api_client.sql to generate the
    -- REST_CLIENT_TOKEN value that callers must send in the x-dbflow-token header.
    begin
        select lower(rawtohex(
                   standard_hash(
                       sys_context('USERENV', 'CURRENT_USER') ||
                       '|' ||
                       (select workspace from apex_workspaces where rownum = 1),
                       'SHA256'
                   )
               ))
          into g_client_token
          from dual;
    exception
        when others then
            g_client_token := null;
    end;
end;
/
