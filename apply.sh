#!/bin/bash
# echo "Your script args ($#) are: $@"

usage() {
  echo -e "${BYELLOW}apply [bash4xcl]${NC} - applies the given build to target database"
  echo -e "------------------------------------------------------------------------------"
  echo -e " Looks in defined depot directory for a build-artifact and applies it to "
  echo -e " specified database connection. All build propterties ard define in build.env."
  echo -e " All deployment properties are define in apply.env"
  echo -e " Please do ${PURPLE}NOT${NC} commit any password specific properties to your scm."
  echo
  echo -e "${BWHITE}USAGE${NC}"
  echo -e "\t$0 <MODE>"
  echo
  echo -e "${BWHITE}MODE${NC}"
  echo -e "\tinit <version> [notar]  deploys an initial build with given version label to target database"
  echo -e "\t                        ${PURPLE}all objects in target-schemas will be dropped before install${NC}"
  echo -e "\t                        if [notar] option is passed, no build file is unzipped from depot directory"
  echo
  echo -e "\tpatch <version> [notar] deploys an update/patch build with given version label to target database"
  echo -e "\t                        if [notar] option is passed, no build file is unzipped from depot directory"
  echo
  echo

 	echo -e "${BWHITE}EXAMPLE${NC}"
  echo "  $0 init 1.0.0"
  echo "  $0 init 1.0.0 notar"
  echo "  $0 patch 1.0.1"
  echo "  $0 patch 1.0.1 notar"
  echo
  echo
  exit 1
}
# get required functions and vars
source ./.bash4xcl/lib.sh

# set project-settings from build
source ./build.env

# set target-env settings from file if exists
if [ -e ./apply.env ]
then
  source ./apply.env
fi


#some env settings sqlcl needs
export NLS_LANG="GERMAN_GERMANY.AL32UTF8"
export NLS_DATE_FORMAT="DD.MM.YYYY HH24:MI:SS"
export JAVA_TOOL_OPTIONS="-Duser.language=en -Duser.region=US -Dfile.encoding=UTF-8"
export CUSTOM_JDBC="-XX:+TieredCompilation -XX:TieredStopAtLevel=1 -Xverify:none"
export LANG="de_DE.utf8"
case $(uname | tr '[:upper:]' '[:lower:]') in
mingw64_nt-10*)
  chcp.com 65001
;;
esac


# validate parameters

# at least 2 params are required
if [ $# -lt 2 ]; then
  echo_error "not enough parameters"
  usage
fi

mode=${1:-""}
patch=${2:-""}
must_extract=${3:-""}
basepath=$(pwd)


if [[ ! "$mode" =~ ^(init|patch)$ ]]; then
    echo "unknown mode: $mode"
    usage
fi


if [ -z $DEPOT_PATH ]
then
  echo_error "Depotpath not defined"
  usage
fi

if [ -z $STAGE ]
then
  echo_error  "Stage not defined"
  usage
fi

if [ -z $DB_APP_USER ]
then
  echo "App-User not defined"
  usage
fi

if [ -z $DB_TNS ]
then
  echo "TNS not defined"
  usage
fi


patch_target_path=.

if [ -d $DEPOT_PATH/$STAGE ]
then
  echo "Targetstage used: $STAGE"
  patch_source_path=${basepath}/$DEPOT_PATH/$STAGE
else
  echo "Targetstage $STAGE inside $DEPOT_PATH is unknown"
  exit 1
fi

# Defing some vars
app_install_file=apex_files_${patch}.lst
remove_old_files=remove_files_${patch}.lst

patch_source_file=$patch_source_path/${mode}_${patch}.tar.gz
patch_target_file=$patch_target_path/${mode}_${patch}.tar.gz

MDATE=`date "+%Y%m%d%H%M%S"`
log_file="${MDATE}_${mode}_${patch}.log"

touch $log_file
full_log_file="$( cd "$( dirname "${log_file}" )" >/dev/null 2>&1 && pwd )/${log_file}"


failure="failure"
success="success"
warning="warning"

write_log() {
  local type=${1:-""}
  case "$type" in
    ${failure})
      color=${RED}
      reset=${NC}
      ;;
    ${success})
      color=${GREEN}
      reset=${NC}
      ;;
    ${warning})
      color=${YELLOW}
      reset=${NC}
      ;;
    *)
      color=""
      reset=""
  esac


  while read text
  do
    LOGTIME=`date "+%Y-%m-%d %H:%M:%S"`
    # If log file is not defined, just echo the output
    if [ "$full_log_file" == "" ]; then
      echo -e $LOGTIME": ${color}${text}${reset}";
    else
      echo -e $LOGTIME": ${color}${text}${reset}" | tee -a $full_log_file;
    fi
  done
}


