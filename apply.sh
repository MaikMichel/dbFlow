#!/bin/bash
echo "Your script args ($#) are: $@"

usage() {
  echo -e "${BYELLOW}.dbFlow/apply.sh${NC} - applies the given build to target database from"
  echo -e "                   depot path, defined in environment. "
  echo ""
  echo -e "${BYELLOW}Usage:${NC}"
  echo -e "  $0 --init --version <label>"
  echo -e "  $0 --patch --version <label> [--noextract] [--redolog <old-logfile>]"
  echo
    echo -e "${BYELLOW}Options:${NC}"
  echo -e "  -h | --help             - Show this screen"
  echo -e "  -d | --debug            - Show additionaly output messages"
  echo -e "  -i | --init             - Flag to install a full installable artifact "
  echo -e "                            this will delete all objects in target schemas upon install"
  echo -e "  -p | --patch            - Flag to install an update/patch as artifact "
  echo -e "                            This will apply on top of the target schemas and consists"
  echo -e "                            of the difference defined during build"
  echo -e "  -v | --version <label>  - Required label of version this artifact represents"
  echo -e "  -n | --noextract        - Optional do not move and extract artifact from depot "
  echo -e "                            Can be used to extract files manually or use a allready extracted build"
  echo -e "  -r | --redolog          - Optional to redo an installation and skip installation-step allready run"
  echo ""
 	echo -e "${BYELLOW}Examples:${NC}"
  echo -e "  $0 --init --version 1.0.0"
  echo -e "  $0 --patch --version 1.1.0"
  echo -e "  $0 --patch --version 1.1.0 --noextract --redolog ../depot/master/old_logfile.log"
  echo
  exit 1
}
# get required functions and vars
source ./.dbFlow/lib.sh

# set project-settings from build.env if exists
if [[ -e ./build.env ]]; then
  source ./build.env
fi

# set target-env settings from file if exists
if [[ -e ./apply.env ]]; then
  source ./apply.env
fi

# get unavalable text
if [[ -e ./apex/maintence.html ]]; then
  maintence=`cat ./apex/maintence.html`
else
  maintence=`cat .dbFlow/maintence.html`
fi
maintence="<span />${maintence}"

# choose CLI to call
SQLCLI=${SQLCLI:-sqlplus}

basepath=$(pwd)
runfile=""

