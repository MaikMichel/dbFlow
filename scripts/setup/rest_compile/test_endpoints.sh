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
#   TEST_MODULE_NAME   existing ORDS module name
#   TEST_TABLE_NAME    existing table name for a targeted DDL export
#
# Usage:
#   ./test_endpoints.sh                       (auto-detects apply.env)
#   source apply.env && ./test_endpoints.sh   (explicit)
#
# All tests are non-destructive: nothing is imported, removed or changed
# except a "begin null; end;" payload executed by POST /compile.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- auto-source apply.env if REST_SQL_URL is not already in the environment --
if [[ -z "${REST_SQL_URL:-}" ]]; then
  for _candidate in \
      "./apply.env" \
      "${SCRIPT_DIR}/../../../apply.env" \
      "${SCRIPT_DIR}/../../../../apply.env"; do
    if [[ -f "${_candidate}" ]]; then
      # shellcheck source=/dev/null
      source "${_candidate}"
      break
    fi
  done
  unset _candidate
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

function t_ok() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf "%sok%s %d - %s\n" "${C_GREEN}" "${C_OFF}" "${TESTS_RUN}" "$1"
}

function t_fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "%snot ok%s %d - %s\n" "${C_RED}" "${C_OFF}" "${TESTS_RUN}" "$1"
  if [[ -n "${2:-}" ]]; then
    printf "       %s\n" "$2"
  fi
}

function t_skip() {
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  printf "%sskip%s - %s (%s)\n" "${C_YELLOW}" "${C_OFF}" "$1" "$2"
}

