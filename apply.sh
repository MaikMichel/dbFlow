#!/usr/bin/env bash
#echo "Your script args ($#) are: $@"

function usage() {
  echo -e "${BWHITE}.dbFlow/apply.sh${NC} - applies the given build to target database from"
  echo -e "                   depot path, defined in environment. "
  echo ""
  echo -e "${BWHITE}Usage:${NC}"
  echo -e "  ${0} --init --version <label>"
  echo -e "  ${0} --patch --version <label> [--noextract] [--redolog <old-logfile>]"
  echo
  echo -e "${BWHITE}Options:${NC}"
  echo -e "  -h | --help             - Show this screen"
  echo -e ""
  echo -e "  -i | --init             - Flag to install a full installable artifact "
  echo -e "                            this will delete all objects in target schemas upon install"
  echo -e "  -p | --patch            - Flag to install an update/patch as artifact "
  echo -e "                            This will apply on top of the target schemas and consists"
  echo -e "                            of the difference defined during build"
  echo -e "  -v | --version <label>  - Required label of version this artifact represents"
  echo -e "  -n | --noextract        - Optional do not move and extract artifact from depot "
  echo -e "                            Can be used to extract files manually or use a already extracted build"
  echo -e "  -r | --redolog          - Optional to redo an installation and skip installation-step already run"
  echo -e "  -s | --stepwise         - Runs the installation interactively step by step"
  echo ""
 	echo -e "${BWHITE}Examples:${NC}"
  echo -e "  ${0} --init --version 1.0.0"
  echo -e "  ${0} --patch --version 1.1.0"
  echo -e "  ${0} --patch --version 1.1.0 --noextract --redolog ../depot/master/old_logfile.log"
  echo

  exit $1
}

# set project-settings from build.env if exists
if [[ -e ./build.env ]]; then
  source ./build.env
fi

# get required functions and vars
source ./.dbFlow/lib.sh

# set target-env settings from file if exists
if [[ -e ./apply.env ]]; then
  source ./apply.env

  validate_passes
fi


# get unavalable text
if [[ -e ./apex/maintence.html ]]; then
  maintence=`cat ./apex/maintence.html`
else
  maintence=`cat .dbFlow/maintence.html`
fi
maintence="<span />${maintence}"

# choose CLI to call
SQLCLI=${SQLCLI:-sqlplus}
CONN_MODE=${CONN_MODE:-SQLNET}
REST_ACCESS_TOKEN=""
REST_ACCESS_TOKEN_EXPIRES_AT=0
REST_TOKEN_EXPIRY_SAFETY_SECONDS=30
REST_USES_OAUTH="${REST_USES_OAUTH:-TRUE}"

basepath=$(pwd)

# get branch name
{ #try
  this_branch=$(git branch --show-current)
} || { # catch
  this_branch="develop"
}

#
AT_LEAST_ON_INSTALLFILE_STARTED="NO"

# initinlize env_vars array
env_vars=()

runfile=""
debug="n"
help="h"
init="n"
patch="n"
version="-"
noextract="n"
redolog=""

