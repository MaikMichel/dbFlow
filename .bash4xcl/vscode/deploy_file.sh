#!/bin/bash

# params
SOURCE_FILE=$1
source build.env
source apply.env


function print_help() {
  echo "Please call script with following parameters"
  echo "  1 - source_file"
  echo ""
  echo "following dependencies are required"
  echo "  npm install -g uglifycss terser @babel/core @babel/cli @babel/preset-env"
  echo ""
  echo "Examples: "
  echo "  $0 static/f100/src/test.js"
  echo "  $0 db/xxx_logic/source/packages/test.pks"
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

if [ -z "$SOURCE_FILE" ]
then
  echo_red "SourceDatei als Parameter fehlt"
  print_help
fi

if [ -z "$DB_APP_USER" ]
then
  echo_red "DeploymentUser nicht gefunden"
  print_help
fi

if [ -z "$DB_APP_PWD" ]
then
  echo_red "DeploymenPasswort nicht gefunden"
  print_help
fi


export NLS_LANG="GERMAN_GERMANY.AL32UTF8"
export NLS_DATE_FORMAT="DD.MM.YYYY HH24:MI:SS"
export JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.region=US -Dfile.encoding=UTF-8"
export CUSTOM_JDBC="-XX:+TieredCompilation -XX:TieredStopAtLevel=1 -Xverify:none"

SOURCE_FILE=$(echo "${SOURCE_FILE}" | sed 's/\\/\//g' | sed 's/://')
INPATH=$(dirname -- "${SOURCE_FILE}")
BASEFL=$(basename -- "${SOURCE_FILE}")
EXTENSION="${BASEFL##*.}"
SOURCE_FILE_MINIFIED=${INPATH}/"$(basename "${SOURCE_FILE}" $EXTENSION)min.$EXTENSION"

SOURCE_FILE_IE=${INPATH}/"$(basename "${SOURCE_FILE}" $EXTENSION)IE.$EXTENSION"
SOURCE_FILE_IE_MINIFIED=${INPATH}/"$(basename "${SOURCE_FILE_IE}" $EXTENSION)min.$EXTENSION"


# je nach Verzeichnis Schema bestimmen
#
TARGET_SCHEMA="unknown"
APPLICATION_ID="unknown"
DB_TARGET_FILE=""
static="false"
aop="false"
if [[ "$SOURCE_FILE" == *"db/${DATA_SCHEMA}"* ]]; then
  TARGET_SCHEMA=${DATA_SCHEMA}
elif [[ "$SOURCE_FILE" == *"db/${LOGIC_SCHEMA}"* ]]; then
  TARGET_SCHEMA=${LOGIC_SCHEMA}
elif [[ "$SOURCE_FILE" == *"db/${APP_SCHEMA}"* ]]; then
  TARGET_SCHEMA=${APP_SCHEMA}
elif [[ "$SOURCE_FILE" == *"static/f"* ]]; then
  TARGET_SCHEMA=${APP_SCHEMA}

  # ermitteln der ApplikationsID
  IFS=/ read -a arr <<< "${SOURCE_FILE}"

  for i in "${arr[@]}"
  do
    if [[ $static == "true" && $i == "f"* ]]; then
      APPLICATION_ID=${i/"f"/}
      break
    fi

    if [ $i=="static" ]; then
      static="true"
    fi

  done

  DB_TARGET_FILE=${SOURCE_FILE/"static/f$APPLICATION_ID/src/"/}
elif [[ "$SOURCE_FILE" == *"reports/"*".docx" ]]; then
  TARGET_SCHEMA=${LOGIC_SCHEMA}
  aop="true"
else
  echo
  echo_red "ERROR: unknown path: ${SOURCE_FILE} !!!"
  echo "---"
  exit 1
fi

export NLS_LANG="GERMAN_GERMANY.AL32UTF8"
export NLS_DATE_FORMAT="DD.MM.YYYY HH24:MI:SS"
#chcp 65001

if [ $USE_PROXY == "FALSE" ]
then
  CONNECTION=$DB_APP_USER/$DB_APP_PWD@$DB_TNS
else
  CONNECTION=$DB_APP_USER[$TARGET_SCHEMA]/$DB_APP_PWD@$DB_TNS
fi
echo -e "${BYELLOW}Connection:${NC}  ${WHITE}${DB_TNS}${NC}"
echo -e "${BYELLOW}Schema:${NC}      ${WHITE}$DB_APP_USER[$TARGET_SCHEMA]${NC}"
echo -e "${BYELLOW}Sourcefile:${NC}  ${WHITE}${SOURCE_FILE}${NC}"



if [ "$static" == "true" ]; then
echo -e "${BYELLOW}Application:${NC} ${WHITE}${APPLICATION_ID}${NC}"

  if [ $EXTENSION == "css" ]
  then
    uglifycss --max-line-len 500 ${SOURCE_FILE} > ${SOURCE_FILE_MINIFIED}
    base64 ${SOURCE_FILE_MINIFIED} > ${SOURCE_FILE_MINIFIED}.txt
  fi

  if [ $EXTENSION == "js" ]
  then
    terser  ${SOURCE_FILE} --compress --mangle --output ${SOURCE_FILE_MINIFIED}
    base64 ${SOURCE_FILE_MINIFIED} > ${SOURCE_FILE_MINIFIED}.txt
  fi


  base64 ${SOURCE_FILE} > ${SOURCE_FILE}.txt

  OUTPUT="${SOURCE_FILE}.sql"


  echo -e " ${BLUE}... uploading ${SOURCE_FILE} to application ${APPLICATION_ID}${NC}"

  echo "set serveroutput on"> $OUTPUT

  echo "declare" >> $OUTPUT
  echo "  v_app_id         varchar2(200)  := '${APPLICATION_ID}'; " >> $OUTPUT
  echo "  v_file_name      varchar2(2000) := '${DB_TARGET_FILE}'; " >> $OUTPUT
  echo "  v_application_id apex_applications.application_id%type;" >> $OUTPUT
  echo "  v_workspace_id   apex_applications.workspace_id%type;" >> $OUTPUT
  echo "  v_mime_type      varchar2(2000);" >> $OUTPUT
  echo "  v_mime_type_min  varchar2(2000);" >> $OUTPUT
  echo "  v_b64            clob;" >> $OUTPUT
  echo "  v_bin            blob;" >> $OUTPUT
  echo "  v_b64_min        clob;" >> $OUTPUT
  echo "  v_bin_min        blob;" >> $OUTPUT
  echo "  v_b64_ie         clob;" >> $OUTPUT
  echo "  v_bin_ie         blob;" >> $OUTPUT
  echo "  v_b64_ie_min     clob;" >> $OUTPUT
  echo "  v_bin_ie_min     blob;" >> $OUTPUT
  echo "  gc_red           varchar2(7) := chr(27) || '[31m';" >> $OUTPUT
  echo "  gc_green         varchar2(7) := chr(27) || '[32m';" >> $OUTPUT
  echo "  gc_yellow        varchar2(7) := chr(27) || '[33m';" >> $OUTPUT
  echo "  gc_blue          varchar2(7) := chr(27) || '[34m';" >> $OUTPUT
  echo "  gc_cyan          varchar2(7) := chr(27) || '[36m';" >> $OUTPUT
  echo "  gc_reset         varchar2(7) := chr(27) || '[0m';" >> $OUTPUT

  echo "  cursor c_mime_types (p_file_name in varchar2) is" >> $OUTPUT
  echo "  select mime_type" >> $OUTPUT
  echo "    from xmltable (" >> $OUTPUT
  echo "            xmlnamespaces (" >> $OUTPUT
  echo "                  default 'http://xmlns.oracle.com/xdb/xdbconfig.xsd')," >> $OUTPUT
  echo "                          '//mime-mappings/mime-mapping' " >> $OUTPUT
  echo "                  passing xdb.dbms_xdb.cfg_get()" >> $OUTPUT
  echo "              columns" >> $OUTPUT
  echo "                extension varchar2(50) path 'extension'," >> $OUTPUT
  echo "                mime_type varchar2(100) path 'mime-type' " >> $OUTPUT
  echo "           )" >> $OUTPUT
  echo "     where lower(extension) = lower(substr(p_file_name, instr(p_file_name, '.', -1) + 1));" >> $OUTPUT

  echo "begin" >> $OUTPUT
  echo  >> $OUTPUT
  echo "  select application_id, workspace_id" >> $OUTPUT
  echo "    into v_application_id, v_workspace_id" >> $OUTPUT
  echo "    from apex_applications" >> $OUTPUT
  echo "   where to_char(application_id) = v_app_id or upper(alias) = upper(v_app_id);" >> $OUTPUT
  echo  >> $OUTPUT
  echo "  apex_util.set_security_group_id (p_security_group_id => v_workspace_id);" >> $OUTPUT
  echo >> $OUTPUT
  echo "  execute immediate 'alter session set current_schema=' || apex_application.g_flow_schema_owner;" >> $OUTPUT
  echo >> $OUTPUT

  ## File itself
  echo  >> $OUTPUT
  echo "  dbms_lob.createtemporary(v_b64, true, dbms_lob.session);" >> $OUTPUT
  echo >> $OUTPUT

  ## Default File
  while IFS= read -r line
  do
    echo "  dbms_lob.append(v_b64, '$line');" >> $OUTPUT
  done < "$SOURCE_FILE.txt"
  echo  >> $OUTPUT
  echo "  v_bin := apex_web_service.clobbase642blob(v_b64);" >> $OUTPUT
  echo >> $OUTPUT
  echo "  for i in c_mime_types (p_file_name => v_file_name) loop" >> $OUTPUT
  echo "    v_mime_type := i.mime_type;" >> $OUTPUT
  echo "  end loop;" >> $OUTPUT
  echo >> $OUTPUT

  echo "  wwv_flow_api.create_app_static_file (p_flow_id      => v_application_id," >> $OUTPUT
  echo "                                       p_file_name    => v_file_name," >> $OUTPUT
  echo "                                       p_mime_type    => nvl(v_mime_type, 'application/octet-stream')," >> $OUTPUT
  echo "                                       p_file_charset => 'utf-8'," >> $OUTPUT
  echo "                                       p_file_content => v_bin);" >> $OUTPUT
  echo >> $OUTPUT
  echo "  dbms_output.put_line(gc_green||' ... File uploaded as: ' || v_file_name||gc_reset);" >> $OUTPUT
  echo  >> $OUTPUT
  echo  >> $OUTPUT
  echo  >> $OUTPUT

  ## Minified CSS/JS
  if [[ $EXTENSION == "css" || $EXTENSION == "js" ]]
  then
    echo "  dbms_lob.createtemporary(v_b64_min, true, dbms_lob.session);" >> $OUTPUT
    echo >> $OUTPUT

    while IFS= read -r line
    do
      echo "  dbms_lob.append(v_b64_min, '$line');" >> $OUTPUT
    done < "$SOURCE_FILE_MINIFIED.txt"
    echo  >> $OUTPUT

    echo "  v_bin_min := apex_web_service.clobbase642blob(v_b64_min);" >> $OUTPUT
    echo >> $OUTPUT

    echo "  for i in c_mime_types (p_file_name => replace(v_file_name, '.$EXTENSION', '.min.$EXTENSION')) loop" >> $OUTPUT
    echo "    v_mime_type_min := i.mime_type;" >> $OUTPUT
    echo "  end loop;" >> $OUTPUT
    echo >> $OUTPUT
    echo "  wwv_flow_api.create_app_static_file (p_flow_id      => v_application_id," >> $OUTPUT
    echo "                                       p_file_name    => replace(v_file_name, '.$EXTENSION', '.min.$EXTENSION')," >> $OUTPUT
    echo "                                       p_mime_type    => nvl(v_mime_type_min, 'application/octet-stream')," >> $OUTPUT
    echo "                                       p_file_charset => 'utf-8'," >> $OUTPUT
    echo "                                       p_file_content => v_bin_min);" >> $OUTPUT
    echo >> $OUTPUT
    echo "  dbms_output.put_line(gc_green||' ... File uploaded as: ' || replace(v_file_name, '.$EXTENSION', '.min.$EXTENSION')||gc_reset);" >> $OUTPUT
  fi


  if [[ $EXTENSION == "js" ]]
  then
    ## babel
    npx babel ${SOURCE_FILE} --out-file ${SOURCE_FILE_IE} --presets /c/Users/$(whoami)/AppData/Roaming/npm/node_modules/@babel/preset-env
    terser  ${SOURCE_FILE_IE} --compress --mangle --output ${SOURCE_FILE_IE_MINIFIED}
    base64 ${SOURCE_FILE_IE} > ${SOURCE_FILE_IE}.txt
    base64 ${SOURCE_FILE_IE_MINIFIED} > ${SOURCE_FILE_IE_MINIFIED}.txt

    echo "  dbms_lob.createtemporary(v_b64_ie, true, dbms_lob.session);" >> $OUTPUT
    echo >> $OUTPUT

    while IFS= read -r line
    do
      echo "  dbms_lob.append(v_b64_ie, '$line');" >> $OUTPUT
    done < "$SOURCE_FILE_IE.txt"
    echo  >> $OUTPUT

    echo "  v_bin_ie := apex_web_service.clobbase642blob(v_b64_ie);" >> $OUTPUT
    echo >> $OUTPUT

    echo "  for i in c_mime_types (p_file_name => replace(v_file_name, '.$EXTENSION', '.IE.$EXTENSION')) loop" >> $OUTPUT
    echo "    v_mime_type_min := i.mime_type;" >> $OUTPUT
    echo "  end loop;" >> $OUTPUT
    echo >> $OUTPUT
    echo "  wwv_flow_api.create_app_static_file (p_flow_id      => v_application_id," >> $OUTPUT
    echo "                                       p_file_name    => replace(v_file_name, '.$EXTENSION', '.IE.$EXTENSION')," >> $OUTPUT
    echo "                                       p_mime_type    => nvl(v_mime_type_min, 'application/octet-stream')," >> $OUTPUT
    echo "                                       p_file_charset => 'utf-8'," >> $OUTPUT
    echo "                                       p_file_content => v_bin_ie);" >> $OUTPUT
    echo >> $OUTPUT
    echo "  dbms_output.put_line(gc_green||' ... File uploaded as: ' || replace(v_file_name, '.$EXTENSION', '.IE.$EXTENSION')||gc_reset);" >> $OUTPUT

    ##### MIN #####
    echo "  dbms_lob.createtemporary(v_b64_ie_min, true, dbms_lob.session);" >> $OUTPUT
    echo >> $OUTPUT

    while IFS= read -r line
    do
      echo "  dbms_lob.append(v_b64_ie_min, '$line');" >> $OUTPUT
    done < "$SOURCE_FILE_IE_MINIFIED.txt"
    echo  >> $OUTPUT

    echo "  v_bin_ie_min := apex_web_service.clobbase642blob(v_b64_ie_min);" >> $OUTPUT
    echo >> $OUTPUT

    echo "  for i in c_mime_types (p_file_name => replace(v_file_name, '.$EXTENSION', '.IE.min.$EXTENSION')) loop" >> $OUTPUT
    echo "    v_mime_type_min := i.mime_type;" >> $OUTPUT
    echo "  end loop;" >> $OUTPUT
    echo >> $OUTPUT
    echo "  wwv_flow_api.create_app_static_file (p_flow_id      => v_application_id," >> $OUTPUT
    echo "                                       p_file_name    => replace(v_file_name, '.$EXTENSION', '.IE.min.$EXTENSION')," >> $OUTPUT
    echo "                                       p_mime_type    => nvl(v_mime_type_min, 'application/octet-stream')," >> $OUTPUT
    echo "                                       p_file_charset => 'utf-8'," >> $OUTPUT
    echo "                                       p_file_content => v_bin_ie_min);" >> $OUTPUT
    echo >> $OUTPUT
    echo "  dbms_output.put_line(gc_green||' ... File uploaded as: ' || replace(v_file_name, '.$EXTENSION', '.IE.min.$EXTENSION')||gc_reset);" >> $OUTPUT

  fi #babel

  echo >> $OUTPUT
  echo "  commit;" >> $OUTPUT
  echo "end;" >> $OUTPUT
  echo "/" >> $OUTPUT

  echo -e "${GREEN}$(date '+%d.%m.%Y %H:%M:%S') >> start uploading${NC}"

  sqlplus -s -l $CONNECTION <<!
    @${OUTPUT}
    exit
!

  [ ! -d ${INPATH/\/src\//\/dist\/} ] && mkdir -p ${INPATH/\/src\//\/dist\/}

  mv ${OUTPUT} ${OUTPUT/\/src\//\/dist\/}
  mv ${SOURCE_FILE}.txt ${SOURCE_FILE/\/src\//\/dist\/}.txt


  ## Minified CSS/JS
  if [[ $EXTENSION == "css" || $EXTENSION == "js" ]]
  then
    mv ${SOURCE_FILE_MINIFIED} ${SOURCE_FILE_MINIFIED/\/src\//\/dist\/}
    mv ${SOURCE_FILE_MINIFIED}.txt ${SOURCE_FILE_MINIFIED/\/src\//\/dist\/}.txt
  fi

  if [[ $EXTENSION == "js" ]]
  then
    mv ${SOURCE_FILE_IE} ${SOURCE_FILE_IE/\/src\//\/dist\/}
    mv ${SOURCE_FILE_IE}.txt ${SOURCE_FILE_IE/\/src\//\/dist\/}.txt
    mv ${SOURCE_FILE_IE_MINIFIED} ${SOURCE_FILE_IE_MINIFIED/\/src\//\/dist\/}
    mv ${SOURCE_FILE_IE_MINIFIED}.txt ${SOURCE_FILE_IE_MINIFIED/\/src\//\/dist\/}.txt
  fi

  cp ${SOURCE_FILE} ${SOURCE_FILE/\/src\//\/dist\/}

  echo -e "${GREEN}$(date '+%d.%m.%Y %H:%M:%S') >> uploading done${NC}"
elif [ "$aop" == "true" ]; then
  base64 ${SOURCE_FILE} > ${SOURCE_FILE}.txt
  OUTPUT="${SOURCE_FILE}.sql"

  echo -e " ${BLUE}... uploading ${SOURCE_FILE} to table dokumenttypen${NC}"

  echo "set serveroutput on"> $OUTPUT
  echo "declare" >> $OUTPUT
  echo "  v_b64         clob;" >> $OUTPUT
  echo "  v_bin         blob;" >> $OUTPUT
  echo "  v_dkt_typ     v_dokumenttypen.dkt_typ%type;" >> $OUTPUT
  echo "  gc_red           varchar2(7) := chr(27) || '[31m';" >> $OUTPUT
  echo "  gc_green         varchar2(7) := chr(27) || '[32m';" >> $OUTPUT
  echo "  gc_yellow        varchar2(7) := chr(27) || '[33m';" >> $OUTPUT
  echo "  gc_blue          varchar2(7) := chr(27) || '[34m';" >> $OUTPUT
  echo "  gc_cyan          varchar2(7) := chr(27) || '[36m';" >> $OUTPUT
  echo "  gc_reset         varchar2(7) := chr(27) || '[0m';" >> $OUTPUT
  echo "begin" >> $OUTPUT
  echo "  dbms_lob.createtemporary(v_b64, true, dbms_lob.session);" >> $OUTPUT
  echo  >> $OUTPUT
  while IFS= read -r line
  do
    echo "  dbms_lob.append(v_b64, '$line');" >> $OUTPUT
  done < "${SOURCE_FILE}.txt"

  echo >> $OUTPUT
  echo "  v_bin := apex_web_service.clobbase642blob(v_b64);" >> $OUTPUT
  echo >> $OUTPUT
  echo "  v_dkt_typ := substr('$BASEFL', instr('$BASEFL', '_', 1, 1)+1);" >> $OUTPUT
  echo "  v_dkt_typ := substr(v_dkt_typ, 1, instr(v_dkt_typ, '.', 1, 1)-1);" >> $OUTPUT
  echo "  update v_dokumenttypen" >> $OUTPUT
  echo "     set dkt_template = v_bin" >> $OUTPUT
  echo "   where dkt_typ = upper(v_dkt_typ);" >> $OUTPUT
  echo >> $OUTPUT
  echo "  commit;" >> $OUTPUT
  echo "  dbms_output.put_line(gc_green||' ... Document uploaded to type: ' || upper(v_dkt_typ) ||gc_reset);" >> $OUTPUT
  echo "end;" >> $OUTPUT
  echo "/" >> $OUTPUT

  sqlplus -s -l $CONNECTION <<!
    @${OUTPUT}
    exit
!

  init="created"
  initcolor=${GREEN}
  post="created"
  postcolor=${GREEN}

  if [ -f "db/${PROJECT}_logic/dml/post/update_${BASEFL}.sql" ]
  then
    post="replaced"
    postcolor=${BYELLOW}
  fi

  if [ -f "db/${PROJECT}_logic/dml/init/update_${BASEFL}.sql" ]
  then
    init="replaced"
    initcolor=${BYELLOW}
  fi


  cp ${OUTPUT} db/${PROJECT}_logic/dml/post/"update_${BASEFL}.sql"
  cp ${OUTPUT} db/${PROJECT}_logic/dml/init/"update_${BASEFL}.sql"

  rm ${SOURCE_FILE}.txt
  rm ${OUTPUT}

  echo -e "${postcolor} File db/${PROJECT}_logic/dml/post/update_${BASEFL}.sql $post ${NC}"
  echo -e "${initcolor} File db/${PROJECT}_logic/dml/init/update_${BASEFL}.sql $init ${NC}"
else

  sqlplus -s -l $CONNECTION <<!
set linesize 2000
set tab off
set serveroutput on
set scan off
set define off
set pagesize 9999
set linesize 9999
set trim on

COLUMN MY_USER FORMAT A20
COLUMN DB FORMAT A20
COLUMN NOW FORMAT A35
Prompt
Prompt Show the details of the connection for confirmation
select user as MY_USER
       ,ora_database_name as DB
       ,systimestamp as NOW
from dual;
COLUMN MY_USER CLEAR
COLUMN DB CLEAR
COLUMN NOW CLEAR

set heading off

Rem Run the Sublime File
@"$SOURCE_FILE"

Rem show errors for easy correction
Rem prompt Errors
set pagesize 9999
set linesize 9999
set heading off
set trim on

select user_errors
  from (
            select chr(27) || '[31m' || lower(attribute) -- error or warning
              || ' '
              || line || '/' || position -- line and column
              || ' '
              || lower(name) -- file name
              || case -- file extension
                when type = 'PACKAGE' then '.pks'
                when type = 'PACKAGE BODY' then '.pkb'
                else '.sql'
              end
              || ' '
              || replace(text, chr(10), ' ') -- remove line breaks from error text
              || chr(27) || '[0m'
              as user_errors
            from user_errors
            where attribute in ('ERROR', 'WARNING')
            order by type, name, line, position)
 union
select chr(27) || '[32m' || '$(date '+%d.%m.%Y %H:%M:%S') >> Alles OK' || chr(27) || '[0m'
  from dual
 where not exists (select 1
                     from user_errors
                    where attribute in ('ERROR', 'WARNING') ) ;
!


fi
echo "---"