print_info()
{
  echo -e "Installing    ${BWHITE}${mode} ${patch}${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "mode:         ${BWHITE}$mode${NC}" | write_log
  echo -e "version:      ${BWHITE}$patch${NC}" | write_log
  echo -e "log_file:     ${BWHITE}$log_file${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "project:      ${BWHITE}${PROJECT}${NC}" | write_log
  echo -e "app_schema:   ${BWHITE}${APP_SCHEMA}${NC}" | write_log
  echo -e "data_schema:  ${BWHITE}${DATA_SCHEMA}${NC}" | write_log
  echo -e "logic_schema: ${BWHITE}${LOGIC_SCHEMA}${NC}" | write_log
  echo -e "workspace:    ${BWHITE}${WORKSPACE}${NC}" | write_log
  echo -e "schemas:      ${BWHITE}${SCHEMAS}${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "stage:        ${BWHITE}${STAGE}${NC}" | write_log
  echo -e "depot:        ${BWHITE}${DEPOT_PATH}${NC}" | write_log
  echo -e "use_proxy:    ${BWHITE}${USE_PROXY}${NC}" | write_log
  echo -e "app_offset:   ${BWHITE}${APP_OFFSET}${NC}" | write_log
  echo -e "db_app_user:  ${BWHITE}${DB_APP_USER}${NC}" | write_log
  echo -e "db_tns:       ${BWHITE}${DB_TNS}${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e | write_log
}


extract_patchfile()
{
  if [ -z "$must_extract" ]
  then
    # check if patch exists
    if [ -e $patch_source_file ]
    then
      echo "$patch_source_file exists" | write_log

      # copy patch to _installed
      cp $patch_source_file $patch_target_path/
    else
      if [ -e $patch_target_file ]
      then
        echo "$patch_target_file allready copied" | write_log
      else
        echo_error "$patch_target_file not found, nothing to install" | write_log $failure
        manage_result "failure"
      fi
    fi

    # extract file
    echo "extracting file $patch_target_file" | write_log
    tar -zxf $patch_target_file
  else
    if [ $must_extract == "notar" ]
    then
      echo "notar option choosen" | write_log
    else
      echo_error "unknown option notar" | write_log
      manage_result "failure"
    fi
  fi
}


read_db_pass()
{
  if [ -z "$DB_APP_PWD" ]
  then
    ask4pwd "Enter Password for deployment user ${DB_APP_USER} on ${DB_TNS}: "
    exp_pwd=${pass}
  else
    echo "Password has allrady been set" | write_log
  fi
}



remove_dropped_files()
{
  echo "Check if any file should be removed ..." | write_log
  if [ -e $remove_old_files ]
  then
    # loop throug content
    while IFS= read -r line; do
      echo "Removing file $line" | write_log
      rm -f $line
    done < "$remove_old_files"
  else
    echo "No files to remove" | write_log
  fi
}