function print_rest_response_as_problem_lines() {
  local json_response="$1"
  local default_fileinfo="${2}:1:1"

  local color_off=""
  local color_orangeb=""
  local color_orange=""
  local color_redb=""
  local color_red=""
  local color_dgray=""

  # if [[ "${DBFLOW_COLOR_ON}" == "true" ]]; then
    color_off="${ESC}${BSE_RESET}"
    color_orangeb="${ESC}${BSE_ORANGEBGR}"
    color_orange="${ESC}${BSE_ORANGE}"
    color_redb="${ESC}${BSE_REDBGR}"
    color_red="${ESC}${BSE_RED}"
    color_dgray="${ESC}${BSE_DGRAY}"
  # fi

  function print_problem_line() {
    local severity="$1"
    local code="$2"
    local fileinfo="$3"
    local message="$4"
    local sev_bg="${color_redb}"
    local sev_fg="${color_red}"
    local msg_fg="${color_red}"

    if [[ "${severity}" == "WARNING" ]]; then
      sev_bg="${color_orangeb}"
      sev_fg="${color_orange}"
      msg_fg="${color_orange}"
    fi

    printf "%b%s%b %b%s%b %b%s%b\n%b%s%b\n" \
      "${sev_bg}" "${severity}" "${color_off}" \
      "${sev_fg}" "${code}" "${color_off}" \
      "${color_dgray}" "${fileinfo}" "${color_off}" \
      "${msg_fg}" "${message}" "${color_off}"
  }

  # Prefer jq for robust JSON parsing. Fallback prints raw response.
  if ! command -v jq >/dev/null 2>&1; then
    [[ -z "${json_response}" ]] || echo "${json_response}"
    return 0
  fi

  # Return silently for successful JSON response
  if jq -e '(.success // false) == true' >/dev/null 2>&1 <<< "${json_response}"; then
    return 0
  fi

  # 1) Primary path: parse detailed user_errors into matcher compatible lines
  local parsed_lines
  parsed_lines=$(jq -r --arg default_file "${default_fileinfo}" '
      [ .log_results[]?.user_errors[]? |
        [
          ((.attribute // "ERROR") | ascii_upcase),
          (.typeid // "ORA-24344"),
          (.fileinfo // $default_file),
          ((.errtext // "Compilation error") | gsub("[\\r\\n]+"; " "))
        ]
      ]
      | .[]
      | @tsv
    ' <<< "${json_response}" 2>/dev/null)

  if [[ $? -ne 0 ]]; then
    # Fallback: at least emit raw response so user sees compile failure.
    [[ -z "${json_response}" ]] || echo "${json_response}"
    return 0
  fi

  if [[ -n "${parsed_lines}" ]]; then
    REST_ERRORS_FOUND=1
    while IFS=$'\t' read -r attribute code fileinfo errtext; do
      [[ -n "${attribute}" ]] || continue
      print_problem_line "${attribute}" "${code}" "${fileinfo}" "${errtext}"
    done <<< "${parsed_lines}"
    return 0
  fi

  # 2) Secondary path: fallback from top-level/log_results message
  local fallback_code
  local fallback_message
  fallback_code=$(jq -r 'if .code != null then (.code|tostring) else "ORA-ERROR" end' <<< "${json_response}" 2>/dev/null)
  fallback_message=$(jq -r 'first([.log_results[]?.error_message?, .cause?, .message?] | map(select(. != null and . != ""))[]) // "Compilation error"' <<< "${json_response}" 2>/dev/null)
  REST_ERRORS_FOUND=1
  print_problem_line "ERROR" "${fallback_code}" "${default_fileinfo}" "${fallback_message}"
}

function ensure_rest_access_token() {
  local now
  now=$(date +%s)

  if [[ -n "${REST_ACCESS_TOKEN:-}" ]] && [[ ${REST_ACCESS_TOKEN_EXPIRES_AT:-0} -gt $((now + REST_TOKEN_EXPIRY_SAFETY_SECONDS)) ]]; then
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    timelog "REST OAuth requires jq to parse token response" "${failure}"
    return 1
  fi

  local token_response
  token_response=$(rest_curl -sS \
    --header "Authorization: Basic ${REST_OAUTH_BASIC_B64}" \
    --data "grant_type=client_credentials" \
    "${REST_OAUTH_TOKEN_URL}")
  local token_rc=$?

  if [[ ${token_rc} -ne 0 ]]; then
    [[ -z "${token_response}" ]] || echo_error "${token_response}"
    timelog "Failed to get OAuth access token from ${REST_OAUTH_TOKEN_URL}" "${failure}"
    return ${token_rc}
  fi

  local access_token
  local expires_in
  access_token=$(jq -r '.access_token // empty' <<< "${token_response}" 2>/dev/null)
  expires_in=$(jq -r '.expires_in // 3600' <<< "${token_response}" 2>/dev/null)

  if [[ -z "${access_token}" ]]; then
    [[ -z "${token_response}" ]] || echo_error "${token_response}"
    timelog "OAuth token response did not contain access_token" "${failure}"
    return 1
  fi

  if [[ ! "${expires_in}" =~ ^[0-9]+$ ]]; then
    expires_in=3600
  fi

  REST_ACCESS_TOKEN="${access_token}"
  REST_ACCESS_TOKEN_EXPIRES_AT=$((now + expires_in))

  return 0
}

function run_sql_file_rest() {
  local targetschema=$1
  local sql_file=$2
  local use_embeded=$3

  if [[ ! -f "${sql_file}" ]]; then
    timelog "REST execution failed: SQL file ${sql_file} does not exist" "${failure}"
    return 1
  fi

  abs_file="$(realpath "$sql_file")"
  rel_file="${abs_file#"$basepath"/}"    

  if [[ ${use_embeded} == "true" ]]; then
    timelog "Running SQL file ${rel_file} via REST with embeded file calls"

    local line
    local include_file
    local include_path
    local include_has_embedded
    local include_base
    local counter=0
    include_base=$(dirname "${sql_file}")

    while IFS= read -r line; do
      if [[ "${line}" =~ ^[[:space:]]*@@([^[:space:];]+) ]]; then
        include_file="${BASH_REMATCH[1]}"
        include_path="${include_base}/${include_file}"

        if [[ -f "${include_path}" ]]; then
          counter=$((counter+1))
          if grep -Eq '^[[:space:]]*@@([^[:space:];]+)' "${include_path}"; then
            include_has_embedded=true
          else
            include_has_embedded=false
          fi

          run_sql_file_rest "${targetschema}" "${include_path}" "${include_has_embedded}"
          if [[ $? -ne 0 ]]; then
            return 1
          fi
          
        else
          timelog "REST execution failed: included SQL file ${include_path} does not exist" "${failure}"
          return 1
        fi
      fi
    done < "${sql_file}"

    return 0
  fi
  
  timelog "Running SQL file ${rel_file} via REST"

  if ! command -v zip >/dev/null 2>&1; then
    timelog "REST execution failed: zip command is required for REST compile payloads" "${failure}"
    return 1
  fi

  local payload_dir
  local payload_file
  payload_dir="$(mktemp -d "${TMPDIR:-/tmp}/dbflow-rest-compile.XXXXXX")"
  payload_file="${payload_dir}/payload.zip"

  mkdir -p "${payload_dir}/$(dirname "${rel_file}")"
  cp "${sql_file}" "${payload_dir}/${rel_file}"

  (
    cd "${payload_dir}" && zip -q "${payload_file}" "${rel_file}"
  )
  local zip_rc=$?

  if [[ ${zip_rc} -ne 0 ]]; then
    rm -rf "${payload_dir}"
    timelog "REST execution failed: could not create ZIP payload for ${rel_file}" "${failure}"
    return ${zip_rc}
  fi

  local -a curl_args
  curl_args=(
    -sS
    -X POST
    --header "Content-Type:application/zip"
    --header "file_name:${rel_file}"
  )

  local header_var
  while IFS= read -r header_var; do
    local header_value="${!header_var}"
    if [[ -n "${header_value}" ]]; then
      curl_args+=( --header "${header_value}" )
    fi
  done < <(compgen -A variable REST_HEADER_ | sort)

  if [[ "${REST_USES_OAUTH}" == "TRUE" ]]; then
    ensure_rest_access_token
    if [[ $? -ne 0 ]]; then
      rm -rf "${payload_dir}"
      return 1
    fi
    curl_args+=( --header "Authorization: Bearer ${REST_ACCESS_TOKEN}" )
  fi

  if [[ -n "${REST_CLIENT_TOKEN:-}" ]]; then
    curl_args+=( --header "x-dbflow-token: ${REST_CLIENT_TOKEN}" )
  fi

  local curl_response
  curl_response=$(rest_curl "${curl_args[@]}" --data-binary @"${payload_file}" "${REST_SQL_URL}/compile")
  local curl_rc=$?

  rm -rf "${payload_dir}"

  if [[ ${curl_rc} -ne 0 ]]; then
    [[ -z "${curl_response}" ]] || echo "${curl_response}"
    return ${curl_rc}
  fi

  # Print response only when it is not JSON or JSON.success != true
  if [[ "${curl_response}" =~ ^[[:space:]]*\{ ]]; then
    local compact_response
    compact_response=$(echo "${curl_response}" | tr -d '\r\n')
    if [[ ! "${compact_response}" =~ \"success\"[[:space:]]*:[[:space:]]*true ]]; then
      print_rest_response_as_problem_lines "${curl_response}" "${rel_file}"
    fi
  else
    [[ -z "${curl_response}" ]] || echo "${curl_response}"
  fi

  return 0
}

function run_app_import_rest() {
  local targetschema=$1
  local targetworkspace=$2
  local targetappid=$3
  local orginalappid=$4


  local expanded_tmp_sql
  expanded_tmp_sql="$(mktemp -u "${log_file}.XXXXXX").imp.sql"

  # Build expanded content from referenced @@ files only.
  # Non-include lines in ${tmp_sql} are ignored by design for app imports.
  # Include paths are resolved relative to the current app folder (PWD)
  # and recursively relative to each included file's folder.
  local expand_failed="false"
  local includes_found="false"
    _dbflow_expand_sql_file() {
      local source_file=$1
      local source_base=$2
      local target_file=$3

      local line
      local include_file
      local include_path

      while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]*@@([^[:space:];]+) ]]; then
          include_file="${BASH_REMATCH[1]}"

          if [[ "${include_file}" == /* ]]; then
            include_path="${include_file}"
          else
            include_path="${source_base}/${include_file}"
          fi

          if [[ -f "${include_path}" ]]; then
            _dbflow_expand_sql_file "${include_path}" "$(dirname "${include_path}")" "${target_file}"
            if [[ $? -ne 0 ]]; then
              return 1
            fi
          else
            timelog "REST execution failed: included SQL file ${include_path} does not exist" "${failure}"
            return 1
          fi
        else
          printf "%s\n" "${line}" >> "${target_file}"
        fi
      done < "${source_file}"

      return 0
    }

    : > "${expanded_tmp_sql}"

    while IFS= read -r line; do
      if [[ "${line}" =~ ^[[:space:]]*@@([^[:space:];]+) ]]; then
        includes_found="true"
        include_file="${BASH_REMATCH[1]}"

        if [[ "${include_file}" == /* ]]; then
          include_path="${include_file}"
        else
          include_path="$(pwd)/${include_file}"
        fi

        if [[ -f "${include_path}" ]]; then
          _dbflow_expand_sql_file "${include_path}" "$(dirname "${include_path}")" "${expanded_tmp_sql}"
          if [[ $? -ne 0 ]]; then
            expand_failed="true"
            break
          fi
        else
          timelog "REST execution failed: included SQL file ${include_path} does not exist" "${failure}"
          expand_failed="true"
          break
        fi
      fi
    done < "install.sql"


  timelog "Running APP Import file ${expanded_tmp_sql} on ${targetschema} via REST"

  local -a curl_args
  curl_args=(
    -sS
    -X POST
    --header "Content-Type:text/plain"
    --header "target_app_id:${targetappid}"
    --header "target_schema:${targetschema}"
    --header "target_workspace:${targetworkspace}"
    --header "original_app_id:${orginalappid}"

  )

  local header_var
  while IFS= read -r header_var; do
    local header_value="${!header_var}"
    if [[ -n "${header_value}" ]]; then
      curl_args+=( --header "${header_value}" )
    fi
  done < <(compgen -A variable REST_HEADER_ | sort)

  if [[ "${REST_USES_OAUTH}" == "TRUE" ]]; then
    ensure_rest_access_token
    if [[ $? -ne 0 ]]; then
      return 1
    fi
    curl_args+=( --header "Authorization: Bearer ${REST_ACCESS_TOKEN}" )
  fi

  if [[ -n "${REST_CLIENT_TOKEN:-}" ]]; then
    curl_args+=( --header "x-dbflow-token: ${REST_CLIENT_TOKEN}" )
  fi

  local curl_response

  curl_response=$(rest_curl "${curl_args[@]}" --data-binary @"${expanded_tmp_sql}" "${REST_SQL_URL}/impapp")
  local curl_rc=$?

  if [[ ${curl_rc} -ne 0 ]]; then
    [[ -z "${curl_response}" ]] || echo_error "${curl_response}"
    return ${curl_rc}
  fi

  # Print response only when it is not JSON or JSON.success != true
  if [[ "${curl_response}" =~ ^[[:space:]]*\{ ]]; then
    local compact_response
    compact_response=$(echo "${curl_response}" | tr -d '\r\n')
    if [[ ! "${compact_response}" =~ \"success\"[[:space:]]*:[[:space:]]*true ]]; then
      echo_warning "${curl_response}"
    fi
  else
    [[ -z "${curl_response}" ]] || echo_warning "${curl_response}"
  fi

  rm -f "${expanded_tmp_sql}"

  return 0
}

function run_sql_file() {
  local targetschema=$1
  local sql_file=$2
  local embeded=$3
  shift 3
  local -a sql_args=( "$@" )

  if [[ "${CONN_MODE}" == "SQLNET" ]]; then
    "$SQLCLI" -S -L "$(get_connect_string "${targetschema}")" @"${sql_file}" "${sql_args[@]}"
    return $?
  fi

  run_sql_file_rest "${targetschema}" "${sql_file}" ${embeded}
}

function run_sql_block() {
  local targetschema=$1
  local sql_block=$2
  local embeded=${3:-false}

  if [[ "${CONN_MODE}" == "SQLNET" ]]; then
    "$SQLCLI" -S -L "$(get_connect_string "${targetschema}")" <<EOF
${sql_block}
EOF
    return $?
  fi

  local tmp_sql
  tmp_sql="$(mktemp -u ${log_file}.XXXXXX).sql"
  timelog "Writing to temp file ${tmp_sql}" ${grayed}
  printf "%s\n" "${sql_block}" > "${tmp_sql}"

  run_sql_file_rest "${REST_APP_SCHEMA}" "${tmp_sql}" ${embeded}
  local rc=$?

  # rm -f "${tmp_sql}"
  return ${rc}
}

function resolve_rest_target_app_id() {
  local source_app_id=$1
  local map_string="${REST_APP_ID_MAP:-}"

  if [[ -z "${source_app_id}" ]]; then
    timelog "REST APP ID resolution failed: source_app_id is empty" "${failure}"
    return 1
  fi

  # If no mapping is provided, use source app id as target app id.
  if [[ -z "${map_string}" ]]; then
    echo "${source_app_id}"
    return 0
  fi

  local pair
  local source_id
  local target_id

  IFS=',' read -ra __rest_map_pairs <<< "${map_string}"
  for pair in "${__rest_map_pairs[@]}"; do
    pair="$(echo "${pair}" | tr -d '[:space:]')"
    [[ -n "${pair}" ]] || continue

    if [[ ! "${pair}" =~ ^[0-9]+:[0-9]+$ ]]; then
      timelog "Invalid REST_APP_ID_MAP entry '${pair}'. Expected format <source>:<target>, e.g. 1111:12120" "${failure}"
      return 1
    fi

    source_id="${pair%%:*}"
    target_id="${pair##*:}"

    if [[ "${source_id}" == "${source_app_id}" ]]; then
      echo "${target_id}"
      return 0
    fi
  done

  timelog "No REST APP ID mapping found for source app ${source_app_id} in REST_APP_ID_MAP" "${failure}"
  return 1
}


function check_vars() {
  # validate parameters
  do_exit="NO"

  if [[ -z ${DEPOT_PATH:-} ]]; then
    echo_error "Depotpath not defined"
    do_exit="YES"
  fi

  if [[ -z ${STAGE:-} ]]; then
    echo_error  "Stage not defined"
    do_exit="YES"
  fi

  if [[ "${CONN_MODE}" != "SQLNET" ]] && [[ "${CONN_MODE}" != "REST" ]]; then
    echo_error "CONN_MODE must be SQLNET or REST"
    do_exit="YES"
  fi

  if [[ "${CONN_MODE}" == "REST" ]] && [[ -z ${REST_SQL_URL:-} ]]; then
    echo_error "REST_SQL_URL not defined (required when CONN_MODE=REST)"
    do_exit="YES"
  fi

  if [[ "${CONN_MODE}" == "REST" ]] && [[ "${REST_USES_OAUTH:-TRUE}" == "TRUE" ]] && [[ -z ${REST_OAUTH_TOKEN_URL:-} ]]; then
    echo_error "REST_OAUTH_TOKEN_URL not defined (required when REST_USES_OAUTH=TRUE)"
    do_exit="YES"
  fi

  if [[ "${CONN_MODE}" == "REST" ]] && [[ "${REST_USES_OAUTH:-TRUE}" == "TRUE" ]] && [[ -z ${REST_OAUTH_BASIC_B64:-} ]]; then
    echo_error "REST_OAUTH_BASIC_B64 not defined (required when REST_USES_OAUTH=TRUE)"
    do_exit="YES"
  fi

  if [[ "${CONN_MODE}" == "SQLNET" ]] && [[ -z ${DB_APP_USER:-} ]]; then
    echo_error "App-User not defined"
    do_exit="YES"
  fi

  if [[ "${CONN_MODE}" == "SQLNET" ]] && [[ -z ${DB_TNS} ]]; then
    echo_error "TNS not defined"
    do_exit="YES"
  fi


  if [[ -d ${DEPOT_PATH}/${STAGE} ]]; then
    install_source_path=${basepath}/${DEPOT_PATH}/${STAGE}
  else
    echo_error "Targetstage ${STAGE} inside ${DEPOT_PATH} is unknown"
    echo_warning "Check your STAGE environment var in apply.env"
    do_exit="YES"
  fi

  if [[ -z ${LOG_PATH:-} ]]; then
    if [[ -f "apply.env" && -z "$(grep 'LOG_PATH=' "apply.env")" ]]; then
      {
        echo ""
        echo "# auto added @${MDATE}"
        echo "# Path to copy logs to after installation"
        echo "LOG_PATH=_logs"
      } >> apply.env

      echo -e "${LWHITE}set LOG_PATH to ${NC}${BWHITE}_logs${NC} ${LWHITE} in your apply.env - please configure as you like with a relative path${NC}"
      LOG_PATH="_logs"
    else
      echo_error "Logpath not defined"
      do_exit="YES"
    fi
  fi




  ####
  if [[ ${do_exit} == "YES" ]]; then
    echo_warning "aborting"
    exit 1;
  fi

  # Defing some vars
  app_install_file=apex_files_${version}.lst
  remove_old_files=remove_files_${version}.lst

  install_target_path=.
  install_source_file=$install_source_path/${mode}_${version}.tar.gz
  install_target_file=$install_target_path/${mode}_${version}.tar.gz

  MDATE=`date "+%Y%m%d%H%M%S"`
  log_file="${MDATE}_dpl_${mode}_${version}.log"

  touch "${log_file}"
  full_log_file="$( cd "$( dirname "${log_file}" )" >/dev/null 2>&1 && pwd )/${log_file}"

  exec 3>&1 4>&2
  exec &> >(tee -a "$log_file")


  # reading defined vars from VAR_LIST
  if [ -n "$VAR_LIST" ]; then
    # set IFS to colon
    IFS=':'

    # lets build an array from that list
    read -ra VAR_ARRAY <<< "$VAR_LIST"

    # reset IFS
    unset IFS

    # build the array to inject in sql hooks
    for var_name in "${VAR_ARRAY[@]}"; do
      env_vars+=( "define $(echo "$var_name" | tr '[:lower:]' '[:upper:]')=\"${!var_name}\" \"UNDEFINED\"" )
    done
  fi
}

function check_params() {
  help_option="NO"
  init_option="NO"
  patch_option="NO"
  version_option="NO"
  version_argument="-"
  noextract_option="NO"
  redolog_option="NO"
  redolog_argument="-"
  stepwise_option="NO"

  while getopts_long 'hipv:nr:s help init patch version: noextract redolog: stepwise' OPTKEY "${@}"; do
      case ${OPTKEY} in
          'h'|'help')
              help_option="YES"
              ;;
          'i'|'init')
              init_option="YES"
              ;;
          'p'|'patch')
              patch_option="YES"
              ;;
          'v'|'version')
              version_option="YES"
              version_argument="${OPTARG}"
              ;;
          'n'|'noextract')
              noextract_option="YES"
              ;;
          'r'|'redolog')
              redolog_option="YES"
              redolog_argument="${OPTARG}"
              ;;
          's'|'stepwise')
              stepwise_option="YES"
              ;;
          '?')
              echo_error "INVALID OPTION -- ${OPTARG}" >&2
              usage 10
              ;;
          ':')
              echo_error "MISSING ARGUMENT for option -- ${OPTARG}" >&2
              usage 11
              ;;
          *)
              echo_error "UNIMPLEMENTED OPTION -- ${OPTKEY}" >&2
              usage 12
              ;;
      esac
  done

  # help first
  if [[ ${help_option} == "YES" ]]; then
    usage 0
  fi

  # Rule 1: init or patch
  if [[ ${init_option} == "NO" ]] && [[ ${patch_option} == "NO" ]]; then
    echo_error "Missing apply mode, init or patch using flags -i or -p"
    usage 2
  fi

  if [[ ${init_option} == "YES" ]] && [[ ${patch_option} == "YES" ]]; then
    echo_error "Build mode can only be init or patch, not both"
    usage 3
  fi

  # Rule 2: we always need a version
  if [[ ${version_option} == "NO" ]] || [[ ${version_argument} == "-" ]]; then
    echo_error "Missing version, use flag --version x.x.x"
    usage 4
  else
    version=${version_argument}
  fi

  # now check dependent params
  if [[ ${init_option} == "YES" ]]; then
    mode="init"
  elif [[ ${patch_option} == "YES" ]]; then
    mode="patch"
  fi

  # now check dependent params
  if [[ ${noextract_option} == "YES" ]]; then
    must_extract="FALSE"
  else
    must_extract="TRUE"
  fi

  if [[ ${redolog_option} == "YES" ]]; then
    oldlogfile=$redolog_argument
  fi
}

function print_info() {
  timelog "Installing    ${BWHITE}${mode} ${version}${NC}"
  timelog "----------------------------------------------------------"
  timelog "Mode:                ${BWHITE}$mode${NC}"
  timelog "Version:             ${BWHITE}${version}${NC}"
  timelog "Log File:            ${BWHITE}${log_file}${NC}"
  timelog "Extract:             ${BWHITE}$must_extract${NC}"
  timelog "Stepwise:            ${BWHITE}${stepwise_option}${NC}"
  if [[ $oldlogfile != "" ]]; then
    timelog "Redolog:             ${BWHITE}$oldlogfile${NC}"
  fi
  timelog "Bash-Version:        ${BWHITE}${BASH_VERSION}${NC}"
  timelog "----------------------------------------------------------"
  timelog "Project:             ${BWHITE}${PROJECT}${NC}"
  if [[ ${PROJECT_MODE} != "FLEX" ]]; then
    timelog "App Schema           ${BWHITE}${APP_SCHEMA}${NC}"
    if [[ ${PROJECT_MODE} != "SINGLE" ]]; then
      timelog "Data Schema:         ${BWHITE}${DATA_SCHEMA}${NC}"
      timelog "Logic Schema:        ${BWHITE}${LOGIC_SCHEMA}${NC}"
    fi
    timelog "Workspace:           ${BWHITE}${WORKSPACE}${NC}"
  fi

  timelog "Schemas:             ${BWHITE}${SCHEMAS[*]}${NC}"
  if [[ -n ${CHANGELOG_SCHEMA} ]]; then
    timelog "----------------------------------------------------------"
    timelog "Changelog Schema:    ${BWHITE}${CHANGELOG_SCHEMA}${NC}"
    timelog "Intent Prefixes:     ${BWHITE}${INTENT_PREFIXES[@]}${NC}"
    timelog "Intent Names:        ${BWHITE}${INTENT_NAMES[@]}${NC}"
    timelog "Intent Else:         ${BWHITE}${INTENT_ELSE}${NC}"
    timelog "Ticket Match:        ${BWHITE}${TICKET_MATCH}${NC}"
    timelog "Ticket URL:          ${BWHITE}${TICKET_URL}${NC}"
  fi

  if [[ -n ${TEAMS_WEBHOOK_URL} ]]; then
    timelog "Teams WebHook:       ${BWHITE}TRUE${NC}"
  fi

  timelog "----------------------------------------------------------"
  timelog "Stage:               ${BWHITE}${STAGE}${NC}"
  timelog "Depot:               ${BWHITE}${DEPOT_PATH}${NC}"
  timelog "Logs :               ${BWHITE}${LOG_PATH}${NC}"
  timelog "Application Offset:  ${BWHITE}${APP_OFFSET}${NC}"
  if [[ "${CONN_MODE}" == "SQLNET" ]]; then
    timelog "Deployment User:     ${BWHITE}${DB_APP_USER}${NC}"
    timelog "DB Connection:       ${BWHITE}${DB_TNS}${NC}"
  fi
  timelog "Connection Mode:     ${BWHITE}${CONN_MODE}${NC}"
  if [[ "${CONN_MODE}" == "REST" ]]; then
    timelog "REST SQL URL:        ${BWHITE}${REST_SQL_URL}${NC}"
    timelog "REST OAuth URL:      ${BWHITE}${REST_OAUTH_TOKEN_URL}${NC}"
    timelog "REST OAuth Basic:    ${BWHITE}TRUE${NC}"
  fi
  timelog "----------------------------------------------------------"
  timelog
}

function extract_patchfile() {
  if [[ ${must_extract} == "TRUE" ]]; then
    # check if patch exists
    if [[ -e "${install_source_file}" ]]; then
      timelog "${install_source_file} exists"

      # copy patch to _installed
      cp "${install_source_file}" "${install_target_path}"/
    else
      if [[ -e "${install_target_file}" ]]; then
        timelog "${install_target_file} already copied"
      else
        timelog "${install_target_file} not found, nothing to install" "${failure}"
        manage_result "failure"
      fi
    fi

    # extract file
    timelog "extracting file ${install_target_file}"
    tar -zxf "${install_target_file}"


    if [[ -e ./build.env ]]; then
      source ./build.env
    fi

    # maybe something changed during the release
    define_folders_and_schemas
  else
    timelog "artifact will not be extracted from depot"
  fi
}

function validate_dbflow_version() {
  if [[ -f "dbFlow_${mode}_${version}.version" ]]; then
    version_apply=$(sed '/^## \[./!d;q' .dbFlow/CHANGELOG.md)
    version_built=$(head -n 1 "dbFlow_${mode}_${version}.version")
    if [[ "${version_apply}" == "${version_built}" ]]; then
      timelog "dbFlow Versions matched"
    else
      timelog "Mismatched Versions build vs apply" "${warning}"
      timelog ":${version_apply}: != :${version_built}:" "${warning}"

      if [[ -z ${DBFLOW_JENKINS:-} ]]; then
        read -r -p "$(echo -e "${BORANGE}Version mismatch${NC} - Do you want to proceed? (y/n)" ) " -n 1
        echo    # (optional) move to a new line
        if [[ ! $REPLY =~ ^[Yy]$ ]]
        then
            [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
        fi
      else
        timelog "Running different dbFlow version but JENKINS is set, so keep on running"
      fi
    fi
  fi
}

function validate_init_mode() {
  # init mode is a kind of dangerous, cause everything is removed from schemas beforehand
  if [[ "${mode}" == "init" ]]; then
    if [[ -z ${DBFLOW_JENKINS:-} ]] && [[ "${version}" != "install" ]]; then
      timelog "You are using init mode. All content will be dropped from schemas included in this artifact" "${warning}"
      timelog "If you are running dbFLow inside CI/CD you can place DBFLOW_JENKINS as environment var with any value" "${warning}"
      read -r -p "$(echo -e "${RED}CI/CD not set${NC} - Do you want to proceed? (y/n)" ) " -n 1
      echo    # (optional) move to a new line
      if [[ ! $REPLY =~ ^[Yy]$ ]]
      then
          [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
      fi
    else
      timelog "Running init on JENKINS or version is install"
    fi
  fi
}

function prepare_excludes() {
  if [[ -n ${EXCLUDE_EXEC_DB_PATHES+x} ]] && [[ ${#EXCLUDE_EXEC_DB_PATHES[@]} -gt 0 ]]; then
    timelog "Preparing to exclude: (${BWHITE}${EXCLUDE_EXEC_DB_PATHES[*]}${NC})"

    for schema in "${DBFOLDERS[@]}"
    do
      db_install_file=./db/$schema/${mode}_${schema}_${version}.sql

      if [[ -f "${db_install_file}" ]]; then
        local tmp_install_file="${db_install_file}.tmp"
        local exclude_comment_count=0
        : > "${tmp_install_file}"

        while IFS= read -r line || [[ -n "${line}" ]]; do
          if [[ "${line}" =~ ^[[:space:]]*@@([^[:space:];]+) ]]; then
            local include_path="${BASH_REMATCH[1]}"
            local normalized_include_path="${include_path#./}"
            local must_exclude="NO"

            for exclude_dir in "${EXCLUDE_EXEC_DB_PATHES[@]}"
            do
              local normalized_exclude_dir="${exclude_dir#./}"
              normalized_exclude_dir="${normalized_exclude_dir%/}"

              if [[ -n "${normalized_exclude_dir}" ]] && \
                 ([[ "${normalized_include_path}" == "${normalized_exclude_dir}" ]] || [[ "${normalized_include_path}" == "${normalized_exclude_dir}/"* ]]); then
                must_exclude="YES"
                break
              fi
            done

            if [[ "${must_exclude}" == "YES" ]] && [[ ! "${line}" =~ ^[[:space:]]*-- ]]; then
              line="--${line}"
              exclude_comment_count=$((exclude_comment_count+1))
            fi
          fi

          printf "%s\n" "${line}" >> "${tmp_install_file}"
        done < "${db_install_file}"

        mv "${tmp_install_file}" "${db_install_file}"
        timelog "Excluded ${exclude_comment_count} include(s) in ${db_install_file}"
      fi

    done # schema

  fi
}

function prepare_redo() {
  if [[ -f "${oldlogfile}" ]]; then
    timelog "parsing redolog ${oldlogfile}"

    redo_file="redo_${MDATE}_${mode}_${version}.log"
    grep '^<<< ' "${oldlogfile}" | cat > "${redo_file}"
    sed "s/^<<< //" "${redo_file}" > "${redo_file}.tmp" && mv "${redo_file}.tmp" "${redo_file}"

    # backup install files
    for schema in "${DBFOLDERS[@]}"
    do

      db_install_file=./db/$schema/${mode}_${schema}_${version}.sql
      if [[ -f $db_install_file ]]; then
        mv "${db_install_file}" "${db_install_file}.org"
      fi
    done # schema

    declare -A map
    while IFS= read -r line; do
      timelog " ... Skipping line $line"
      map[$line]=$line
    done < "${redo_file}"

    for schema in "${DBFOLDERS[@]}"
    do
      old_install_file=./db/$schema/${mode}_${schema}_${version}.sql.org
      db_install_file=./db/$schema/${mode}_${schema}_${version}.sql

      while IFS= read -r line; do
        key=${line/@@/db/$schema/}

        if [[ ${THIS_OS} == "Darwin" ]]; then
          # on macos double bracket lead to failure, for now I can't fix that cause I need assoziative array
          if [ -v map[${key}] ]; then
              line="Prompt skipped redo: $line"
          fi
        else
          if [[ ${map[${key}]+_} ]]; then
              line="Prompt skipped redo: $line"
          fi
        fi
        echo "$line"
      done < "${old_install_file}" > "${db_install_file}"
    done # schema

  fi
}

function read_db_pass() {
  if [[ "${CONN_MODE}" == "SQLNET" ]]; then
    if [[ -z "$DB_APP_PWD" ]]; then
      ask4pwd "Enter Password for deployment user ${DB_APP_USER} on ${DB_TNS}: "
      DB_APP_PWD=${pass}
    else
      timelog "Password has already been set"
    fi
  fi
}

function remove_dropped_files() {
  timelog "Check if any file should be removed ..."
  if [[ -e $remove_old_files ]]; then
    # loop throug content
    while IFS= read -r line; do
      timelog "Removing file ${line}"
      rm -f "${line}"
    done < "$remove_old_files"
  else
    timelog "No files to remove"
  fi
}

function execute_global_hook_scripts() {
  local entrypath=$1    # pre or post
  local targetschema=""

  timelog "Checking hook ${entrypath}"

  if [[ -d "${entrypath}" ]]; then
    for file in $(ls "${entrypath}" | sort )
    do
      if [[ -f "${entrypath}/${file}" ]]; then
        targetschema=$(get_schema_from_file_name "${file}")
        runfile="${entrypath}/${file}"

        if [[ ${targetschema} != "_" ]]; then
          timelog "executing hook file ${runfile} in ${targetschema}"
          local sql_block
          sql_block=$(cat <<EOF
define VERSION="${version}"
define MODE="${mode}"

$(
  for element in "${env_vars[@]}"
  do
    echo "$element"
  done
)

set define '^'
set concat on
set concat .
set verify off


set timing on
set trim on
set linesize 2000
set sqlblanklines on
set tab off
set pagesize 9999
set trimspool on

set serveroutput on

Prompt calling file ${runfile}
@${runfile}
EOF
)
          run_sql_block "${targetschema}" "${sql_block}"

        else
          timelog "no schema found to execute hook file ${runfile} target schema has to be a part of filename" "${warning}"
        fi
      fi
    done


    if [[ $? -ne 0 ]]; then
      timelog "ERROR when executing ${entrypath}/${file}" "${failure}"
      manage_result "failure"
    fi
  fi
}

function clear_db_schemas_on_init() {
  if [[ "${mode}" == "init" ]]; then
    if [[ "${DO_NOT_CLEAR_SCHEMA_ON_INIT:-}" != "YES" ]]; then
      [[ ${stepwise_option} == "NO" ]] || ask_step "${RED}INIT! > clear schemas${NC}"
      timelog "INIT - Mode, Schemas will be cleared"
      # loop through schemas reverse
      for (( idx=${#SCHEMAS[@]}-1 ; idx>=0 ; idx-- )) ; do
        local schema=${SCHEMAS[idx]}
        # On init mode schema content will be dropped
        timelog "DROPING ALL OBJECTS on schema ${schema}"
        run_sql_file "${schema}" ".dbFlow/lib/drop_all.sql" false "${full_log_file}" "${version}" "${mode}"
      done
    else
      timelog "INIT - Mode, But Schemas will not be touched as DO_NOT_CLEAR_SCHEMA_ON_INIT set to ${DO_NOT_CLEAR_SCHEMA_ON_INIT}" "info"
    fi
  fi
}

function validate_connections() {
  # loop through schemas
  for schema in "${SCHEMAS[@]}"
  do
    check_connection "${schema}"
  done

}

function install_db_schemas() {
  cd "${basepath}" || exit

  # execute all files in global pre path
  execute_global_hook_scripts "db/.hooks/pre"
  execute_global_hook_scripts "db/.hooks/pre/${mode}"

  cd db || exit

  timelog "Start installing schemas"
  # loop through schemas
  for schema in "${DBFOLDERS[@]}"
  do
    if [[ -d ${schema} ]]; then
      cd "${schema}" || exit

      [[ ${stepwise_option} == "NO" ]] || ask_step "Install Schema ${schema}"

      # now executing main installation file if exists
      db_install_file="${mode}_${schema}_${version}.sql"
      # exists db install file
      if [[ -e $db_install_file ]]; then
        if [[ "${CONN_MODE}" == "REST" ]]; then
          timelog "Installing objects of folder $schema to ${WKSP_APEXDX} using ${REST_SQL_URL}"
        else
          timelog "Installing objects of folder $schema to ${DB_APP_USER} on ${DB_TNS}"
        fi

        # uncomment cleaning scripts specific to this stage/branch ex:--test or --acceptance
        sed "s:--$STAGE:Prompt uncommented cleanup for stage $STAGE\n:g" "${db_install_file}" > "${db_install_file}.tmp" && mv "${db_install_file}.tmp" "${db_install_file}"

        runfile=${db_install_file}
        AT_LEAST_ON_INSTALLFILE_STARTED="YES"
        run_sql_file "${schema}" "${db_install_file}" true "${version}" "${mode}"
        runfile=""

        if [[ $? -ne 0 ]]; then
          timelog "ERROR when executing db/${schema}/${db_install_file}" "${failure}"
          manage_result "failure"
        fi

      else
        timelog "File db/$schema/$db_install_file does not exist"
      fi

      cd ..
    fi
  done

  cd ..


  # execute all files in global post path
  execute_global_hook_scripts "db/.hooks/post"
  execute_global_hook_scripts "db/.hooks/post/${mode}"
}

function set_rest_publish_state() {
  cd "${basepath}" || exit
  local publish=$1
  if [[ -d "rest" ]]; then
    local appschema=${APP_SCHEMA}

    local -a folders=()
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      while IFS= read -r d; do
        folders+=( "$(basename "${d}")/modules" )
      done < <(find rest -maxdepth 1 -mindepth 1 -type d | sort -f)
    else
      folders=( "modules" )
    fi

    local fldr
    for fldr in "${folders[@]}"; do
      if [[ ${PROJECT_MODE} == "FLEX" ]]; then
        appschema=${fldr/\/modules/}
      fi
      local -a modules=()
      if [[ -d "rest/$fldr" ]]; then
        while IFS= read -r mods; do
          local mbase
          local module_def
          mbase=$(basename "${mods}")
          module_def="${mods}/${mbase}.module.sql"

          # A REST module is valid only if a file named
          # <module-folder>/<module-folder>.module.sql exists.
          if [[ -f "${module_def}" ]]; then
            timelog "Setting REST publish state ${publish} for module ${mbase} in schema ${appschema}"
            modules+=( "${mbase}" )
          fi
        done < <(find "rest/$fldr" -maxdepth 1 -mindepth 1 -type d | sort -f)

        if [[ ${#modules[@]} -eq 0 ]]; then
          timelog "No REST modules with '*.module.sql' definition found in rest/${fldr}" "info"
          continue
        fi

        local sql_block
        sql_block=$(cat <<EOF
          set define off;
          set serveroutput on;
          $(
            for element in "${modules[@]}"
            do
              echo "Declare"
              echo "  ex_schema_not_enabled exception;"
              echo "  PRAGMA EXCEPTION_INIT(ex_schema_not_enabled, -20012);"
              echo "Begin"
              echo "  dbms_output.put_line('setting publish state to ${publish} for REST module ${element} for schema ${appschema}...');"
              echo "  ords.publish_module(p_module_name  => '${element}',"
              echo "                      p_status       => '${publish}');"
              echo "Exception"
              echo "  when ex_schema_not_enabled then"
              echo "    dbms_output.put_line((chr(27) || '[31m') || sqlerrm || (chr(27) || '[0m'));"
              echo "  when no_data_found then"
              echo "    dbms_output.put_line((chr(27) || '[31m') || 'REST Modul: ${element} not found!' || (chr(27) || '[0m'));"
              echo "End;"
              echo "/"
            done
          )

EOF
)   
      
        run_sql_block "${appschema}" "${sql_block}" 
      fi
    done
  else
    timelog "Directory rest does not exist" "${warning}"
  fi

  cd "${basepath}" || exit
}


function set_apps_unavailable() {
  cd "${basepath}" || exit

  if [[ -d "apex" ]]; then

    depth=1
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=3
    fi

    for d in $(find apex -maxdepth ${depth} -mindepth ${depth} -type d)
    do
      local app_name=$(basename "${d}")
      local l_app_id=${app_name/f}
      local l_workspace=${WORKSPACE}
      local l_appschema=${APP_SCHEMA}

      if [[ ${PROJECT_MODE} == "FLEX" ]]; then
        l_workspace=$(basename $(dirname "${d}"))
        l_appschema=$(basename $(dirname $(dirname "${d}")))
      fi

      if [[ ${CONN_MODE} == "REST" ]]; then
        l_app_id=$(resolve_rest_target_app_id "${l_app_id}")
        if [[ $? -ne 0 ]] || [[ -z "${l_app_id}" ]]; then
          exit 3
        fi
        l_workspace=${REST_WORKSPACE}
        l_appschema=${REST_APP_SCHEMA}
      fi

      timelog "Disabling APEX-App ${l_app_id} in workspace ${l_workspace} for schema ${l_appschema}..."

      local sql_block
      sql_block=$(cat <<EOF
      set serveroutput on;
      set define off;
      Declare
        v_application_id  apex_application_build_options.application_id%type := ${l_app_id} + ${APP_OFFSET};
        v_workspace_id    apex_workspaces.workspace_id%type;
      Begin
        select workspace_id
          into v_workspace_id
          from apex_workspaces
          where workspace = upper('${l_workspace}');

        apex_application_install.set_workspace_id(v_workspace_id);
        apex_util.set_security_group_id(p_security_group_id => apex_application_install.get_workspace_id);

        apex_util.set_application_status(p_application_id     => v_application_id,
                                          p_application_status => 'UNAVAILABLE',
                                          p_unavailable_value  => '${maintence}' );

        dbms_output.put_line('.. APP: '|| v_application_id || ' has been disabled');

        -- check translated Applications additionally
        for cur in ( select translated_application_id, translated_app_language
                       from apex_application_trans_map
                      where primary_application_id = v_application_id
                      order by translated_application_id)
        loop
          begin
            apex_util.set_application_status(p_application_id     => cur.translated_application_id,
                                             p_application_status => 'UNAVAILABLE',
                                             p_unavailable_value  => '${maintence}' );
            dbms_output.put_line('.... Translated APP: '|| cur.translated_application_id || ' (' || cur.translated_app_language || ') has been disabled');
          exception
            when others then
              if sqlerrm like '%Application not found%' then
                dbms_output.put_line( 'Application: '||upper(cur.translated_application_id)||' probably not published!');
              else
                raise;
              end if;
          end;
        end loop;
      Exception
        when no_data_found then
          dbms_output.put_line('Workspace: '||upper('${l_workspace}')||' not found!');
        when others then
          if sqlerrm like '%Application not found%' then
            dbms_output.put_line('Application: '||upper(v_application_id)||' not found!');
          else
            raise;
          end if;
End;
/

EOF
)
      run_sql_block "${l_appschema}" "${sql_block}"

    done
  else
    timelog "Directory apex does not exist" "${warning}"
  fi

}

function set_apps_available() {
  cd "${basepath}" || exit

  if [[ -d "apex" ]]; then

    depth=1
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=3
    fi

    for d in $(find apex -maxdepth ${depth} -mindepth ${depth} -type d)
    do
      local l_app_name=$(basename "${d}")
      local l_app_id=${l_app_name/f}
      local l_workspace=${WORKSPACE}
      local l_appschema=${APP_SCHEMA}

      if [[ ${PROJECT_MODE} == "FLEX" ]]; then
        l_workspace=$(basename $(dirname ${d}))
        l_appschema=$(basename $(dirname $(dirname ${d})))
      fi

      if [[ ${CONN_MODE} == "REST" ]]; then
        l_app_id=$(resolve_rest_target_app_id "${l_app_id}")
        if [[ $? -ne 0 ]] || [[ -z "${l_app_id}" ]]; then
          exit 3
        fi
        l_workspace=${REST_WORKSPACE}
        l_appschema=${REST_APP_SCHEMA}
      fi

      # Enable only Applications which were not part of the current deployment process
      if grep -q "\b${l_app_name}\b" "${app_install_file}"; then
        timelog "App ${l_app_id} not enabled; included in deployment. Publish translated apps manually using hooks."
      else
        timelog "enabling APEX-App ${l_app_id} in workspace ${l_workspace} for schema ${l_appschema}..."
        local sql_block
        sql_block=$(cat <<EOF
set serveroutput on;
set define off;

Declare
  v_application_id  apex_application_build_options.application_id%type := ${l_app_id} + ${APP_OFFSET};
  v_workspace_id    apex_workspaces.workspace_id%type;
  l_text            varchar2(100);
Begin

  select workspace_id
    into v_workspace_id
    from apex_workspaces
    where workspace = upper('${l_workspace}');

  apex_application_install.set_workspace_id(v_workspace_id);
  apex_util.set_security_group_id(p_security_group_id => apex_application_install.get_workspace_id);

  begin
    select substr(unavailable_text, 1, 50)
      into l_text
      from apex_applications
    where application_id = v_application_id;

    -- only enable, what has been disabled by dbFlow with the marker "<span />"
    if (apex_util.get_application_status(p_application_id => v_application_id) = 'UNAVAILABLE' and l_text like '<span />%') then

      apex_util.set_application_status(p_application_id     => v_application_id,
                                      p_application_status => 'AVAILABLE_W_EDIT_LINK',
                                      p_unavailable_value  => null );

      dbms_output.put_line('.. APP: '|| v_application_id || ' has been enabled');


      -- check translated Applications additionally
      for cur in ( select translated_application_id, translated_app_language
                      from apex_application_trans_map
                    where primary_application_id = v_application_id )
      loop
        begin
          apex_util.set_application_status(p_application_id     => cur.translated_application_id,
                                          p_application_status => 'AVAILABLE_W_EDIT_LINK',
                                          p_unavailable_value  => null );

          dbms_output.put_line('.... Translated APP: '|| cur.translated_application_id || ' (' || cur.translated_app_language || ') has been enabled');
        exception
          when others then
            if sqlerrm like '%Application not found%' then
              dbms_output.put_line((chr(27) || '[31m') || 'Application: '||upper(v_application_id)||' probably not published!' || (chr(27) || '[0m'));
            else
              raise;
            end if;
        end;
      end loop;
    end if;
  exception
    when no_data_found then
      dbms_output.put_line((chr(27) || '[31m') || 'Application: '||upper(v_application_id)||' not found!' || (chr(27) || '[0m'));
  end;
Exception
  when no_data_found then
    dbms_output.put_line((chr(27) || '[31m') || 'Workspace: '||upper('${l_workspace}')||' not found!' || (chr(27) || '[0m'));
End;
/
EOF
)
        run_sql_block "${l_appschema}" "${sql_block}"
      fi # grep
    done


  else
    timelog "Directory apex does not exist" "${warning}"
  fi

}

function install_apps() {

  cd "${basepath}" || exit

  # app install
  # exists app_install_file
  if [[ -e $app_install_file ]]; then
    timelog "Installing APEX-Apps ..."
    # loop throug content
    while IFS= read -r line; do
      if [[ -e ${line}/install.sql ]]; then
        local app_name=$(basename "${line}")
        local app_id=${app_name/f}

        local workspace=${WORKSPACE}
        local appschema=${APP_SCHEMA}
        if [[ ${PROJECT_MODE} == "FLEX" ]]; then
          workspace=$(basename $(dirname "${line}"))
          appschema=$(basename $(dirname $(dirname "${line}")))
        fi

        cd "${line}" || exit
        if [[ $(uname) == "Darwin" ]]; then
          # on macos the -P parameter does not exist for grep, so we use sed instead
          local original_app_id=$(grep -oE "p_default_application_id=>([^[:space:]]+)" "application/set_environment.sql" | sed 's/.*>\(.*\)/\1/')
        else
          local original_app_id=$(grep -oP 'p_default_application_id=>\K\d+' "application/set_environment.sql")
        fi
        
        # begin .hooks/pre
        if [[ -d ".hooks/pre" ]]; then
          for pre_hook in .hooks/pre/*.sh; do
            [[ -e "${pre_hook}" ]] || continue
            timelog "Running hook ${pre_hook}" "${info}"
            "${pre_hook}"
          done
        fi
        # end .hooks/pre

        if [[ "${CONN_MODE}" == "SQLNET" ]]; then
          timelog "Installing $line Num: ${app_id} Workspace: ${workspace} Schema: ${appschema} Original Num: ${original_app_id}"

          local sql_block
          sql_block=$(cat <<EOF
define VERSION="${version}"
define MODE="${mode}"

set define '^'
set concat on
set concat .
set verify off

set serveroutput on

Prompt Workspace: ${workspace}
Prompt Application: ${app_id}
declare
  v_workspace_id	apex_workspaces.workspace_id%type;
begin
  select workspace_id
    into v_workspace_id
    from apex_workspaces
  where workspace = upper('${workspace}');

  apex_application_install.set_workspace_id(v_workspace_id);

  apex_application_install.set_application_id(${app_id} + nvl(${APP_OFFSET}, 0));

  if nvl(${APP_OFFSET}, 0) > 0 or ${app_id} != nvl(${original_app_id}, 0) then
    dbms_output.put_line((chr(27) || '[33m') || 'Original APP ID differs from Target APP ID. Generating Offset.' || (chr(27) || '[0m'));
    apex_application_install.generate_offset;
    -- alias must be unique per instance, so when offset is definded
    -- it should be modified. In this case a post hook at root level
    -- has to be used to give it a correct alias
    apex_application_install.set_application_alias('${app_id}_${APP_OFFSET}');
  end if;

  apex_application_install.set_schema(upper('${appschema}'));
Exception
  when no_data_found then
    dbms_output.put_line((chr(27) || '[31m') || 'Workspace: '||upper('${workspace}')||' not found!' || (chr(27) || '[0m'));
end;
/

@@install.sql

EOF
)
          run_sql_block "${appschema}" "${sql_block}" true
        else
          local target_app_id
          target_app_id=$(resolve_rest_target_app_id "${app_id}")
          if [[ $? -ne 0 ]] || [[ -z "${target_app_id}" ]]; then
            timelog "ERROR when resolving REST target app id for source app ${app_id}" "${failure}"
            exit 3
          fi

          timelog "Installing $line using REST API Num: ${target_app_id} Workspace: ${REST_WORKSPACE} Schema: ${REST_APP_SCHEMA} Original Num: ${original_app_id}"
          run_app_import_rest "${REST_APP_SCHEMA}" "${REST_WORKSPACE}" "${target_app_id}" "${original_app_id}"
        fi
        if [[ $? -ne 0 ]]; then
          timelog "ERROR when executing ${line}" "${failure}"
          exit 3
        fi

        # begin .hooks/post
        if [[ -d ".hooks/post" ]]; then
          for post_hook in .hooks/post/*.sh; do
            [[ -e "${post_hook}" ]] || continue
            timelog "Running hook ${post_hook}" "${info}"
            "${post_hook}"
          done
        fi
        # end .hooks/post

        cd "${basepath}" || exit
      fi

    done < "$app_install_file"
  else
    timelog "File $app_install_file does not exist" "${warning}"
  fi

  cd "${basepath}" || exit
}


# Function to install REST-Services
#######################################

function install_rest() {
  cd "${basepath}" || exit

  rest_install_file=rest_${mode}_${version}.sql

  if [[ -d rest ]]; then

    depth=0
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=1
    fi

    for d in $(find rest -maxdepth ${depth} -mindepth ${depth} -type d)
    do
      cd "${d}" || exit

      if [[ -f ${rest_install_file} ]]; then

        local appschema=${APP_SCHEMA}
        if [[ ${PROJECT_MODE} == "FLEX" ]]; then
          appschema=$(basename "${d}")
        fi

        timelog "Installing REST-Services ..."
        local sql_block
        sql_block=$(cat <<EOF

define VERSION="${version}"
define MODE="${mode}"

set define '^'
set concat on
set concat .
set verify off

Prompt calling file ${instfile}
@@${rest_install_file}

EOF
)

        run_sql_block "${appschema}" "${sql_block}" true


        if [ $? -ne 0 ]
        then
          timelog "ERROR when executing $line" "${failure}"
          exit 1
        fi
      fi

      cd "${basepath}" || exit
    done

  else
    timelog "Directory rest does not exist"
  fi

  cd "${basepath}" || exit
}


# when changelog is found and changelog template is defined then
# execute template on configured schema build.env:CHANGELOG_SCHEMA=?
function process_changelog() {
  chlfile=changelog_${mode}_${version}.md
  tplfile=reports/changelog/template.sql
  if [[ -f ${chlfile} ]]; then
    timelog "Changelog found"

    if [[ -f "${tplfile}" ]]; then
      timelog "Template file found"

      if [[ -n ${CHANGELOG_SCHEMA} ]]; then
        timelog "changelog schema '${CHANGELOG_SCHEMA}' is configured"

        # now gen merged sql file
        create_merged_report_file "${chlfile}" "${tplfile}" "${chlfile}.sql"

        # and run
        local sql_block
        sql_block=$(cat <<EOF

Prompt executing changelog file ${chlfile}.sql
@@${chlfile}.sql

EOF
)
        run_sql_block "${CHANGELOG_SCHEMA}" "${sql_block}" true

        if [ $? -ne 0 ]
        then
          timelog "ERROR when runnin ${chlfile}.sql" "${failure}"
          exit 1
        # else
        #   rm "${chlfile}.sql"
        fi
      else
        timelog "changelog schema is NOT configured"
      fi
    else
      timelog "No templatefile found"
    fi
  else
    timelog "No changelog ${chlfile} found"
  fi
}

# when releasenotes are found and release_note template is defined then
# execute template on configured schema build.env:RELEASENOTES_SCHEMA=?
function process_release_notes() {
  rlsnfile=release_notes_${mode}_${version}.md
  tplfile=reports/release_notes/template.sql
  if [[ -f ${rlsnfile} ]]; then
    timelog "Release note found"

    if [[ -f "${tplfile}" ]]; then
      timelog "Template file found"

      if [[ ${PROJECT_MODE} == "SINGLE" ]]; then
        RELEASENOTES_SCHEMA=${APP_SCHEMA}
        timelog "Release note schema set to '${APP_SCHEMA}' because project mode is SINGLE"
      fi

      if [[ -n ${RELEASENOTES_SCHEMA} ]]; then
        timelog "Release note schema '${RELEASENOTES_SCHEMA}' is configured"

        # now gen merged sql file
        create_merged_report_file "${rlsnfile}" "${tplfile}" "${rlsnfile}.sql"

        # and run
        local sql_block
        sql_block=$(cat <<EOF

Prompt executing release_notes file ${rlsnfile}.sql
@@${rlsnfile}.sql

EOF
)
        run_sql_block "${RELEASENOTES_SCHEMA}" "${sql_block}" true

        if [ $? -ne 0 ]
        then
          timelog "ERROR when runnin ${rlsnfile}.sql" "${failure}"
          exit 1
        else
          rm "${rlsnfile}.sql"
        fi
      else
        timelog "RELEASENOTES_SCHEMA is NOT configured"
      fi
    else
      timelog "No template file found"
    fi
  else
    timelog "No release note ${rlsnfile} found"
  fi
}

function post_message_to_teams() {
  cd "${basepath}" || exit

  local TITLE=$1
  local COLOR=$2
  local TEXT=$3

  if [ -z "${TEAMS_WEBHOOK_URL}" ]
  then
    timelog "No webhook_url specified."
  else
    # Convert formating.
    MESSAGE=$( echo "${TEXT}" | sed 's/"/\"/g' | sed "s/'/\'/g" )
    JSON="{\"title\": \"${TITLE}\", \"themeColor\": \"${COLOR}\", \"text\": \"${MESSAGE}\" }"

    timelog "Posting to url: ${JSON} "
    # Post to Microsoft Teams.
    curl -H "Content-Type: application/json" -d "${JSON}" "${TEAMS_WEBHOOK_URL}"

  fi
}

function process_logs() {
  local target_move=$1
  local view_output=$2

  # Send stdout back to stdin
  exec >&3 2>&4
  #exec 1>&0

  # remove colorcodes from file
  echo "Processing logs"
  cat "${full_log_file}" | sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" > "${full_log_file}.colorless"
  rm "${full_log_file}"
  mv "${full_log_file}.colorless" "${full_log_file}"

  local lfile=$(basename "${full_log_file}")

  # write definition to current apply.env
  if [[ -f "apply.env" && -z "$(grep 'LOG_PATH=' "apply.env")" ]]; then
    {
    echo ""
    echo "# auto added @${MDATE}"
    echo "# Path to copy logs to after installation"
    echo "LOG_PATH=_logs"
    } >> apply.env
    echo -e "${LWHITE}set LOG_PATH to ${NC}${BWHITE}_logs${NC} ${LWHITE} in your apply.env - please configure as you like with a relative path${NC}"
    LOG_PATH="_logs"
  fi


  # create path if needed
  [[ -d "${LOG_PATH}" ]] || mkdir "${LOG_PATH}"

  # create succcess or failure subfolder
  [[ -d "${LOG_PATH}/${target_move}" ]] || mkdir "${LOG_PATH}/${target_move}"


  # rm tarball
  rm ${install_target_file}

  # move all artifacts
  mv ./*"${mode}"*"${version}"* "${target_relative_path}"

  view_output="${target_relative_path}/$(basename "${full_log_file}")"
  echo_debug "view output: \"${view_output}\""
}

function manage_result() {
  cd "${basepath}" || exit

  local target_move=$1
  target_relative_path=${LOG_PATH}/${target_move}/${version}
  target_finalize_path=${basepath}/${target_relative_path}

  # create path if not exists
  [ -d "${target_finalize_path}" ] || mkdir -p "${target_finalize_path}"

  # notify
  timelog "${mode} ${version} moved to ${target_finalize_path}" "${target_move}"
  timelog "Done with ${target_move}" "${target_move}"


  # move apex lst
  [[ -f "apex_files_${version}.lst" ]] && mv "apex_files_${version}.lst" "${target_finalize_path}"
  [[ -f "remove_files_${version}.lst" ]] && mv "remove_files_${version}.lst" "${target_finalize_path}"

  # move rest files
  depth=1
  if [[ ${PROJECT_MODE} == "FLEX" ]]; then
    depth=2
  fi

  if [[ -d rest ]]; then
    for restfile in $(find rest -maxdepth ${depth} -mindepth ${depth} -type f)
    do
      mv "${restfile}" "${target_finalize_path}"
    done
  fi

  # loop through schemas
  for schema in "${DBFOLDERS[@]}"
  do
    db_install_file="${mode}_${schema}_${version}.sql"

    if [[ -f "db/${schema}/${db_install_file}" ]]; then
      [[ -d "${target_finalize_path}/db/${schema}" ]] || mkdir -p "${target_finalize_path}/db/${schema}"
      mv "db/${schema}/${db_install_file}"* "${target_finalize_path}/db/${schema}"
    fi
  done

  # write Info to markdown-table
  deployed_at=`date +"%Y-%m-%d %T"`
  deployed_by=$(whoami)

  versionmd=`printf '%-10s' "V${version}"`
  deployed_at=`printf '%-19s' "$deployed_at"`
  deployed_by=`printf '%-11s' "$deployed_by"`
  result=`printf '%-11s' "$target_move"`

  echo "| $versionmd | $deployed_at | $deployed_by |  $result " >> "${basepath}/version.md"

  finallog=$(basename "${full_log_file}")


  if [[ $target_move == "success" ]]; then
    post_message_to_teams "Release ${version}" "4CCC3B" "Release ${version} has been successfully applied to stage: <b>${STAGE}</b>."
    process_logs ${target_move} "${target_relative_path}/${finallog}";

    # commit if stage != develop or build and current branch is main or master
    if [[ -d ".git" ]]; then
      if [[ ${STAGE} != "develop" && ${STAGE} != "build" ]]; then
        if [[ ${this_branch} == "main" || ${this_branch} == "master" ]]; then
          echo_success "Adding all changes to this repo"
          git add --all
          git commit -m "${version}" --quiet

          if [[ -n "$(git remote)" ]]; then
            git push --quiet
          fi

          if [[ $(git tag -l "$version") ]]; then
            echo_success "Tag $version already exists, nothing to do"
          else
            echo_success "Writing tag $version to repo"
            git tag "${version}"

            if [[ -n "$(git remote)" ]]; then
              git push --quiet
            fi
          fi

        fi
      fi
    fi
    exit 0
  else
    redolog=$(basename "${full_log_file}")

    # this is only usefull when at least on installation file has been executed
    if [[ ${AT_LEAST_ON_INSTALLFILE_STARTED} == "YES" ]]; then
      # failure
      echo_debug "You can either copy the broken patch into the current directory and restart "
      echo_debug "the patch after the respective problem has been fixed by using the redolog param"
      echo_debug "---"
      echo_debug "${WHITE}cp ${target_relative_path}/${mode}_${version}.tar.gz .${NC}"
      echo_debug "${WHITE}$0 --${mode} --version ${version} --redolog ${target_relative_path}/${redolog}${NC}"
      echo_debug "---"
      echo_debug "Or create a new fixed release and restart the deployment of the patch. In both cases you have the"
      echo_debug "possibility to specifiy the log file ${WHITE}${target_relative_path}/${log_file}${NC}"
      echo_debug "as redolog parameter. This will not repeat the steps that have already been successfully executed."
    fi

    process_logs ${target_move} "${target_relative_path}/${finallog}";
    exit 1
  fi
}

function ask_step() {
  local step=${1}
  read -r -p "$(echo -e "${BWHITE}Step:${NC} - ${step} - proceed (y/n) ? ") " -n 1
  echo    # (optional) move to a new line
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
  fi
}

#################################################################################################
function notify() {
    [[ ${1} = 0 ]] || echo ❌ EXIT "${1}"
    # you can notify some external services here,
    # ie. Slack webhook, Github commit/PR etc.
    if [[ ${1} -gt 2 ]]; then
      if [[ "${runfile}" != "" ]]; then
        timelog "ERROR when executing ${runfile}" "${failure}"
      else
        timelog "ERROR in last statement" "${failure}"
      fi

      manage_result "failure"
    fi

}

trap '(exit 130)' INT
trap '(exit 143)' TERM
trap 'rc=$?; notify $rc; exit $rc' EXIT

# validate params this script was called with
check_params "$@"
validate_init_mode

# validate and check existence of vars defined in apply.env and build.env
check_vars

# print some global vars to output
print_info

[[ ${stepwise_option} == "NO" ]] || ask_step "Validate deplyoment file"
# preparation and validation
extract_patchfile
validate_dbflow_version
read_db_pass
validate_connections
prepare_redo
prepare_excludes

[[ ${stepwise_option} == "NO" ]] || ask_step "Remove dropped files"
# files to be removed
remove_dropped_files

[[ ${stepwise_option} == "NO" ]] || ask_step "Set APPs or RESTmodules offline"
# now disable all, so that during build noone can do anything
set_apps_unavailable
set_rest_publish_state "NOT_PUBLISHED"

# when in init mode, ALL schema objects will be
# dropped
clear_db_schemas_on_init

[[ ${stepwise_option} == "NO" ]] || ask_step "exec global PRE hooks"
# execute pre hooks in root folder
execute_global_hook_scripts ".hooks/pre"
execute_global_hook_scripts ".hooks/pre/${mode}"

# install product
[[ ${stepwise_option} == "NO" ]] || ask_step "Install db schema(s)"
install_db_schemas

[[ ${stepwise_option} == "NO" ]] || ask_step "Install APP(s)"
install_apps

[[ ${stepwise_option} == "NO" ]] || ask_step "Install RESTmodule(s)"
install_rest

[[ ${stepwise_option} == "NO" ]] || ask_step "exec global POST hooks"
# execute post hooks in root folder
execute_global_hook_scripts ".hooks/post"
execute_global_hook_scripts ".hooks/post/${mode}"

[[ ${stepwise_option} == "NO" ]] || ask_step "Process changelogs"
# take care of changelog
process_changelog

# and release notes
process_release_notes

[[ ${stepwise_option} == "NO" ]] || ask_step "Set Apps or RESTmodules online"
# now enable all,
set_apps_available
set_rest_publish_state "PUBLISHED"

[[ ${stepwise_option} == "NO" ]] || ask_step "Cleaning Artefacts"
# final works
manage_result "success"
