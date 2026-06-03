#!/usr/bin/env bash

function usage() {
  cat <<'EOF'
Usage:
  ./.dbFlow/exec-sql.sh <schema> <command>
  ./.dbFlow/exec-sql.sh --help

Arguments:
  <schema>   Target schema. Required in all project modes.
  <command>  Existing .sql file path or inline SQL/PLSQL command.

Examples:
  ./.dbFlow/exec-sql.sh ati db/ati/sources/packages/my_package.pkb
  ./.dbFlow/exec-sql.sh ati "alter package my_package compile body;"
  ./.dbFlow/exec-sql.sh ati $'begin\n  my_package.recompile;\nend;\n/'
EOF
}

function fail_plain() {
  local message=$1
  local exit_code=${2:-2}

  echo "${message}" >&2
  exit "${exit_code}"
}

function load_environment() {
  if [[ -e ./build.env ]]; then
    source ./build.env
  fi

  if [[ ! -r ./.dbFlow/lib.sh ]]; then
    fail_plain "Missing required file ./.dbFlow/lib.sh"
  fi

  source ./.dbFlow/lib.sh

  if [[ ! -e ./apply.env ]]; then
    echo_fatal "Missing required file ./apply.env"
    exit 2
  fi

  source ./apply.env
  validate_passes

  SQLCLI=${SQLCLI:-sqlplus}
  CONN_MODE=${CONN_MODE:-SQLNET}
  PROJECT_MODE=${PROJECT_MODE:-SINGLE}
}

function fail() {
  local message=$1
  local exit_code=${2:-2}

  echo_fatal "${message}"
  exit "${exit_code}"
}

function validate_runtime() {
  if [[ "${CONN_MODE}" != "SQLNET" ]]; then
    fail "exec-sql.sh supports only CONN_MODE=SQLNET"
  fi

  if [[ -z "${DB_APP_USER:-}" ]]; then
    fail "DB_APP_USER not defined in apply.env"
  fi

  if [[ -z "${DB_TNS:-}" ]]; then
    fail "DB_TNS not defined in apply.env"
  fi

  if ! command -v "${SQLCLI}" >/dev/null 2>&1; then
    fail "SQL client '${SQLCLI}' not found in PATH"
  fi
}

function validate_single_schema() {
  local targetschema=$1

  if [[ -z "${APP_SCHEMA:-}" ]]; then
    fail "APP_SCHEMA not defined for PROJECT_MODE=SINGLE"
  fi

  if [[ "${targetschema}" != "${APP_SCHEMA}" ]]; then
    fail "Schema '${targetschema}' is invalid for PROJECT_MODE=SINGLE; expected '${APP_SCHEMA}'"
  fi
}

function validate_multi_schema() {
  local targetschema=$1
  local schema

  for schema in "${APP_SCHEMA:-}" "${DATA_SCHEMA:-}" "${LOGIC_SCHEMA:-}"; do
    if [[ -n "${schema}" ]] && [[ "${targetschema}" == "${schema}" ]]; then
      return 0
    fi
  done

  fail "Schema '${targetschema}' is not one of APP_SCHEMA/DATA_SCHEMA/LOGIC_SCHEMA"
}

function validate_flex_schema() {
  local targetschema=$1
  local schema

  for schema in "${DBSCHEMAS[@]}"; do
    if [[ "${targetschema}" == "${schema}" ]]; then
      return 0
    fi
  done

  fail "Schema '${targetschema}' is not part of DBSCHEMAS (${DBSCHEMAS[*]})"
}

function validate_schema() {
  local targetschema=$1

  if [[ -z "${targetschema}" ]]; then
    fail "Schema argument is required"
  fi

  case "${PROJECT_MODE}" in
    SINGLE)
      validate_single_schema "${targetschema}"
      ;;
    MULTI)
      validate_multi_schema "${targetschema}"
      ;;
    FLEX)
      validate_flex_schema "${targetschema}"
      ;;
    *)
      fail "Unsupported PROJECT_MODE '${PROJECT_MODE}'"
      ;;
  esac
}

function execute_sql_file() {
  local targetschema=$1
  local sql_file=$2

  "${SQLCLI}" -S -L "$(get_connect_string "${targetschema}")" <<EOF
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set serveroutput on
@"${sql_file}"
exit success
EOF
}

function execute_inline_sql() {
  local targetschema=$1
  local sql_command=$2

  "${SQLCLI}" -S -L "$(get_connect_string "${targetschema}")" <<EOF
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set serveroutput on
${sql_command}
exit success
EOF
}

function execute_command() {
  local targetschema=$1
  local command_input=$2

  if [[ -f "${command_input}" ]]; then
    execute_sql_file "${targetschema}" "${command_input}"
    return $?
  fi

  execute_inline_sql "${targetschema}" "${command_input}"
}

function main() {
  local targetschema=""
  local command_input=""

  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  case "${1}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  if [[ $# -lt 2 ]]; then
    usage
    exit 1
  fi

  targetschema=$1
  shift
  command_input="$*"

  load_environment
  validate_schema "${targetschema}"
  validate_runtime
  execute_command "${targetschema}" "${command_input}"
}

main "$@"
