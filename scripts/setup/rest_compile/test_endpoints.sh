#!/usr/bin/env bash
# Smoke tests for the rest_compile ORDS endpoints.
#
# Runs non-destructive requests against a live ORDS/APEX instance to verify
# the installation: OAuth flow, privilege protection, header parameter
# bindings, content-type discrimination (ZIP on success, JSON on error) and
# the version/api_level contract. Intended as a post-install / post-upgrade
# check after running install.sql.
#
# Required environment (as printed by rest_compile_api_client.sql):
#   REST_SQL_URL          .../<workspace>/dbflow/deploy
#   REST_CLIENT_TOKEN     SHA-256 token printed by rest_compile_api_client.sql
#   REST_USES_OAUTH       TRUE (default) or FALSE
#
# OAuth mode (REST_USES_OAUTH=TRUE, default):
#   REST_OAUTH_TOKEN_URL  .../<workspace>/oauth/token
#   REST_OAUTH_BASIC_B64  base64(client_id:client_secret)
#
# Optional fixtures (tests are skipped when unset):
#   TEST_APP_ID        existing APEX application id
#   TEST_PLUGIN_NAME   plugin name inside TEST_APP_ID (e.g. DE.MYCOMPANY.REGION)
#   TEST_MODULE_NAME   existing ORDS module name (default: com.dbflow.deploy,
#                      which is installed by definition)
#   TEST_TABLE_NAME    existing table name for a targeted DDL export
#
# Usage:
#   ./test_endpoints.sh                       (auto-detects apply.env)
#   source apply.env && ./test_endpoints.sh   (explicit)
#
# All tests are non-destructive: nothing is imported, removed or changed.
# POST /compile only executes harmless anonymous blocks (begin null; end;,
# a raise_application_error probe, dbms_output) that leave no objects behind;
# the impapp test targets a non-existing workspace and fails before install.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# lib.sh references DB schema variables not available in this context;
# disable nounset for the source call to avoid "unbound variable" errors.
set +u
# shellcheck source=../../../lib.sh
source "${SCRIPT_DIR}/../../../lib.sh"
# restore settings lib.sh changes that we don't want here
set -u
set +o errexit
set +o errtrace
set +o pipefail

# --- auto-source apply.env if REST_SQL_URL is not already in the environment --
# Walk up from CWD (like git does for .git) so the script works from any
# subdirectory of the project, regardless of where dbFlow sources live.
if [[ -z "${REST_SQL_URL:-}" ]]; then
  _search_dir="$(pwd)"
  while [[ "${_search_dir}" != "/" ]]; do
    if [[ -f "${_search_dir}/apply.env" ]]; then
      # shellcheck source=/dev/null
      source "${_search_dir}/apply.env"
      break
    fi
    _search_dir="$(dirname "${_search_dir}")"
  done
  unset _search_dir
fi

# --- configuration ---------------------------------------------------------

TEST_CONNECT_TIMEOUT="${TEST_CONNECT_TIMEOUT:-10}"
TEST_TOKEN_MAX_TIME="${TEST_TOKEN_MAX_TIME:-30}"
TEST_COMPILE_MAX_TIME="${TEST_COMPILE_MAX_TIME:-120}"
TEST_EXPORT_MAX_TIME="${TEST_EXPORT_MAX_TIME:-600}"

for cmd in curl jq unzip; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "FATAL: required command '${cmd}' not found" >&2
    exit 2
  fi
done

# optional: only needed for the ZIP payload test (skipped when missing)
HAS_ZIP=0
command -v zip >/dev/null 2>&1 && HAS_ZIP=1

# the com.dbflow.deploy module itself exists on every installation, so the
# exprest positive test can always run unless a different module is requested
TEST_MODULE_NAME="${TEST_MODULE_NAME:-com.dbflow.deploy}"

REST_USES_OAUTH="${REST_USES_OAUTH:-TRUE}"

if [[ -z "${REST_SQL_URL:-}" ]]; then
  echo "FATAL: REST_SQL_URL is not set — place an apply.env in your project root" >&2
  echo "       or run: source apply.env && $0" >&2
  exit 2
