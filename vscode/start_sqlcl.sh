#!/bin/bash

SOURCE_FILE=$1

source ./.dbFlow/lib.sh

# params
source ./build.env
source ./apply.env


function print_help() {
  echo "Please call script with following parameters"
  echo "  1 - source_file"
  echo ""
  echo ""
  echo "Examples: "
  echo "  $0 db/xxx_logic/source/packages/test.pks"
  echo ""

  exit 1
}


if [ -z "$DB_TNS" ]
then
  echo_error "Connection nicht gefunden"
  print_help
fi

if [ -z "$SOURCE_FILE" ]
then
  echo_error "SourceDatei als Parameter fehlt"
  print_help
fi

if [ -z "$DB_APP_USER" ]
then
  echo_error "DeploymenUser nicht gefunden"
  print_help
fi

if [ -z "$DB_APP_PWD" ]
then
  echo_error "DeploymenPasswort nicht gefunden"
  print_help
fi

SOURCE_FILE=$(echo "${SOURCE_FILE}" | sed 's/\\/\//g' | sed 's/://')

# je nach Verzeichnis Schema bestimmen
#
TARGET_SCHEMA="unknown"
if [[ "$SOURCE_FILE" == *"db/${DATA_SCHEMA}"* ]]; then
  TARGET_SCHEMA=${DATA_SCHEMA}
elif [[ "$SOURCE_FILE" == *"db/${LOGIC_SCHEMA}"* ]]; then
  TARGET_SCHEMA=${LOGIC_SCHEMA}
elif [[ "$SOURCE_FILE" == *"db/${APP_SCHEMA}"* ]]; then
  TARGET_SCHEMA=${APP_SCHEMA}
elif [[ "$SOURCE_FILE" == *"nitro/f"* ]]; then
  TARGET_SCHEMA=${APP_SCHEMA}
else
  echo_error "ERROR: unknown path: ${SOURCE_FILE} !!!"
  echo_warning "Defaulting to ${DATA_SCHEMA}"
  TARGET_SCHEMA=${DATA_SCHEMA}
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


CONNECTION=$DB_APP_USER[$TARGET_SCHEMA]/$DB_APP_PWD@$DB_TNS
echo -e "${BYELLOW}Connection:${NC}  ${BWHITE}${DB_TNS}${NC}"
echo -e "${BYELLOW}Schema:${NC}      ${BWHITE}$DB_APP_USER[$TARGET_SCHEMA]${NC}"

sql $CONNECTION