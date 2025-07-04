#!/usr/bin/env bash
# echo "Your script args ($#) are: $@"


function usage() {
  printf "${BWHITE}setup [${CYAN}dbFlow${NC}${BWHITE}]${NC} - generate project structure and install dependencies. \n"
  # Tree chars └ ─ ├ ─ │
  echo
  printf "${BWHITE}USAGE${NC}\n"
  printf "  ${0} --generate <project-name> [--envonly]\n"
  printf "  ${0} --install [--force]\n"
  printf "  ${0} --copyto <target-path>\n"
  echo
  printf "${BWHITE}Options${NC}\n"
  printf "  -h | --help                    - Show this screen\n"
  printf "\n"
  printf "  -g | --generate <project-name> - generates project structure\n"
  printf "                                   project-name is required, other options are read from env\n"
  printf "     └─[ -w | --wizard ]         - do NOT start with a wizard questionare, import from env\n"
  printf "     └─[ -e | --envonly ]        - option on generate, to create only environment files\n"
  printf "\n"
  printf "  -i | --install                 - installs project dependencies to db\n"
  printf "     └─[ -f | --force ]          - features will be reinstalled if exists\n"
  printf "                                 - ${RED}schemas/users will be dropped and recreated${NC}\n"
  printf "                                 - ${RED}workspace will be dropped and recreated${NC}\n"
  printf "\n"
  printf "  -c | --copyto <target-path>   - copy db/_setup, env files, and .dbFlow to target\n"
  printf "\n"
  printf "  -a | --apply                   - Generate and write apply.env only\n"
  printf "     └─[ -w | --wizard ]         - do NOT start with a wizard questionare, import from env\n"
  printf "\n"
  printf "${PURPLE}Flex-Mode helpers${NC}\n"
  printf "  -s | --add_schema <schema-name>    - add schema folder to apex, db, rest and _setup incl. install-file\n"  printf "\n"
  printf "  -p | --add_workspace <schema-name> - add workspace folder to apex and _setup incl. install-files\n"
  echo
  printf "${BWHITE}Examples:${NC}\n"
  printf "  ${0} --generate mytest\n"
  printf "  ${0} --install\n"
  printf "  ${0} --copyto \"../instances/build\"\n"
  echo
  echo
  exit $1
}

# get required functions and vars
source ./.dbFlow/lib.sh

# choose CLI to call
SQLCLI=${SQLCLI:-sqlplus}

# target environment
[ ! -f ./build.env ] || source ./build.env

if [[ -e ./apply.env ]]; then
  source ./apply.env

  validate_passes
fi


# name of setup directory
targetpath="db/_setup"
basepath=$(pwd)


# array of subdirectories inside $targetpath to scan for executables (sh/sql)
array=( tablespaces directories users features workspaces acls )

function notify() {
    [[ ${1} = 0 ]] || echo ❌ EXIT "${1}"
    # you can notify some external services here,
    # ie. Slack webhook, Github commit/PR etc.
    remove2envsql
}

trap '(exit 130)' INT
trap '(exit 143)' TERM
trap 'rc=$?; notify $rc; exit $rc' EXIT

function check_vars() {
  # validate parameters
  do_exit="NO"

  if [[ -z $DB_TNS ]]; then
    echo_error "TNS not defined"
    do_exit="YES"
  fi

  ####
  if [[ ${do_exit} == "YES" ]]; then
    echo_warning "aborting"
    exit 1;
  fi

}

function print2envsql() {
  echo define project="${PROJECT}" > "${targetpath}/env.sql"

  if [[ -n ${APP_SCHEMA} ]]; then
    echo define app_schema="${APP_SCHEMA}" >> "${targetpath}/env.sql"
  fi
  if [[ -n ${DATA_SCHEMA} ]]; then
    echo define data_schema="${DATA_SCHEMA}" >> "${targetpath}/env.sql"
  fi
  if [[ -n ${LOGIC_SCHEMA} ]]; then
    echo define logic_schema="${LOGIC_SCHEMA}" >> "${targetpath}/env.sql"
  fi
  if [[ -n ${WORKSPACE} ]]; then
    echo define workspace="${WORKSPACE}" >> "${targetpath}/env.sql"
  fi
  if [[ -n ${DB_APP_PWD} ]]; then
    echo define db_app_pwd="${DB_APP_PWD}" >> "${targetpath}/env.sql"
  fi

  echo define db_app_user="${DB_APP_USER}" >> "${targetpath}/env.sql"

  if [[ ${DB_ADMIN_USER} != "sys" ]]; then
    echo define deftablespace=data >> "${targetpath}/env.sql"
  else
    echo define deftablespace=users >> "${targetpath}/env.sql"
  fi
}