function check_vars() {
  # validate parameters
  do_exit="NO"

  if [[ -z ${DEPOT_PATH:-} ]]; then
    echo_error "Depotpath not defined"
    do_exit="YES"
  fi

  if [[ -z ${STAGE:-} ]]; then
    echo_error  "Stage not defined"
    do_exit="YES"
  fi

  if [[ -z ${DB_APP_USER:-} ]]; then
    echo_error "App-User not defined"
    do_exit="YES"
  fi

  if [[ -z $DB_TNS ]]; then
    echo_error "TNS not defined"
    do_exit="YES"
  fi

  if [[ -d $DEPOT_PATH/$STAGE ]]; then
    install_source_path=${basepath}/$DEPOT_PATH/$STAGE
  else
    echo_error "Targetstage $STAGE inside $DEPOT_PATH is unknown"
    do_exit="YES"
  fi

  # get distinct values of array
  ALL_SCHEMAS=( ${DATA_SCHEMA} ${LOGIC_SCHEMA} ${APP_SCHEMA} )
  SCHEMAS=($(printf "%s\n" "${ALL_SCHEMAS[@]}" | sort -u))
  # if length is equal than ALL_SCHEMAS, otherwise distinct
  if [[ ${#SCHEMAS[@]} == ${#ALL_SCHEMAS[@]} ]]; then
    SCHEMAS=(${ALL_SCHEMAS[@]})
  fi


  ####
  if [[ ${do_exit} == "YES" ]]; then
    echo_warning "aborting"
    exit 1;
  fi

}

function check_params() {
  ! getopt --test > /dev/null
  if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
      echo_fatal 'I’m sorry, `getopt --test` failed in this environment.'
      exit 1
  fi

  OPTIONS=dhipv:nr:
  LONGOPTS=debug,help,init,patch,version:,noextract,redolog:

  # -regarding ! and PIPESTATUS see above
  # -temporarily store output to be able to check for errors
  # -activate quoting/enhanced mode (e.g. by writing out “--options”)
  # -pass arguments only via   -- "$@"   to separate them correctly
  ! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      # e.g. return value is 1
      #  then getopt has complained about wrong arguments to stdout
      exit 2
  fi

  # read getopt’s output this way to handle the quoting right:
  eval set -- "$PARSED"

  debug="n" help="h" init="n" patch="n" version="-" noextract="n"  redolog=""

  # now enjoy the options in order and nicely split until we see --
  while true; do
      case "$1" in
          -d|--debug)
              d=y
              shift
              ;;
          -h|--help)
              h=y
              shift
              ;;
          -i|--init)
              i=y
              shift
              ;;
          -p|--patch)
              p=y
              shift
              ;;
          -v|--version)
              version="$2"
              shift 2
              ;;
          -n|--noextract)
              noextract=y
              shift
              ;;
          -r|--redolog)
              redolog="$2"
              shift 2
              ;;
          --)
              shift
              break
              ;;
          *)
              echo_fatal "Programming error $1"
              exit 3
              ;;
      esac
  done

  # handle non-option arguments
  # if [[ $# -ne 1 ]]; then
  #     echo "$0: A single input file is required."
  #     exit 4
  # fi

  # help first
  if [[ -n $h ]] && [[ $h == "y" ]]; then
    usage
  fi

  # Rule 1: init or patch
  if [[ -z $i ]] && [[ -z $p ]]; then
    echo_error "Missing apply mode, init or patch using flags -i or -p"
    echo_error "type $0 --help for more informations"
    exit 1
  fi

  if [[ $i == "y" ]] && [[ $p == "y" ]]; then
    echo_error "Build mode can only be init or patch, not both"
    echo_error "type $0 --help for more informations"
    exit 1
  fi

  # Rule 2: we always need a version
  if [[ -z $version ]] || [[ $version == "-" ]]; then
    echo_error "Missing version, use flag -v x.x.x"
    echo_error "type $0 --help for more informations"
    exit 1
  fi

  # now check dependent params
  if [[ $i == "y" ]]; then
    mode="init"
  elif [[ $p == "y" ]]; then
    mode="patch"
  fi

  # now check dependent params
  if [[ $noextract == "y" ]]; then
    must_extract="FALSE"
  else
    must_extract="TRUE"
  fi

  oldlogfile=$redolog

  # Defing some vars
  app_install_file=apex_files_${version}.lst
  rest_install_file=rest_${mode}_${version}.sql
  remove_old_files=remove_files_${version}.lst

  install_target_path=.
  install_source_file=$install_source_path/${mode}_${version}.tar.gz
  install_target_file=$install_target_path/${mode}_${version}.tar.gz

  MDATE=`date "+%Y%m%d%H%M%S"`
  log_file="${MDATE}_dpl_${mode}_${version}.log"

  touch $log_file
  full_log_file="$( cd "$( dirname "${log_file}" )" >/dev/null 2>&1 && pwd )/${log_file}"
}



