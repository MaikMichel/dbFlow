#!/bin/bash

# params
SOURCE_FILE=$1
SOURCE_FILE_NO_EXT=$2

source ./build.env
source ./apply.env


function print_help() {
  echo "Please call script with following parameters"
  echo "  1 - source_file"
  echo ""
  echo "following dependencies are required"
  echo "  npm install -g uglifycss terser @babel/core @babel/cli @babel/preset-env"
  echo ""
  echo "Examples: "
  echo "  $0 static/f100/src/test.js"
  echo "  $0 db/xxx_logic/source/packages/test.pks"
  echo ""

  exit 1
}


# Reset
NC="\033[0m"       # Text Reset

# Regular Colors
BLACK="\033[0;30m"        # Black
RED="\033[0;31m"          # Red
GREEN="\033[0;32m"        # Green
BGREEN="\033[1;32m"        # Green
YELLOW="\033[0;33m"       # Yellow
BLUE="\033[0;34m"         # Blue
PURPLE="\033[0;35m"       # Purple
CYAN="\033[0;36m"         # Cyan
WHITE="\033[0;37m"        # White
BYELLOW="\033[1;33m"       # Yellow

echo_red(){
    echo -e "${RED}${1}${NC}"
}

echo_green(){
    echo -e "${GREEN}${1}${NC}"
}


if [ -z "$DB_TNS" ]
then
  echo_red "Connection nicht gefunden"
  print_help
fi

if [ -z "$SOURCE_FILE" ]
then
  echo_red "SourceDatei als Parameter fehlt"
  print_help
fi

if [ -z "$DB_APP_USER" ]
then
  echo_red "DeploymentUser nicht gefunden"
  print_help
fi

if [ -z "$DB_APP_PWD" ]
then
  echo_red "DeploymenPasswort nicht gefunden"
  print_help
fi


export NLS_LANG="GERMAN_GERMANY.AL32UTF8"
export NLS_DATE_FORMAT="DD.MM.YYYY HH24:MI:SS"
export JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.region=US -Dfile.encoding=UTF-8"
export CUSTOM_JDBC="-XX:+TieredCompilation -XX:TieredStopAtLevel=1 -Xverify:none"
export LANG="de_DE.utf8"

SOURCE_FILE=$(echo "${SOURCE_FILE}" | sed 's/\\/\//g' | sed 's/://')
INPATH=$(dirname -- "${SOURCE_FILE}")
BASEFL=$(basename -- "${SOURCE_FILE}")
EXTENSION="${BASEFL##*.}"


# je nach Verzeichnis Schema bestimmen
#
TARGET_SCHEMA="unknown"
DB_TARGET_FILE=""

if [[ "$SOURCE_FILE" == *"db/${DATA_SCHEMA}/tests/"* ]]; then
  TARGET_SCHEMA=${DATA_SCHEMA}
elif [[ "$SOURCE_FILE" == *"db/${LOGIC_SCHEMA}/tests/"* ]]; then
  TARGET_SCHEMA=${LOGIC_SCHEMA}
elif [[ "$SOURCE_FILE" == *"db/${APP_SCHEMA}/tests/"* ]]; then
  TARGET_SCHEMA=${APP_SCHEMA}
else
  echo
  echo_red "ERROR: unknown path: ${SOURCE_FILE} !!!"
  echo "---"
  exit 1
fi

#sqlcl needs that
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

if [ $USE_PROXY == "FALSE" ]
then
  CONNECTION=$DB_APP_USER/$DB_APP_PWD@$DB_TNS
else
  CONNECTION=$DB_APP_USER[$TARGET_SCHEMA]/$DB_APP_PWD@$DB_TNS
fi

echo -e "${BYELLOW}Connection:${NC}  ${WHITE}${DB_TNS}${NC}"
echo -e "${BYELLOW}Schema:${NC}      ${WHITE}$DB_APP_USER[$TARGET_SCHEMA]${NC}"
echo -e "${BYELLOW}Sourcefile:${NC}  ${WHITE}${SOURCE_FILE}${NC}"
echo -e "${BYELLOW}TestPackage:${NC} ${WHITE}${SOURCE_FILE_NO_EXT}${NC}"

sqlplus -s -l $CONNECTION <<!
set pagesize 9999
set linesize 2000
set serveroutput on
set scan off
set define off
set trim on

exec ut.run(a_path => user||'.'||'${SOURCE_FILE_NO_EXT}', a_color_console => true);
!