function show_generate_summary() {
  local env_only=$2
  # target environment
  [ ! -f ./build.env ] || source ./build.env
  [ ! -f ./apply.env ] || source ./apply.env


  log_file="readme.md"
  if [[ ! -f ${log_file} ]]; then
    touch "${log_file}.colored"
    exec &> >(tee -a "${log_file}.colored")
  fi

  echo
  printf "# Project - ${BWHITE}$PROJECT${NC}\n"
  echo
  printf "Your project **${BWHITE}$PROJECT${NC}** has been ${GREEN}successfully${NC} created. \n"
  if [[ ${env_only} == "NO" ]]; then
    printf "Scripts have been added inside directory: \`${CYAN}db/_setup${NC}\` that allow you \n"
    printf "to create the respective schemas, workspaces as well as ACLs and features, as long \n"
    printf "as you specified them during the configuration. \n"
  fi
  echo
  printf "${BWHITE}${PROJECT} - directory structure${NC}\n"
  echo "\`\`\`"
  if [[ ${env_only} == "NO" ]]; then
  printf "|-- %-22b %b\n" "${DEPOT_PATH}" ">> Path to store your build artifacts"
  printf "|-- %-22b %b\n" "${LOG_PATH}"   ">> Path to store installation logs and artifacts to"
  fi
  printf "|-- ${CYAN}%-22b${NC} %b\n" ".dbFlow" ">> ${CYAN}dbFlow itself${NC}"
  if [[ ${env_only} == "NO" ]]; then
  printf "|-- %-22b %b\n" ".hooks" ">> Scripts/Tasks to run pre or post deployment"
  printf "|-- %-22b %b\n" "apex" ">> APEX applications in subfolders (f123)"
  if [[ ${PROJECT_MODE} = "FLEX" ]]; then
    printf "|   %-22b %b\n" "|-- ${PROJECT}_app" ">> Example DB Schema assigned to workspace"
    printf "|   %-22b %b\n" "|   |-- ${PROJECT}" ">> Example Workspace assigned to apps"
    printf "|   %-22b %b\n" "|   |   |-- f123" ">> Example Application 123 as subfolder"
  fi
  printf "|-- %-22b %b\n" "db" ">> All DB Schemas used"
  printf "|   %-22b %b\n" "|-- _setup" ">> Scripts to create schemas, features, ${BORANGE}workspaces${NC}, ..."
  printf "|   %-22b %b\n" "|-- .hooks" ">> Scripts/Tasks to run pre or post db schema deployments"
  if [[ ${PROJECT_MODE} != "FLEX" ]]; then
    if [[ -d db/${PROJECT}_logic ]]; then
      printf "|   %-22b %b\n" "|-- ${PROJECT}_data" ">> DB Schema responsible for data in MultiMode (3 Tier)"
      printf "|   %-22b %b\n" "|-- ${PROJECT}_logic" ">> DB Schema responsible for logic in MultiMode (3 Tier)"
      printf "|   %-22b %b\n" "|-- ${PROJECT}_app" ">> DB Schema responsible for app in MultiMode (3 Tier)"
    else
      printf "|   %-22b %b\n" "|-- ${PROJECT}" ">> Main DB Schema mostly used for SingleMode"
    fi
  else
  printf "|   %-22b %b\n" "|-- ${PROJECT}_app" ">> Example DB schema when using FlexMode"
  fi
  printf "|-- %-22b %b\n" "reports" ">> Place all your binaries for upload in a seperate folder here"
  printf "|-- %-22b %b\n" "rest" ">> REST Modules"
  if [[ ${PROJECT_MODE} != "FLEX" ]]; then
    printf "|   %-22b %b\n" "|-- access" ">> Place all your privileges, roles and clients here (plsql)"
    printf "|   %-22b %b\n" "|-- modules" ">> The REST modules inside seperate folders"
  else
    printf "|   %-22b %b\n" "|-- schema" ">> DB Schema responible for running this RESTservice"
    printf "|   %-22b %b\n" "|   |-- access" ">> Place all your privileges, roles and clients here (plsql)"
    printf "|   %-22b %b\n" "|   |-- module" ">> The REST modules in subfolders (api)"
  fi
  printf "|-- %-22b %b\n" "static" ">> StaticFiles used to uploads go here (managed by dbFlux)"
  fi
  printf "%-26b %b\n" "apply.env" ">> Environment configuration added to .gitignore"
  printf "%-26b %b\n" "build.env" ">> Project configuration"
  echo "\`\`\`"
  echo
  if [[ ${env_only} == "NO" ]]; then
  printf "To execute the installation just run: ${CYAN}\`.dbFlow/setup.sh --install\`${NC}\n"
  else
  printf "This was an environment only generation. This is meant for environments you are\n"
  printf "not allowed to install your initial setup on your own. For example create users\n"
  printf "and install features. \n"
  printf "To apply any patch you built run e.g. ${CYAN}.dbFlow/apply.sh --patch --version 1.2.3${NC}\n"
  fi
  echo
  printf ">For your daily work I recommend the use of the extension: \n"
  printf ">${BLBACK}**dbFlux** - https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow${NC}\n"
  printf ">\n"
  printf ">For more information refer to readme: \`${CYAN}.dbFlow/readme.md${NC}\`\n"
  echo
  printf "To configure changelog settings, just modify corresponding parameters in \`${BWHITE}build.env${NC}\`\n"
  echo
  if [[ ${env_only} == "NO" ]]; then
    if [[ ${PROJECT_MODE} != "FLEX" ]]; then
      printf "${BORANGE}Keep in mind that the script to create the workspace **${BWHITE}$PROJECT${NC}${BORANGE}** will drop the one with the same name!${NC}\n"
    else
      printf "${BORANGE}As you have choosen a flex project, you have now the option to add schemas or workspaces on your own. Just use:${NC}\n"
      printf "${CYAN}.dbFlow/setup --add_workspace \"workspace_name\"${NC}\n"
      printf "${CYAN}.dbFlow/setup --add_schema \"schema_name\"${NC}\n"
    fi
  fi

  if [[ -f "${log_file}.colored" ]]; then
    cat "${log_file}.colored" | sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" > "${log_file}"
    rm "${log_file}.colored"

    cat ".dbFlow/read_part.md" >> "${log_file}"
  fi
}


function remove2envsql() {
  rm -f "${basepath}/${targetpath}/env.sql"
}

