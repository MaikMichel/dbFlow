#!/bin/bash

source ../../../.dbFlow/lib.sh

# target environment
source ../../../build.env
source ../../../apply.env

# ------------------------------------------------------------------- #
echo " ============================================================================="
echo " ==   Installing utPLSQL"
echo " ============================================================================="
echo
yes=${1:-"NO"}
DB_PASSWORD=${2:-$DB_PASSWORD}

utplsql_schema="ut3"
utplsql_pass=$(shuf -zer -n20 {A..Z} {a..z} {0..9} | tr -d '\0')
utplsql_tspace="users"

tag_name=$(curl --silent "https://api.github.com/repos/utPLSQL/utPLSQL/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -OL "https://github.com/utPLSQL/utPLSQL/releases/download/${tag_name}/utPLSQL.zip"

unzip utPLSQL.zip -d utplsql
rm utPLSQL.zip

cd utplsql/utPLSQL/source

if [ -z "$DB_ADMINUSER" ]
then
  read -p "Enter username of admin user (admin, sys, ...) [sys]: " DB_ADMINUSER
  DB_ADMINUSER=${DB_ADMINUSER:-"sys"}
fi

if [[ ${DB_ADMINUSER,,} != "sys" ]]; then
  DBA_OPTION=""
  utplsql_tspace="data" # no users tablespace when using autonomous db
fi

if [ -z "$DB_PASSWORD" ]
then
  ask4pwd "Enter password für user ${DB_ADMINUSER}: "
  DB_PASSWORD=${pass}
fi

is_utplsql_installed () {
    sqlplus -s ${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION} <<!
    set heading off
    set feedback off
    set pages 0
    with checksql as (select count(1) cnt
  from all_users
 where username = upper('${utplsql_schema}'))
 select case when cnt = 1 then 'true' else 'false' end ding
   from checksql;
!
}

UTPLSQL_INSTALLED=$(is_utplsql_installed)
if [ "${UTPLSQL_INSTALLED}" == "true" ]
then
  if [ $yes == "YES" ]; then
    reinstall="Y"
  else
    read -p "$(echo -e ${BWHITE}"UTPLSQL is allready installed. Would you like to reinstall? (Y/N) [Y]: "${NC})" reinstall
    reinstall=${reinstall:-"Y"}
  fi

  if [ ${reinstall,,} == "y" ]; then
    sqlplus -s ${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION} @uninstall.sql ${utplsql_schema}

    sqlplus -s ${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION} <<!
  Prompt ${utplsql_schema} droppen
  drop user ${utplsql_schema} cascade;
!
  else
    cd ../../..
    rm -rf utplsql
    exit
  fi
fi

sqlplus -s ${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION} @install_headless.sql ${utplsql_schema} ${utplsql_pass} ${utplsql_tspace}

cd ../../..
rm -rf utplsql

exit