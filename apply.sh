#!/usr/bin/env bash
#echo "Your script args ($#) are: $@"

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

  validate_passes
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

  if [[ ${PROJECT_MODE} == "FLEX" ]]; then
    SCHEMAS=(${DBSCHEMAS[@]})
  else
    # get distinct values of array
    ALL_SCHEMAS=( ${DATA_SCHEMA} ${LOGIC_SCHEMA} ${APP_SCHEMA} )
    SCHEMAS=($(printf "%s\n" "${ALL_SCHEMAS[@]}" | sort -u))

    # if length is equal than ALL_SCHEMAS, otherwise distinct
    if [[ ${#SCHEMAS[@]} == ${#ALL_SCHEMAS[@]} ]]; then
      SCHEMAS=(${ALL_SCHEMAS[@]})
    fi

    # When in Single or Multi Mode, Folders have to name as Schemas
    DBFOLDERS=(${SCHEMAS[@]})
  fi


  ####
  if [[ ${do_exit} == "YES" ]]; then
    echo_warning "aborting"
    exit 1;
  fi

}

function check_params() {
  debug="n" help="h" init="n" patch="n" version="-" noextract="n"  redolog=""

  while getopts_long 'dhipv:nr: debug help init patch version: noextract redolog:' OPTKEY "${@}"; do
      case ${OPTKEY} in
          'd'|'debug')
              d=y
              ;;
          'h'|'help')
              h=y
              ;;
          'i'|'init')
              i=y
              ;;
          'p'|'patch')
              p=y
              ;;
          'v'|'version')
              version="${OPTARG}"
              ;;
          'n'|'noextract')
              noextract=y
              ;;
          'r'|'redolog')
              redolog="${OPTARG}"
              ;;
          '?')
              echo_error "INVALID OPTION -- ${OPTARG}" >&2
              usage
              ;;
          ':')
              echo_error "MISSING ARGUMENT for option -- ${OPTARG}" >&2
              usage
              ;;
          *)
              echo_error "UNIMPLEMENTED OPTION -- ${OPTKEY}" >&2
              usage
              ;;
      esac
  done

  # help first
  if [[ -n $h ]] && [[ $h == "y" ]]; then
    usage
  fi

  # Rule 1: init or patch
  if [[ -z $i ]] && [[ -z $p ]]; then
    echo_error "Missing apply mode, init or patch using flags -i or -p"
    echo_error "type $0 --help for more informations"
    usage
  fi

  if [[ $i == "y" ]] && [[ $p == "y" ]]; then
    echo_error "Build mode can only be init or patch, not both"
    echo_error "type $0 --help for more informations"
    usage
  fi

  # Rule 2: we always need a version
  if [[ -z $version ]] || [[ $version == "-" ]]; then
    echo_error "Missing version, use flag -v x.x.x"
    echo_error "type $0 --help for more informations"
    usage
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
  remove_old_files=remove_files_${version}.lst

  install_target_path=.
  install_source_file=$install_source_path/${mode}_${version}.tar.gz
  install_target_file=$install_target_path/${mode}_${version}.tar.gz

  MDATE=`date "+%Y%m%d%H%M%S"`
  log_file="${MDATE}_dpl_${mode}_${version}.log"

  touch $log_file
  full_log_file="$( cd "$( dirname "${log_file}" )" >/dev/null 2>&1 && pwd )/${log_file}"

  exec &> >(tee -a "$log_file")
}



