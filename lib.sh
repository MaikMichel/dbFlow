# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

# A better class of script...
set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
# set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline


# Reset
NC="\033[0m"       # Text Reset

# Regular Colors
BLACK="\033[0;30m"        # Black
RED="\033[0;31m"          # Red
GREEN="\033[0;32m"        # Green
YELLOW="\033[0;33m"       # Yellow
BLUE="\033[0;34m"         # Blue
PURPLE="\033[0;35m"       # Purple
CYAN="\033[0;36m"         # Cyan
BWHITE="\033[1;37m"       # White
BYELLOW="\033[1;33m"      # Yellow



pass=""
function ask4pwd() {
  local prompt_text=$1

  unset CHARCOUNT
  PROMPT=""
  pass=""

  echo -n "${prompt_text}"

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


# Function return connect string
#########################################
get_connect_string() {
  local arg1=$1

  if [[ ${#SCHEMAS[@]} -gt 1 ]]; then
    echo "$DB_APP_USER[$arg1]/$DB_APP_PWD@$DB_TNS"
  else
    echo "$DB_APP_USER/$DB_APP_PWD@$DB_TNS"
  fi
}

function toLowerCase() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

#some env settings SQLCL needs
export NLS_LANG="GERMAN_GERMANY.AL32UTF8"
export NLS_DATE_FORMAT="DD.MM.YYYY HH24:MI:SS"
export JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.region=US -Dfile.encoding=UTF-8"
export CUSTOM_JDBC="-XX:+TieredCompilation -XX:TieredStopAtLevel=1 -Xverify:none"
export LANG="de_DE.utf8"
case $(uname | tr '[:upper:]' '[:lower:]') in
mingw64_nt-10*)
  chcp.com 65001
;;
esac


## Logging

failure="failure"
success="success"
warning="warning"

write_log() {
  local type=${1:-""}
  case "$type" in
    ${failure})
      color=${RED}
      reset=${NC}
      ;;
    ${success})
      color=${GREEN}
      reset=${NC}
      ;;
    ${warning})
      color=${YELLOW}
      reset=${NC}
      ;;
    *)
      color=""
      reset=""
  esac


  while read text
  do
    LOGTIME=`date "+%Y-%m-%d %H:%M:%S"`
    # If log file is not defined, just echo the output
    if [[ "$full_log_file" == "" ]]; then
      echo -e $LOGTIME": ${color}${text}${reset}";
    else
      echo -e $LOGTIME": ${color}${text}${reset}" | tee -a $full_log_file;
    fi
  done
}

function check_admin_connection() {
  sql_output=`${SQLCLI} -S "${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION}" <<EOF
  select 'connected as '||user t from dual;
  exit
EOF
` || true

  if [[ $sql_output == *"connected as"* ]]; then
    echo_success "Connection as ${DB_ADMINUSER} is working"
  else
    echo_error "Error to connect as ${DB_ADMINUSER}"
    echo_error "${sql_output}"
    exit 2
  fi
}

function check_connection() {
  local CONN_STR=get_connect_string $1
  sql_output=`${SQLCLI} -S "${CONN_STR}" <<EOF
  select 'connected to schema '||user t from dual;
  exit
EOF
` || true

  if [[ $sql_output == *"connected to"* ]]; then
    echo_success "Connection to schema ${1} is working"
  else
    echo_error "Error to connect to schema ${1}"
    echo_error "${sql_output}"
    exit 2
  fi
}