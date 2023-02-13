#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

# A better class of script...
set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
# set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline

# null value in array
shopt -s nullglob

# Reset
NC="\033[0m"       # Text Reset

# Regular Colors
BLACK="\033[0;30m"        # Black
RED="\033[0;31m"          # Red
REDB="\033[1;41m"         # BoldRedBack
GREEN="\033[0;32m"        # Green
BGREEN="\033[1;32m"        # Green
YELLOW="\033[0;33m"       # Yellow
BLUE="\033[0;34m"         # Blue
PURPLE="\033[0;35m"       # Purple
CYAN="\033[0;36m"         # Cyan
BCYAN="\033[1;36m"         # Cyan
BWHITE="\033[1;97m"       # White
WHITE="\033[0;97m"        # White
LWHITE="\033[1;30m"       # White
BYELLOW="\e[30;48;5;82m"  # Yellow
BORANGE="\e[38;5;208m"    # Orange
BUNLINE="\e[1;4m"
BUNLINE="\e[1;4m"
BGRAY="\e[0;90m"
BLBACK="\e[30;48;5;81m"

LIBSOURCED="TRUE"

NUMBERPATTERN='^[0-9]+$'

pass=""
function ask4pwd() {
  local prompt_text=$1

  unset CHARCOUNT
  PROMPT=""
  pass=""

  echo -n -e "${prompt_text}"

  stty -echo

  CHARCOUNT=0
  while IFS= read -p "$PROMPT" -r -s -n 1 CHAR
  do
      # Enter - accept password
      if [[ $CHAR == $'\0' ]] ; then
          break
      fi
      # Backspace
      if [[ $CHAR == $'\177' ]] ; then
          if [[ $CHARCOUNT -gt 0 ]] ; then
              CHARCOUNT=$((CHARCOUNT-1))
              PROMPT=$'\b \b'
              pass="${pass%?}"
          else
              PROMPT=''
          fi
      else
          CHARCOUNT=$((CHARCOUNT+1))
          PROMPT='*'
          pass+="$CHAR"
      fi
  done

  stty echo
  echo
}

function echo_fatal() {
  local prompt_text=$1

  echo -e "${REDB}$prompt_text${NC}"
}

function echo_error() {
  local prompt_text=$1

  echo -e "${RED}$prompt_text${NC}"
}

function echo_success() {
  local prompt_text=$1

  echo -e "${GREEN}$prompt_text${NC}"
}

function echo_warning() {
  local prompt_text=$1

  echo -e "${YELLOW}$prompt_text${NC}"
}

function echo_debug() {
  local prompt_text=$1

  echo -e "${CYAN}$prompt_text${NC}"
}

# used when admin user is sys
DBA_OPTION=" as sysdba"

# array to hold all pathes to files which have to deployed based on mode and branch
SCAN_PATHES=()

function define_folders() {
  local l_mode="${1}";
  local l_branch="${2}";

  # at INIT there is no pretreatment or an evaluation of the table_ddl
  # !: Don't forgett to change documentation when changing these arrays
  if [[ "${l_mode}" == "init" ]]; then
    SCAN_PATHES=( .hooks/pre sequences tables indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies sources/types sources/packages sources/functions sources/procedures views mviews sources/triggers jobs tests/packages ddl/init dml/init dml/base .hooks/post)
  else
    # building pre and post based on branches
    pres=( ".hooks/pre ddl/patch/pre_${l_branch}" "dml/patch/pre_${l_branch}" ddl/patch/pre dml/patch/pre )
    post=( "ddl/patch/post_${l_branch}" "dml/patch/post_${l_branch}" ddl/patch/post dml/base dml/patch/post .hooks/post )

    SCAN_PATHES=( ${pres[@]} )
    SCAN_PATHES+=( sequences tables tables/tables_ddl indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies sources/types sources/packages sources/functions sources/procedures views mviews sources/triggers jobs tests/packages )
    SCAN_PATHES+=( ${post[@]} )
  fi
}



# Function return connect string
#########################################
function get_connect_string() {
  local dbfolder=$1
  local dbschema=$dbfolder
  local firstpart=${dbfolder%%_*}

  # when dbfolder starts with a number and underscore
  # then remove it, cause this is for sorting
  if [[ $firstpart =~ $NUMBERPATTERN ]]; then
    dbschema=${dbfolder/$firstpart"_"/""}
  fi

  # when connection user != target schema then use proxy
  if [[ ${DB_APP_USER} != "${dbschema}" ]]; then
    echo "${DB_APP_USER}[${dbschema}]/${DB_APP_PWD}@${DB_TNS}"
  else
    echo "${DB_APP_USER}/${DB_APP_PWD}@${DB_TNS}"
  fi
}

function toLowerCase() {
  echo "${1}" | tr '[:upper:]' '[:lower:]'
}

