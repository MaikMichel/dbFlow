#!/bin/bash

source ../../../.dbFlow/lib.sh

# target environment
source ../../../build.env
source ../../../apply.env

# ------------------------------------------------------------------- #
echo " ============================================================================="
echo " ==   Installing Logger $1"
echo " ============================================================================="
echo
yes=${1:-"NO"}
DB_PASSWORD=${2:-$DB_PASSWORD}

logger_schema="logger"
logger_pass=$(base64 < /dev/urandom | tr -d 'O0Il1+/' | head -c 20; printf '\n')
logger_tspace="users"

tag_name=$(curl --silent "https://github.com/OraOpenSource/Logger/releases/latest" | sed 's#.*tag/\(.*\)\".*#\1#')
curl -OL "https://github.com/OraOpenSource/Logger/raw/master/releases/logger_${tag_name}.zip"

unzip logger_${tag_name}.zip -d logger
rm logger_${tag_name}.zip

if [[ -z "$DB_ADMINUSER" ]]; then
  read -p "Enter username of admin user (admin, sys, ...) [sys]: " DB_ADMINUSER
  DB_ADMINUSER=${DB_ADMINUSER:-"sys"}
fi

if [[ $(toLowerCase $DB_ADMINUSER) != "sys" ]]; then
  DBA_OPTION=""
  logger_tspace="data" # no users tablespace when using autonomous db
fi

if [[ -z "$DB_PASSWORD" ]]; then
  ask4pwd "Enter password für user ${DB_ADMINUSER}: "
  DB_PASSWORD=${pass}
fi

is_logger_installed () {
    ${SQLCLI} -s ${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION} <<!
    set heading off
    set feedback off
    set pages 0
    with checksql as (select count(1) cnt
  from all_users
 where username = upper('${logger_schema}'))
 select case when cnt = 1 then 'true' else 'false' end ding
   from checksql;
!
}

LOGGER_INSTALLED=$(is_logger_installed)
if [[ "${LOGGER_INSTALLED}" == *"true"* ]]
then
  if [[ $yes == "YES" ]]; then
    reinstall="Y"
  else
    read -p "$(echo -e ${BWHITE}"Logger is allready installed. Would you like to reinstall? (Y/N) [Y]: "${NC})" reinstall
    reinstall=${reinstall:-"Y"}
  fi

  if [[ $(toLowerCase $reinstall) == "y" ]]; then
    ${SQLCLI} -s ${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION} <<!
  Prompt ${logger_schema} droppen
  drop user ${logger_schema} cascade;
!
  else
    rm -rf logger
    exit
  fi
fi

${SQLCLI} -s ${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION} <<!
Prompt create user: ${logger_schema}
create user ${logger_schema} identified by "${logger_pass}" default tablespace ${logger_tspace} temporary tablespace temp
/
alter user ${logger_schema} quota unlimited on ${logger_tspace}
/
grant connect,create view, create job, create table, create sequence, create trigger, create procedure, create any context, create public synonym to ${logger_schema}
/
conn logger/${logger_pass}@$DB_TNS
Prompt install logger
@@logger/logger_install.sql
Prompt create public synonyms
create or replace public synonym logger for ${logger_schema}.logger;
create or replace public synonym logger_logs for ${logger_schema}.logger_logs;
create or replace public synonym logger_logs_apex_items for ${logger_schema}.logger_logs_apex_items;
create or replace public synonym logger_prefs for ${logger_schema}.logger_prefs;
create or replace public synonym logger_prefs_by_client_id for ${logger_schema}.logger_prefs_by_client_id;
create or replace public synonym logger_logs_5_min for ${logger_schema}.logger_logs_5_min;
create or replace public synonym logger_logs_60_min for ${logger_schema}.logger_logs_60_min;
create or replace public synonym logger_logs_terse for ${logger_schema}.logger_logs_terse;
Prompt grant public synonyms
grant execute on logger to public;
grant select, delete on logger_logs to public;
grant select on logger_logs_apex_items to public;
grant select, update on logger_prefs to public;
grant select on logger_prefs_by_client_id to public;
grant select on logger_logs_5_min to public;
grant select on logger_logs_60_min to public;
grant select on logger_logs_terse to public;
Promp lock user: ${logger_schema}
conn ${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION}
alter user ${logger_schema} account lock;
!

rm -rf logger
exit