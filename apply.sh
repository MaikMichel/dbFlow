#!/usr/bin/env bash
#echo "Your script args ($#) are: $@"

function usage() {
  echo -e "${BWHITE}.dbFlow/apply.sh${NC} - applies the given build to target database from"
  echo -e "                   depot path, defined in environment. "
  echo ""
  echo -e "${BWHITE}Usage:${NC}"
  echo -e "  ${0} --init --version <label>"
  echo -e "  ${0} --patch --version <label> [--noextract] [--redolog <old-logfile>]"
  echo
  echo -e "${BWHITE}Options:${NC}"
  echo -e "  -h | --help             - Show this screen"
  echo -e ""
  echo -e "  -i | --init             - Flag to install a full installable artifact "
  echo -e "                            this will delete all objects in target schemas upon install"
  echo -e "  -p | --patch            - Flag to install an update/patch as artifact "
  echo -e "                            This will apply on top of the target schemas and consists"
  echo -e "                            of the difference defined during build"
  echo -e "  -v | --version <label>  - Required label of version this artifact represents"
  echo -e "  -n | --noextract        - Optional do not move and extract artifact from depot "
  echo -e "                            Can be used to extract files manually or use a already extracted build"
  echo -e "  -r | --redolog          - Optional to redo an installation and skip installation-step already run"
  echo -e "  -s | --stepwise         - Runs the installation interactively step by step"
  echo ""
 	echo -e "${BWHITE}Examples:${NC}"
  echo -e "  ${0} --init --version 1.0.0"
  echo -e "  ${0} --patch --version 1.1.0"
  echo -e "  ${0} --patch --version 1.1.0 --noextract --redolog ../depot/master/old_logfile.log"
  echo

  exit $1
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

# get branch name
{ #try
  this_branch=$(git branch --show-current)
} || { # catch
  this_branch="develop"
}

#
AT_LEAST_ON_INSTALLFILE_STARTED="NO"

runfile=""
debug="n"
help="h"
init="n"
patch="n"
version="-"
noextract="n"
redolog=""

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

  if [[ -z ${DB_TNS} ]]; then
    echo_error "TNS not defined"
    do_exit="YES"
  fi

  if [[ -d ${DEPOT_PATH}/${STAGE} ]]; then
    install_source_path=${basepath}/${DEPOT_PATH}/${STAGE}
  else
    echo_error "Targetstage ${STAGE} inside ${DEPOT_PATH} is unknown"
    echo_warning "Check your STAGE environment var in apply.env"
    do_exit="YES"
  fi

  if [[ -z ${LOG_PATH:-} ]]; then
    if [[ -f "apply.env" && -z "$(grep 'LOG_PATH=' "apply.env")" ]]; then
      {
        echo ""
        echo "# auto added @${MDATE}"
        echo "# Path to copy logs to after installation"
        echo "LOG_PATH=_logs"
      } >> apply.env

      echo -e "${LWHITE}set LOG_PATH to ${NC}${BWHITE}_logs${NC} ${LWHITE} in your apply.env - please configure as you like with a relative path${NC}"
      LOG_PATH="_logs"
    else
      echo_error "Logpath not defined"
      do_exit="YES"
    fi
  fi

  if [[ ${PROJECT_MODE} == "FLEX" ]]; then
    SCHEMAS=(${DBSCHEMAS[@]})
  else
    # get distinct values of array
    ALL_SCHEMAS=( "${DATA_SCHEMA}" "${LOGIC_SCHEMA}" "${APP_SCHEMA}" )
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

  # Defing some vars
  app_install_file=apex_files_${version}.lst
  remove_old_files=remove_files_${version}.lst

  install_target_path=.
  install_source_file=$install_source_path/${mode}_${version}.tar.gz
  install_target_file=$install_target_path/${mode}_${version}.tar.gz

  MDATE=`date "+%Y%m%d%H%M%S"`
  log_file="${MDATE}_dpl_${mode}_${version}.log"

  touch "${log_file}"
  full_log_file="$( cd "$( dirname "${log_file}" )" >/dev/null 2>&1 && pwd )/${log_file}"

  exec 3>&1 4>&2
  exec &> >(tee -a "$log_file")
}