function install() {
  local yes=${1:-"NO"}

  if [[ ! -d "${targetpath}" ]]; then
     echo_error "Project setup folder does not exist, so nothing to install. Run \"$0 --generate <project>\" at first!"
     exit 1
  fi

  if [[ $yes == "YES" ]]; then
    echo_warning "Force option detected!"
  fi

  if [[ -z "$DB_ADMIN_USER" ]]; then
    read -r -p "Enter username of admin user (admin, sys, ...) [sys]: " DB_ADMIN_USER
    DB_ADMIN_USER=${DB_ADMIN_USER:-"sys"}
  fi

  if [[ $(toLowerCase "${DB_ADMIN_USER}") != "sys" ]]; then
   DBA_OPTION=""
  fi

  if [[ -z "$DB_ADMIN_PWD" ]]; then
    ask4pwd "Enter password für user ${DB_ADMIN_USER}: "
    DB_ADMIN_PWD="${pass}"
  fi

  if [[ -z "$DB_APP_PWD" ]]; then
    ask4pwd "Enter password für user ${DB_APP_USER}: "
    DB_APP_PWD="${pass}"
  fi

  # validate connection and exit when not working
  check_admin_connection

  PROJECT_INSTALLED=$(is_any_schema_installed)
  WORKSPACE_INSTALLED=$(is_workspace_installed)

  if ([[ "${PROJECT_INSTALLED}" == *"true"* ]] || [[ "${WORKSPACE_INSTALLED}" == *"true"* ]]) && [[ ${yes} == "NO" ]]; then
    [[ "${PROJECT_INSTALLED}" == *"true"* ]] && printf "${BORANGE}One or more schemas exist${NC}\n"
    [[ "${WORKSPACE_INSTALLED}" == *"true"* ]] && printf "${BORANGE}Workspace exists${NC}\n"
    echo_error "Use option -f to force overwrite or schemas and or workspace (drop + create)"

    exit 1
  fi

  print2envsql
  #-----------------------------------------------------------#

  # check every path in given order
  for path in "${array[@]}"
  do
    level1_dir=$targetpath/$path
    if [[ -d "${level1_dir}" ]]; then
      echo "Installing $path"
      for file in $(ls "${level1_dir}" | sort )
      do
        if [[ -f "${level1_dir}"/${file} ]]; then
          BASEFL=$(basename -- "${file}")
          EXTENSION="${BASEFL##*.}"

          if [[ $EXTENSION == "sql" ]]; then
            cd "${level1_dir}" || exit
            echo "Calling ${level1_dir}/${file}"
            exit | ${SQLCLI} -S -L "${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION}" @"${file}"
            cd ../../..
          elif [[ $EXTENSION == "sh" ]]; then
            cd "${level1_dir}" || exit
            echo "Executing ${level1_dir}/${file}"
            "./${file}" "${yes}" "${DB_ADMIN_PWD}"
            cd ../../..
          fi

        elif [[ -d "${level1_dir}"/${file} ]]; then

          level2_dir=${level1_dir}/${file}

          echo "Installing $file"
          for file2 in $(ls "${level2_dir}" | sort )
          do
            if [[ -f "${level2_dir}"/${file2} ]]; then
              BASEFL=$(basename -- "${file2}")
              EXTENSION="${BASEFL##*.}"

              if [[ $EXTENSION == "sql" ]]; then
                cd "${level2_dir}" || exit
                echo "Calling ${level2_dir}/${file2}"
                exit | ${SQLCLI} -S -L "${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION}" @"${file2}"
                cd ../../../..
              elif [[ $EXTENSION == "sh" ]]; then
                cd "${level2_dir}" || exit
                echo "Executing ${level2_dir}/${file2}"
                "./${file2}" "${yes}" "${DB_ADMIN_PWD}"
                cd ../../../..
              fi
            fi

          done #file


        fi

      done #file
    fi
  done #path

  #-----------------------------------------------------------#

  remove2envsql

  echo_success "Installation done"

} # install

