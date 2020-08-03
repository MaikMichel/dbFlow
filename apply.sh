#!/bin/bash

echo "Your script args ($#) are: $@"

# TODO: Hier fehlt noch eine anständige Beschreibung / Kommentarblock

function print_help() {
 	echo "Please call script with following parameters"
	echo "  1 - mode [init | patch]"
  echo "  2 - version"
  echo "  3 - notar (optional) when no extraction should be done"
  echo
  echo "Example: "
  echo "  $0 init 1.0.0"
  echo "  $0 patch 1.0.1"
  echo
  echo "  $0 init 1.0.0 notar"
  echo "  $0 patch 1.0.1 notar"
	echo ""
  exit 1
}

# Validating parameters, at least 2 params are required
if [ $# -lt 2 ]; then
  print_help
fi

mode=$1
patch=$2
must_extract=$3

#sqlcl needs that
export JAVA_TOOL_OPTIONS='-Duser.language=en -Duser.region=US -Dfile.encoding=UTF-8'

# set project-settings from build
source ./build.env

# set target-env settings from file if exists
if [ -e apply.env ]
then
  source ./apply.env
fi

if [ -z $DEPOT_PATH ]
then
  echo "Depotpath not defined"
  exit 1
fi

if [ -z $STAGE ]
then
  echo "Stage not defined"
  exit 1
fi

if [ -z $DB_APP_USER ]
then
  echo "App-User not defined"
  exit 1
fi

if [ -z $DB_TNS ]
then
  echo "TNS not defined"
  exit 1
fi


patch_target_path=.

if [ -d $DEPOT_PATH/$STAGE ]
then
  echo "Targetstage used: $STAGE"
  patch_source_path=$DEPOT_PATH/$STAGE
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

echo "Mode:         $mode"
echo "Patch:        $patch"
echo "log_file:     $log_file"
echo "----------------------------------------------------------"
echo "project:      ${PROJECT}"
echo "app_schema:   ${APP_SCHEMA}"
echo "data_schema:  ${DATA_SCHEMA}"
echo "logic_schema: ${LOGIC_SCHEMA}"
echo "workspace:    ${WORKSPACE}"
echo "schemas:      ${SCHEMAS}"
echo "----------------------------------------------------------"
echo "Stage:        ${STAGE}"
echo "Depot:        ${DEPOT_PATH}"
echo "USE_PROXY:    ${USE_PROXY}"
echo "APP_OFFSET:   ${APP_OFFSET}"
echo "DB_APP_USER:  ${DB_APP_USER}"
echo "DB_APP_PWD:   ${DB_APP_PWD}"
echo "DB_TNS:       ${DB_TNS}"
echo "----------------------------------------------------------"
echo

touch $log_file
full_log_file="$( cd "$( dirname "${log_file}" )" >/dev/null 2>&1 && pwd )/${log_file}"

# Function to write to the Log file
###################################

write_log()
{
  while read text
  do
    LOGTIME=`date "+%Y-%m-%d %H:%M:%S"`
    # If log file is not defined, just echo the output
    if [ "$full_log_file" == "" ]; then
      echo $full_log_file": $text";
    else
      #if [ ! -f $full_log_file ]; then echo "ERROR!! Cannot create log file $full_log_file. Exiting."; exit 1; fi
      echo $LOGTIME": $text" | tee -a $full_log_file;
    fi
  done
}

# Function to print head informations
#########################################
print_info()
{
  echo "Installing ${mode} ${patch}" | write_log
  echo "---------------------------" | write_log
}

# Function return connect string
#########################################
get_connect_string() {
  local arg1=$1

  if [ $USE_PROXY == "FALSE" ]
  then
    echo "$DB_APP_USER/$DB_APP_PWD@$DB_TNS"
  else
    echo "$DB_APP_USER[$arg1]/$DB_APP_PWD@$DB_TNS"
  fi
}

# Function to copy and extract Patch-file
#########################################
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
        echo "$patch_target_file not found, nothing to install" | write_log
        exit 1
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
      echo "unknown option notar" | write_log
      exit 1
    fi
  fi
}