print_info()
{
  echo -e "Installing    ${BWHITE}${mode} ${version}${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "mode:         ${BWHITE}$mode${NC}" | write_log
  echo -e "version:      ${BWHITE}${version}${NC}" | write_log
  echo -e "log_file:     ${BWHITE}$log_file${NC}" | write_log
  echo -e "extract:      ${BWHITE}$must_extract${NC}" | write_log
  if [[ $oldlogfile != "" ]]; then
    echo -e "redolog:      ${BWHITE}$oldlogfile${NC}" | write_log
  fi
  echo -e "----------------------------------------------------------" | write_log
  echo -e "project:      ${BWHITE}${PROJECT}${NC}" | write_log
  echo -e "app_schema:   ${BWHITE}${APP_SCHEMA}${NC}" | write_log
  echo -e "data_schema:  ${BWHITE}${DATA_SCHEMA}${NC}" | write_log
  echo -e "logic_schema: ${BWHITE}${LOGIC_SCHEMA}${NC}" | write_log
  echo -e "workspace:    ${BWHITE}${WORKSPACE}${NC}" | write_log
  echo -e "schemas:      ${BWHITE}${SCHEMAS[@]}${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "stage:        ${BWHITE}${STAGE}${NC}" | write_log
  echo -e "depot:        ${BWHITE}${DEPOT_PATH}${NC}" | write_log
  echo -e "app_offset:   ${BWHITE}${APP_OFFSET}${NC}" | write_log
  echo -e "db_app_user:  ${BWHITE}${DB_APP_USER}${NC}" | write_log
  echo -e "db_tns:       ${BWHITE}${DB_TNS}${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e | write_log
}


extract_patchfile()
{
  if [[ $must_extract == "TRUE" ]]; then
    # check if patch exists
    if [[ -e $install_source_file ]]; then
      echo "$install_source_file exists" | write_log

      # copy patch to _installed
      mv $install_source_file $install_target_path/
    else
      if [[ -e $install_target_file ]]; then
        echo "$install_target_file allready copied" | write_log
      else
        echo_error "$install_target_file not found, nothing to install" | write_log $failure
        manage_result "failure"
      fi
    fi

    # extract file
    echo "extracting file $install_target_file" | write_log
    tar -zxf $install_target_file
  else
    echo "artifact will not be extracted from depot" | write_log
  fi
}

prepare_redo(){
  if [[ -f ${oldlogfile} ]]; then
    redo_file="redo_${MDATE}_${mode}_${version}.log"
    grep '^<<< ' ${oldlogfile} > ${redo_file}
    sed -i 's/^<<< //' ${redo_file}

    # backup install files
    for schema in "${SCHEMAS[@]}"
    do
      db_install_file=./db/$schema/${mode}_${schema}_${version}.sql
      if [[ -f $db_install_file ]]; then
        mv ${db_install_file} ${db_install_file}.org
      fi
    done # schema

    declare -A map
    while IFS= read -r line; do
      echo "fetch $line"
      map[$line]=$line
    done < ${redo_file}

    for schema in "${SCHEMAS[@]}"
    do
      old_install_file=./db/$schema/${mode}_${schema}_${version}.sql.org
      db_install_file=./db/$schema/${mode}_${schema}_${version}.sql

      while IFS= read -r line; do
        key=${line/@@/db/$schema/}

        # on macos double bracket lead to failure
        if [ -v map[${key}] ]; then
            line="Prompt skipped redo: $line"
        fi
        echo "$line"
      done < ${old_install_file} > ${db_install_file}
    done # schema

  fi
}

read_db_pass()
{
  if [[ -z "$DB_APP_PWD" ]]; then
    ask4pwd "Enter Password for deployment user ${DB_APP_USER} on ${DB_TNS}: "
    DB_APP_PWD=${pass}
  else
    echo "Password has already been set" | write_log
  fi
}



remove_dropped_files()
{
  echo "Check if any file should be removed ..." | write_log
  if [[ -e $remove_old_files ]]; then
    # loop throug content
    while IFS= read -r line; do
      echo "Removing file $line" | write_log
      rm -f $line
    done < "$remove_old_files"
  else
    echo "No files to remove" | write_log
  fi
}

