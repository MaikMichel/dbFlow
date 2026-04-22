create or replace package rest_compile_test is
    --%suite(Tests for rest_compile package)
    --%rollback(manual)

    --%beforeall
    procedure setup_suite;

    --%aftereach
    procedure teardown_test;

    --%test(NULL input returns empty_clob)
    procedure null_returns_empty_clob;

    --%test(normalizes CRLF and CR to LF)
    procedure normalizes_newlines;

    --%test(trims trailing whitespace and ensures exactly one trailing LF)
    procedure trims_and_appends_one_lf;

    -------

    --%test(NULL input returns empty array)
    procedure null_returns_empty;

    --%test(Single line without LF returns one element)
    procedure single_line_no_lf;

    --%test(Two lines separated by LF)
    procedure two_lines_with_lf;

    --%test(Handles empty lines)
    procedure empty_line_in_between;

    -------

    --%test(returns true for NULL and whitespace-only lines)
    procedure null_and_blank;

    --%test(returns true for known SQL*Plus directives, case-insensitive, with optional leading spaces)
    procedure directives_are_true;

    --%test(returns false for non-directive SQL and for the slash terminator line)
    procedure non_directives_are_false;

    --%test(only exact prefixes match: e.g. "SETX" is not "SET ")
    procedure prefix_boundary_cases;

    ------
    --%test(creates a temporary CLOB when target is NULL and appends line + newline)
  procedure creates_and_appends_first_line;

  --%test(appends multiple lines, each terminated by LF)
  procedure appends_multiple_lines;

  --%test(appends an empty string as just a newline)
  procedure appends_empty_line;

  --%test(accepts NULL line and still appends a newline)
  procedure appends_null_line_as_newline;


  -------

  --%test(ignores SQL*Plus directives)
  procedure ignores_sqlplus_directives;

  --%test(splits simple DDL by semicolon)
  procedure splits_simple_ddl;

  --%test(collects declare/begin/end block as one statement)
  procedure collects_plsql_block;

  --%test(collects nested anonymous block with exception section as one statement)
  procedure collects_nested_anonymous_block;

  --%test(collects create or replace unit terminated by slash line)
  procedure collects_cor_terminated_by_slash;

  --%test(does not terminate on semicolons inside string literals)
  procedure ignores_semicolon_in_string;

  --%test(does not terminate on semicolons inside quoted string literals)
  procedure ignores_semicolon_in_quoted_string;

  --%test(does not terminate on semicolons inside block comments)
  procedure ignores_semicolon_in_block_comment;

  --%test(does not terminate on semicolons inside line comments)
  procedure ignores_semicolon_in_line_comment;

  --%test(collects anonymous block with multiline comment markers as one statement)
  procedure collects_anonymous_block_with_multiline_comment;

  --%test(collects nested anonymous block with line comment before nested begin)
  procedure collects_nested_block_after_line_comment;

  --%test(skips leading multiline comment before first statement)
  procedure skips_leading_multiline_comment_before_statement;

  --%test(executes nested anonymous block as a single statement)
  procedure runs_nested_anonymous_block;

  --%test(executes anonymous block with multiline comment markers as a single statement)
  procedure runs_anonymous_block_with_multiline_comment;

  --%test(processes plain blob payloads)
  procedure runs_plain_blob_payload;

  --%test(processes zipped payload with a single sql file)
  procedure runs_single_file_zip_payload;

  --%test(rejects zipped payloads with multiple files)
  procedure rejects_multi_file_zip_payload;

  --%test(rejects invalid zip payloads declared as zip)
  procedure rejects_invalid_zip_payload;

  ----
  --%test(runs json fixtures)
  procedure run_all;

  --%test(keep multiline comment slash in place)
  procedure test_multiline_comment_slashs;
end;
/
