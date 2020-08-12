#!/bin/bash

# params
APPLICATION_ID=$1

source build.env
source apply.env

function print_help() {
 	echo "Please call script with following parameters"
  echo "  1 - application_id to export"
  echo ""
  echo "Example: "
  echo "  $0 100"
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

if [ -z "$DB_APP_USER" ]
then
  echo_red "DeploymentUser nicht gefunden"
  print_help
fi

if [ -z "$DB_APP_PWD" ]
then
  echo_red "DeploymentPasswort nicht gefunden"
  print_help
fi

if [ -z "$APPLICATION_ID" ]
then
  echo "ApplicationID als 1. Parameter fehlt"
  print_help
fi

export NLS_LANG="GERMAN_GERMANY.AL32UTF8"
export NLS_DATE_FORMAT="DD.MM.YYYY HH24:MI:SS"
export JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.region=US -Dfile.encoding=UTF-8"
export CUSTOM_JDBC="-XX:+TieredCompilation -XX:TieredStopAtLevel=1 -Xverify:none"

TARGET_SCHEMA=${APP_SCHEMA}
if [ $USE_PROXY == "FALSE" ]
then
  CONNECTION=$DB_APP_USER/$DB_APP_PWD@$DB_TNS
else
  CONNECTION=$DB_APP_USER[$TARGET_SCHEMA]/$DB_APP_PWD@$DB_TNS
fi
echo -e "${BYELLOW}CONNECTION:${NC}     ${WHITE}${DB_TNS}${NC}"
echo -e "${BYELLOW}APPLICATION_ID:${NC} ${WHITE}${APPLICATION_ID}${NC}"

echo -e " ${BLUE}$(date '+%d.%m.%Y %H:%M:%S') >> exporting Application ${APPLICATION_ID} ... ${NC}"

cd apex
sql -s -l $CONNECTION <<!
  apex export -applicationid ${APPLICATION_ID} -split -skipExportDate
!
rm f${APPLICATION_ID}.sql

echo -e "${GREEN}$(date '+%d.%m.%Y %H:%M:%S') >> export done${NC}"

