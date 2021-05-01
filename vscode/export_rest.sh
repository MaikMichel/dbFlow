#!/bin/bash

# params
REST_MODULE=$1

source ./build.env
source ./apply.env


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
fi

if [ -z "$DB_APP_USER" ]
then
  echo_red "DeploymentUser nicht gefunden"
fi

if [ -z "$DB_APP_PWD" ]
then
  echo_red "DeploymentPasswort nicht gefunden"
fi

if [ -z "$REST_MODULE" ]
then
  echo "RestModule als 1. Parameter fehlt"
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
echo -e "${BYELLOW}CONNECTION:${NC}  ${WHITE}${DB_TNS}${NC}"
echo -e "${BYELLOW}REST_MODULE:${NC}  ${WHITE}${REST_MODULE}${NC}"

echo -e " ${BLUE}$(date '+%d.%m.%Y %H:%M:%S') >> exporting REST Module ${REST_MODULE} ... ${NC}"

cd rest
if [[ ${REST_MODULE} == "SCHEMA" ]]; then
  sql -s -l $CONNECTION <<!
    spool ${REST_MODULE}.sql
    rest export
    prompt /
    spool off

!

else
  [ -d modules ] || mkdir modules
  sql -s -l $CONNECTION <<!
    spool modules/${REST_MODULE}.sql
    rest export ${REST_MODULE}
    prompt /
    spool off
!

fi

echo -e "${GREEN}$(date '+%d.%m.%Y %H:%M:%S') >> export done${NC}"
