create or replace package body rest_compile is


    g_logs        t_array;
    g_log_entries json_array_t := json_array_t();

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

                -- If we are in CREATE OR REPLACE mode and stack empty, a slash line terminates the statement
                if l_is_slash_line and not l_in_squote and not l_in_line_comment and not l_in_block_comment then
                    -- SQL*Plus/SQLcl delimiter: never part of the statement text
                    -- If a statement is still open and we are in a create-unit, you may finalize here.
                    if l_expect_slash_end and l_stmt.stmt_text is not null then
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

    procedure execute_statement(p_fname in varchar2,
                                p_stmt in r_statement) is
        l_start number := dbms_utility.get_time;
    begin
        execute immediate p_stmt.stmt_text;
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

end;
/