execute_global_hook_scripts() {
  local entrypath=$1    # pre or post
  local targetschema=""

  echo "checking hook .hooks/${entrypath}" | write_log

  if [[ -d ".hooks/${entrypath}" ]]; then
    for file in $(ls .hooks/${entrypath} | sort )
    do
      if [[ -f .hooks/${entrypath}/${file} ]]; then
        case ${file} in
          *"${DATA_SCHEMA}"*)
            targetschema=${DATA_SCHEMA}
            ;;
          *"${LOGIC_SCHEMA}"*)
            targetschema=${LOGIC_SCHEMA}
            ;;
          *"${APP_SCHEMA}"*)
            targetschema=${APP_SCHEMA}
            ;;
        esac
        runfile=".hooks/${entrypath}/${file}"

        echo "executing hook file ${runfile}" | write_log
        $SQLCLI -S "$(get_connect_string $targetschema)" <<! | tee -a ${full_log_file}
          define VERSION="${version}"
          define MODE="${mode}"

          set define '^'
          set concat on
          set concat .
          set verify off

          Prompt calling file ${runfile}
          @${runfile}
!


        runfile=""
      fi
    done


    if [[ $? -ne 0 ]]; then
      echo "ERROR when executing .hooks/${entrypath}/${file}" | write_log $failure
      manage_result "failure"
    fi
  fi

  ### mode specific

  if [[ -d ".hooks/${entrypath}/${mode}" ]]
  then
    for file in $(ls .hooks/${entrypath}/${mode} | sort )
    do
      if [[ .hooks/${entrypath}/${mode}/${file} ]]; then
        case ${file} in
          *"${DATA_SCHEMA}"*)
            targetschema=${DATA_SCHEMA}
            ;;
          *"${LOGIC_SCHEMA}"*)
            targetschema=${LOGIC_SCHEMA}
            ;;
          *"${APP_SCHEMA}"*)
            targetschema=${APP_SCHEMA}
            ;;
        esac
        runfile=".hooks/${entrypath}/${mode}/${file}"
        echo "executing hook file ${runfile}" | write_log

        $SQLCLI -S "$(get_connect_string $targetschema)" <<! | tee -a ${full_log_file}
          define VERSION="${version}"
          define MODE="${mode}"

          set define '^'
          set concat on
          set concat .
          set verify off

          Prompt calling file ${runfile}
          @${runfile}
!

        runfile=""
      fi
    done


    if [[ $? -ne 0 ]]; then
      echo "ERROR when executing .hooks/${entrypath}/${file}" | write_log $failure
      manage_result "failure"
    fi
  fi
}