fi

if [[ "${REST_USES_OAUTH}" == "TRUE" ]]; then
  for var in REST_OAUTH_TOKEN_URL REST_OAUTH_BASIC_B64; do
    if [[ -z "${!var:-}" ]]; then
      echo "FATAL: ${var} is not set (required when REST_USES_OAUTH=TRUE)" >&2
      echo "       see rest_compile_api_client.sql output for the values" >&2
      exit 2
    fi
  done
fi

REST_SQL_URL="${REST_SQL_URL%/}"

if [[ -t 1 ]]; then
  C_GREEN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_YELLOW=$'\033[0;33m'; C_OFF=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_OFF=""
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dbflow-rest-test.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# millisecond timestamps for per-test durations; macOS ships bash 3.2 without
# $EPOCHREALTIME and a date that ignores %N, so use perl (always available there)
function now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf("%d", time()*1000)'
  else
    printf '%s000' "$(date +%s)"
  fi
}

T_SUITE_START_MS="$(now_ms)"
T_LAST_MS="${T_SUITE_START_MS}"
T_ELAPSED=""

# t_mark: format the time since the last report into T_ELAPSED (e.g. "1.4s")
# and restart the timer. Must set a global — a $(...) call would lose the
# T_LAST_MS update to the subshell.
function t_mark() {
  local _now _delta
  _now="$(now_ms)"
  _delta=$(( _now - T_LAST_MS ))
  T_ELAPSED="$(( _delta / 1000 )).$(( (_delta % 1000) / 100 ))s"
  T_LAST_MS="${_now}"
}

function t_ok() {
  t_mark
  TESTS_RUN=$((TESTS_RUN + 1))
  printf "%sok%s %d - %s (%s)\n" "${C_GREEN}" "${C_OFF}" "${TESTS_RUN}" "$1" "${T_ELAPSED}"
}

function t_fail() {
  t_mark
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "%snot ok%s %d - %s (%s)\n" "${C_RED}" "${C_OFF}" "${TESTS_RUN}" "$1" "${T_ELAPSED}"
  if [[ -n "${2:-}" ]]; then
    printf "       %s\n" "$2"
  fi
}

function t_skip() {
  # restart the timer so skips do not inflate the next test's duration
  t_mark
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  printf "%sskip%s - %s (%s)\n" "${C_YELLOW}" "${C_OFF}" "$1" "$2"
}

# --- request helpers -------------------------------------------------------

# Wrapper around rest_curl (from lib.sh): adds browser headers + proxy support,
# suppresses HTTP/2 stream-closure noise (exit code 92), forwards other errors.
function _curl() {
  local _err="${WORK_DIR}/curl_err"
  # rest_curl uses empty arrays (proxy_args) that trigger set -u; disable briefly
  set +u
  rest_curl -sS "$@" 2>"${_err}"
  local _rc=$?
  set -u
  [[ ${_rc} -ne 0 ]] && [[ ${_rc} -ne 92 ]] && cat "${_err}" >&2
  return ${_rc}
}

ACCESS_TOKEN=""
RESP_STATUS=""
RESP_CONTENT_TYPE=""
RESP_BODY_FILE="${WORK_DIR}/body"

# call_endpoint <max-time> <endpoint> [curl args ...]
# POSTs to ${REST_SQL_URL}/<endpoint> with auth headers and stores
# http status / content type / body for the assertions below.
function call_endpoint() {
  local max_time="$1"
  local endpoint="$2"
  shift 2

  local headers_file="${WORK_DIR}/headers"
  : > "${RESP_BODY_FILE}"

  local -a auth_args=()
  if [[ "${REST_USES_OAUTH}" == "TRUE" ]] && [[ -n "${ACCESS_TOKEN:-}" ]]; then
    auth_args+=( --header "Authorization: Bearer ${ACCESS_TOKEN}" )
  fi
  if [[ -n "${REST_CLIENT_TOKEN:-}" ]]; then
    auth_args+=( --header "x-dbflow-token: ${REST_CLIENT_TOKEN}" )
  fi

  RESP_STATUS=$(_curl \
    --connect-timeout "${TEST_CONNECT_TIMEOUT}" \
    --max-time "${max_time}" \
    -X POST \
    -D "${headers_file}" \
    -o "${RESP_BODY_FILE}" \
    -w '%{http_code}' \
    "${auth_args[@]}" \
    "$@" \
    "${REST_SQL_URL}/${endpoint}")
  local rc=$?

  RESP_CONTENT_TYPE=$(awk 'tolower($1) == "content-type:" {print tolower($2)}' "${headers_file}" 2>/dev/null | tr -d '\r' | tail -1)
  return ${rc}
}