function check_params() {
  help_option="NO"
  init_option="NO"
  patch_option="NO"
  version_option="NO"
  version_argument="-"
  noextract_option="NO"
  redolog_option="NO"
  redolog_argument="-"
  stepwise_option="NO"

  while getopts_long 'hipv:nr:s help init patch version: noextract redolog: stepwise' OPTKEY "${@}"; do
      case ${OPTKEY} in
          'h'|'help')
              help_option="YES"
              ;;
          'i'|'init')
              init_option="YES"
              ;;
          'p'|'patch')
              patch_option="YES"
              ;;
          'v'|'version')
              version_option="YES"
              version_argument="${OPTARG}"
              ;;
          'n'|'noextract')
              noextract_option="YES"
              ;;
          'r'|'redolog')
              redolog_option="YES"
              redolog_argument="${OPTARG}"
              ;;
          's'|'stepwise')
              stepwise_option="YES"
              ;;
          '?')
              echo_error "INVALID OPTION -- ${OPTARG}" >&2
              usage 10
              ;;
          ':')
              echo_error "MISSING ARGUMENT for option -- ${OPTARG}" >&2
              usage 11
              ;;
          *)
              echo_error "UNIMPLEMENTED OPTION -- ${OPTKEY}" >&2
              usage 12
              ;;
      esac
  done

  # help first
  if [[ ${help_option} == "YES" ]]; then
    usage 0
  fi

  # Rule 1: init or patch
  if [[ ${init_option} == "NO" ]] && [[ ${patch_option} == "NO" ]]; then
    echo_error "Missing apply mode, init or patch using flags -i or -p"
    usage 2
  fi

  if [[ ${init_option} == "YES" ]] && [[ ${patch_option} == "YES" ]]; then
    echo_error "Build mode can only be init or patch, not both"
    usage 3
  fi

  # Rule 2: we always need a version
  if [[ ${version_option} == "NO" ]] || [[ ${version_argument} == "-" ]]; then
    echo_error "Missing version, use flag --version x.x.x"
    usage 4
  else
    version=${version_argument}
  fi

  # now check dependent params
  if [[ ${init_option} == "YES" ]]; then
    mode="init"
  elif [[ ${patch_option} == "YES" ]]; then
    mode="patch"
  fi

  # now check dependent params
  if [[ ${noextract_option} == "YES" ]]; then
    must_extract="FALSE"
  else
    must_extract="TRUE"
  fi

  if [[ ${redolog_option} == "YES" ]]; then
    oldlogfile=$redolog_argument
  fi
}

function print_info() {
  timelog "Installing    ${BWHITE}${mode} ${version}${NC}"
  timelog "----------------------------------------------------------"
  timelog "Mode:                ${BWHITE}$mode${NC}"
  timelog "Version:             ${BWHITE}${version}${NC}"
  timelog "Log File:            ${BWHITE}${log_file}${NC}"
  timelog "Extract:             ${BWHITE}$must_extract${NC}"
  timelog "Stepwise:            ${BWHITE}${stepwise_option}${NC}"
  if [[ $oldlogfile != "" ]]; then
    timelog "Redolog:             ${BWHITE}$oldlogfile${NC}"
  fi
  timelog "Bash-Version:        ${BWHITE}${BASH_VERSION}${NC}"
  timelog "----------------------------------------------------------"
  timelog "Project:             ${BWHITE}${PROJECT}${NC}"
  if [[ ${PROJECT_MODE} != "FLEX" ]]; then
    timelog "App Schema           ${BWHITE}${APP_SCHEMA}${NC}"
    if [[ ${PROJECT_MODE} != "SINGLE" ]]; then
      timelog "Data Schema:         ${BWHITE}${DATA_SCHEMA}${NC}"
      timelog "Logic Schema:        ${BWHITE}${LOGIC_SCHEMA}${NC}"
    fi
    timelog "Workspace:           ${BWHITE}${WORKSPACE}${NC}"
  fi

  timelog "Schemas:             ${BWHITE}${SCHEMAS[*]}${NC}"
  if [[ -n ${CHANGELOG_SCHEMA} ]]; then
    timelog "----------------------------------------------------------"
    timelog "Changelog Schema:    ${BWHITE}${CHANGELOG_SCHEMA}${NC}"
    timelog "Intent Prefixes:     ${BWHITE}${INTENT_PREFIXES[@]}${NC}"
    timelog "Intent Names:        ${BWHITE}${INTENT_NAMES[@]}${NC}"
    timelog "Intent Else:         ${BWHITE}${INTENT_ELSE}${NC}"
    timelog "Ticket Match:        ${BWHITE}${TICKET_MATCH}${NC}"
    timelog "Ticket URL:          ${BWHITE}${TICKET_URL}${NC}"
  fi

  if [[ -n ${TEAMS_WEBHOOK_URL} ]]; then
    timelog "Teams WebHook:       ${BWHITE}TRUE${NC}"
  fi

  timelog "----------------------------------------------------------"
  timelog "Stage:               ${BWHITE}${STAGE}${NC}"
  timelog "Depot:               ${BWHITE}${DEPOT_PATH}${NC}"
  timelog "Logs :               ${BWHITE}${LOG_PATH}${NC}"
  timelog "Application Offset:  ${BWHITE}${APP_OFFSET}${NC}"
  timelog "Deployment User:     ${BWHITE}${DB_APP_USER}${NC}"
  timelog "DB Connection:       ${BWHITE}${DB_TNS}${NC}"
  timelog "----------------------------------------------------------"
  timelog
}