install_db_schemas()
{
  echo "Start installing schemas" | write_log
  # loop through schemas
  for schema in "${SCHEMAS[@]}"
  do
    db_install_file=${mode}_${schema}_${patch}.sql
    # exists db install file
    if [ -e db/$schema/$db_install_file ]
    then
      # On init mode schema content will be dropped
      if [ "${mode}" == "init" ]; then
        echo "DROPING ALL OBJECTS" | write_log
        exit | $SQLCL -S "$(get_connect_string $schema)" @.bash4xcl/api/drop_all.sql ${full_log_file} ${patch}
      fi

      cd db/$schema
      echo "Installing schema $schema to ${DB_APP_USER} on ${DB_TNS}"  | write_log

      # calling all api/pre files
      if [[ -d api/pre ]]
      then
        echo "EXCEUTING API/PREs" | write_log
        echo "Prompt executing api/pre file" > tmp_api_pre.sql
        echo "set define '^'" >> tmp_api_pre.sql
        echo "set concat on" >> tmp_api_pre.sql
        echo "set concat ." >> tmp_api_pre.sql
        echo "set verify off" >> tmp_api_pre.sql
        echo "define SPOOLFILE = '^1'" >> tmp_api_pre.sql
        echo "define VERSION = '^2'" >> tmp_api_pre.sql
        echo "set timing on;" >> tmp_api_pre.sql
        echo "spool ^SPOOLFILE append;" >> tmp_api_pre.sql
        for file in $(ls api/pre | sort )
        do
          echo "Prompt executing db/$schema/api/pre/${file}" >> tmp_api_pre.sql
          echo "@api/pre/${file} ^SPOOLFILE ^VERSION" >> tmp_api_pre.sql
          echo "" >> tmp_api_pre.sql
        done

        exit | $SQLCL -S "$(get_connect_string $schema)" @tmp_api_pre.sql ${full_log_file} ${patch}


        if [ $? -ne 0 ]
        then
          echo "ERROR when executing db/$schema/tmp_api_pre.sql" | write_log $failure
          cat tmp_api_pre.sql >> ${full_log_file}
          manage_result "failure"
        fi

        rm tmp_api_pre.sql
      fi

      # uncomment cleaning scripts specific to this stage/branch ex:--test or --acceptance
      sed -i -E "s:--$STAGE:Prompt uncommented cleanup for stage $STAGE\n:g" $db_install_file

      $SQLCL -S "$(get_connect_string $schema)" @$db_install_file ${full_log_file} ${patch}
      if [ $? -ne 0 ]
      then
        echo "ERROR when executing db/$schema/$db_install_file" | write_log $failure
        manage_result "failure"
      fi

      # calling all api/post files
      if [[ -d api/post ]]
      then
        echo "EXCEUTING API/POSTs" | write_log
        echo "Prompt executing api/post file" > tmp_api_post.sql
        echo "set define '^'" >> tmp_api_post.sql
        echo "set concat on" >> tmp_api_post.sql
        echo "set concat ." >> tmp_api_post.sql
        echo "set verify off" >> tmp_api_post.sql
        echo "define SPOOLFILE = '^1'" >> tmp_api_post.sql
        echo "define VERSION = '^2'" >> tmp_api_post.sql
        echo "set timing on;" >> tmp_api_post.sql
        echo "spool ^SPOOLFILE append;" >> tmp_api_post.sql
        for file in $(ls api/post | sort )
        do
          echo "Prompt executing db/$schema/api/post/${file}" >> tmp_api_post.sql
          echo "@api/post/${file}" >> tmp_api_post.sql
          echo "" >> tmp_api_post.sql
        done

        exit | $SQLCL -S "$(get_connect_string $schema)" @tmp_api_post.sql ${full_log_file} ${patch}


        if [ $? -ne 0 ]
        then
          echo "ERROR when executing db/$schema/tmp_api_post.sql" | write_log $failure
          cat tmp_api_post.sql >> ${full_log_file}
          manage_result "failure"
        fi

        rm tmp_api_post.sql
      fi


      cd ../..
    else
      echo "File db/$schema/$db_install_file does not exist" | write_log
    fi

  done
}


set_apps_unavailable() {
  # exists app_install_file
  if [ -e $app_install_file ]
  then
    echo "disabling APEX-Apps ..." | write_log
    # loop throug content
    while IFS= read -r line; do
      $SQLCL -S "$(get_connect_string $APP_SCHEMA)" <<!
        set serveroutput on;
        prompt logging to ${log_file}
        set define off;
        spool ${log_file} append;
        Declare
          v_application_id  apex_application_build_options.application_id%type := ${line/apex\/f} + ${APP_OFFSET};
          v_workspace_id	apex_workspaces.workspace_id%type;
        Begin
          select workspace_id
              into v_workspace_id
              from apex_workspaces
            where workspace = upper('${WORKSPACE}');

            apex_application_install.set_workspace_id(v_workspace_id);
            apex_util.set_security_group_id(p_security_group_id => apex_application_install.get_workspace_id);

            apex_util.set_application_status(p_application_id => v_application_id,
                                            p_application_status => 'UNAVAILABLE',
                                            p_unavailable_value => '<h1><center>Wegen Wartungsarbeiten ist die Applikation vor&uuml;bergehend nicht erreichbar</center></h1>' );
        End;
/
!

    done < "$app_install_file"
  else
    echo "File $app_install_file does not exist" | write_log $warning
  fi

}