function body_json() {
  jq -r "$1" "${RESP_BODY_FILE}" 2>/dev/null
}

function body_excerpt() {
  head -c 300 "${RESP_BODY_FILE}" 2>/dev/null | tr -d '\r\n'
}

# expect_zip <test name>: response must be application/zip and a valid archive
function expect_zip() {
  local name="$1"
  if [[ "${RESP_CONTENT_TYPE}" != application/zip* ]]; then
    t_fail "${name}" "expected application/zip, got '${RESP_CONTENT_TYPE}' (HTTP ${RESP_STATUS}): $(body_excerpt)"
    return 1
  fi
  if ! unzip -t -qq "${RESP_BODY_FILE}" >/dev/null 2>&1; then
    t_fail "${name}" "response is application/zip but not a valid archive"
    return 1
  fi
  t_ok "${name}"
}

# expect_json_error <test name>: response must be JSON with success=false
function expect_json_error() {
  local name="$1"
  if [[ "${RESP_CONTENT_TYPE}" == application/zip* ]]; then
    t_fail "${name}" "expected a JSON error response, got application/zip"
    return 1
  fi
  if [[ "$(body_json '.success')" == "false" ]]; then
    t_ok "${name}"
  else
    t_fail "${name}" "expected success:false (HTTP ${RESP_STATUS}): $(body_excerpt)"
  fi
}

# --- OAuth token --------------------------------------------------------

echo "# rest_compile endpoint smoke tests against ${REST_SQL_URL}"
echo

if [[ "${REST_USES_OAUTH}" == "TRUE" ]]; then
  token_response=$(_curl \
    --connect-timeout "${TEST_CONNECT_TIMEOUT}" \
    --max-time "${TEST_TOKEN_MAX_TIME}" \
    --header "Authorization: Basic ${REST_OAUTH_BASIC_B64}" \
    --data "grant_type=client_credentials" \
    "${REST_OAUTH_TOKEN_URL}")
  _token_curl_rc=${PIPESTATUS[0]:-$?}

  ACCESS_TOKEN=$(jq -r '.access_token // empty' <<< "${token_response}" 2>/dev/null)
  if [[ -n "${ACCESS_TOKEN}" ]]; then
    t_ok "OAuth token endpoint returns access_token"
  else
    t_fail "OAuth token endpoint returns access_token" \
      "curl rc=${_token_curl_rc} url=${REST_OAUTH_TOKEN_URL} response=${token_response:-<empty>}"
    echo
    echo "FATAL: cannot continue without an access token" >&2
    exit 1
  fi
else
  t_skip "OAuth token endpoint returns access_token" "REST_USES_OAUTH=FALSE"
fi

# --- protection check ---------------------------------------------------

if [[ "${REST_USES_OAUTH}" == "TRUE" ]]; then
  status_no_auth=$(_curl -o /dev/null -w '%{http_code}' \
    --connect-timeout "${TEST_CONNECT_TIMEOUT}" \
    --max-time "${TEST_TOKEN_MAX_TIME}" \
    "${REST_SQL_URL}/compile")

  if [[ "${status_no_auth}" == "401" ]] || [[ "${status_no_auth}" == "403" ]]; then
    t_ok "GET compile without any auth is rejected (HTTP ${status_no_auth})"
  else
    t_fail "GET compile without any auth is rejected" "got HTTP ${status_no_auth} - endpoint may be unprotected!"
  fi
else
  t_skip "GET compile without any auth is rejected" "REST_USES_OAUTH=FALSE — ORDS-level OAuth protection not active"