#some env settings SQLCL needs
export NLS_LANG="GERMAN_GERMANY.AL32UTF8"
export NLS_DATE_FORMAT="DD.MM.YYYY HH24:MI:SS"
export JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.region=US -Dfile.encoding=UTF-8"
export LANG="de_DE.utf8"
case $(uname | tr '[:upper:]' '[:lower:]') in
mingw64_nt-10*)
  chcp.com 65001 > /dev/null 2>&1
;;
esac


## Logging

failure="failure"
success="success"
warning="warning"
info="info"

timelog () {
  local text=${1:-""}
  local type=${2:-""}

  case "$type" in
    "${failure}")
      color=${RED}
      reset=${NC}
      ;;
    "${success}")
      color=${GREEN}
      reset=${NC}
      ;;
    "${warning}")
      color=${YELLOW}
      reset=${NC}
      ;;
    "${info}")
      color=${CYAN}
      reset=${NC}
      ;;
    *)
      color=${WHITE}
      reset=${NC}
  esac

  LOGTIME=`date "+%Y-%m-%d %H:%M:%S"`
  echo -e "${LWHITE}$LOGTIME${NC}: ${color}${text}${reset}";
}


function check_admin_connection() {
  sql_output=`${SQLCLI} -S -L "${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION}" <<EOF
  select 'connected as '||user t from dual;
  exit
EOF
` || true

  if [[ $sql_output == *"connected as"* ]]; then
    echo_success "Connection as ${DB_ADMIN_USER} is working"
  else
    echo_fatal "Error to connect as ${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION}"
    echo_error "${sql_output}"
    exit 2
  fi
}

function check_connection() {
  local CONN_STR="$(get_connect_string "${1}")"

  sql_output=`${SQLCLI} -S -L "${CONN_STR}" <<EOF
  select 'connected to schema '||user t from dual;
  exit
EOF
` || true

  if [[ $sql_output == *"connected to"* ]]; then
    echo_success "Connection to schema ${1} is working"
  else
    echo_fatal "Error to connect to schema ${1}"
    echo_error "${sql_output}"
    #echo_error ${CONN_STR}
    exit 2
  fi
}

function get_schema_from_folder_name() {
  local dbfolder=$1
  local dbschema=$dbfolder
  local firstpart=${dbfolder%%_*}

  # when dbfolder starts with a number and underscore
  # then remove it, cause this is for sorting
  if [[ $firstpart =~ $NUMBERPATTERN ]]; then
    dbschema=${dbfolder/$firstpart"_"/""}
  fi

  echo "${dbschema}"
}

function get_schema_from_file_name() {
  local fname=$1
  local schema="_"
  # loof through dbschemas and check if file contains schema
  for s in "${DBSCHEMAS[@]}"
  do
    if [[ ${fname} == *${s}* ]]; then
      schema=$s
      break
    fi
  done
  echo "${schema}"
}


# fill dbschema and dbfolder
DBFOLDERS=()
DBSCHEMAS=()

{
  if [[ -d "db" ]]; then
    for d in $(find db -maxdepth 1 -mindepth 1 -type d | sort -f)
    do
      folder=$(basename "${d}")
      if [[ ${folder} != "_setup" ]] && [[ ${folder} != ".hooks" ]]; then
        DBFOLDERS+=( ${folder} )
        DBSCHEMAS+=( $(get_schema_from_folder_name "${folder}") )
      fi
    done
  fi
}


function write_line_if_not_exists () {
  local line=$1
  local file=$2

  if  grep -qxF "$line" "$file" ; then
    : # echo "$line exists in $file"
  else
    echo "$line" >> "$file"
  fi
}

create_merged_report_file() {
  local source_file=$1
  local template_file=$2
  local output_file=$3
  local base64_file=${source_file}.base64.txt

  # gen base64 from input
  base64 -w 1000 "${source_file}" > "${base64_file}"

  ## write the output sql
  echo "set serveroutput on" > "${output_file}"
  echo "declare" >> "${output_file}"
  echo "  l_b64         clob;" >> "${output_file}"
  echo "  l_bin         blob;" >> "${output_file}"
  echo "  l_file_name   varchar2(2000) := '${source_file}';  " >> "${output_file}"
  echo "" >> "${output_file}"
  echo "  gc_red           varchar2(7) := chr(27) || '[31m';" >> "${output_file}"
  echo "  gc_green         varchar2(7) := chr(27) || '[32m';" >> "${output_file}"
  echo "  gc_yellow        varchar2(7) := chr(27) || '[33m';" >> "${output_file}"
  echo "  gc_blue          varchar2(7) := chr(27) || '[34m';" >> "${output_file}"
  echo "  gc_cyan          varchar2(7) := chr(27) || '[36m';" >> "${output_file}"
  echo "  gc_reset         varchar2(7) := chr(27) || '[0m';" >> "${output_file}"
  echo "" >> "${output_file}"

  echo "begin" >> "${output_file}"
  echo "  dbms_lob.createtemporary(l_b64, true, dbms_lob.session);" >> "${output_file}"
  echo  >> "${output_file}"
  while IFS= read -r line
  do
    echo "  dbms_lob.append(l_b64, '$line');" >> "${output_file}"
  done < "${base64_file}"

  echo >> "${output_file}"
  echo "  l_bin := apex_web_service.clobbase642blob(l_b64);" >> "${output_file}"
  echo >> "${output_file}"

  echo "-------------" >> "${output_file}"
  cat "${template_file}" >> "${output_file}"
  echo "-------------" >> "${output_file}"

  echo "  commit;" >> "${output_file}"
  echo "exception" >> "${output_file}"
  echo "  when others then" >> "${output_file}"
  echo "    dbms_output.put_line(gc_red||sqlerrm || gc_reset);" >> "${output_file}"
  echo "    raise;" >> "${output_file}"

  echo "end;" >> "${output_file}"
  echo "/" >> "${output_file}"
  echo >> "${output_file}"

  rm "${base64_file}"
}