install_apps() {
  # app install
  # exists app_install_file
  if [ -e $app_install_file ]
  then
    echo "Installing APEX-Apps ..." | write_log
    # loop throug content
    while IFS= read -r line; do
      if [ -e $line/install.sql ]
      then
        echo "Installing $line Num: ${line/apex\/f} Workspace: ${WORKSPACE}" | write_log
        cd $line
        $SQLCL -S "$(get_connect_string $APP_SCHEMA)" <<!
          spool ../../${log_file} append;
          Prompt Workspace: ${WORKSPACE}
          Prompt Application: ${line/apex\/f}
          declare
            v_workspace_id	apex_workspaces.workspace_id%type;
          begin
            select workspace_id
              into v_workspace_id
              from apex_workspaces
            where workspace = upper('${WORKSPACE}');

            apex_application_install.set_workspace_id(v_workspace_id);

            if nvl(${APP_OFFSET}, 0) > 0 then
              apex_application_install.generate_offset;
            end if;

            apex_application_install.set_application_id(${line/apex\/f} + ${APP_OFFSET});
            apex_application_install.set_schema(upper('${APP_SCHEMA}'));
          end;
          /

          @@install.sql
!


        if [ $? -ne 0 ]
        then
          echo "ERROR when executing $line" | write_log
          manage_result "failure"
        fi

        cd ../..
      fi
    done < "$app_install_file"
  else
    echo "File $app_install_file does not exist" | write_log $warning
  fi

}


exec_final_unit_tests()
{
  if [ -e .bash4xcl/api/execute_tests.sql ]
  then
  echo "Start testing with utplsql" | write_log

    # loop through schemas
    for schema in "${SCHEMAS[@]}"
    do
      echo "Executing unit tests for schema $schema " | write_log
      exit | $SQLCL -S "$(get_connect_string $schema)" @.bash4xcl/api/execute_tests.sql ${full_log_file} ${patch}
      if [ $? -ne 0 ]
      then
        echo "ERROR when executing .bash4xcl/api/execute_tests.sql" | write_log $failure
        manage_result "failure"
      fi
    done
  fi
}


manage_result()
{
  local target_move=$1

  target_finalize_path=${patch_source_path}/${target_move}/${patch}

  # create path if not exists
  [ -d ${target_finalize_path} ] || mkdir -p ${target_finalize_path}

  echo "${mode} ${patch} moved to ${target_finalize_path}" | write_log ${target_move}
  echo "Done with ${target_move}" | write_log ${target_move}

  cat ${full_log_file} | sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" > ${full_log_file}.colorless
  rm ${full_log_file}
  mv ${full_log_file}.colorless ${full_log_file}

  # move all
  mv *${patch}* ${target_finalize_path} | write_log ${target_move}

  # loop through schemas
  for schema in "${SCHEMAS[@]}"
  do
    db_install_file=${mode}_${schema}_${patch}.sql
    # exists db install file
    if [ -e db/$schema/$db_install_file ]
    then
      mv db/$schema/$db_install_file ${target_finalize_path} | write_log ${target_move}
    fi
  done


  # write Info to markdown-table
  deployed_at=`date +"%Y-%m-%d %T"`
  deployed_by=$(whoami)

  version=`printf '%-10s' "V$patch"`
  deployed_at=`printf '%-19s' "$deployed_at"`
  deployed_by=`printf '%-11s' "$deployed_by"`
  result=`printf '%-11s' "$target_move"`

  echo "| $version | $deployed_at | $deployed_by |  $result " >> ${basepath}/version.md

  if [ $target_move == "success" ]; then
    exit
  else
    exit 1
  fi
}

#################################################################################################

print_info
extract_patchfile
read_db_pass
set_apps_unavailable
remove_dropped_files

install_db_schemas
install_apps

exec_final_unit_tests
manage_result "success"