fi

# --- version / api_level contract ---------------------------------------

info_auth_args=()
if [[ "${REST_USES_OAUTH}" == "TRUE" ]] && [[ -n "${ACCESS_TOKEN:-}" ]]; then
  info_auth_args+=( --header "Authorization: Bearer ${ACCESS_TOKEN}" )
fi
if [[ -n "${REST_CLIENT_TOKEN:-}" ]]; then
  info_auth_args+=( --header "x-dbflow-token: ${REST_CLIENT_TOKEN}" )
fi

info_response=$(_curl \
  --connect-timeout "${TEST_CONNECT_TIMEOUT}" \
  --max-time "${TEST_TOKEN_MAX_TIME}" \
  "${info_auth_args[@]}" \
  "${REST_SQL_URL}/compile")

info_success=$(jq -r '.success // false' <<< "${info_response}" 2>/dev/null)
info_version=$(jq -r '.version // empty' <<< "${info_response}" 2>/dev/null)
info_api_level=$(jq -r '.api_level // 0' <<< "${info_response}" 2>/dev/null)
info_error=$(jq -r '.error // empty' <<< "${info_response}" 2>/dev/null)

if [[ "${info_success}" == "true" ]] && [[ "${info_version}" =~ ^1\. ]] && [[ "${info_api_level}" -ge 3 ]]; then
  t_ok "GET compile reports version ${info_version}, api_level ${info_api_level}"
elif [[ -n "${info_error}" ]]; then
  t_fail "GET compile reports version and api_level >= 3" "${info_response}"
  echo
  echo "FATAL: server rejected the request (${info_error})" >&2
  echo "       check REST_CLIENT_TOKEN and REST_USES_OAUTH / OAuth credentials" >&2
  exit 1
else
  t_fail "GET compile reports version and api_level >= 3" "${info_response}"
  echo
  echo "FATAL: server reports api_level ${info_api_level} — the installed rest_compile" >&2
  echo "       package is older than 1.3.0 and does not accept hyphen request headers" >&2
  echo "       (app-id, file-name, ...); re-run install.sql and try again" >&2
  exit 1
fi

# --- client token protection ----------------------------------------------
# In no-OAuth installations the x-dbflow-token check is the ONLY protection;
# these tests fail loudly if g_client_token ever ends up NULL (open API).

if [[ -n "${REST_CLIENT_TOKEN:-}" ]]; then
  bearer_args=()
  if [[ "${REST_USES_OAUTH}" == "TRUE" ]] && [[ -n "${ACCESS_TOKEN:-}" ]]; then
    bearer_args+=( --header "Authorization: Bearer ${ACCESS_TOKEN}" )
  fi

  # ${arr[@]+...} keeps bash 3.2 (macOS) happy when the array is empty under set -u
  wrong_token_response=$(_curl \
    --connect-timeout "${TEST_CONNECT_TIMEOUT}" \
    --max-time "${TEST_TOKEN_MAX_TIME}" \
    ${bearer_args[@]+"${bearer_args[@]}"} \
    --header "x-dbflow-token: 0000000000000000000000000000000000000000000000000000000000000000" \
    "${REST_SQL_URL}/compile")

  # note: jq's // operator treats false as empty, so query .success directly
  if [[ "$(jq -r '.success' <<< "${wrong_token_response}" 2>/dev/null)" == "false" ]] \
     && [[ "$(jq -r '.error // empty' <<< "${wrong_token_response}" 2>/dev/null)" == "Unauthorized" ]]; then
    t_ok "GET compile with a wrong x-dbflow-token is rejected (Unauthorized)"
  else
    t_fail "GET compile with a wrong x-dbflow-token is rejected" \
      "expected success:false/Unauthorized — token check may be inactive! response: ${wrong_token_response:-<empty>}"
  fi

  # WAFs (e.g. Akamai on oracleapex.com) may already block token-less requests
  # with an HTML 403 before ORDS is reached, so only assert that the request
  # is NOT answered with success:true — the wrong-token test above covers the
  # package-level check precisely.
  no_token_response=$(_curl \
    --connect-timeout "${TEST_CONNECT_TIMEOUT}" \
    --max-time "${TEST_TOKEN_MAX_TIME}" \
    ${bearer_args[@]+"${bearer_args[@]}"} \
    "${REST_SQL_URL}/compile")

  if [[ "$(jq -r '.success' <<< "${no_token_response}" 2>/dev/null)" == "true" ]]; then
    t_fail "GET compile without x-dbflow-token is not accepted" \
      "got success:true without a token — the endpoint is unprotected!"
  else
    t_ok "GET compile without x-dbflow-token is not accepted"
  fi
