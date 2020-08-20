#!/bin/bash

source ../../../.bash4xcl/lib.sh

# target environment
source ../../../build.env
source ../../../apply.env

# ------------------------------------------------------------------- #
echo " ============================================================================="
echo " ==   Installing utPLSQL"
echo " ============================================================================="
echo
yes=${1:-"NO"}
utplsql_schema="ut3"

tag_name=$(curl --silent "https://api.github.com/repos/utPLSQL/utPLSQL/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -OL "https://github.com/utPLSQL/utPLSQL/releases/download/${tag_name}/utPLSQL.zip"

unzip utPLSQL.zip -d utplsql
rm utPLSQL.zip

cd utplsql/utPLSQL/source

if [ -z "$DB_PASSWORD" ]
then
  ask4pwd "Enter password für user sys: "
  DB_PASSWORD=${pass}
fi

is_utplsql_installed () {
    sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
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
    sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba @uninstall.sql ${utplsql_schema}

    sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
  Prompt ${utplsql_schema} droppen
  drop user ${utplsql_schema} cascade;
!
  else
    cd ../../..
    rm -rf utplsql
    exit
  fi
fi

sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba @install_headless.sql

cd ../../..
rm -rf utplsql

exit