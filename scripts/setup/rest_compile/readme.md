# dbFlow REST Compile

## What `rest_compile` is

`rest_compile` is a lightweight deployment component for Oracle environments where direct database access is not available or not desired. It installs a PL/SQL package, a small log table, and an ORDS REST module that together allow dbFlow to send SQL or PL/SQL deployment payloads over HTTPS instead of using SQL*Net.

In practice, `rest_compile` acts as a remote execution endpoint for deployment artifacts. A client such as dbFlow can upload a script to the REST service, and the package executes the contained statements inside the target schema.

## What it is used for

`rest_compile` is intended for restricted environments such as:

- Oracle APEX workspaces
- ORDS-based environments with web access but without direct database connectivity
- customer environments where opening SQL*Net access is not possible or not approved

This makes it possible to deploy selected database changes through a controlled REST interface. It is especially useful for setup, patching, and object compilation scenarios in environments that can only be reached through ORDS.

## What the installation provides

The accompanying `install.sql` installs the following pieces:

- the `rest_compile` PL/SQL package, which parses and executes incoming deployment content
- the `rest_compile_logs` table, which stores the received payload and request metadata for traceability
- an ORDS module under `/dbflow/deploy/`
- REST handlers for script execution and APEX application import
- ORDS role and privilege definitions required to secure the endpoint

## How it works

For script deployment, dbFlow sends a file payload to the ORDS endpoint. `rest_compile` accepts plain text content and also supports ZIP payloads that contain exactly one file. The payload is normalized, split into executable statements, and then executed sequentially in the target schema.

The service returns a JSON response with execution status, statement counters, runtime information, and error details where available. This gives calling tools a machine-readable result that can be used for deployment feedback and troubleshooting.

## Endpoints

All endpoints live under the module base path `/dbflow/deploy/` and are protected by the same OAuth privilege:

| Method | Path | Purpose | Response |
|--------|------|---------|----------|
| GET  | `compile` | health check, returns `version` and `api_level` | JSON |
| POST | `compile` | execute a SQL/PLSQL payload (plain or ZIP) | JSON |
| POST | `impapp` | import an APEX application | JSON |
| POST | `compileschema` | recompile all/invalid objects of the schema | JSON |
| POST | `expapp` | export an APEX application (split files) | ZIP |
| POST | `expplugin` | export an APEX plugin component | ZIP |
| POST | `expstatics` | export APEX application static files | ZIP |
| POST | `exppluginfiles` | export APEX plugin files | ZIP |
| POST | `rmstaticfile` | remove an APEX static file | JSON |
| POST | `expschema` | export schema/object DDL via dbms_metadata | ZIP |
| POST | `exprest` | export an ORDS REST module | ZIP |

Export endpoints respond with `Content-Type: application/zip` on success and with the regular JSON error structure (`success: false`, `code`, `message`, `stackTrace`) on failure, so clients discriminate on the response content type.

## Versioning and upgrades

`GET /dbflow/deploy/compile` returns the installed package version and an `api_level`. Clients such as dbFlux check this level before calling the newer endpoints and ask the user to upgrade when the installed package is too old. Installations created before version 1.1.0 return neither field, which clients treat as `api_level 0` (compile/impapp only).

Upgrading is done by re-running `install.sql` in the target schema (all objects are created with `create or replace`, the ORDS module definition is re-applied). Note that re-running the install script drops and recreates the `rest_compile_logs` table, so previously logged payloads are lost.

## Testing the installation

`test_endpoints.sh` runs a non-destructive smoke test suite against a live installation. It verifies the OAuth flow, the privilege protection, the header parameter bindings of every endpoint, the version/`api_level` contract, and the content-type discrimination of the export endpoints (ZIP on success, JSON on error). It is the recommended check after every `install.sql` run — initial install or upgrade.

It requires `curl`, `jq`, and `unzip`, plus the three connection variables printed by `rest_compile_api_client.sql`:

```bash
source apply.env   # provides REST_SQL_URL, REST_OAUTH_TOKEN_URL, REST_OAUTH_BASIC_B64
./test_endpoints.sh
```

Tests for the export endpoints need existing objects to export. They are skipped unless the corresponding fixture variables are set:

```bash
TEST_APP_ID=123 TEST_PLUGIN_NAME=DE.MYCOMPANY.REGION \
TEST_MODULE_NAME=api TEST_TABLE_NAME=EMPLOYEES ./test_endpoints.sh
```

Nothing is imported, removed, or changed in the target schema; the only executed payload is a `begin null; end;` block sent to `POST compile`. The script exits with the number of failed tests (`0` = all green). Against an installation older than 1.1.0 it stops at the version check with a hint to re-run `install.sql`.

## Scope and intended use

`rest_compile` is designed to support controlled remote compilation and deployment of database artifacts when conventional database connections are not available. It is not intended to replace full-access deployment pipelines in environments where standard dbFlow deployment via SQL*Net is possible.

The component is best suited for:

- remote installation of SQL and PL/SQL objects
- controlled delivery of single-file deployment artifacts
- integration with dbFlow-based deployment workflows in web-only environments

## Deliverable note

This `readme.md` is intended to be distributed together with `install.sql`. The SQL script installs the technical runtime; this document explains its purpose, operating model, and typical use case from a customer perspective.