else
  t_skip "GET compile with a wrong x-dbflow-token is rejected" "REST_CLIENT_TOKEN not set"
  t_skip "GET compile without x-dbflow-token is rejected" "REST_CLIENT_TOKEN not set"
fi

# --- POST compile with a plain payload ----------------------------------

printf 'begin\n  null;\nend;\n/\n' > "${WORK_DIR}/payload.sql"
call_endpoint "${TEST_COMPILE_MAX_TIME}" "compile" \
  --header "Content-Type: application/sql" \
  --header "file-name: dbflow_smoke_test.sql" \
  --data-binary @"${WORK_DIR}/payload.sql"

if [[ "$(body_json '.success')" == "true" ]]; then
  t_ok "POST compile executes a plain 'begin null; end;' payload"
else
  t_fail "POST compile executes a plain 'begin null; end;' payload" "HTTP ${RESP_STATUS}: $(body_excerpt)"
fi

# regression: proxies like Akamai silently drop request headers containing
# underscores; the echoed file_name proves the hyphen header arrived intact
if [[ "$(body_json '.file_name')" == "dbflow_smoke_test.sql" ]]; then
  t_ok "POST compile echoes the file-name header (no header mangling by proxies)"
else
  t_fail "POST compile echoes the file-name header" \
    "expected 'dbflow_smoke_test.sql', got '$(body_json '.file_name')' — a proxy between client and ORDS may drop custom request headers"
fi

# --- POST compile with a ZIP payload (exactly one file inside) ------------

if [[ "${HAS_ZIP}" -eq 1 ]]; then
  printf 'begin\n  null;\nend;\n/\n' > "${WORK_DIR}/dbflow_zip_test.sql"
  (cd "${WORK_DIR}" && zip -q payload.zip dbflow_zip_test.sql)
  call_endpoint "${TEST_COMPILE_MAX_TIME}" "compile" \
    --header "Content-Type: application/zip" \
    --data-binary @"${WORK_DIR}/payload.zip"

  if [[ "$(body_json '.success')" == "true" ]] \
     && [[ "$(body_json '.is_zip')" == "true" ]] \
     && [[ "$(body_json '.file_name')" == "dbflow_zip_test.sql" ]]; then
    t_ok "POST compile executes a ZIP payload (is_zip:true, file name from archive)"
  else
    t_fail "POST compile executes a ZIP payload" "HTTP ${RESP_STATUS}: $(body_excerpt)"
  fi
else
  t_skip "POST compile executes a ZIP payload" "zip command not available"
fi

# --- POST compile handles SQL*Plus directives and exec conversion ---------
# prompt/set must be ignored, exec must become one anonymous PL/SQL block;
# covers split_into_statements end-to-end over REST.

cat > "${WORK_DIR}/payload_sqlplus.sql" <<'SQL'
prompt dbflow smoke test
set define off
exec dbms_output.put_line('dbflow smoke test')
SQL
call_endpoint "${TEST_COMPILE_MAX_TIME}" "compile" \
  --header "Content-Type: application/sql" \
  --header "file-name: dbflow_sqlplus_test.sql" \
  --data-binary @"${WORK_DIR}/payload_sqlplus.sql"

if [[ "$(body_json '.success')" == "true" ]] \
   && [[ "$(body_json '.info.total_statements')" == "1" ]] \
   && [[ "$(body_json '.info.executed_count')" == "1" ]]; then
  t_ok "POST compile ignores SQL*Plus directives and converts exec to one statement"