# Function to read password
#########################################

read_db_pass()
{
  if [ -z "$DB_APP_PWD" ]
  then

    unset DB_APP_PWD
    unset CHARCOUNT

    echo -n "Enter Password for deployment user ${DB_APP_USER} on ${DB_TNS}: "

    stty -echo

    CHARCOUNT=0
    while IFS= read -p "$PROMPT" -r -s -n 1 CHAR
    do
        # Enter - accept password
        if [[ $CHAR == $'\0' ]] ; then
            break
        fi
        # Backspace
        if [[ $CHAR == $'\177' ]] ; then
            if [ $CHARCOUNT -gt 0 ] ; then
                CHARCOUNT=$((CHARCOUNT-1))
                PROMPT=$'\b \b'
                DB_APP_PWD="${DB_APP_PWD%?}"
            else
                PROMPT=''
            fi
        else
            CHARCOUNT=$((CHARCOUNT+1))
            PROMPT='*'
            DB_APP_PWD+="$CHAR"
        fi
    done

    stty echo
    echo
    echo
  else
    echo "Password has allrady been set" | write_log
  fi
}

# Function to remove dropped files
#########################################

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

# Function to install schemas
##############################

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
      cd db/$schema
      echo "Installing schema $schema to ${DB_APP_USER} on ${DB_TNS}"  | write_log

      # uncomment cleaning scripts specific to this stage/branch ex:--test or --acceptance
      sed -i -E "s:--$STAGE:Prompt uncommented cleanup for stage $STAGE\n:g" $db_install_file

      $SQLCL -s "$(get_connect_string $schema)" @$db_install_file ${full_log_file}
      if [ $? -ne 0 ]
      then
        echo "ERROR when executing db/$schema/$db_install_file" | write_log
        exit 1
      fi

      cd ../..
    else
      echo "File db/$schema/$db_install_file does not exist" | write_log
    fi
  done
}

# Function to enable policies
################################

enable_policies()
{
  # policies will be created disables. now we will enable them
  if [ -e db/$DATA_SCHEMA/api/enable_policies.sql ]
  then
    echo "Enabling Policies " | write_log
    exit | $SQLCL -s "$(get_connect_string $DATA_SCHEMA)" @db/$DATA_SCHEMA/api/enable_policies.sql

    if [ $? -ne 0 ]
    then
      echo "ERROR when executing db/$DATA_SCHEMA/api/enable_policies.sql" | write_log
      exit 1
    fi
  fi
}


# Function to disable policies
################################

disable_policies()
{
  # policies will be created disables. now we will disable them
  if [ -e db/$DATA_SCHEMA/api/disable_policies.sql ]
  then
    echo "Disabling Policies " | write_log
    exit | $SQLCL -s "$(get_connect_string $DATA_SCHEMA)" @db/$DATA_SCHEMA/api/disable_policies.sql

    if [ $? -ne 0 ]
    then
      echo "ERROR when executing db/$DATA_SCHEMA/api/disable_policies.sql" | write_log
      exit 1
    fi
  fi
}

# Function to make APP unavailable
#######################################

set_apps_unavailable() {
  # exists app_install_file
  if [ -e $app_install_file ]
  then
    echo "disabling APEX-Apps ..." | write_log
    # loop throug content
    while IFS= read -r line; do
      $SQLCL -s "$(get_connect_string $APP_SCHEMA)" <<!
set define off;
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
    echo "File $app_install_file does not exist" | write_log
  fi

}


# Function to install APEX-Applications
#######################################

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
        $SQLCL -s "$(get_connect_string $APP_SCHEMA)" <<!
  Spool install_xyz.log
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
          exit 1
        else
          if [ -z ${APP_BUILD_OPTION_LIKE} ]
          then
            echo "No buildoptions found" | write_log
          else
            echo "Enabling buildoptions ${APP_BUILD_OPTION_LIKE}" | write_log

        $SQLCL -s "$(get_connect_string $APP_SCHEMA)" <<!
