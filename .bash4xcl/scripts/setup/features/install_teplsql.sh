#!/bin/bash

source ../../.bash4xcl/lib.sh

# target environment
source ../../build.env
source ../../apply.env

# ------------------------------------------------------------------- #
echo " ============================================================================="
echo " ==   Installing osalvador/tePLSQL: MaikMichel/tePLSQL"
echo " ============================================================================="
echo
teplsql_schema="teplsql"
teplsql_pass=$(shuf -zer -n20 {A..Z} {a..z} {0..9} | tr -d '\0')

tag_name=$(curl --silent "https://api.github.com/repos/MaikMichel/tePLSQL/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -OL "https://github.com/MaikMichel/tePLSQL/archive/${tag_name}.zip"

unzip ${tag_name}.zip -d "tePLSQL-${tag_name}"
rm ${tag_name}.zip

cd "tePLSQL-"${tag_name}/tePLSQL-${tag_name/v/} # remove v from tag-name

if [ -z "$DB_PASSWORD" ]
then
  ask4pwd "Enter password für user sys: "
  DB_PASSWORD=${pass}
fi


is_teplsql_installed () {
    sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
    set heading off
    set feedback off
    set pages 0
    with checksql as (select count(1) cnt
  from all_users
 where username = upper('${teplsql_schema}'))
 select case when cnt = 1 then 'true' else 'false' end ding
   from checksql;
!
}

TEPLSQL_INSTALLED=$(is_teplsql_installed)
echo "TEPLSQL installed: '${TEPLSQL_INSTALLED}'"
if [ "${TEPLSQL_INSTALLED}" == "true" ]
then
  sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
  Prompt ${teplsql_schema} droppen
  drop user ${teplsql_schema} cascade;
!
fi

sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba <<!
Prompt create user: ${teplsql_schema}
create user ${teplsql_schema} identified by "${teplsql_pass}" default tablespace users temporary tablespace temp
/
alter user ${teplsql_schema} quota unlimited on users
/
grant connect, create view, create job, create table, create sequence, create trigger, create procedure, create public synonym to ${teplsql_schema}
/

conn ${teplsql_schema}/${teplsql_pass}@$DB_TNS

Prompt installing tePLSQL

@@install.sql

Prompt create public synonyms
create or replace public synonym TE_TEMPLATES for ${teplsql_schema}.TE_TEMPLATES;
create or replace public synonym teplsql for ${teplsql_schema}.teplsql;
create or replace public synonym te_templates_api for ${teplsql_schema}.te_templates_api;

Prompt grant public synonyms
grant select, insert, delete, update on TE_TEMPLATES to public;
grant execute on teplsql to public;
grant execute on te_templates_api to public;

Promp lock user: ${teplsql_schema}
conn sys/${DB_PASSWORD}@$DB_TNS as sysdba
alter user ${teplsql_schema} account lock;

Promp tePLSQL installed

!

cd ../..

rm -rf "tePLSQL-"${tag_name}

exit