function copytopath() {
  local target_path=${1}

  if [[ ! -d "${targetpath}" ]]; then
     echo_error "Project setup folder does not exist, so nothing to copy. Run \"$0 --generate <project>\" at first!"
     exit 1
  fi

  [[ -d "${target_path}/${targetpath}" ]] || mkdir -p "${target_path}/db"
  echo "copy ${targetpath} to ${target_path}"
  cp -r ./${targetpath} "${target_path}"/db

  chmod +x "${target_path}"/db/_setup/features/*.sh 2>/dev/null || echo "no files to grant access to"

  echo "copy env files to ${target_path}"
  cp ./build.env "${target_path}"
  cp ./apply.env "${target_path}"

  echo "initialize git and add dbFlow as submodule"
  cp .gitignore "${target_path}"
  cd "${target_path}" || exit
  git init
  git submodule add https://github.com/MaikMichel/dbFlow.git .dbFlow
  ls -la
  cd "${basepath}" || exit

  echo "After changing your database connection you just have to execute:"
  printf "${YELLOW}.dbFlow/setup.sh install${NC}\n"
  echo "to install your base dependencies"
}


function wizard() {
  wiz_project_name="${1}"
  env_only=${2}
  apply_only=${3}

  if [[ ${env_only} == "NO" ]]; then
    if [[ ${apply_only} == "NO" ]]; then
      printf "Generate Project: ${BWHITE}${wiz_project_name}${NC}\n"
    else
      printf "Generate ${BGRAY}apply.env${NC} of Project: ${BWHITE}${wiz_project_name}${NC}\n"
    fi
  else
    printf "Configure Project: ${BWHITE}${wiz_project_name}${NC} (${BGRAY}Environment only option${NC})\n"
  fi


  if [[ ${apply_only} == "NO" ]]; then
    local local_project_mode=${PROJECT_MODE-"M"}
    read -r -p "$(printf "Which dbFLow project type do you want to create? ${BUNLINE}S${NC}ingle, ${BUNLINE}M${NC}ulti or ${BUNLINE}F${NC}lex [${BGRAY}${local_project_mode:0:1}${NC}]: ")" wiz_project_mode
    wiz_project_mode=${wiz_project_mode:-"${local_project_mode:0:1}"}

    local local_build_branch=${BUILD_BRANCH-"build"}
    read -r -p "$(printf "When running release tests, what is your prefered branch name [${BGRAY}${local_build_branch}${NC}]: ")" wiz_build_branch
    wiz_build_branch=${wiz_build_branch:-"${local_build_branch}"}

    if [[ -z ${CHANGELOG_SCHEMA} ]]; then
      local_gen_chlog_yn="N"
    else
      local_gen_chlog_yn="Y"
    fi
    read -r -p "$(printf "Would you like to process changelogs during deployment [${BGRAY}${local_gen_chlog_yn}${NC}]: ")" wiz_create_changelogs
    wiz_create_changelogs=${wiz_create_changelogs:-"${local_gen_chlog_yn}"}

    if [[ $(toLowerCase "${wiz_create_changelogs:-${local_gen_chlog_yn}}") == "y" ]]; then
      if [[ $(toLowerCase "${wiz_project_mode}") == "s" ]]; then
        # when SingleSchema then there is only one possibility
        wiz_chl_schema=${wiz_project_name}
      elif [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
        local_default_chlog_schema=${CHANGELOG_SCHEMA:-"${wiz_project_name}_app"}
        read -r -p "$(printf "What is the schema name the changelog is processed with [${BGRAY}${local_default_chlog_schema}${NC}]: ")" wiz_chl_schema
        wiz_chl_schema=${wiz_chl_schema:-"${local_default_chlog_schema}"}
      elif [[ $(toLowerCase "${wiz_project_mode}") == "m" ]]; then
        local_default_chlog_schema=${CHANGELOG_SCHEMA:-"${wiz_project_name}_app"}
        read -r -p "$(printf "What is the schema the changelog is processed with (${BUNLINE}${wiz_project_name}_data${NC}, ${BUNLINE}${wiz_project_name}_logic${NC}, ${BUNLINE}${wiz_project_name}_app${NC}) [${BGRAY}${local_default_chlog_schema}${NC}]: ")" wiz_chl_schema
        wiz_chl_schema=${wiz_chl_schema:-"${local_default_chlog_schema}"}
      fi
    fi
  fi

  local local_db_tns=${DB_TNS-"localhost:1521/freepdb1"}
  read -r -p "$(printf "Enter database connections [${BGRAY}${local_db_tns}${NC}]: ")" wiz_db_tns
  wiz_db_tns=${wiz_db_tns:-"${local_db_tns}"}

  local local_db_admin_user=${DB_ADMIN_USER-"sys"}
  read -r -p "$(printf "Enter username of admin user (${BUNLINE}admin${NC}, ${BUNLINE}sys${NC}, ...) [${BGRAY}${local_db_admin_user}${NC}]: ")" wiz_db_admin_user
  wiz_db_admin_user=${wiz_db_admin_user:-"${local_db_admin_user}"}

  ask4pwd "$(printf "Enter password for ${BUNLINE}${wiz_db_admin_user}${NC} [${BGRAY}leave blank and you will be asked for${NC}]: ")"
  if [[ ${pass} != "" ]]; then
    wiz_db_admin_pwd=`echo "${pass}"`
  fi

  if [[ $(toLowerCase "${wiz_project_mode}") != "s" ]]; then
    wiz_db_app_user=${DB_APP_USER-"${wiz_project_name}_depl"}
    ask4pwd "$(printf "Enter password for deployment_user (proxyuser: ${BUNLINE}${wiz_db_app_user}${NC}) [${BGRAY}leave blank and you will be asked for${NC}]: ")"
  else
    wiz_db_app_user=${DB_APP_USER-"${wiz_project_name}"}
    ask4pwd "$(printf "Enter password for user ${BUNLINE}${wiz_db_app_user}${NC} [${BGRAY}leave blank and you will be asked for${NC}]: ")"
  fi
  if [[ ${pass} != "" ]]; then
    wiz_db_app_pwd=`echo "${pass}"`
  fi

  local local_depot_path=${DEPOT_PATH-"_depot"}
  read -r -p "$(printf "Enter path to depot [${BGRAY}${local_depot_path}${NC}]: ")" wiz_depot_path
  wiz_depot_path=${wiz_depot_path:-"${local_depot_path}"}

  local local_stage=${STAGE-"develop"}
  read -r -p "$(printf "Enter stage of this configuration mapped to branch (${BUNLINE}develop${NC}, ${BUNLINE}test${NC}, ${BUNLINE}master${NC}) [${BGRAY}${local_stage}${NC}]: ")" wiz_stage
  wiz_stage=${wiz_stage:-"${local_stage}"}

  local local_sqlcli=${SQLCLI-"sqlplus"}
  read -r -p "$(printf "Install with ${BUNLINE}sql(cl)${NC} or ${BUNLINE}sqlplus${NC}? [${BGRAY}${local_sqlcli}${NC}]: ")" wiz_sqlcli
  wiz_sqlcli=${wiz_sqlcli:-"${local_sqlcli}"}

  local local_logpath=${LOG_PATH-"_logs"}
  read -r -p "$(printf "Enter path to place logfiles and artifacts into after installation? [${BGRAY}${local_logpath}${NC}]: ")" wiz_logpath
  wiz_logpath=${wiz_logpath:-"${local_logpath}"}

  if [[ ${apply_only} == "NO" ]]; then

    if [[ ${env_only} == "NO" ]]; then
      read -r -p "$(printf "Do you wish to generate and install default tooling? (Logger, utPLSQL, teplsql, tapi) [${BGRAY}Y${NC}]: ")" wiz_with_tools
      wiz_with_tools=${wiz_with_tools:-"Y"}

      if [[ $(toLowerCase "${wiz_project_mode}") != "f" ]]; then
        # ask for application IDs
        wiz_apex_ids=""
        read -r -p "Enter application IDs (comma separated) you wish to use initialy (100,101,...): " wiz_apex_ids

        # ask for restful Modulsa
        wiz_rest_modules=""
        read -r -p "Enter restful Moduls (comma separated) you wish to use initialy (api,test,...): " wiz_rest_modules
      fi
    else
      wiz_with_tools="N"
    fi

  fi
}

function write_apply() {
  if [[ -z ${wiz_db_tns+x} ]] || \
     [[ -z ${wiz_db_app_user+x} ]] || \
     [[ -z ${wiz_db_admin_user+x} ]] || \
     [[ -z ${wiz_depot_path+x} ]] ||\
     [[ -z ${wiz_stage+x} ]] ||\
     [[ -z ${wiz_sqlcli+x} ]]
    then
    echo_error "Not all vars set"
    exit 1
  fi

  # apply.env
  {
    echo "# DB Connection"
    echo "DB_TNS=${wiz_db_tns}"
    echo ""
    echo "# Deployment User"
    echo "DB_APP_USER=${wiz_db_app_user}"
    if [[ ${wiz_db_app_pwd} != "" ]]; then
      wiz_db_app_pwd=`echo "${wiz_db_app_pwd}" | base64`
      echo "DB_APP_PWD=\"!${wiz_db_app_pwd}\""
    else
      echo "DB_APP_PWD="
    fi
    echo ""
    echo "# SYS/ADMIN Pass"
    echo "DB_ADMIN_USER=${wiz_db_admin_user}"
    if [[ ${wiz_db_admin_pwd} != "" ]]; then
      wiz_db_admin_pwd=`echo "${wiz_db_admin_pwd}" | base64`
      echo "DB_ADMIN_PWD=\"!${wiz_db_admin_pwd}\""
    else
      echo "DB_ADMIN_PWD="
    fi
    echo ""
    echo "# Path to Depot"
    echo "DEPOT_PATH=${wiz_depot_path}"
    echo ""
    echo "# Stage mapped to source branch ( develop test master )"
    echo "# this is used to get artifacts from depot_path"
    echo "STAGE=${wiz_stage}"
    echo ""
    echo ""
    echo "# ADD this to original APP-NUM"
    echo "APP_OFFSET=0"
    echo ""
    echo "# Scripts are executed with"
    echo "SQLCLI=${wiz_sqlcli}"
    echo ""
    echo "# TEAMS Channel to Post to on success"
    echo "TEAMS_WEBHOOK_URL="
    echo ""
    echo "# Path to pace logs and artifacts into after installation"
    echo "LOG_PATH=${wiz_logpath}"
    echo ""
    echo "# List of Environment Vars to inject into global hooks, separated by colons"
    echo "# VAR_LIST=\"LOG_PATH:STAGE:DEPOT_PATH\""

  } > apply.env
}

function generate() {
  printf "${CYAN}Generating project with following options${NC}\n"
  printf "  Project:                          ${BWHITE}${wiz_project_name}${NC}\n"
  printf "  Mode:                             ${BWHITE}${wiz_project_mode}${NC}\n"
  printf "  Build Branch:                     ${BWHITE}${wiz_build_branch}${NC}\n"
  printf "  Create Changelos:                 ${BWHITE}${wiz_create_changelogs}${NC}\n"
  printf "  Schema Changelog proccessed:      ${BWHITE}${wiz_chl_schema}${NC}\n"
  printf "  Connection:                       ${BWHITE}${wiz_db_tns}${NC}\n"
  printf "  Admin User:                       ${BWHITE}${wiz_db_admin_user}${NC}\n"
  printf "  Deployment User:                  ${BWHITE}${wiz_db_app_user}${NC}\n"
  printf "  Location depot:                   ${BWHITE}${wiz_depot_path}${NC}\n"
  printf "  Location logs:                    ${BWHITE}${wiz_logpath}${NC}\n"
  printf "  Branch is mapped to Stage:        ${BWHITE}${wiz_stage}${NC}\n"
  printf "  SQl commandline:                  ${BWHITE}${wiz_sqlcli}${NC}\n"
  printf "  Install default tools:            ${BWHITE}${wiz_with_tools}${NC}\n"
  printf "  Configure with default apps:      ${BWHITE}${wiz_apex_ids}${NC}\n"
  printf "  Configure with default modules:   ${BWHITE}${wiz_rest_modules}${NC}\n"
  printf "  Just install environment onyl:    ${BWHITE}${env_only}${NC}\n"
  echo


  if [[ -z ${wiz_project_name+x} ]] || \
     [[ -z ${wiz_project_mode+x} ]] || \
     [[ -z ${wiz_build_branch+x} ]] || \
     [[ -z ${wiz_create_changelogs+x} ]] || \
     [[ -z ${wiz_db_tns+x} ]] || \
     [[ -z ${wiz_db_app_user+x} ]] || \
     [[ -z ${wiz_db_admin_user+x} ]] || \
     [[ -z ${wiz_depot_path+x} ]] ||\
     [[ -z ${wiz_stage+x} ]] ||\
     [[ -z ${wiz_sqlcli+x} ]]
    then
    echo_error "Not all vars set"
    exit 1
  fi
  printf "${BGRAY}... working ... ${NC}\n"

  # create directories :: wiz_project_mode
  if [[ ${env_only} == "NO" ]]; then
    if [[ $(toLowerCase "${wiz_project_mode}") == "m" ]]; then
      mkdir -p db/{.hooks/{pre,post},"${wiz_project_name}"_data/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,patch/{private,public},ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
      mkdir -p db/{.hooks/{pre,post},"${wiz_project_name}"_logic/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,patch/{private,public},ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
      mkdir -p db/{.hooks/{pre,post},"${wiz_project_name}"_app/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,patch/{private,public},ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
    elif [[ $(toLowerCase "${wiz_project_mode}") == "s" ]]; then
      mkdir -p db/{.hooks/{pre,post},"${wiz_project_name}"/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,patch/{private,public},ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
    elif [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
      mkdir -p db/{.hooks/{pre,post},"${wiz_project_name}"_app/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,patch/{private,public},ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
    else
      echo_error "unknown type ${wiz_project_mode}"
      exit 1
    fi
  fi


  # build.env
  {
    echo "# project name"
    echo "PROJECT=${wiz_project_name}"
    echo ""
    echo ""
    if [[ $(toLowerCase "${wiz_project_mode}") == "m" ]]; then
      echo "# In MultiSchema Mode, we have a classic 3 Tier model"
      echo "PROJECT_MODE=MULTI"
      echo "APP_SCHEMA=${wiz_project_name}_app"
      echo "DATA_SCHEMA=${wiz_project_name}_data"
      echo "LOGIC_SCHEMA=${wiz_project_name}_logic"
    elif [[ $(toLowerCase "${wiz_project_mode}") == "s" ]]; then
      echo "# In SingleSchema Mode, we have a only one schema"
      echo "PROJECT_MODE=SINGLE"
      echo "APP_SCHEMA=${wiz_project_name}"
    elif [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
      echo "# In FlexSchema Mode, you have to create the schemas by your own"
      echo "# and don't forget to grant connect through proxy_user "
      echo "PROJECT_MODE=FLEX"
    fi
    echo ""

    if [[ $(toLowerCase "${wiz_project_mode}") != "f" ]]; then
      echo ""
      echo "# workspace app belongs to"
      echo "WORKSPACE=${wiz_project_name}"
      echo ""
    fi


    echo ""
    echo "# Name of the branch, where release tests are build"
    echo "BUILD_BRANCH=${wiz_build_branch}"
    echo ""


    echo ""
    echo "# Generate a changelog with these settings"
    echo "# When template.sql file found in reports/changelog then it will be"
    echo "# executed on apply with the CHANGELOG_SCHEMA ."
    echo "# The changelog itself is structured using INTENT_PREFIXES to look"
    echo "# for in commits and to place them in corresponding INTENT_NAMES inside"
    echo "# the file itself. You can define a regexp in TICKET_MATCH to look for"
    echo "# keys to link directly to your ticketsystem using TICKET_URL"


    if [[ $(toLowerCase "${wiz_create_changelogs}") == "y" ]]; then
      echo "CHANGELOG_SCHEMA=${wiz_chl_schema}"
      echo "INTENT_PREFIXES=( Feat Fix )"
      echo "INTENT_NAMES=( Features Fixes )"
      echo "INTENT_ELSE=\"Others\""
      echo "TICKET_MATCH=\"[A-Z]\+-[0-9]\+\""
      echo "TICKET_URL=\"https://url-to-your-issue-tracker-like-jira/browse\""

      if [[ ${env_only} == "NO" ]]; then
        chltemplate=reports/changelog/template.sql
        if [[ ! -f ${chltemplate} ]]; then
          [[ -d reports/changelog ]] || mkdir -p reports/changelog
          cp ".dbFlow/scripts/changelog_template.sql" ${chltemplate}
        fi
      else
        echo "# this was an env-only configuration so you have to"
        echo "# copy template to reports/changelog folder on your own"
        echo "# cp .dbFlow/scripts/changelog_template.sql ${chltemplate}"
      fi
    else
      echo "# copy template to reports/changelog folder"
      echo "# cp .dbFlow/scripts/changelog_template.sql ${chltemplate}"
      echo "# CHANGELOG_SCHEMA=PROCESSING_SCHEMA"
      echo "# INTENT_PREFIXES=( Feat Fix )"
      echo "# INTENT_NAMES=( Features Fixes )"
      echo "# INTENT_ELSE=\"Others\""
      echo "# TICKET_MATCH=\"[A-Z]\+-[0-9]\+\""
      echo "# TICKET_URL=\"https://url-to-your-issue-tracker-like-jira/browse\""
    fi
    echo ""
    echo "# Set a personal reminder, which will ask you to proceed"
    echo "REMIND_ME=\"\""
    echo ""
  } > build.env

  write_apply

  # write gitignore
  [[ -f .gitignore ]] || touch .gitignore
  write_line_if_not_exists "# dbFlow target infos" .gitignore
  write_line_if_not_exists "apply.env" .gitignore

  echo "" >> .gitignore
  write_line_if_not_exists "# static files" .gitignore
  if [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
    write_line_if_not_exists "static/**/f*/dist" .gitignore
  else
    write_line_if_not_exists "static/f*/dist" .gitignore
  fi

  echo "" >> .gitignore
  write_line_if_not_exists "# vscode configuration" .gitignore
  write_line_if_not_exists ".vscode" .gitignore

  if [[ ${wiz_depot_path} != ".."* ]] || [[ ${wiz_depot_path} != "/"* ]]; then
    echo "" >> .gitignore
    write_line_if_not_exists "# depot inside working dir" .gitignore
    write_line_if_not_exists "${wiz_depot_path}" .gitignore
  fi

  if [[ ${env_only} == "NO" ]]; then
    # create targetpath directory
    mkdir -p "${targetpath}"/{tablespaces,directories,users,features,workspaces/"${wiz_project_name}",acls}
    mkdir -p "${wiz_depot_path}"

    # copy some examples into it
    if [[ $(toLowerCase "${wiz_project_mode}") != "f" ]]; then
      cp -rf .dbFlow/scripts/setup/workspaces/workspace/* "${targetpath}/workspaces/${wiz_project_name}"
      cp -rf .dbFlow/scripts/setup/workspaces/*.* "${targetpath}/workspaces"
    fi
    cp -rf .dbFlow/scripts/setup/acls/* "${targetpath}/acls"

    if [[ $(toLowerCase "${wiz_with_tools}") == "y" ]]; then
      cp -rf .dbFlow/scripts/setup/features/* "${targetpath}/features"
      chmod +x "${targetpath}"/features/*.sh 2>/dev/null || echo "no files to grant access to"
    else
      mkdir -p "${targetpath}"/features
    fi

    # create gen_users..
    if [[ $(toLowerCase "${wiz_project_mode}") == "m" ]]; then
      sed "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" .dbFlow/scripts/setup/users/00_depl.sql > "${targetpath}/users/00_create_${wiz_project_name}_depl.sql"

      sed "s/\^schema_name/${wiz_project_name}_data/g" .dbFlow/scripts/setup/users/01_schema.sql > "${targetpath}/users/01_create_${wiz_project_name}_data.sql"
      sed "s/\^schema_name/${wiz_project_name}_logic/g" .dbFlow/scripts/setup/users/01_schema.sql > "${targetpath}/users/02_create_${wiz_project_name}_logic.sql"
      sed "s/\^schema_name/${wiz_project_name}_app/g" .dbFlow/scripts/setup/users/01_schema.sql > "${targetpath}/users/03_create_${wiz_project_name}_app.sql"

      schema_file="${targetpath}/users/01_create_${wiz_project_name}_data.sql"
      sed "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" "${schema_file}" > "${schema_file}.tmp" && mv "${schema_file}.tmp" "${schema_file}"

      schema_file="${targetpath}/users/02_create_${wiz_project_name}_logic.sql"
      sed "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" "${schema_file}" > "${schema_file}.tmp" && mv "${schema_file}.tmp" "${schema_file}"

      schema_file="${targetpath}/users/03_create_${wiz_project_name}_app.sql"
      sed "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" "${schema_file}" > "${schema_file}.tmp" && mv "${schema_file}.tmp" "${schema_file}"

    elif [[ $(toLowerCase "${wiz_project_mode}") == "s" ]]; then
      sed "s/\^wiz_db_app_user/${wiz_project_name}/g" .dbFlow/scripts/setup/users/00_depl.sql > "${targetpath}/users/00_create_${wiz_project_name}.sql"
      sed "s/\^schema_name/${wiz_project_name}/g" .dbFlow/scripts/setup/users/02_grants.sql >> "${targetpath}/users/00_create_${wiz_project_name}.sql"
    elif [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
      sed "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" .dbFlow/scripts/setup/users/00_depl.sql > "${targetpath}/users/00_create_${wiz_project_name}_depl.sql"
    fi

    # static files
    mkdir -p {apex,static,rest,reports,.hooks/{pre,post}}

    # default directories
    # split ids gen directories
    if [[ $(toLowerCase "${wiz_project_mode}") != "f" ]]; then
      apexids=(`echo "${wiz_apex_ids}" | sed 's/,/\n/g'`)
      for apxID in "${apexids[@]}"
      do
        mkdir -p apex/f"${apxID}"
        mkdir -p static/f"${apxID}"/{dist/{css,img,js},src/{css,img,js}}
      done
    fi


    # default directories
    # split modules
    if [[ $(toLowerCase "${wiz_project_mode}") != "f" ]]; then
      restmodules=(`echo "${wiz_rest_modules}" | sed 's/,/\n/g'`)
      for restMOD in "${restmodules[@]}"
      do
        mkdir -p rest/modules/"${restMOD}"
        mkdir -p rest/access/{privileges,roles,mapping}
      done
    fi

    # workspace files
    if [[ $(toLowerCase "${wiz_project_mode}") != "f" ]]; then
      workspace_file="${targetpath}/workspaces/${wiz_project_name}/create_00_workspace.sql"
      sed "s/\^workspace/${wiz_project_name}/g" "${workspace_file}" > "${workspace_file}.tmp" && mv "${workspace_file}.tmp" "${workspace_file}"

      wsadmin_file="${targetpath}/workspaces/${wiz_project_name}/create_01_user_wsadmin.sql"
      sed "s/\^workspace/${wiz_project_name}/g" "${wsadmin_file}" > "${wsadmin_file}.tmp" && mv "${wsadmin_file}.tmp" "${wsadmin_file}"

      if [[ $(toLowerCase "${wiz_project_mode}") == "s" ]]; then
        sed "s/\^app_schema/${wiz_project_name}/g" "${workspace_file}" > "${workspace_file}.tmp" && mv "${workspace_file}.tmp" "${workspace_file}"
        sed "s/\^app_schema/${wiz_project_name}/g" "${wsadmin_file}" > "${wsadmin_file}.tmp" && mv "${wsadmin_file}.tmp" "${wsadmin_file}"
      else
        sed "s/\^app_schema/${wiz_project_name}_app/g" "${workspace_file}" > "${workspace_file}.tmp" && mv "${workspace_file}.tmp" "${workspace_file}"
        sed "s/\^app_schema/${wiz_project_name}_app/g" "${wsadmin_file}" > "${wsadmin_file}.tmp" && mv "${wsadmin_file}.tmp" "${wsadmin_file}"
      fi
    fi
  fi

  show_generate_summary "${wiz_project_name}" "${env_only}"
} # generate

function is_any_schema_installed () {
    ${SQLCLI} -S -L "${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION}" << EOF
    set heading off
    set feedback off
    set pages 0
    with checksql as (select count(1) cnt
                        from all_users
                       where username in (upper('${DATA_SCHEMA}'), upper('${LOGIC_SCHEMA}'), upper('${APP_SCHEMA}')))
    select case when nvl(cnt, 0) = 0 then 'false' else 'true' end
      from checksql;

EOF

}

function is_workspace_installed () {
  ${SQLCLI} -S -L "${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION}" << EOF
    set heading off
    set feedback off
    set pages 0
    with checksql as (select count(1) cnt
                        from apex_workspaces
                       where workspace = upper('${WORKSPACE}'))
    select case when nvl(cnt, 0) = 0 then 'false' else 'true' end
      from checksql;

EOF

}

function add_workspace () {
  local workspace_name=${1}

  # check if projectmode is flex
  if [[ ${PROJECT_MODE} != "FLEX" ]]; then
    echo_error "This option is only allowed when project mode is FLEX"
    exit 1
  fi

  # check if there is at least one folder inside dir ./apex
  if [[ ! -d "./apex" ]] || [[ -z $(ls -A ./apex) ]]; then
    echo_error "No folders found inside ./apex"
    exit 1
  fi

  # if there is exact one folder inside ./apex then assign it to a variable, otherwise let the user choose a folder
  schema_folders=($(ls -d ./apex/*/))
  if [[ ${#schema_folders[@]} -eq 1 ]]; then
    chosen_folder=${schema_folders[0]}
  else
    echo "Multiple folders found inside ./apex. Please choose one:"
    select chosen_folder in "${schema_folders[@]}"; do
      if [[ -n $chosen_folder ]]; then
        break
      else
        echo "Invalid selection. Please try again."
      fi
    done
  fi

  # add workspace folder to chosen folder
  mkdir -p "${chosen_folder}/${workspace_name}"

  # copy template files to setup
  mkdir -p "${targetpath}/workspaces/${workspace_name}"
  cp -rf .dbFlow/scripts/setup/workspaces/workspace/* "${targetpath}/workspaces/${workspace_name}/"

  echo_success "Workspace ${workspace_name} added successfully, workspace creation files created, you can edit or run them now"
  printf "see folder: ${BORANGE}${targetpath}/workspaces/${workspace_name}${NC}\n"
  ls -la "${targetpath}/workspaces/${workspace_name}"

  schema_name=$(basename "${chosen_folder}")
  # loop through files and replace placeholders
  for file in "${targetpath}/workspaces/${workspace_name}"/*; do
    if [[ -f "${file}" ]]; then
      sed "s/\^workspace/${workspace_name}/g" "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
      sed "s/\^app_schema/${schema_name}/g" "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
    fi
  done


}

function add_schema () {
  local schema_name=${1}

  if [[ ${PROJECT_MODE} != "FLEX" ]]; then
    echo_error "This option is only allowed when project mode is FLEX"
    exit 1
  fi

  if [[ -d "db/${schema_name}" ]]; then
    echo_error "Schema ${schema_name} already exists"
    exit 1
  fi

  # count files in users
  file_count=$(printf "%02d" "$(find "${targetpath}/users" -type f | wc -l)")

  # edit files and replace placeholders
  schema_file="${targetpath}/users/${file_count}_create_${schema_name}.sql"
  sed "s/\^schema_name/${schema_name}/g" .dbFlow/scripts/setup/users/01_schema.sql > "${schema_file}"
  sed "s/\^wiz_db_app_user/${schema_name}_depl/g" "${schema_file}" > "${schema_file}.tmp" && mv "${schema_file}.tmp" "${schema_file}"

  echo_success "Schema ${schema_name} added successfully, schema creation file ${schema_file} created, you can edit or run it now"

  # create folders
  mkdir -p db/"${schema_name}"/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,patch/{private,public},ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}

  mkdir "apex/${schema_name}"
  mkdir "rest/${schema_name}"

  # no static folder because this is a dbFLux-feature
}

function check_params_and_run_command() {
  pname_argument="-"
  folder_argument="-"

  help_option="NO"
  gen_project_option="NO"
  inst_project_option="NO"
  copy_config_option="NO"
  envonly_option="NO"
  force_option="NO"
  wizard_option="NO"
  apply_option="NO"
  add_workspace_option="NO"
  add_schema_option="NO"

  while getopts_long 'hg:p:s:ic:efwa help generate: add_workspace: add_schema: install copyto: envonly force wizard apply' OPTKEY "${@}"; do
      case ${OPTKEY} in
          'h'|'help')
              help_option="YES"
              ;;
          'g'|'generate')
              gen_project_option="YES"
              pname_argument="${OPTARG}"
              ;;
          'p'|'add_workspace')
              add_workspace_option="YES"
              pname_argument="${OPTARG}"
              ;;
          's'|'add_schema')
              add_schema_option="YES"
              pname_argument="${OPTARG}"
              ;;
          'i'|'install')
              inst_project_option="YES"
              ;;
          'c'|'copyto')
              copy_config_option="YES"
              folder_argument="${OPTARG}"
              ;;
          'e'|'envonly')
              envonly_option="YES"
              ;;
          'f'|'force')
              force_option="YES"
              ;;
          'w'|'wizard')
              wizard_option="YES"
              ;;
          'a'|'apply')
              apply_option="YES"
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

  if [[ $# -lt 1 ]]; then
    printf "${RED}No parameters found${NC}\n" 1>&2
    usage 1
  fi

  if [[ ${gen_project_option} == "YES" ]] && [[ ${#pname_argument} -lt 3 ]]; then
    printf "${RED}Missing or to small argument project name (${pname_argument}) for command generate${NC}\n" 1>&2
    usage 2
  fi

  if [[ ${add_workspace_option} == "YES" ]] && [[ ${#pname_argument} -lt 3 ]]; then
    printf "${RED}Missing or to small argument workspace name (${pname_argument}) for command add_worspace${NC}\n" 1>&2
    usage 2
  fi

  if [[ ${add_schema_option} == "YES" ]] && [[ ${#pname_argument} -lt 3 ]]; then
    printf "${RED}Missing or to small argument schema name (${pname_argument}) for command add_schema${NC}\n" 1>&2
    usage 2
  fi
  if [[ ${copy_config_option} == "YES" ]] && [[ ${#folder_argument} -lt 3 ]]; then
    printf "${RED}Missing or to small argument target folder (${folder_argument}) for command copyto${NC}\n" 1>&2
    usage 3
  fi

    ####
  if [[ ${gen_project_option} == "YES" ]] && [[ ${#pname_argument} -gt 2 ]]; then
    if [[ "${pname_argument}" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
      # Default: use wizard
      if [[ ${wizard_option} != "YES" ]]; then
        wizard ${pname_argument} ${envonly_option} "NO"
      fi
      generate
      exit 0
    else
      printf "${RED}Invalid project name! Project name must be a valid schema name.${NC}\n" 1>&2
      exit 4
    fi
  fi

  if [[ ${add_workspace_option} == "YES" ]] && [[ ${#pname_argument} -gt 2 ]]; then
    if [[ "${pname_argument}" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
      add_workspace ${pname_argument}
      exit 0
    else
      printf "${RED}Invalid workspace name!${NC}\n" 1>&2
      exit 4
    fi
  fi

  if [[ ${add_schema_option} == "YES" ]] && [[ ${#pname_argument} -gt 2 ]]; then
    if [[ "${pname_argument}" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
      add_schema ${pname_argument}
      exit 0
    else
      printf "${RED}Invalid schema name!${NC}\n" 1>&2
      exit 4
    fi
  fi

  if [[ ${copy_config_option} == "YES" ]] && [[ ${#folder_argument} -gt 2 ]]; then
    copytopath ${folder_argument}
    exit 0
  fi

  if [[ ${inst_project_option} == "YES" ]]; then
    install ${force_option}
    exit 0
  fi

  if [[ ${apply_option} == "YES" ]]; then
    if [[ -f "./build.env" ]]; then
      source "./build.env"

      if [[ ${wizard_option} != "YES" ]]; then
        wizard ${PROJECT} ${envonly_option} ${apply_option}
      fi

      write_apply

      echo
      printf "${BGREEN}apply.env successfully written${NC}\n"
      printf "For your daily work I recommend the use of the extension: \n"
      printf "${BLBACK}dbFlux - https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow${NC}\n"
      printf "For more information refer to readme: ${CYAN}.dbFlow/readme.md${NC} or the online docs: https://maikmichel.github.io/dbFlow\n"

      exit 0
    else
      printf "${RED}A valid dbFlow project has to exist, before you are able to generate an apply.env file.${NC}\n" 1>&2
      exit 6
    fi
  fi;

  ####

  if [[ $# -gt 0 ]]; then
    printf "${RED}Unknown arguments${NC}\n" 1>&2
    usage 5
  fi
}

# validate params this script was called with
check_params_and_run_command "$@"