print_info()
{
  timelog "Installing    ${BWHITE}${mode} ${version}${NC}"
  timelog "----------------------------------------------------------"
  timelog "Mode:         ${BWHITE}$mode${NC}"
  timelog "Version:      ${BWHITE}${version}${NC}"
  timelog "Log File:     ${BWHITE}$log_file${NC}"
  timelog "Extract:      ${BWHITE}$must_extract${NC}"
  if [[ $oldlogfile != "" ]]; then
    timelog "Redolog:      ${BWHITE}$oldlogfile${NC}"
  fi
  timelog "----------------------------------------------------------"
  timelog "Project:             ${BWHITE}${PROJECT}${NC}"
  if [[ ${PROJECT_MODE} != "FLEX" ]]; then
    timelog "Application Schema:  ${BWHITE}${APP_SCHEMA}${NC}"
    if [[ ${PROJECT_MODE} != "SINGLE" ]]; then
      timelog "Data Schema:         ${BWHITE}${DATA_SCHEMA}${NC}"
      timelog "Logic Schema:        ${BWHITE}${LOGIC_SCHEMA}${NC}"
    fi
    timelog "Workspace:           ${BWHITE}${WORKSPACE}${NC}"
  fi
  timelog "Schemas:             ${BWHITE}${SCHEMAS[*]}${NC}"
  if [[ -n ${CHANGELOG_SCHEMA} ]]; then
    timelog "----------------------------------------------------------"
    timelog "Changelog Schema: ${BWHITE}${CHANGELOG_SCHEMA}${NC}"
    timelog "Intent Prefixes:  ${BWHITE}${INTENT_PREFIXES[@]}${NC}"
    timelog "Intent Names:     ${BWHITE}${INTENT_NAMES[@]}${NC}"
    timelog "Intent Else:      ${BWHITE}${INTENT_ELSE}${NC}"
    timelog "Ticket Match:     ${BWHITE}${TICKET_MATCH}${NC}"
    timelog "Ticket URL:       ${BWHITE}${TICKET_URL}${NC}"
  fi

  if [[ -n ${TEAMS_WEBHOOK_URL} ]]; then
    timelog "Teams WebHook:    ${BWHITE}TRUE${NC}"
  fi

  timelog "----------------------------------------------------------"
  timelog "Stage:               ${BWHITE}${STAGE}${NC}"
  timelog "Depot:               ${BWHITE}${DEPOT_PATH}${NC}"
  timelog "Application Offset:  ${BWHITE}${APP_OFFSET}${NC}"
  timelog "Deployment User:     ${BWHITE}${DB_APP_USER}${NC}"
  timelog "DB Connection:       ${BWHITE}${DB_TNS}${NC}"
  timelog "----------------------------------------------------------"
  timelog
}


extract_patchfile()
{
  if [[ $must_extract == "TRUE" ]]; then
    # check if patch exists
    if [[ -e $install_source_file ]]; then
      timelog "$install_source_file exists"

      # copy patch to _installed
      mv $install_source_file $install_target_path/
    else
      if [[ -e $install_target_file ]]; then
        timelog "$install_target_file allready copied"
      else
        timelog "$install_target_file not found, nothing to install" $failure
        manage_result "failure"
      fi
    fi

    # extract file
    timelog "extracting file $install_target_file"
    tar -zxf $install_target_file
  else
    timelog "artifact will not be extracted from depot"
  fi
}

prepare_redo(){
  if [[ -f ${oldlogfile} ]]; then
    timelog "parsing redolog ${oldlogfile}"

    this_os=$(uname)

    redo_file="redo_${MDATE}_${mode}_${version}.log"
    grep '^<<< ' ${oldlogfile} > ${redo_file}
    sed -i 's/^<<< //' ${redo_file}

    # backup install files
    for schema in "${DBFOLDERS[@]}"
    do

      db_install_file=./db/$schema/${mode}_${schema}_${version}.sql
      if [[ -f $db_install_file ]]; then
        mv ${db_install_file} ${db_install_file}.org
      fi
    done # schema

    declare -A map
    while IFS= read -r line; do
      timelog " ... Skipping line $line"
      map[$line]=$line
    done < ${redo_file}

    for schema in "${DBFOLDERS[@]}"
    do
      old_install_file=./db/$schema/${mode}_${schema}_${version}.sql.org
      db_install_file=./db/$schema/${mode}_${schema}_${version}.sql

      while IFS= read -r line; do
        key=${line/@@/db/$schema/}

        if [[ ${this_os} == "Darwin" ]]; then
          # on macos double bracket lead to failure, for now I can't fix that cause I need assoziative array
          if [ -v map[${key}] ]; then
              line="Prompt skipped redo: $line"
          fi
        else
          if [[ -v map[${key}] ]]; then
              line="Prompt skipped redo: $line"
          fi
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
    timelog "Password has already been set"
  fi
}



remove_dropped_files()
{
  timelog "Check if any file should be removed ..."
  if [[ -e $remove_old_files ]]; then
    # loop throug content
    while IFS= read -r line; do
      timelog "Removing file $line"
      rm -f $line
    done < "$remove_old_files"
  else
    timelog "No files to remove"
  fi
}