Spool install_xyz.log
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


    -- get IDs of build option
    for cur in (select build_option_id
                  from apex_application_build_options
                where build_option_name like '${APP_BUILD_OPTION_LIKE}%'
                  and application_id = v_application_id)
    loop
      -- set buildoption to be included
      apex_util.set_build_option_status(p_application_id        => v_application_id,
                                        p_id                    => cur.build_option_id,
                                        p_build_status          => 'INCLUDE');
    end loop;
End;
/
!

          fi
        fi

        cd ../..

        cat $line/install_xyz.log >> ${full_log_file}
        rm $line/install_xyz.log
      fi
    done < "$app_install_file"
  else
    echo "File $app_install_file does not exist" | write_log
  fi

}

## Function to write Versioninfo to DB
######################################

write_version_info()
{
  # writing version to table
  if [ -e db/$DATA_SCHEMA/api/set_version.sql ]
  then
    echo "Writing verioninfo to table" | write_log
    exit | $SQLCL -s "$(get_connect_string $DATA_SCHEMA)" @db/$DATA_SCHEMA/api/set_version.sql ${patch}
    if [ $? -ne 0 ]
    then
      echo "ERROR when executing db/$DATA_SCHEMA/api/set_version.sql" | write_log
      exit 1
    else

      # if file exists execute it
      if [ -e commits_${patch}.sql ]
      then
        echo "Writing commits to table" | write_log

        exit | $SQLCL -s "$(get_connect_string $APP_SCHEMA)" @commits_${patch}.sql ${patch}

      fi
    fi
  fi
}

## Function to call final unit tests
####################################
exec_final_unit_tests()
{
  echo "Start testing with utplsql" | write_log

  # loop through schemas
  for schema in "${SCHEMAS[@]}"
  do

    if [ -e db/$schema/api/execute_tests.sql ]
    then
      echo "Executing unit tests for schema $schema " | write_log
      exit | $SQLCL -s "$(get_connect_string $schema)" @db/$schema/api/execute_tests.sql
      if [ $? -ne 0 ]
      then
        echo "ERROR when executing db/$schema/api/execute_tests.sql" | write_log
        exit 1
      fi
    fi

  done
}

## Function to manage results of install process
################################################
manage_result()
{

  # ask for success
  echo
  echo "Move Patch?"
  echo "  N - No, keep it >  (patch-files and log are inside your folders, you have to move it manually)"
  echo "  F - Fail!       > Move logs and patchfiles to _installed/failure"
  echo "  S - Success     > Move logs and patchfiles to _installed/success"

  read modus

  shopt -s nocasematch
  case "$modus" in
    "F" )
      target_move="failure"
      ;;
    "S" )
      target_move="success"
      ;;
    *)
      echo "Files will not touched - exit" | write_log
      exit
      ;;
  esac


  target_finalize_path=${patch_target_path}/_build/${target_move}/${patch}

  # create path if not exists
  [ -d ${target_finalize_path} ] || mkdir -p ${target_finalize_path}


  echo "${mode} ${patch} moved to ${target_finalize_path}" | write_log
  echo "Done " | write_log

  # move all
  mv *${patch}* ${target_finalize_path}

  # loop through schemas
  for schema in "${SCHEMAS[@]}"
  do
    db_install_file=${mode}_${schema}_${patch}.sql
    # exists db install file
    if [ -e db/$schema/$db_install_file ]
    then
      mv db/$schema/$db_install_file ${target_finalize_path}
    fi
  done

  # write Info to markdown-table
  deployed_at=`date +"%Y-%m-%d %T"`
  deployed_by=$(whoami)

  version=`printf '%-10s' "V$patch"`
  deployed_at=`printf '%-19s' "$deployed_at"`
  deployed_by=`printf '%-11s' "$deployed_by"`

  echo "| $version | $deployed_at | $deployed_by |" >> version.md
}

#################################################################################################

print_info
extract_patchfile
read_db_pass
set_apps_unavailable
remove_dropped_files
disable_policies
install_db_schemas
enable_policies
install_apps
write_version_info
exec_final_unit_tests
manage_result
