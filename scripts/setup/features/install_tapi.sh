#!/bin/bash

source ../../../.dbFlow/lib.sh

# target environment
source ../../../build.env
source ../../../apply.env

# ------------------------------------------------------------------- #
echo " ============================================================================="
echo " ==   Installing OraMUC/table-api-generator"
echo " ============================================================================="
echo
yes=${1:-"NO"}
DB_ADMIN_PWD=${2:-$DB_ADMIN_PWD}

tapi_schema="tapi"
tapi_pass=$(base64 < /dev/urandom | tr -d 'O0Il1+/' | head -c 20; printf '\n')
tapi_tspace="users"

tag_name=$(basename $(curl -fs -o/dev/null -w %{redirect_url} https://github.com/MaikMichel/table-api-generator/releases/latest))
echo "Downloading ... https://github.com/MaikMichel/table-api-generator/archive/${tag_name}.zip"
curl -OL "https://github.com/MaikMichel/table-api-generator/archive/${tag_name}.zip"

unzip ${tag_name}.zip -d "tapi-${tag_name}"
rm ${tag_name}.zip

cd tapi-${tag_name}/table-api-generator-${tag_name/v/} # remove v from tag-name

if [[ -z "$DB_ADMIN_USER" ]]; then
  read -p "Enter username of admin user (admin, sys, ...) [sys]: " DB_ADMIN_USER
  DB_ADMIN_USER=${DB_ADMIN_USER:-"sys"}
fi

if [[ $(toLowerCase $DB_ADMIN_USER) != "sys" ]]; then
  DBA_OPTION=""
  tapi_tspace="data" # no users tablespace when using autonomous db
fi

if [[ -z "$DB_ADMIN_PWD" ]]; then
  ask4pwd "Enter password für user ${DB_ADMIN_USER}: "
  DB_ADMIN_PWD=${pass}
fi


is_tapi_installed () {
    ${SQLCLI} -s ${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION} <<!
    set heading off
    set feedback off
    set pages 0
    with checksql as (select count(1) cnt
  from all_users
 where username = upper('${tapi_schema}'))
 select case when cnt = 1 then 'true' else 'false' end ding
   from checksql;
!
}

TAPI_INSTALLED=$(is_tapi_installed)

if [[ "${TAPI_INSTALLED}" == *"true"* ]]
then
  if [[ $yes == "YES" ]]; then
    reinstall="Y"
  else
    read -p "$(echo -e ${BWHITE}"TableAPI is allready installed. Would you like to reinstall? (Y/N) [Y]: "${NC})" reinstall
    reinstall=${reinstall:-"Y"}
  fi

  if [[ $(toLowerCase $reinstall) == "y" ]]; then
    ${SQLCLI} -s ${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION} <<!
  Prompt ${tapi_schema} droppen
  drop user ${tapi_schema} cascade;
!
  else
    cd ../..
    rm -rf tapi-${tag_name}
    exit
  fi
fi

${SQLCLI} -s ${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION} <<!
Prompt create user: ${tapi_schema}
create user ${tapi_schema} identified by "${tapi_pass}" default tablespace ${tapi_tspace} temporary tablespace temp
/
alter user ${tapi_schema} quota unlimited on ${tapi_tspace}
/
grant connect, create view, create job, create table, create sequence, create trigger, create procedure, create public synonym to ${tapi_schema}
/

conn ${tapi_schema}/${tapi_pass}@$DB_TNS

Prompt installing table-api

@@install.sql

Prompt create public synonyms
create or replace public synonym om_tapigen for ${tapi_schema}.om_tapigen;
create or replace public synonym om_tapigen_oddgen_wrapper for ${tapi_schema}.om_tapigen_oddgen_wrapper;

Prompt grant public synonyms
grant execute on om_tapigen to public;
grant execute on om_tapigen_oddgen_wrapper to public;

Promp lock user: ${tapi_schema}
conn ${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION}
alter user ${tapi_schema} account lock;

Promp table-api installen

!

cd ../..
rm -rf tapi-${tag_name}

exit