getopts_long() {
    : "${1:?Missing required parameter -- long optspec}"
    : "${2:?Missing required parameter -- variable name}"

    local optspec_short="${1%% *}-:"
    local optspec_long="${1#* }"
    local optvar="${2}"

    shift 2

    if [[ "${#}" == 0 ]]; then
        local args=()
        while [[ ${#BASH_ARGV[@]} -gt ${#args[@]} ]]; do
            local index=$(( ${#BASH_ARGV[@]} - ${#args[@]} - 1 ))
            args[${#args[@]}]="${BASH_ARGV[${index}]}"
        done
        set -- "${args[@]}"
    fi

    builtin getopts "${optspec_short}" "${optvar}" "${@}" || return 1
    [[ "${!optvar}" == '-' ]] || return 0

    printf -v "${optvar}" "%s" "${OPTARG%%=*}"

    if [[ "${optspec_long}" =~ (^|[[:space:]])${!optvar}:([[:space:]]|$) ]]; then
        OPTARG="${OPTARG#${!optvar}}"
        OPTARG="${OPTARG#=}"

        # Missing argument
        if [[ -z "${OPTARG}" ]]; then
            OPTARG="${!OPTIND}" && OPTIND=$(( OPTIND + 1 ))
            [[ -z "${OPTARG}" ]] || return 0

            if [[ "${optspec_short:0:1}" == ':' ]]; then
                OPTARG="${!optvar}" && printf -v "${optvar}" ':'
            else
                [[ "${OPTERR}" == 0 ]] || \
                    echo_error "${0}: option requires an argument -- ${!optvar}" >&2
                unset OPTARG && printf -v "${optvar}" '?'
            fi
        fi
    elif [[ "${optspec_long}" =~ (^|[[:space:]])${!optvar}([[:space:]]|$) ]]; then
        unset OPTARG
    else
        # Invalid option
        if [[ "${optspec_short:0:1}" == ':' ]]; then
            OPTARG="${!optvar}"
        else
            [[ "${OPTERR}" == 0 ]] || echo_error "${0}: illegal option -- ${!optvar}" >&2
            unset OPTARG
        fi
        printf -v "${optvar}" '?'
    fi
}

rem_trailing_slash() {
    echo "$1" | sed 's/\/*$//g'
}

force_trailing_slash() {
    echo "$(rem_trailing_slash "$1")/"
}

exists_in_list() {
  LIST=$1
  DELIMITER=$2
  VALUE=$3
  [[ "$LIST" =~ ($DELIMITER|^)$VALUE($DELIMITER|$) ]]
}


function validate_passes() {
   # decode when starting with a !
  if [[ $DB_APP_PWD == !* ]]; then
    DB_APP_PWD=`echo "${DB_APP_PWD:1}" | base64 --decode`
  else
    # write back encoded
    if [[ -n $DB_APP_PWD ]]; then
      pwd_enc=`echo" ${DB_APP_PWD}" | base64`

      # sed syntax is different in macos
      if [[ $(uname) == "Darwin" ]]; then
        sed -i"y" "/^DB_APP_PWD=/s/=.*/=\"\!$pwd_enc\"/" ./apply.env
      else
        sed -i "/^DB_APP_PWD=/s/=.*/=\"\!$pwd_enc\"/" ./apply.env
      fi
    fi
  fi

  # decode when starting with a !
  if [[ $DB_ADMIN_PWD == !* ]]; then
    DB_ADMIN_PWD=`echo "${DB_ADMIN_PWD:1}" | base64 --decode`
  else
    # write back encoded
    if [[ -n $DB_ADMIN_PWD ]]; then
      pwd_enc=`echo "${DB_ADMIN_PWD}" | base64`

      # sed syntax is different in macos
      if [[ $(uname) == "Darwin" ]]; then
        sed -i"y" "/^DB_ADMIN_PWD=/s/=.*/=\"\!$pwd_enc\"/" ./apply.env
      else
        sed -i "/^DB_ADMIN_PWD=/s/=.*/=\"\!$pwd_enc\"/" ./apply.env
      fi
    fi
  fi
}