clear_db_schemas_on_init() {
  if [[ "${mode}" == "init" ]]; then
    echo "INIT - Mode, Schemas will be cleared" | write_log
    # loop through schemas reverse
    for (( idx=${#SCHEMAS[@]}-1 ; idx>=0 ; idx-- )) ; do
      local schema=${SCHEMAS[idx]}
      # On init mode schema content will be dropped
      echo "DROPING ALL OBJECTS on schema $schema" | write_log
       exit | $SQLCLI -S "$(get_connect_string $schema)" @.dbFlow/lib/drop_all.sql ${full_log_file} ${version} ${mode} | tee -a ${full_log_file}
    done
  fi
}

validate_connections(){
  # loop through schemas
  for schema in "${SCHEMAS[@]}"
  do
    check_connection ${schema}
  done

}

install_db_schemas()
{
  cd ${basepath}
  cd db

  # execute all files in global pre path
  execute_global_hook_scripts "pre"

  echo "Start installing schemas" | write_log
  # loop through schemas
  for schema in "${SCHEMAS[@]}"
  do
    if [[ -d $schema ]]; then
      cd $schema

      # now executing main installation file if exists
      db_install_file=${mode}_${schema}_${version}.sql
      # exists db install file
      if [[ -e $db_install_file ]]; then
        echo "Installing schema $schema to ${DB_APP_USER} on ${DB_TNS}"  | write_log

        # uncomment cleaning scripts specific to this stage/branch ex:--test or --acceptance
        sed -i -E "s:--$STAGE:Prompt uncommented cleanup for stage $STAGE\n:g" $db_install_file

        runfile=$db_install_file
        $SQLCLI -S "$(get_connect_string $schema)" @$db_install_file ${version} ${mode} | tee -a ${full_log_file}
        runfile=""

        if [[ $? -ne 0 ]]; then
          echo "ERROR when executing db/$schema/$db_install_file" | write_log $failure
          manage_result "failure"
        fi

      else
        echo "File db/$schema/$db_install_file does not exist" | write_log
      fi

      cd ..
    fi
  done

  # execute all files in global post path
  execute_global_hook_scripts "post"

  cd ..
}

set_rest_unavailable() {
  cd ${basepath}

  if [[ -d "rest/modules" ]]; then
    cd rest/modules
    for module in *; do
      if [[ -d "$module" ]]; then

        echo "disabling REST module $module ..." | write_log
        $SQLCLI -S "$(get_connect_string $APP_SCHEMA)" <<! | tee -a ${full_log_file}
        set define off;
        set serveroutput on;
        Begin
          ords.publish_module(p_module_name  => '${module}',
                              p_status       => 'NOT_PUBLISHED');
        Exception
          when no_data_found then
            dbms_output.put_line((chr(27) || '[31m') || 'REST Module: ${module} not found!' || (chr(27) || '[0m'));
        End;
/
!
      fi
    done
  else
    echo "Directory rest/modules does not exist" | write_log $warning
  fi

  cd ${basepath}
}


set_rest_available() {
  cd ${basepath}

  if [[ -d "rest/modules" ]]; then
    cd rest/modules
    for module in *; do
      if [[ -d "$module" ]]; then

        echo "enabling REST module $module ..." | write_log
        $SQLCLI -S "$(get_connect_string $APP_SCHEMA)" <<! | tee -a ${full_log_file}
        set define off;
        set serveroutput on;
        Begin
          ords.publish_module(p_module_name  => '${module}',
                              p_status       => 'PUBLISHED');
        Exception
          when no_data_found then
            dbms_output.put_line((chr(27) || '[31m') || 'REST Modul: ${module} not found!' || (chr(27) || '[0m'));
        End;
/
!
      fi
    done
  else
    echo "Directory rest/modules does not exist" | write_log $warning
  fi

  cd ${basepath}
}




set_apps_unavailable() {
  cd ${basepath}

  if [[ -d "apex" ]]; then
    for appid in apex/* ; do
      if [[ -d "$appid" ]]; then

        echo "disabling APEX-App $appid ..." | write_log
        $SQLCLI -S "$(get_connect_string $APP_SCHEMA)" <<! | tee -a ${full_log_file}
        set serveroutput on;
        set escchar @
        set define off;
        Declare
          v_application_id  apex_application_build_options.application_id%type := ${appid/apex\/f} + ${APP_OFFSET};
          v_workspace_id    apex_workspaces.workspace_id%type;
        Begin
          select workspace_id
            into v_workspace_id
            from apex_workspaces
           where workspace = upper('${WORKSPACE}');

          apex_application_install.set_workspace_id(v_workspace_id);
          apex_util.set_security_group_id(p_security_group_id => apex_application_install.get_workspace_id);

          begin
            apex_util.set_application_status(p_application_id     => v_application_id,
                                             p_application_status => 'UNAVAILABLE',
                                             p_unavailable_value  => '${maintence}' );
          exception
            when others then
              if sqlerrm like '%Application not found%' then
                dbms_output.put_line((chr(27) || '[31m') || 'Application: '||upper(v_application_id)||' not found!' || (chr(27) || '[0m'));
              else
                raise;
              end if;
          end;
        Exception
          when no_data_found then
            dbms_output.put_line((chr(27) || '[31m') || 'Workspace: '||upper('${WORKSPACE}')||' not found!' || (chr(27) || '[0m'));
        End;
/
!
      fi
    done
  else
    echo "Directory apex does not exist" | write_log $warning
  fi

}

set_apps_available() {
  cd ${basepath}

  if [[ -d "apex" ]]; then
    for appid in apex/* ; do
      if [[ -d "$appid" ]]; then
        echo "enabling APEX-App $appid ..." | write_log
        $SQLCLI -S "$(get_connect_string $APP_SCHEMA)" <<! | tee -a ${full_log_file}
        set serveroutput on;
        set define off;
        Declare
          v_application_id  apex_application_build_options.application_id%type := ${appid/apex\/f} + ${APP_OFFSET};
          v_workspace_id    apex_workspaces.workspace_id%type;
          l_text            varchar2(100);
        Begin
          select workspace_id
            into v_workspace_id
            from apex_workspaces
           where workspace = upper('${WORKSPACE}');

          apex_application_install.set_workspace_id(v_workspace_id);
          apex_util.set_security_group_id(p_security_group_id => apex_application_install.get_workspace_id);

          begin
            select substr(unavailable_text, 1, 50)
              into l_text
              from apex_applications
             where application_id = v_application_id;

            if (apex_util.get_application_status(p_application_id => v_application_id) = 'UNAVAILABLE' and l_text like '<span />%') then
              apex_util.set_application_status(p_application_id     => v_application_id,
                                               p_application_status => 'AVAILABLE_W_EDIT_LINK');
            end if;
          exception
            when no_data_found then
              dbms_output.put_line((chr(27) || '[31m') || 'Application: '||upper(v_application_id)||' not found!' || (chr(27) || '[0m'));
            when others then
              if sqlerrm like '%Application not found%' then
                dbms_output.put_line((chr(27) || '[31m') || 'Application: '||upper(v_application_id)||' not found!' || (chr(27) || '[0m'));
              else
                raise;
              end if;
          end;
        Exception
          when no_data_found then
            dbms_output.put_line((chr(27) || '[31m') || 'Workspace: '||upper('${WORKSPACE}')||' not found!' || (chr(27) || '[0m'));
        End;
/
!
      fi
    done
  else
    echo "Directory apex does not exist" | write_log $warning
  fi

}

install_apps() {

  cd ${basepath}

  # app install
  # exists app_install_file
  if [[ -e $app_install_file ]]; then
    echo "Installing APEX-Apps ..." | write_log
    # loop throug content
    while IFS= read -r line; do
      if [[ -e $line/install.sql ]]; then
        echo "Installing $line Num: ${line/apex\/f} Workspace: ${WORKSPACE}" | write_log
        cd $line
        $SQLCLI -S "$(get_connect_string $APP_SCHEMA)" <<! | tee -a ${full_log_file}
          define VERSION="${version}"
          define MODE="${mode}"

          set define '^'
          set concat on
          set concat .
          set verify off

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


        if [[ $? -ne 0 ]]; then
          echo "ERROR when executing $line" | write_log $failure
          manage_result "failure"
        fi

        cd ../..
      fi
    done < "$app_install_file"
  else
    echo "File $app_install_file does not exist" | write_log $warning
  fi

  cd ${basepath}
}


# Function to install REST-Services
#######################################

install_rest() {
  cd ${basepath}

  if [[ -d rest ]]; then
    cd rest

    # exists rest_install_file
    if [ -e $rest_install_file ]
    then
      echo "Installing REST-Services ..." | write_log
      $SQLCLI -s "$(get_connect_string $APP_SCHEMA)" <<! | tee -a ${full_log_file}

      define VERSION="${version}"
      define MODE="${mode}"

      set define '^'
      set concat on
      set concat .
      set verify off

      Prompt calling file ${rest_install_file}
      @@${rest_install_file}
!

      if [ $? -ne 0 ]
      then
        echo "ERROR when executing $line" | write_log $failure
        exit 1
      fi
    else
      echo "File $rest_install_file does not exist" | write_log $warning
    fi

  else
    echo "Directory rest does not exist" | write_log
  fi

  cd ${basepath}
}



exec_final_unit_tests()
{
  if [[ -e .dbFlow/lib/execute_tests.sql ]]; then
  echo "Start testing with utplsql" | write_log

    # loop through schemas
    for schema in "${SCHEMAS[@]}"
    do
      echo "Executing unit tests for schema $schema " | write_log
      exit | $SQLCLI -S "$(get_connect_string $schema)" @.dbFlow/lib/execute_tests.sql ${version} ${mode}
      if [[ $? -ne 0 ]]; then
        echo "ERROR when executing .dbFlow/lib/execute_tests.sql" | write_log $failure
        manage_result "failure"
      fi
    done
  fi
}

manage_result()
{
  local target_move=$1
  target_finalize_path=${install_source_path}/${target_move}/${version}

  cd ${basepath}

  # create path if not exists
  [ -d ${target_finalize_path} ] || mkdir -p ${target_finalize_path}

  echo "${mode} ${version} moved to ${target_finalize_path}" | write_log ${target_move}
  echo "Done with ${target_move}" | write_log ${target_move}

  cat ${full_log_file} | sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" > ${full_log_file}.colorless
  rm ${full_log_file}
  mv ${full_log_file}.colorless ${full_log_file}

  # move all
  mv *${version}* ${target_finalize_path}
  [[ -f rest/rest_${mode}_${version}.sql ]] && mv rest/rest_${mode}_${version}.sql ${target_finalize_path}

  # loop through schemas
  for schema in "${SCHEMAS[@]}"
  do

    db_install_file=${mode}_${schema}_${version}.sql
    [[ -f db/$schema/$db_install_file ]] && mv db/$schema/$db_install_file* ${target_finalize_path} | write_log ${target_move}

  done

  # write Info to markdown-table
  deployed_at=`date +"%Y-%m-%d %T"`
  deployed_by=$(whoami)

  version=`printf '%-10s' "V${version}"`
  deployed_at=`printf '%-19s' "$deployed_at"`
  deployed_by=`printf '%-11s' "$deployed_by"`
  result=`printf '%-11s' "$target_move"`

  echo "| $version | $deployed_at | $deployed_by |  $result " >> ${basepath}/version.md

  if [[ $target_move == "success" ]]; then
    exit 0
  else
    exit 1
  fi
}

#################################################################################################
notify() {
    [[ $1 = 0 ]] || echo ❌ EXIT $1
    # you can notify some external services here,
    # ie. Slack webhook, Github commit/PR etc.
    if [[ $1 -gt 2 ]]; then
      if [[ "${runfile}" != "" ]]; then
        echo "ERROR when executing ${runfile}" | write_log $failure
      else
        echo "ERROR in last statement" | write_log $failure
      fi

      manage_result "failure"
    fi

}

trap '(exit 130)' INT
trap '(exit 143)' TERM
trap 'rc=$?; notify $rc; exit $rc' EXIT

# validate and check existence of vars defined in apply.env and build.env
check_vars

# validate params this script was called with
check_params "$@"

# print some global vars to output
print_info

# preparation and validation
extract_patchfile
read_db_pass
validate_connections
prepare_redo

# files to be removed
remove_dropped_files

# now disable all, so that during build noone can do anything
set_apps_unavailable
set_rest_unavailable

# when in init mode, ALL schema objects will be
# dropped
clear_db_schemas_on_init


# execute pre hooks in root folder
execute_global_hook_scripts "pre"

# install product
install_db_schemas
install_apps
install_rest

# execute post hooks in root folder
execute_global_hook_scripts "post"

# now enable all,
set_apps_available
set_rest_available


# final works
manage_result "success"
