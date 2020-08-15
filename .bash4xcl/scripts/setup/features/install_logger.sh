#!/bin/bash

source ../../../.bash4xcl/lib.sh

# target environment
source ../../../build.env
source ../../../apply.env

# ------------------------------------------------------------------- #
echo " ============================================================================="
echo " ==   Installing Logger"
echo " ============================================================================="
echo
logger_schema="logger"
lg_pass=$(shuf -zer -n20 {A..Z} {a..z} {0..9} | tr -d '\0')
tag_name=$(curl --silent "https://api.github.com/repos/OraOpenSource/Logger/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -OL "https://github.com/OraOpenSource/Logger/raw/master/releases/logger_${tag_name}.zip"

unzip logger_${tag_name}.zip -d logger
rm logger_${tag_name}.zip

if [ -z "$DB_PASSWORD" ]
then
  ask4pwd "Enter password für user sys: "
  DB_PASSWORD=${pass}
fi

is_logger_installed () {
    sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
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
if [ "${LOGGER_INSTALLED}" == "true" ]
then
  read -p "$(echo -e ${BWHITE}"Logger is allready installed. Would you like to reinstall? (Y/N) [Y]: "${NC})" reinstall
  reinstall=${reinstall:-"Y"}

  if [ ${reinstall,,} == "y" ]; then
    sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
  Prompt ${logger_schema} droppen
  drop user ${logger_schema} cascade;
!
  else
    rm -rf logger
    exit
  fi
fi

sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
Prompt create user: ${logger_schema}
create user ${logger_schema} identified by "${lg_pass}" default tablespace users temporary tablespace temp
/
alter user ${logger_schema} quota unlimited on users
/
grant connect,create view, create job, create table, create sequence, create trigger, create procedure, create any context, create public synonym to ${logger_schema}
/
conn logger/${lg_pass}@$DB_TNS
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
conn sys/${DB_PASSWORD}@$DB_TNS as sysdba
alter user ${logger_schema} account lock;
!

rm -rf logger
exit