# --- request helpers -------------------------------------------------------

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

  RESP_STATUS=$(curl -sS \
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

# --- 1: OAuth token --------------------------------------------------------

echo "# rest_compile endpoint smoke tests against ${REST_SQL_URL}"
echo

if [[ "${REST_USES_OAUTH}" == "TRUE" ]]; then
  token_response=$(curl -sS \
    --connect-timeout "${TEST_CONNECT_TIMEOUT}" \
    --max-time "${TEST_TOKEN_MAX_TIME}" \
    --header "Authorization: Basic ${REST_OAUTH_BASIC_B64}" \
    --data "grant_type=client_credentials" \
    "${REST_OAUTH_TOKEN_URL}")

  ACCESS_TOKEN=$(jq -r '.access_token // empty' <<< "${token_response}" 2>/dev/null)
  if [[ -n "${ACCESS_TOKEN}" ]]; then
    t_ok "OAuth token endpoint returns access_token"
  else
    t_fail "OAuth token endpoint returns access_token" "${token_response}"
    echo
    echo "FATAL: cannot continue without an access token" >&2
    exit 1
  fi
else
  t_skip "OAuth token endpoint returns access_token" "REST_USES_OAUTH=FALSE"
fi

# --- 2: protection check ---------------------------------------------------

status_no_auth=$(curl -sS -o /dev/null -w '%{http_code}' \
  --connect-timeout "${TEST_CONNECT_TIMEOUT}" \
  --max-time "${TEST_TOKEN_MAX_TIME}" \
  "${REST_SQL_URL}/compile")

if [[ "${status_no_auth}" == "401" ]] || [[ "${status_no_auth}" == "403" ]]; then
  t_ok "GET compile without any auth is rejected (HTTP ${status_no_auth})"
else
  t_fail "GET compile without any auth is rejected" "got HTTP ${status_no_auth} - endpoint may be unprotected!"
fi

# --- 3: version / api_level contract ---------------------------------------

info_auth_args=()
if [[ "${REST_USES_OAUTH}" == "TRUE" ]] && [[ -n "${ACCESS_TOKEN:-}" ]]; then
  info_auth_args+=( --header "Authorization: Bearer ${ACCESS_TOKEN}" )
fi
if [[ -n "${REST_CLIENT_TOKEN:-}" ]]; then
  info_auth_args+=( --header "x-dbflow-token: ${REST_CLIENT_TOKEN}" )
fi

info_response=$(curl -sS \
  --connect-timeout "${TEST_CONNECT_TIMEOUT}" \
  --max-time "${TEST_TOKEN_MAX_TIME}" \
  "${info_auth_args[@]}" \
  "${REST_SQL_URL}/compile")

info_success=$(jq -r '.success // false' <<< "${info_response}" 2>/dev/null)
info_version=$(jq -r '.version // empty' <<< "${info_response}" 2>/dev/null)
info_api_level=$(jq -r '.api_level // 0' <<< "${info_response}" 2>/dev/null)

if [[ "${info_success}" == "true" ]] && [[ "${info_version}" =~ ^1\. ]] && [[ "${info_api_level}" -ge 2 ]]; then
  t_ok "GET compile reports version ${info_version}, api_level ${info_api_level}"
else
  t_fail "GET compile reports version and api_level >= 2" "${info_response}"
  echo
  echo "FATAL: server reports api_level ${info_api_level} - the installed rest_compile" >&2
  echo "       package is older than 1.2.0; re-run install.sql and try again" >&2
  exit 1
fi

# --- 4: POST compile with a plain payload ----------------------------------

printf 'begin\n  null;\nend;\n/\n' > "${WORK_DIR}/payload.sql"
call_endpoint "${TEST_COMPILE_MAX_TIME}" "compile" \
  --header "Content-Type: application/sql" \
  --header "file_name: dbflow_smoke_test.sql" \
  --data-binary @"${WORK_DIR}/payload.sql"

if [[ "$(body_json '.success')" == "true" ]]; then
  t_ok "POST compile executes a plain 'begin null; end;' payload"
else
  t_fail "POST compile executes a plain 'begin null; end;' payload" "HTTP ${RESP_STATUS}: $(body_excerpt)"
fi

# --- 5: POST compileschema --------------------------------------------------

call_endpoint "${TEST_COMPILE_MAX_TIME}" "compileschema" \
  --header "compile_all: false" \
  --header "db_folder: db"

if [[ "$(body_json '.success')" == "true" ]] && [[ "$(body_json '.errors | type')" == "array" ]]; then
  t_ok "POST compileschema returns success and an errors array ($(body_json '.errors | length') entries)"
else
  t_fail "POST compileschema returns success and an errors array" "HTTP ${RESP_STATUS}: $(body_excerpt)"
fi

# --- 6/7: POST expapp -------------------------------------------------------

if [[ -n "${TEST_APP_ID:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "expapp" \
    --header "app_id: ${TEST_APP_ID}" \
    --header "export_options: -skipExportDate"
  expect_zip "POST expapp exports application ${TEST_APP_ID} as ZIP"
else
  t_skip "POST expapp exports an application as ZIP" "set TEST_APP_ID"
fi

call_endpoint "${TEST_EXPORT_MAX_TIME}" "expapp" \
  --header "app_id: 999999999" \
  --header "export_options:"
expect_json_error "POST expapp with unknown app id returns a JSON error"

# --- 8/9: POST expplugin ----------------------------------------------------

if [[ -n "${TEST_APP_ID:-}" ]] && [[ -n "${TEST_PLUGIN_NAME:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "expplugin" \
    --header "app_id: ${TEST_APP_ID}" \
    --header "plugin_name: ${TEST_PLUGIN_NAME}"
  expect_zip "POST expplugin exports plugin ${TEST_PLUGIN_NAME} as ZIP"
else
  t_skip "POST expplugin exports a plugin as ZIP" "set TEST_APP_ID and TEST_PLUGIN_NAME"
fi

if [[ -n "${TEST_APP_ID:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "expplugin" \
    --header "app_id: ${TEST_APP_ID}" \
    --header "plugin_name: __dbflow_smoke_test__"
  expect_json_error "POST expplugin with unknown plugin returns a JSON error"
else
  t_skip "POST expplugin with unknown plugin returns a JSON error" "set TEST_APP_ID"
fi

# --- 10: POST expstatics ----------------------------------------------------

if [[ -n "${TEST_APP_ID:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "expstatics" \
    --header "app_id: ${TEST_APP_ID}"
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

# --- 11: POST exppluginfiles ------------------------------------------------

if [[ -n "${TEST_APP_ID:-}" ]] && [[ -n "${TEST_PLUGIN_NAME:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "exppluginfiles" \
    --header "app_id: ${TEST_APP_ID}" \
    --header "plugin_name: ${TEST_PLUGIN_NAME}"
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

# --- 12: POST rmstaticfile (non-destructive: file does not exist) -----------

if [[ -n "${TEST_APP_ID:-}" ]]; then
  call_endpoint "${TEST_COMPILE_MAX_TIME}" "rmstaticfile" \
    --header "app_id: ${TEST_APP_ID}" \
    --header "file_name: __dbflow_smoke_test__.js" \
    --header "file_ext: js"
  if [[ "$(body_json '.success')" == "true" ]] && [[ "$(body_json '.found')" == "false" ]]; then
    t_ok "POST rmstaticfile handles a non-existing file (success:true, found:false)"
  else
    t_fail "POST rmstaticfile handles a non-existing file" "HTTP ${RESP_STATUS}: $(body_excerpt)"
  fi
else
  t_skip "POST rmstaticfile handles a non-existing file" "set TEST_APP_ID"
fi

# --- 13: POST expschema (targeted, fast) ------------------------------------

if [[ -n "${TEST_TABLE_NAME:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "expschema" \
    --header "folder: tables" \
    --header "file_name: ${TEST_TABLE_NAME}" \
    --header "grants_with_object: false"
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

# --- 14/15: POST exprest ----------------------------------------------------

if [[ -n "${TEST_MODULE_NAME:-}" ]]; then
  call_endpoint "${TEST_EXPORT_MAX_TIME}" "exprest" \
    --header "module_name: ${TEST_MODULE_NAME}"
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
  --header "module_name: __dbflow_smoke_test__"
expect_json_error "POST exprest with unknown module returns a JSON error"

# --- summary -----------------------------------------------------------------

echo
printf "# %d tests, %s%d failed%s, %d skipped\n" \
  "${TESTS_RUN}" \
  "$([[ ${TESTS_FAILED} -gt 0 ]] && printf '%s' "${C_RED}" || printf '%s' "${C_GREEN}")" \
  "${TESTS_FAILED}" "${C_OFF}" \
  "${TESTS_SKIPPED}"

exit "${TESTS_FAILED}"