execute_global_hook_scripts() {
  local entrypath=$1    # pre or post
  local targetschema=""

  timelog "checking hook ${entrypath}"

  if [[ -d "${entrypath}" ]]; then
    for file in $(ls ${entrypath} | sort )
    do
      if [[ -f ${entrypath}/${file} ]]; then
        # determine target schema
        targetschema=$(get_schema_from_file_name ${file})
        runfile="${entrypath}/${file}"

        if [[ ${targetschema} != "_" ]]; then
          timelog "executing hook file ${runfile} in ${targetschema}"
          $SQLCLI -S -L "$(get_connect_string $targetschema)" <<!
            define VERSION="${version}"
            define MODE="${mode}"

            set define '^'
            set concat on
            set concat .
            set verify off

            set timing on
            set trim on
            set linesize 2000
            set sqlblanklines on
            set tab off
            set pagesize 9999
            set trimspool on

            set serveroutput on

            Prompt calling file ${runfile}
            @${runfile}
!

        else
          timelog "no schema found to execute hook file ${runfile} target schema has to be a part of filename" ${warning}
        fi
      fi
    done


    if [[ $? -ne 0 ]]; then
      timelog "ERROR when executing ${entrypath}/${file}" ${failure}
      manage_result "failure"
    fi
  fi
}

