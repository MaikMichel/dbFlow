#!/bin/bash

source ../../.bash4xcl/lib.sh

# target environment
source ../../build.env
source ../../apply.env

# ------------------------------------------------------------------- #
echo " ============================================================================="
echo " ==   Installing OraMUC/table-api-generator"
echo " ============================================================================="
echo
tapi_schema="tapi"
tapi_pass=$(shuf -zer -n20 {A..Z} {a..z} {0..9} | tr -d '\0')

tag_name=$(curl --silent "https://api.github.com/repos/MaikMichel/table-api-generator/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -OL "https://github.com/MaikMichel/table-api-generator/archive/${tag_name}.zip"

unzip ${tag_name}.zip -d "tapi-${tag_name}"
rm ${tag_name}.zip

cd tapi-${tag_name}/table-api-generator-${tag_name/v/} # remove v from tag-name

if [ -z "$DB_PASSWORD" ]
then
  ask4pwd "Enter password für user sys: "
  DB_PASSWORD=${pass}
fi


is_tapi_installed () {
    sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
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
echo "TAPI installed: '${TAPI_INSTALLED}'"
if [ "${TAPI_INSTALLED}" == "true" ]
then
  sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
  Prompt ${tapi_schema} droppen
  drop user ${tapi_schema} cascade;
!
fi

sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
Prompt create user: ${tapi_schema}
create user ${tapi_schema} identified by "${tapi_pass}" default tablespace users temporary tablespace temp
/
alter user ${tapi_schema} quota unlimited on users
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
conn sys/${DB_PASSWORD}@$DB_TNS as sysdba
alter user ${tapi_schema} account lock;

Promp table-api installen

!

cd ../..

rm -rf tapi-${tag_name}

exit