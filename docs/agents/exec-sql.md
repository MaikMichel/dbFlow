# Database Query and SQL Execution Workflow

Use `.dbFlow/exec-sql.sh` whenever you need to test SQL scripts, compile a package or package body, or run ad-hoc SQL/PLSQL queries against the configured database from this repository.

## Why use it

- Prefer `.dbFlow/exec-sql.sh` over custom `sqlplus` command lines so the connection details from `apply.env`, password decoding via `validate_passes`, proxy schema handling, and project-mode schema validation stay consistent with `.dbFlow/apply.sh`.
- The canonical script path is `./.dbFlow/exec-sql.sh`.
- The script returns the `sqlplus` exit code and prints SQL*Plus stdout/stderr directly.

## Syntax

```bash
./.dbFlow/exec-sql.sh <schema> <command>
./.dbFlow/exec-sql.sh --help
```

`<command>` may be either a path to an existing `.sql` file or an inline SQL/PLSQL statement or block.

## Examples

```bash
./.dbFlow/exec-sql.sh ati db/ati/sources/packages/my_package.pkb
./.dbFlow/exec-sql.sh ati "alter package my_package compile body;"
./.dbFlow/exec-sql.sh ati $'begin\n  my_package.recompile;\nend;\n/'
```

## Behavior

- Loads `build.env`, `.dbFlow/lib.sh`, and `apply.env`.
- Runs `validate_passes`, so encoded passwords in `apply.env` are handled exactly like in `.dbFlow/apply.sh`.
- Uses `get_connect_string()` from `.dbFlow/lib.sh`, including proxy connections and optional `DBFLOW_<SCHEMA>_PWD` overrides.
- Supports only `CONN_MODE=SQLNET`.
- Treats `<command>` as a file when the path exists; otherwise it is executed as inline SQL/PLSQL.

## Project Mode Rules

- `SINGLE`: `<schema>` is mandatory and must equal `APP_SCHEMA`.
- `MULTI`: `<schema>` must be one of `APP_SCHEMA`, `DATA_SCHEMA`, or `LOGIC_SCHEMA`.
- `FLEX`: `<schema>` must match one of the discovered schema folders under `db/`.

## Recommended Use Cases

- Compile package specs or bodies from `db/<schema>/sources/...`.
- Check whether a query returns the expected rows.
- Run targeted anonymous PL/SQL blocks for debugging.

## Notes

- For PL/SQL blocks, pass the command with shell quoting that preserves newlines so the trailing `/` remains on its own line.
- Do not use `.dbFlow/exec-sql.sh` as a replacement for `.dbFlow/apply.sh` when validating full deployments or patch or install flows.