clear_db_schemas_on_init() {
  if [[ "${mode}" == "init" ]]; then
    timelog "INIT - Mode, Schemas will be cleared"
    # loop through schemas reverse
    for (( idx=${#SCHEMAS[@]}-1 ; idx>=0 ; idx-- )) ; do
      local schema=${SCHEMAS[idx]}
      # On init mode schema content will be dropped
      timelog "DROPING ALL OBJECTS on schema $schema"
       exit | $SQLCLI -S -L "$(get_connect_string $schema)" @.dbFlow/lib/drop_all.sql ${full_log_file} ${version} ${mode}
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

  # execute all files in global pre path
  execute_global_hook_scripts "db/.hooks/pre"
  execute_global_hook_scripts "db/.hooks/pre/${mode}"

  cd db

  timelog "Start installing schemas"
  # loop through schemas
  for schema in "${DBFOLDERS[@]}"
  do
    if [[ -d $schema ]]; then
      cd $schema

      # now executing main installation file if exists
      db_install_file=${mode}_${schema}_${version}.sql
      # exists db install file
      if [[ -e $db_install_file ]]; then
        timelog "Installing schema $schema to ${DB_APP_USER} on ${DB_TNS}"

        # uncomment cleaning scripts specific to this stage/branch ex:--test or --acceptance
        sed -i -E "s:--$STAGE:Prompt uncommented cleanup for stage $STAGE\n:g" $db_install_file

        runfile=$db_install_file
        $SQLCLI -S -L "$(get_connect_string $schema)" @$db_install_file ${version} ${mode}
        runfile=""

        if [[ $? -ne 0 ]]; then
          timelog "ERROR when executing db/$schema/$db_install_file" ${failure}
          manage_result "failure"
        fi

      else
        timelog "File db/$schema/$db_install_file does not exist"
      fi

      cd ..
    fi
  done

  cd ..


  # execute all files in global post path
  execute_global_hook_scripts "db/.hooks/post"
  execute_global_hook_scripts "db/.hooks/post/${mode}"
}

set_rest_publish_state() {
  cd ${basepath}
  local publish=$1
  if [[ -d "rest" ]]; then
    local appschema=${APP_SCHEMA}

    folders=()
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      for d in $(find rest -maxdepth 1 -mindepth 1 -type d | sort -f)
      do
        folders+=( $(basename $d)/modules )
      done
    else
      folders=( "modules" )
    fi

    for fldr in "${folders[@]}"
    do
      if [[ ${PROJECT_MODE} == "FLEX" ]]; then
        appschema=${fldr/\/modules/}
      fi
      modules=()
      if [[ -d "rest/$fldr" ]]; then
        for mods in $(find rest/$fldr -maxdepth 1 -mindepth 1 -type d)
        do
          mbase=$(basename $mods)
          modules+=( ${mbase} )
        done

        $SQLCLI -S -L "$(get_connect_string ${appschema})" <<!
          set define off;
          set serveroutput on;
          $(
            for element in "${modules[@]}"
            do
              echo "Declare"
              echo "  ex_schema_not_enabled exception;"
              echo "  PRAGMA EXCEPTION_INIT(ex_schema_not_enabled, -20012);"
              echo "Begin"
              echo "  dbms_output.put_line('setting publish state to ${publish} for REST module ${element} for schema ${appschema}...');"
              echo "  ords.publish_module(p_module_name  => '${element}',"
              echo "                      p_status       => '${publish}');"
              echo "Exception"
              echo "  when ex_schema_not_enabled then"
              echo "    dbms_output.put_line((chr(27) || '[31m') || sqlerrm || (chr(27) || '[0m'));"
              echo "  when no_data_found then"
              echo "    dbms_output.put_line((chr(27) || '[31m') || 'REST Modul: ${element} not found!' || (chr(27) || '[0m'));"
              echo "End;"
              echo "/"
            done
          )

!
      fi
    done
  else
    timelog "Directory rest does not exist" $warning
  fi

  cd ${basepath}
}



set_apps_unavailable() {
  cd ${basepath}

  if [[ -d "apex" ]]; then

    depth=1
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=3
    fi

    for d in $(find apex -maxdepth ${depth} -mindepth ${depth} -type d)
    do
      local app_name=$(basename $d)
      local app_id=${app_name/f}

      local workspace=${WORKSPACE}
      local appschema=${APP_SCHEMA}

      if [[ ${PROJECT_MODE} == "FLEX" ]]; then
        workspace=$(basename $(dirname ${d}))
        appschema=$(basename $(dirname $(dirname ${d})))
      fi

      timelog "disabling APEX-App ${app_id} in workspace ${workspace} for schema ${appschema}..."
      $SQLCLI -S -L "$(get_connect_string ${appschema})" <<!
      set serveroutput on;
      set define off;
      Declare
        v_application_id  apex_application_build_options.application_id%type := ${app_id} + ${APP_OFFSET};
        v_workspace_id    apex_workspaces.workspace_id%type;
      Begin
        select workspace_id
          into v_workspace_id
          from apex_workspaces
          where workspace = upper('${workspace}');

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
          dbms_output.put_line((chr(27) || '[31m') || 'Workspace: '||upper('${workspace}')||' not found!' || (chr(27) || '[0m'));
End;
/

!

    done
  else
    timelog "Directory apex does not exist" $warning
  fi

}

set_apps_available() {
  cd ${basepath}

  if [[ -d "apex" ]]; then

    depth=1
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=3
    fi

    for d in $(find apex -maxdepth ${depth} -mindepth ${depth} -type d)
    do
      local app_name=$(basename $d)
      local app_id=${app_name/f}

      local workspace=${WORKSPACE}
      local appschema=${APP_SCHEMA}

      if [[ ${PROJECT_MODE} == "FLEX" ]]; then
        workspace=$(basename $(dirname ${d}))
        appschema=$(basename $(dirname $(dirname ${d})))
      fi


      timelog "enabling APEX-App ${app_id} in workspace ${workspace} for schema ${appschema}..."
      $SQLCLI -S -L "$(get_connect_string $appschema)" <<!
      set serveroutput on;
      set define off;
      Declare
        v_application_id  apex_application_build_options.application_id%type := ${app_id} + ${APP_OFFSET};
        v_workspace_id    apex_workspaces.workspace_id%type;
        l_text            varchar2(100);
      Begin
        select workspace_id
          into v_workspace_id
          from apex_workspaces
          where workspace = upper('${workspace}');

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
          dbms_output.put_line((chr(27) || '[31m') || 'Workspace: '||upper('${workspace}')||' not found!' || (chr(27) || '[0m'));
      End;
/
!

    done
  else
    timelog "Directory apex does not exist" ${warning}
  fi

}

install_apps() {

  cd ${basepath}

  # app install
  # exists app_install_file
  if [[ -e $app_install_file ]]; then
    timelog "Installing APEX-Apps ..."
    # loop throug content
    while IFS= read -r line; do
      if [[ -e $line/install.sql ]]; then
        local app_name=$(basename $line)
        local app_id=${app_name/f}

        local workspace=${WORKSPACE}
        local appschema=${APP_SCHEMA}
        if [[ ${PROJECT_MODE} == "FLEX" ]]; then
          workspace=$(basename $(dirname $line))
          appschema=$(basename $(dirname $(dirname ${line})))
        fi

        timelog "Installing $line Num: ${app_id} Workspace: ${workspace} Schema: $appschema"
        cd $line
        $SQLCLI -S -L "$(get_connect_string $appschema)" <<!
          define VERSION="${version}"
          define MODE="${mode}"

          set define '^'
          set concat on
          set concat .
          set verify off

          Prompt Workspace: ${workspace}
          Prompt Application: ${app_id}
          declare
            v_workspace_id	apex_workspaces.workspace_id%type;
          begin
            select workspace_id
              into v_workspace_id
              from apex_workspaces
            where workspace = upper('${workspace}');

            apex_application_install.set_workspace_id(v_workspace_id);

            if nvl(${APP_OFFSET}, 0) > 0 then
              apex_application_install.generate_offset;
              -- alias must be unique per instance, so when offset is definded
              -- it should be modified. In this case a post hook at root level
              -- has to be used to give it a correct alias
              apex_application_install.set_application_alias('${app_id}_${APP_OFFSET}');
            end if;

            apex_application_install.set_application_id(${app_id} + ${APP_OFFSET});
            apex_application_install.set_schema(upper('${appschema}'));
          Exception
            when no_data_found then
              dbms_output.put_line((chr(27) || '[31m') || 'Workspace: '||upper('${workspace}')||' not found!' || (chr(27) || '[0m'));
          end;
          /

          @@install.sql
!


        if [[ $? -ne 0 ]]; then
          timelog "ERROR when executing $line" $failure
          manage_result "failure"
        fi

        cd ${basepath}
      fi
    done < "$app_install_file"
  else
    timelog "File $app_install_file does not exist" $warning
  fi

  cd ${basepath}
}


# Function to install REST-Services
#######################################

install_rest() {
  cd ${basepath}

  rest_install_file=rest_${mode}_${version}.sql

  if [[ -d rest ]]; then

    depth=0
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=1
    fi

    for d in $(find rest -maxdepth ${depth} -mindepth ${depth} -type d)
    do
      cd ${d}

      if [[ -f ${rest_install_file} ]]; then

        local appschema=${APP_SCHEMA}
        if [[ ${PROJECT_MODE} == "FLEX" ]]; then
          appschema=$(basename ${d})
        fi

        timelog "Installing REST-Services ${d}/${rest_install_file} on Schema $appschema"
        $SQLCLI -S -L "$(get_connect_string $appschema)" <<!

        define VERSION="${version}"
        define MODE="${mode}"

        set define '^'
        set concat on
        set concat .
        set verify off

        Prompt calling file ${instfile}
        @@${rest_install_file}

!


        if [ $? -ne 0 ]
        then
          timelog "ERROR when executing $line" $failure
          exit 1
        fi
      fi

      cd ${basepath}
    done

  else
    timelog "Directory rest does not exist"
  fi

  cd ${basepath}
}


# when changelog is found and changelog template is defined then
# execute template on configured schema apply.env:CHANGELOG_SCHEMA=?
process_changelog() {
  chlfile=changelog_${mode}_${version}.md
  tplfile=reports/changelog/template.sql
  if [[ -f ${chlfile} ]]; then
    timelog "changelog found"

    if [[ -f ${tplfile} ]]; then
      timelog "templatefile found"

      if [[ -n ${CHANGELOG_SCHEMA} ]]; then
        timelog "changelog schema '${CHANGELOG_SCHEMA}' is configured"

        # now gen merged sql file
        create_merged_report_file ${chlfile} ${tplfile} ${chlfile}.sql

        # and run
        $SQLCLI -S -L "$(get_connect_string ${CHANGELOG_SCHEMA})" <<!

          Prompt executing changelog file ${chlfile}.sql
          @${chlfile}.sql

!

        if [ $? -ne 0 ]
        then
          timelog "ERROR when runnin ${chlfile}.sql" $failure
          exit 1
        else
          rm ${chlfile}.sql
        fi
      else
        timelog "changelog schema is NOT configured"
      fi
    else
      timelog "No templatefile found"
    fi
  else
    timelog "No changelog ${chlfile} found"
  fi
}

post_message_to_teams() {
  cd ${basepath}

  local TITLE=$1
  local COLOR=$2
  local TEXT=$3

  if [ -z ${TEAMS_WEBHOOK_URL} ]
  then
    timelog "No webhook_url specified."
  else
    # Convert formating.
    MESSAGE=$( echo ${TEXT} | sed 's/"/\"/g' | sed "s/'/\'/g" )
    JSON="{\"title\": \"${TITLE}\", \"themeColor\": \"${COLOR}\", \"text\": \"${MESSAGE}\" }"

    timelog "Posting to url: ${JSON} "
    # Post to Microsoft Teams.
    curl -H "Content-Type: application/json" -d "${JSON}" "${TEAMS_WEBHOOK_URL}"

  fi
}

process_logs() {
  # remove colorcodes from file
  echo "Processing logs"
  cat ${full_log_file} | sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" > ${full_log_file}.colorless
  rm ${full_log_file}
  mv ${full_log_file}.colorless ${full_log_file}

  # move all logs
  mv *${mode}*${version}* ${target_finalize_path}
}

manage_result() {
  cd ${basepath}

  local target_move=$1
  target_relative_path=${DEPOT_PATH}/${STAGE}/${target_move}/${version}
  target_finalize_path=${install_source_path}/${target_move}/${version}

  # create path if not exists
  [ -d ${target_finalize_path} ] || mkdir -p ${target_finalize_path}

  # notify
  timelog "${mode} ${version} moved to ${target_finalize_path}" ${target_move}
  timelog "Done with ${target_move}" ${target_move}


  # move apex lst
  [[ -f apex_files_${version}.lst ]] && mv apex_files_${version}.lst ${target_finalize_path}
  [[ -f remove_files_${version}.lst ]] && mv remove_files_${version}.lst ${target_finalize_path}

  # move rest files
  depth=1
  if [[ ${PROJECT_MODE} == "FLEX" ]]; then
    depth=2
  fi

  for restfile in $(find rest -maxdepth ${depth} -mindepth ${depth} -type f)
  do
    mv $restfile ${target_finalize_path}
  done

  # loop through schemas
  for schema in "${DBFOLDERS[@]}"
  do
    db_install_file=${mode}_${schema}_${version}.sql

    if [[ -f db/$schema/$db_install_file ]]; then
      [[ -d ${target_finalize_path}/db/$schema ]] || mkdir -p ${target_finalize_path}/db/$schema
      mv db/$schema/$db_install_file* ${target_finalize_path}/db/$schema
    fi
  done

  # write Info to markdown-table
  deployed_at=`date +"%Y-%m-%d %T"`
  deployed_by=$(whoami)

  versionmd=`printf '%-10s' "V${version}"`
  deployed_at=`printf '%-19s' "$deployed_at"`
  deployed_by=`printf '%-11s' "$deployed_by"`
  result=`printf '%-11s' "$target_move"`

  echo "| $versionmd | $deployed_at | $deployed_by |  $result " >> ${basepath}/version.md

  finallog=$(basename ${full_log_file})


  if [[ $target_move == "success" ]]; then
    post_message_to_teams "Release ${version}" "4CCC3B" "Release ${version} has been successfully applied to stage: <b>${STAGE}</b>."

    echo "view output: ${basepath}/$DEPOT_PATH/$STAGE/$target_move/$version/${finallog}"

    process_logs;
    exit 0
  else
    redolog=$(basename ${full_log_file})

    # failure
    echo_debug "You can either copy the broken patch into the current directory with: "
    echo_debug "${WHITE}cp ${target_relative_path}/${mode}_${version}.tar.gz .${NC}"
    echo_debug "And restart the patch after the respective problem has been fixed"
    echo_debug "Or create a new fixed release and restart the deployment of the patch. In both cases you have the"
    echo_debug "possibility to specifiy the log file ${WHITE}${target_relative_path}/${log_file}${NC} as "
    echo_debug "redolog parameter. This will not repeat the steps that have already been successfully executed."
    echo_debug "${WHITE}$0 --${mode} --version ${version} --redolog ${target_relative_path}/${redolog}${NC}"
    echo_debug "view output: ${basepath}/$DEPOT_PATH/$STAGE/$target_move/$version/${finallog}"

    process_logs
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
        timelog "ERROR when executing ${runfile}" $failure
      else
        timelog "ERROR in last statement" $failure
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
set_rest_publish_state "NOT_PUBLISHED"

# when in init mode, ALL schema objects will be
# dropped
clear_db_schemas_on_init


# execute pre hooks in root folder
execute_global_hook_scripts ".hooks/pre"
execute_global_hook_scripts ".hooks/pre/${mode}"

# install product
install_db_schemas
install_apps
install_rest

# execute post hooks in root folder
execute_global_hook_scripts ".hooks/post"
execute_global_hook_scripts ".hooks/post/${mode}"

# take care of changelog
process_changelog

# now enable all,
set_apps_available
set_rest_publish_state "PUBLISHED"


# final works
manage_result "success"