else
  t_fail "POST compile ignores SQL*Plus directives and converts exec to one statement" \
    "expected total_statements:1 executed_count:1, HTTP ${RESP_STATUS}: $(body_excerpt)"
fi

# --- POST compile error contract -------------------------------------------
# dbFlux parses this JSON shape (success, code, log_results[].status/
# statement_preview); a failing block must not leave any object behind.

cat > "${WORK_DIR}/payload_error.sql" <<'SQL'
begin
  raise_application_error(-20099, 'dbflow smoke test error');
end;
/
SQL
call_endpoint "${TEST_COMPILE_MAX_TIME}" "compile" \
  --header "Content-Type: application/sql" \
  --header "file-name: dbflow_error_test.sql" \
  --data-binary @"${WORK_DIR}/payload_error.sql"

if [[ "$(body_json '.success')" == "false" ]] \
   && [[ "$(body_json '.code')" == "-20099" ]] \
   && [[ "$(body_json '[.log_results[]? | select(.status == "ERROR")] | length')" -ge 1 ]]; then
  t_ok "POST compile reports a failing statement (success:false, code, log_results ERROR entry)"
else
  t_fail "POST compile reports a failing statement" \
    "expected success:false code:-20099 with an ERROR log_results entry, HTTP ${RESP_STATUS}: $(body_excerpt)"
fi

# --- POST compile with an empty body ---------------------------------------

call_endpoint "${TEST_COMPILE_MAX_TIME}" "compile" \
  --header "Content-Type: application/sql" \
  --header "file-name: dbflow_empty_test.sql" \
  --data-binary ""

if [[ "$(body_json '.success')" == "true" ]] \
   && [[ "$(body_json '.info.total_statements')" == "0" ]]; then
  t_ok "POST compile with an empty body succeeds with 0 statements"
else
  t_fail "POST compile with an empty body succeeds with 0 statements" "HTTP ${RESP_STATUS}: $(body_excerpt)"
fi

# --- POST compileschema --------------------------------------------------

call_endpoint "${TEST_COMPILE_MAX_TIME}" "compileschema" \
  --header "compile-all: false" \
  --header "db-folder: db"

if [[ "$(body_json '.success')" == "true" ]] && [[ "$(body_json '.errors | type')" == "array" ]]; then
  t_ok "POST compileschema returns success and an errors array ($(body_json '.errors | length') entries)"
else
  t_fail "POST compileschema returns success and an errors array" "HTTP ${RESP_STATUS}: $(body_excerpt)"
fi

# --- POST compileschema with PL/SQL warnings enabled ----------------------
# exercises the execute-immediate branch for enable-warnings, which is
# otherwise only hit in production deployments

call_endpoint "${TEST_COMPILE_MAX_TIME}" "compileschema" \
  --header "compile-all: false" \
  --header "db-folder: db" \
  --header "enable-warnings: alter session set plsql_warnings='ENABLE:ALL'" \
  --header "warning-string: WARNING" \
  --header "warning-excludes: 5050,6009"

if [[ "$(body_json '.success')" == "true" ]] && [[ "$(body_json '.errors | type')" == "array" ]]; then
  t_ok "POST compileschema with enable-warnings/warning-string returns success"
else
  t_fail "POST compileschema with enable-warnings/warning-string returns success" "HTTP ${RESP_STATUS}: $(body_excerpt)"
fi

# --- POST impapp (non-destructive: unknown workspace) ---------------------
# fails inside apex_util.set_workspace before anything is installed; still
# proves handler wiring, hyphen header bindings and the JSON error contract

printf -- '-- dbflow smoke test payload, never installed\n' > "${WORK_DIR}/impapp_dummy.sql"
call_endpoint "${TEST_COMPILE_MAX_TIME}" "impapp" \
  --header "Content-Type: application/sql" \
  --header "target-workspace: __DBFLOW_SMOKE_TEST__" \
  --header "target-schema: __DBFLOW_SMOKE_TEST__" \
  --header "target-app-id: 999999999" \
  --data-binary @"${WORK_DIR}/impapp_dummy.sql"
expect_json_error "POST impapp with unknown workspace returns a JSON error (nothing installed)"

