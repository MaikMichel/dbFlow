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

## Scope and intended use

`rest_compile` is designed to support controlled remote compilation and deployment of database artifacts when conventional database connections are not available. It is not intended to replace full-access deployment pipelines in environments where standard dbFlow deployment via SQL*Net is possible.

The component is best suited for:

- remote installation of SQL and PL/SQL objects
- controlled delivery of single-file deployment artifacts
- integration with dbFlow-based deployment workflows in web-only environments

## Deliverable note

This `readme.md` is intended to be distributed together with `install.sql`. The SQL script installs the technical runtime; this document explains its purpose, operating model, and typical use case from a customer perspective.