function extract_patchfile() {
  if [[ ${must_extract} == "TRUE" ]]; then
    # check if patch exists
    if [[ -e "${install_source_file}" ]]; then
      timelog "${install_source_file} exists"

      # copy patch to _installed
      cp "${install_source_file}" "${install_target_path}"/
    else
      if [[ -e "${install_target_file}" ]]; then
        timelog "${install_target_file} already copied"
      else
        timelog "${install_target_file} not found, nothing to install" "${failure}"
        manage_result "failure"
      fi
    fi

    # extract file
    timelog "extracting file ${install_target_file}"
    tar -zxf "${install_target_file}"
  else
    timelog "artifact will not be extracted from depot"
  fi
}

function validate_dbflow_version() {
  if [[ -f "dbFlow_${mode}_${version}.version" ]]; then
    version_apply=$(sed '/^## \[./!d;q' .dbFlow/CHANGELOG.md)
    version_built=$(head -n 1 "dbFlow_${mode}_${version}.version")
    if [[ "${version_apply}" == "${version_built}" ]]; then
      timelog "dbFlow Versions matched"
    else
      timelog "Mismatched Versions build vs apply" "${warning}"
      timelog ":${version_apply}: != :${version_built}:" "${warning}"

      if [[ -z ${DBFLOW_JENKINS:-} ]]; then
        read -r -p "$(echo -e "${BORANGE}Version mismatch${NC} - Do you want to proceed? (y/n)" ) " -n 1
        echo    # (optional) move to a new line
        if [[ ! $REPLY =~ ^[Yy]$ ]]
        then
            [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
        fi
      else
        timelog "Running different dbFlow version but JENKINS is set, so keep on running"
      fi
    fi
  fi
}

function validate_init_mode() {
  # init mode is a kind of dangerous, cause everything is removed from schemas beforehand
  if [[ "${mode}" == "init" ]]; then
    if [[ -z ${DBFLOW_JENKINS:-} ]] && [[ "${version}" != "install" ]]; then
      timelog "You are using init mode. All content will be dropped from schemas included in this artifact" "${warning}"
      timelog "If you are running dbFLow inside CI/CD you can place DBFLOW_JENKINS as environment var with any value" "${warning}"
      read -r -p "$(echo -e "${RED}CI/CD not set${NC} - Do you want to proceed? (y/n)" ) " -n 1
      echo    # (optional) move to a new line
      if [[ ! $REPLY =~ ^[Yy]$ ]]
      then
          [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
      fi
    else
      timelog "Running init on JENKINS or version is install"
    fi
  fi
}

function prepare_redo() {
  if [[ -f "${oldlogfile}" ]]; then
    timelog "parsing redolog ${oldlogfile}"

    this_os=$(uname)

    redo_file="redo_${MDATE}_${mode}_${version}.log"
    grep '^<<< ' "${oldlogfile}" | cat > "${redo_file}"
    sed -i 's/^<<< //' "${redo_file}"

    # backup install files
    for schema in "${DBFOLDERS[@]}"
    do

      db_install_file=./db/$schema/${mode}_${schema}_${version}.sql
      if [[ -f $db_install_file ]]; then
        mv "${db_install_file}" "${db_install_file}.org"
      fi
    done # schema

    declare -A map
    while IFS= read -r line; do
      timelog " ... Skipping line $line"
      map[$line]=$line
    done < "${redo_file}"

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
      done < "${old_install_file}" > "${db_install_file}"
    done # schema

  fi
}

function read_db_pass() {
  if [[ -z "$DB_APP_PWD" ]]; then
    ask4pwd "Enter Password for deployment user ${DB_APP_USER} on ${DB_TNS}: "
    DB_APP_PWD=${pass}
  else
    timelog "Password has already been set"
  fi
}

function remove_dropped_files() {
  timelog "Check if any file should be removed ..."
  if [[ -e $remove_old_files ]]; then
    # loop throug content
    while IFS= read -r line; do
      timelog "Removing file ${line}"
      rm -f "${line}"
    done < "$remove_old_files"
  else
    timelog "No files to remove"
  fi
}

function execute_global_hook_scripts() {
  local entrypath=$1    # pre or post
  local targetschema=""

  timelog "checking hook ${entrypath}"

  if [[ -d "${entrypath}" ]]; then
    for file in $(ls "${entrypath}" | sort )
    do
      if [[ -f "${entrypath}/${file}" ]]; then
        targetschema=$(get_schema_from_file_name "${file}")
        runfile="${entrypath}/${file}"

        if [[ ${targetschema} != "_" ]]; then
          timelog "executing hook file ${runfile} in ${targetschema}"
          $SQLCLI -S -L "$(get_connect_string "${targetschema}")" <<!
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
          timelog "no schema found to execute hook file ${runfile} target schema has to be a part of filename" "${warning}"
        fi
      fi
    done


    if [[ $? -ne 0 ]]; then
      timelog "ERROR when executing ${entrypath}/${file}" "${failure}"
      manage_result "failure"
    fi
  fi
}

function clear_db_schemas_on_init() {
  if [[ "${mode}" == "init" ]]; then
    [[ ${stepwise_option} == "NO" ]] || ask_step "${RED}INIT! > clear schemas${NC}"
    timelog "INIT - Mode, Schemas will be cleared"
    # loop through schemas reverse
    for (( idx=${#SCHEMAS[@]}-1 ; idx>=0 ; idx-- )) ; do
      local schema=${SCHEMAS[idx]}
      # On init mode schema content will be dropped
      timelog "DROPING ALL OBJECTS on schema ${schema}"
       exit | $SQLCLI -S -L "$(get_connect_string "${schema}")" @".dbFlow/lib/drop_all.sql" "${full_log_file}" "${version}" "${mode}"
    done
  fi
}

function validate_connections() {
  # loop through schemas
  for schema in "${SCHEMAS[@]}"
  do
    check_connection "${schema}"
  done

}

function install_db_schemas() {
  cd "${basepath}" || exit

  # execute all files in global pre path
  execute_global_hook_scripts "db/.hooks/pre"
  execute_global_hook_scripts "db/.hooks/pre/${mode}"

  cd db || exit

  timelog "Start installing schemas"
  # loop through schemas
  for schema in "${DBFOLDERS[@]}"
  do
    if [[ -d ${schema} ]]; then
      cd "${schema}" || exit

      # now executing main installation file if exists
      db_install_file="${mode}_${schema}_${version}.sql"
      # exists db install file
      if [[ -e $db_install_file ]]; then
        timelog "Installing schema $schema to ${DB_APP_USER} on ${DB_TNS}"

        # uncomment cleaning scripts specific to this stage/branch ex:--test or --acceptance
        sed -i -E "s:--$STAGE:Prompt uncommented cleanup for stage $STAGE\n:g" "${db_install_file}"

        runfile=${db_install_file}
        AT_LEAST_ON_INSTALLFILE_STARTED="YES"
        $SQLCLI -S -L "$(get_connect_string "${schema}")" @"${db_install_file}" "${version}" "${mode}"
        runfile=""

        if [[ $? -ne 0 ]]; then
          timelog "ERROR when executing db/${schema}/${db_install_file}" "${failure}"
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

function set_rest_publish_state() {
  cd "${basepath}" || exit
  local publish=$1
  if [[ -d "rest" ]]; then
    local appschema=${APP_SCHEMA}

    folders=()
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      for d in $(find rest -maxdepth 1 -mindepth 1 -type d | sort -f)
      do
        folders+=( $(basename "${d}")/modules )
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
          mbase=$(basename "${mods}")
          modules+=( "${mbase}" )
        done

        $SQLCLI -S -L "$(get_connect_string "${appschema}")" <<!
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
    timelog "Directory rest does not exist" "${warning}"
  fi

  cd "${basepath}" || exit
}


function set_apps_unavailable() {
  cd "${basepath}" || exit

  if [[ -d "apex" ]]; then

    depth=1
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=3
    fi

    for d in $(find apex -maxdepth ${depth} -mindepth ${depth} -type d)
    do
      local app_name=$(basename "${d}")
      local app_id=${app_name/f}

      local workspace=${WORKSPACE}
      local appschema=${APP_SCHEMA}

      if [[ ${PROJECT_MODE} == "FLEX" ]]; then
        workspace=$(basename $(dirname "${d}"))
        appschema=$(basename $(dirname $(dirname "${d}")))
      fi

      timelog "disabling APEX-App ${app_id} in workspace ${workspace} for schema ${appschema}..."
      $SQLCLI -S -L "$(get_connect_string "${appschema}")" <<!
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

        apex_util.set_application_status(p_application_id     => v_application_id,
                                          p_application_status => 'UNAVAILABLE',
                                          p_unavailable_value  => '${maintence}' );

        dbms_output.put_line('.. APP: '|| v_application_id || ' has been disabled');

        -- check translated Applications additionally
        for cur in ( select translated_application_id, translated_app_language
                       from apex_application_trans_map
                      where primary_application_id = v_application_id
                      order by translated_application_id)
        loop
          begin
            apex_util.set_application_status(p_application_id     => cur.translated_application_id,
                                             p_application_status => 'UNAVAILABLE',
                                             p_unavailable_value  => '${maintence}' );
            dbms_output.put_line('.... Translated APP: '|| cur.translated_application_id || ' (' || cur.translated_app_language || ') has been disabled');
          exception
            when others then
              if sqlerrm like '%Application not found%' then
                dbms_output.put_line((chr(27) || '[33m') || 'Application: '||upper(cur.translated_application_id)||' probably not published!' || (chr(27) || '[0m'));
              else
                raise;
              end if;
          end;
        end loop;
      Exception
        when no_data_found then
          dbms_output.put_line((chr(27) || '[31m') || 'Workspace: '||upper('${workspace}')||' not found!' || (chr(27) || '[0m'));
        when others then
          if sqlerrm like '%Application not found%' then
            dbms_output.put_line((chr(27) || '[31m') || 'Application: '||upper(v_application_id)||' not found!' || (chr(27) || '[0m'));
          else
            raise;
          end if;
End;
/

!

    done
  else
    timelog "Directory apex does not exist" "${warning}"
  fi

}

function set_apps_available() {
  cd "${basepath}" || exit

  if [[ -d "apex" ]]; then

    depth=1
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=3
    fi

    for d in $(find apex -maxdepth ${depth} -mindepth ${depth} -type d)
    do
      local app_name=$(basename "${d}")
      local app_id=${app_name/f}

      # Enable only Applications which were not part of the current deployment process
      if grep -q "\b${app_name}\b" "${app_install_file}"; then
        timelog "no enabling APEX-App ${app_id} in workspace ${workspace} because it was part of the deployment"
        timelog "...any existent translated apps have to be published on your own, using hooks"
      else

        local workspace=${WORKSPACE}
        local appschema=${APP_SCHEMA}

        if [[ ${PROJECT_MODE} == "FLEX" ]]; then
          workspace=$(basename $(dirname ${d}))
          appschema=$(basename $(dirname $(dirname ${d})))
        fi


        timelog "enabling APEX-App ${app_id} in workspace ${workspace} for schema ${appschema}..."
        $SQLCLI -S -L "$(get_connect_string "${appschema}")" <<!
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

            -- only enable, what has been disabled by dbFlow with the marker "<span />"
            if (apex_util.get_application_status(p_application_id => v_application_id) = 'UNAVAILABLE' and l_text like '<span />%') then

              apex_util.set_application_status(p_application_id     => v_application_id,
                                              p_application_status => 'AVAILABLE_W_EDIT_LINK',
                                              p_unavailable_value  => null );

              dbms_output.put_line('.. APP: '|| v_application_id || ' has been enabled');


              -- check translated Applications additionally
              for cur in ( select translated_application_id, translated_app_language
                              from apex_application_trans_map
                            where primary_application_id = v_application_id )
              loop
                begin
                  apex_util.set_application_status(p_application_id     => cur.translated_application_id,
                                                  p_application_status => 'AVAILABLE_W_EDIT_LINK',
                                                  p_unavailable_value  => null );

                  dbms_output.put_line('.... Translated APP: '|| cur.translated_application_id || ' (' || cur.translated_app_language || ') has been enabled');
                exception
                  when others then
                    if sqlerrm like '%Application not found%' then
                      dbms_output.put_line((chr(27) || '[31m') || 'Application: '||upper(v_application_id)||' probably not published!' || (chr(27) || '[0m'));
                    else
                      raise;
                    end if;
                end;
              end loop;
            end if;
          exception
            when no_data_found then
              dbms_output.put_line((chr(27) || '[31m') || 'Application: '||upper(v_application_id)||' not found!' || (chr(27) || '[0m'));
          end;
        Exception
          when no_data_found then
            dbms_output.put_line((chr(27) || '[31m') || 'Workspace: '||upper('${workspace}')||' not found!' || (chr(27) || '[0m'));
        End;
/
!
      fi # grep
    done


  else
    timelog "Directory apex does not exist" "${warning}"
  fi

}

function install_apps() {

  cd "${basepath}" || exit

  # app install
  # exists app_install_file
  if [[ -e $app_install_file ]]; then
    timelog "Installing APEX-Apps ..."
    # loop throug content
    while IFS= read -r line; do
      if [[ -e ${line}/install.sql ]]; then
        local app_name=$(basename "${line}")
        local app_id=${app_name/f}

        local workspace=${WORKSPACE}
        local appschema=${APP_SCHEMA}
        if [[ ${PROJECT_MODE} == "FLEX" ]]; then
          workspace=$(basename $(dirname "${line}"))
          appschema=$(basename $(dirname $(dirname "${line}")))
        fi

        cd "${line}" || exit
        if [[ $(uname) == "Darwin" ]]; then
          # on macos the -P parameter does not exist for grep, so we use sed instead
          local original_app_id=$(grep -oE "p_default_application_id=>([^[:space:]]+)" "application/set_environment.sql" | sed 's/.*>\(.*\)/\1/')
        else
          local original_app_id=$(grep -oP 'p_default_application_id=>\K\d+' "application/set_environment.sql")
        fi
        timelog "Installing $line Num: ${app_id} Workspace: ${workspace} Schema: ${appschema} Original Num: ${original_app_id}"

        $SQLCLI -S -L "$(get_connect_string "${appschema}")" << EOF
          define VERSION="${version}"
          define MODE="${mode}"

          set define '^'
          set concat on
          set concat .
          set verify off

          set serveroutput on

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

            apex_application_install.set_application_id(${app_id} + nvl(${APP_OFFSET}, 0));

            if nvl(${APP_OFFSET}, 0) > 0 or ${app_id} != nvl(${original_app_id}, 0) then
              dbms_output.put_line((chr(27) || '[33m') || 'Original APP ID differs from Target APP ID. Generating Offset.' || (chr(27) || '[0m'));
              apex_application_install.generate_offset;
              -- alias must be unique per instance, so when offset is definded
              -- it should be modified. In this case a post hook at root level
              -- has to be used to give it a correct alias
              apex_application_install.set_application_alias('${app_id}_${APP_OFFSET}');
            end if;

            apex_application_install.set_schema(upper('${appschema}'));
          Exception
            when no_data_found then
              dbms_output.put_line((chr(27) || '[31m') || 'Workspace: '||upper('${workspace}')||' not found!' || (chr(27) || '[0m'));
          end;
          /

          @@install.sql
EOF


        if [[ $? -ne 0 ]]; then
          timelog "ERROR when executing ${line}" "${failure}"
          manage_result "failure"
        fi

        # only for syntax highlighting
        if [[ 1 == 2 ]]; then
          echo <<!
          '\'
!
        fi

        cd "${basepath}" || exit
      fi
    done < "$app_install_file"
  else
    timelog "File $app_install_file does not exist" "${warning}"
  fi

  cd "${basepath}" || exit
}


# Function to install REST-Services
#######################################

function install_rest() {
  cd "${basepath}" || exit

  rest_install_file=rest_${mode}_${version}.sql

  if [[ -d rest ]]; then

    depth=0
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=1
    fi

    for d in $(find rest -maxdepth ${depth} -mindepth ${depth} -type d)
    do
      cd "${d}" || exit

      if [[ -f ${rest_install_file} ]]; then

        local appschema=${APP_SCHEMA}
        if [[ ${PROJECT_MODE} == "FLEX" ]]; then
          appschema=$(basename "${d}")
        fi

        timelog "Installing REST-Services ${d}/${rest_install_file} on Schema ${appschema}"
        $SQLCLI -S -L "$(get_connect_string "${appschema}")" <<!

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
          timelog "ERROR when executing $line" "${failure}"
          exit 1
        fi
      fi

      cd "${basepath}" || exit
    done

  else
    timelog "Directory rest does not exist"
  fi

  cd "${basepath}" || exit
}


# when changelog is found and changelog template is defined then
# execute template on configured schema build.env:CHANGELOG_SCHEMA=?
function process_changelog() {
  chlfile=changelog_${mode}_${version}.md
  tplfile=reports/changelog/template.sql
  if [[ -f ${chlfile} ]]; then
    timelog "changelog found"

    if [[ -f "${tplfile}" ]]; then
      timelog "templatefile found"

      if [[ -n ${CHANGELOG_SCHEMA} ]]; then
        timelog "changelog schema '${CHANGELOG_SCHEMA}' is configured"

        # now gen merged sql file
        create_merged_report_file "${chlfile}" "${tplfile}" "${chlfile}.sql"

        # and run
        $SQLCLI -S -L "$(get_connect_string "${CHANGELOG_SCHEMA}")" <<!

          Prompt executing changelog file ${chlfile}.sql
          @${chlfile}.sql

!

        if [ $? -ne 0 ]
        then
          timelog "ERROR when runnin ${chlfile}.sql" "${failure}"
          exit 1
        else
          rm "${chlfile}.sql"
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

# when releasenotes are found and release_note template is defined then
# execute template on configured schema build.env:RELEASENOTES_SCHEMA=?
function process_release_notes() {
  rlsnfile=release_notes_${mode}_${version}.md
  tplfile=reports/release_notes/template.sql
  if [[ -f ${rlsnfile} ]]; then
    timelog "release_note found"

    if [[ -f "${tplfile}" ]]; then
      timelog "templatefile found"

      if [[ -n ${RELEASENOTES_SCHEMA} ]]; then
        timelog "releasenote schema '${RELEASENOTES_SCHEMA}' is configured"

        # now gen merged sql file
        create_merged_report_file "${rlsnfile}" "${tplfile}" "${rlsnfile}.sql"

        # and run
        $SQLCLI -S -L "$(get_connect_string "${RELEASENOTES_SCHEMA}")" <<!

          Prompt executing release_notes file ${rlsnfile}.sql
          @${rlsnfile}.sql

!

        if [ $? -ne 0 ]
        then
          timelog "ERROR when runnin ${rlsnfile}.sql" "${failure}"
          exit 1
        else
          rm "${rlsnfile}.sql"
        fi
      else
        timelog "RELEASENOTES_SCHEMA is NOT configured"
      fi
    else
      timelog "No templatefile found"
    fi
  else
    timelog "No release_note ${rlsnfile} found"
  fi
}

function post_message_to_teams() {
  cd "${basepath}" || exit

  local TITLE=$1
  local COLOR=$2
  local TEXT=$3

  if [ -z "${TEAMS_WEBHOOK_URL}" ]
  then
    timelog "No webhook_url specified."
  else
    # Convert formating.
    MESSAGE=$( echo "${TEXT}" | sed 's/"/\"/g' | sed "s/'/\'/g" )
    JSON="{\"title\": \"${TITLE}\", \"themeColor\": \"${COLOR}\", \"text\": \"${MESSAGE}\" }"

    timelog "Posting to url: ${JSON} "
    # Post to Microsoft Teams.
    curl -H "Content-Type: application/json" -d "${JSON}" "${TEAMS_WEBHOOK_URL}"

  fi
}

function process_logs() {
  local target_move=$1
  local view_output=$2

  # Send stdout back to stdin
  exec >&3 2>&4
  #exec 1>&0

  # remove colorcodes from file
  echo "Processing logs"
  cat "${full_log_file}" | sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" > "${full_log_file}.colorless"
  rm "${full_log_file}"
  mv "${full_log_file}.colorless" "${full_log_file}"

  local lfile=$(basename "${full_log_file}")

  # write definition to current apply.env
  if [[ -f "apply.env" && -z "$(grep 'LOG_PATH=' "apply.env")" ]]; then
    {
    echo ""
    echo "# auto added @${MDATE}"
    echo "# Path to copy logs to after installation"
    echo "LOG_PATH=_logs"
    } >> apply.env
    echo -e "${LWHITE}set LOG_PATH to ${NC}${BWHITE}_logs${NC} ${LWHITE} in your apply.env - please configure as you like with a relative path${NC}"
    LOG_PATH="_logs"
  fi


  # create path if needed
  [[ -d "${LOG_PATH}" ]] || mkdir "${LOG_PATH}"

  # create succcess or failure subfolder
  [[ -d "${LOG_PATH}/${target_move}" ]] || mkdir "${LOG_PATH}/${target_move}"


  # rm tarball
  rm ${install_target_file}

  # move all artifacts
  mv ./*"${mode}"*"${version}"* "${target_relative_path}"

  view_output="${target_relative_path}/$(basename "${full_log_file}")"
  echo_debug "view output: \"${view_output}\""
}

function manage_result() {
  cd "${basepath}" || exit

  local target_move=$1
  target_relative_path=${LOG_PATH}/${target_move}/${version}
  target_finalize_path=${basepath}/${target_relative_path}

  # create path if not exists
  [ -d "${target_finalize_path}" ] || mkdir -p "${target_finalize_path}"

  # notify
  timelog "${mode} ${version} moved to ${target_finalize_path}" "${target_move}"
  timelog "Done with ${target_move}" "${target_move}"


  # move apex lst
  [[ -f "apex_files_${version}.lst" ]] && mv "apex_files_${version}.lst" "${target_finalize_path}"
  [[ -f "remove_files_${version}.lst" ]] && mv "remove_files_${version}.lst" "${target_finalize_path}"

  # move rest files
  depth=1
  if [[ ${PROJECT_MODE} == "FLEX" ]]; then
    depth=2
  fi

  if [[ -d rest ]]; then
    for restfile in $(find rest -maxdepth ${depth} -mindepth ${depth} -type f)
    do
      mv "${restfile}" "${target_finalize_path}"
    done
  fi

  # loop through schemas
  for schema in "${DBFOLDERS[@]}"
  do
    db_install_file="${mode}_${schema}_${version}.sql"

    if [[ -f "db/${schema}/${db_install_file}" ]]; then
      [[ -d "${target_finalize_path}/db/${schema}" ]] || mkdir -p "${target_finalize_path}/db/${schema}"
      mv "db/${schema}/${db_install_file}"* "${target_finalize_path}/db/${schema}"
    fi
  done

  # write Info to markdown-table
  deployed_at=`date +"%Y-%m-%d %T"`
  deployed_by=$(whoami)

  versionmd=`printf '%-10s' "V${version}"`
  deployed_at=`printf '%-19s' "$deployed_at"`
  deployed_by=`printf '%-11s' "$deployed_by"`
  result=`printf '%-11s' "$target_move"`

  echo "| $versionmd | $deployed_at | $deployed_by |  $result " >> "${basepath}/version.md"

  finallog=$(basename "${full_log_file}")


  if [[ $target_move == "success" ]]; then
    post_message_to_teams "Release ${version}" "4CCC3B" "Release ${version} has been successfully applied to stage: <b>${STAGE}</b>."
    process_logs ${target_move} "${target_relative_path}/${finallog}";

    # commit if stage != develop or build and current branch is main or master
    if [[ -d ".git" ]]; then
      if [[ ${STAGE} != "develop" && ${STAGE} != "build" ]]; then
        if [[ ${this_branch} == "main" || ${this_branch} == "master" ]]; then
          echo_success "Adding all changes to this repo"
          git add --all
          git commit -m "${version}" --quiet
          git push --quiet

          if [[ $(git tag -l "$version") ]]; then
            echo_success "Tag $version already exists, nothing to do"
          else
            echo_success "Writing tag $version to repo"
            git tag "${version}"
            git push --quiet
          fi
        fi
      fi
    fi
    exit 0
  else
    redolog=$(basename "${full_log_file}")

    # this is only usefull when at least on installation file has been executed
    if [[ ${AT_LEAST_ON_INSTALLFILE_STARTED} == "YES" ]]; then
      # failure
      echo_debug "You can either copy the broken patch into the current directory and restart "
      echo_debug "the patch after the respective problem has been fixed by using the redolog param"
      echo_debug "---"
      echo_debug "${WHITE}cp ${target_relative_path}/${mode}_${version}.tar.gz .${NC}"
      echo_debug "${WHITE}$0 --${mode} --version ${version} --redolog ${target_relative_path}/${redolog}${NC}"
      echo_debug "---"
      echo_debug "Or create a new fixed release and restart the deployment of the patch. In both cases you have the"
      echo_debug "possibility to specifiy the log file ${WHITE}${target_relative_path}/${log_file}${NC}"
      echo_debug "as redolog parameter. This will not repeat the steps that have already been successfully executed."
    fi

    process_logs ${target_move} "${target_relative_path}/${finallog}";
    exit 1
  fi
}

function ask_step() {
  local step=${1}
  read -r -p "$(echo -e "${BWHITE}Step:${NC} - ${step} - proceed (y/n) ? ") " -n 1
  echo    # (optional) move to a new line
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
  fi
}

#################################################################################################
function notify() {
    [[ ${1} = 0 ]] || echo ❌ EXIT "${1}"
    # you can notify some external services here,
    # ie. Slack webhook, Github commit/PR etc.
    if [[ ${1} -gt 2 ]]; then
      if [[ "${runfile}" != "" ]]; then
        timelog "ERROR when executing ${runfile}" "${failure}"
      else
        timelog "ERROR in last statement" "${failure}"
      fi

      manage_result "failure"
    fi

}

trap '(exit 130)' INT
trap '(exit 143)' TERM
trap 'rc=$?; notify $rc; exit $rc' EXIT

# validate params this script was called with
check_params "$@"
validate_init_mode

# validate and check existence of vars defined in apply.env and build.env
check_vars

# print some global vars to output
print_info

[[ ${stepwise_option} == "NO" ]] || ask_step "Validate deplyoment file"
# preparation and validation
extract_patchfile
validate_dbflow_version
read_db_pass
validate_connections
prepare_redo

[[ ${stepwise_option} == "NO" ]] || ask_step "Remove dropped files"
# files to be removed
remove_dropped_files

[[ ${stepwise_option} == "NO" ]] || ask_step "Set APPs or RESTmodules offline"
# now disable all, so that during build noone can do anything
set_apps_unavailable
set_rest_publish_state "NOT_PUBLISHED"

# when in init mode, ALL schema objects will be
# dropped
clear_db_schemas_on_init

[[ ${stepwise_option} == "NO" ]] || ask_step "exec global PRE hooks"
# execute pre hooks in root folder
execute_global_hook_scripts ".hooks/pre"
execute_global_hook_scripts ".hooks/pre/${mode}"

# install product
[[ ${stepwise_option} == "NO" ]] || ask_step "Install db schema(s)"
install_db_schemas

[[ ${stepwise_option} == "NO" ]] || ask_step "Install APP(s)"
install_apps

[[ ${stepwise_option} == "NO" ]] || ask_step "Install RESTmodule(s)"
install_rest

[[ ${stepwise_option} == "NO" ]] || ask_step "exec global POST hooks"
# execute post hooks in root folder
execute_global_hook_scripts ".hooks/post"
execute_global_hook_scripts ".hooks/post/${mode}"

[[ ${stepwise_option} == "NO" ]] || ask_step "Process changelogs"
# take care of changelog
process_changelog

# and release notes
process_release_notes

[[ ${stepwise_option} == "NO" ]] || ask_step "Set Apps or RESTmodules online"
# now enable all,
set_apps_available
set_rest_publish_state "PUBLISHED"

[[ ${stepwise_option} == "NO" ]] || ask_step "Cleaning Artefacts"
# final works
manage_result "success"