# --- POST expapp -------------------------------------------------------

if [[ -n "${TEST_APP_ID:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "expapp" \
    --header "app-id: ${TEST_APP_ID}" \
    --header "export-options: -skipExportDate"
  expect_zip "POST expapp exports application ${TEST_APP_ID} as ZIP"
else
  t_skip "POST expapp exports an application as ZIP" "set TEST_APP_ID"
fi

call_endpoint "${TEST_EXPORT_MAX_TIME}" "expapp" \
  --header "app-id: 999999999" \
  --header "export-options:"
expect_json_error "POST expapp with unknown app id returns a JSON error"

# --- POST expplugin -----------------------------------------------------------

if [[ -n "${TEST_APP_ID:-}" ]] && [[ -n "${TEST_PLUGIN_NAME:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "expplugin" \
    --header "app-id: ${TEST_APP_ID}" \
    --header "plugin-name: ${TEST_PLUGIN_NAME}"
  expect_zip "POST expplugin exports plugin ${TEST_PLUGIN_NAME} as ZIP"
else
  t_skip "POST expplugin exports a plugin as ZIP" "set TEST_APP_ID and TEST_PLUGIN_NAME"
fi

if [[ -n "${TEST_APP_ID:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "expplugin" \
    --header "app-id: ${TEST_APP_ID}" \
    --header "plugin-name: __dbflow_smoke_test__"
  expect_json_error "POST expplugin with unknown plugin returns a JSON error"
else
  t_skip "POST expplugin with unknown plugin returns a JSON error" "set TEST_APP_ID"
fi

# --- POST expstatics ----------------------------------------------------------

if [[ -n "${TEST_APP_ID:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "expstatics" \
    --header "app-id: ${TEST_APP_ID}"
  if [[ "${RESP_CONTENT_TYPE}" == application/zip* ]]; then
    expect_zip "POST expstatics exports static files of app ${TEST_APP_ID} as ZIP"
  elif body_json '.message' | grep -q "Nothing found"; then
    t_ok "POST expstatics reports 'Nothing found to export' for app ${TEST_APP_ID} (no static files)"
  else
    t_fail "POST expstatics exports static files or reports 'Nothing found'" "HTTP ${RESP_STATUS}: $(body_excerpt)"
  fi
else
  t_skip "POST expstatics exports static files as ZIP" "set TEST_APP_ID"
fi

call_endpoint "${TEST_EXPORT_MAX_TIME}" "expstatics" \
  --header "app-id: 999999999"
expect_json_error "POST expstatics with unknown app id returns a JSON error"

# --- POST exppluginfiles ------------------------------------------------------

if [[ -n "${TEST_APP_ID:-}" ]] && [[ -n "${TEST_PLUGIN_NAME:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "exppluginfiles" \
    --header "app-id: ${TEST_APP_ID}" \
    --header "plugin-name: ${TEST_PLUGIN_NAME}"
  if [[ "${RESP_CONTENT_TYPE}" == application/zip* ]]; then
    expect_zip "POST exppluginfiles exports plugin files of ${TEST_PLUGIN_NAME} as ZIP"
  elif body_json '.message' | grep -q "Nothing found"; then
    t_ok "POST exppluginfiles reports 'Nothing found to export' for ${TEST_PLUGIN_NAME} (no files)"
  else
    t_fail "POST exppluginfiles exports plugin files or reports 'Nothing found'" "HTTP ${RESP_STATUS}: $(body_excerpt)"
  fi
else
  t_skip "POST exppluginfiles exports plugin files as ZIP" "set TEST_APP_ID and TEST_PLUGIN_NAME"
fi

# --- POST rmstaticfile (non-destructive: file does not exist) ------------------

if [[ -n "${TEST_APP_ID:-}" ]]; then
  call_endpoint "${TEST_COMPILE_MAX_TIME}" "rmstaticfile" \
    --header "app-id: ${TEST_APP_ID}" \
    --header "file-name: __dbflow_smoke_test__.js" \
    --header "file-ext: js"
  if [[ "$(body_json '.success')" == "true" ]] && [[ "$(body_json '.found')" == "false" ]]; then
    t_ok "POST rmstaticfile handles a non-existing file (success:true, found:false)"
  else
    t_fail "POST rmstaticfile handles a non-existing file" "HTTP ${RESP_STATUS}: $(body_excerpt)"
  fi
else
  t_skip "POST rmstaticfile handles a non-existing file" "set TEST_APP_ID"
fi

# --- POST expschema (targeted, fast) -------------------------------------------

# fixture-free: the rest_compile package itself is guaranteed to be installed
call_endpoint "${TEST_EXPORT_MAX_TIME}" "expschema" \
  --header "folder: sources/packages" \
  --header "file-name: rest_compile.pkb" \
  --header "grants-with-object: false"
if expect_zip "POST expschema exports the rest_compile package DDL as ZIP"; then
  if unzip -l "${RESP_BODY_FILE}" 2>/dev/null | grep -q "sources/packages/rest_compile.pkb"; then
    t_ok "expschema ZIP contains sources/packages/rest_compile.pkb"
  else
    t_fail "expschema ZIP contains sources/packages/rest_compile.pkb" \
      "$(unzip -l "${RESP_BODY_FILE}" 2>/dev/null | head -10)"
  fi
fi

call_endpoint "${TEST_EXPORT_MAX_TIME}" "expschema" \
  --header "folder: tables" \
  --header "file-name: __dbflow_smoke_test__.sql" \
  --header "grants-with-object: false"
expect_json_error "POST expschema with unknown object returns a JSON error (Nothing found)"

if [[ -n "${TEST_TABLE_NAME:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "expschema" \
    --header "folder: tables" \
    --header "file-name: ${TEST_TABLE_NAME}" \
    --header "grants-with-object: false"
  if expect_zip "POST expschema exports DDL of table ${TEST_TABLE_NAME} as ZIP"; then
    if ! unzip -l "${RESP_BODY_FILE}" 2>/dev/null | grep -qi "tables/"; then
      t_fail "expschema ZIP contains a tables/ entry" "$(unzip -l "${RESP_BODY_FILE}" 2>/dev/null | head -10)"
    else
      t_ok "expschema ZIP contains a tables/ entry"
    fi
  fi
else
  t_skip "POST expschema exports object DDL as ZIP" "set TEST_TABLE_NAME"
fi

# --- POST exprest (TEST_MODULE_NAME defaults to com.dbflow.deploy) -------------

if [[ -n "${TEST_MODULE_NAME:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "exprest" \
    --header "module-name: ${TEST_MODULE_NAME}"
  if expect_zip "POST exprest exports module ${TEST_MODULE_NAME} as ZIP"; then
    if unzip -l "${RESP_BODY_FILE}" 2>/dev/null | grep -q "\.module\.sql"; then
      t_ok "exprest ZIP contains a .module.sql file"
    else
      t_fail "exprest ZIP contains a .module.sql file" "$(unzip -l "${RESP_BODY_FILE}" 2>/dev/null | head -10)"
    fi
  fi
else
  t_skip "POST exprest exports an ORDS module as ZIP" "set TEST_MODULE_NAME"
fi

call_endpoint "${TEST_EXPORT_MAX_TIME}" "exprest" \
  --header "module-name: __dbflow_smoke_test__"
expect_json_error "POST exprest with unknown module returns a JSON error"

# --- summary -----------------------------------------------------------------

echo
T_SUITE_TOTAL_MS=$(( $(now_ms) - T_SUITE_START_MS ))
printf "# %d tests, %s%d failed%s, %d skipped in %d.%ds\n" \
  "${TESTS_RUN}" \
  "$([[ ${TESTS_FAILED} -gt 0 ]] && printf '%s' "${C_RED}" || printf '%s' "${C_GREEN}")" \
  "${TESTS_FAILED}" "${C_OFF}" \
  "${TESTS_SKIPPED}" \
  "$(( T_SUITE_TOTAL_MS / 1000 ))" "$(( (T_SUITE_TOTAL_MS % 1000) / 100 ))"

exit "${TESTS_FAILED}"
