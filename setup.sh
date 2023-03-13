#!/usr/bin/env bash
# echo "Your script args ($#) are: $@"


function usage() {
  echo -e "${BWHITE}setup [${CYAN}dbFlow${NC}${BWHITE}]${NC} - generate project structure and install dependencies. "
  # Tree chars └ ─ ├ ─ │
  echo
  echo -e "${BWHITE}USAGE${NC}"
  echo -e "  ${0} --generate <project-name> [--envonly]"
  echo -e "  ${0} --install [--force]"
  echo -e "  ${0} --copyto <target-path>"
  echo
  echo -e "${BWHITE}Options${NC}"
  echo -e "  -h | --help                    - Show this screen"
  echo -e "  -d | --debug                   - Show additionaly output messages"
  echo -e ""
  echo -e "  -g | --generate <project-name> - generates project structure"
  echo -e "                                   project-name is required, other options are read from env"
  echo -e "     └─[ -e | --envonly ]        - option on generate, to create only environment files"
  echo -e ""
  echo -e "  -i | --install                 - installs project dependencies to db"
  echo -e "     └─[ -f | --force ]          - features will be reinstalled if exists"
  echo -e "                                 - ${RED}schemas/users will be dropped and recreated${NC}"
  echo -e "                                 - ${RED}workspace will be dropped and recreated${NC}"
  echo -e ""
  echo -e "  - c | --copyto <target-path>   - copy db/_setup, env files, and .dbFlow to target"
  echo
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  ${0} --generate mytest"
  echo -e "  ${0} --install"
  echo -e "  ${0} --copyto \"../../instances/build\""
  echo
  echo
  exit 1
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
    echo define wiz_db_app_pwd="${DB_APP_PWD}" >> "${targetpath}/env.sql"
  fi

  echo define wiz_db_app_user="${DB_APP_USER}" >> "${targetpath}/env.sql"

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

  echo -e
  echo -e
  echo -e "${BGREEN}Congratulations${NC}"
  echo -e "Your project ${BWHITE}$PROJECT${NC} has been ${GREEN}successfully${NC} created. "
  if [[ ${env_only} == "NO" ]]; then
    echo -e "Scripts have been added inside directory: ${CYAN}db/_setup${NC} that allow you "
    echo -e "to create the respective schemas, workspaces as well as ACLs and features, as long "
    echo -e "as you specified them during the configuration. "
  fi
  echo
  echo -e "${BWHITE}${PROJECT} - directory structure${NC}"
  if [[ ${env_only} == "NO" ]]; then
  printf "|-- %-22b %b\n" "${DEPOT_PATH}" ">> Path to store your build artifacts"
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
  echo
  if [[ ${env_only} == "NO" ]]; then
  echo -e "To execute the installation just run: ${CYAN}.dbFlow/setup.sh --install${NC}"
  else
  echo -e "This was an environment only generation. This is meant for environments you are"
  echo -e "not allowed to install your initial setup on your own. For example create users"
  echo -e "and install features. "
  echo -e "To apply any patch you built run e.g. ${CYAN}.dbFlow/apply.sh --patch --version 1.2.3${NC}"
  fi
  echo
  echo -e "For your daily work I recommend the use of the extension: "
  echo -e "${BLBACK}dbFlux - https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow${NC}"
  echo -e "For more information refer to readme: ${CYAN}.dbFlow/readme.md${NC}"
  echo
  echo -e "To configure changelog settings, just modify corresponding parameters in ${BWHITE}build.env${NC}"
  echo
  if [[ ${env_only} == "NO" ]]; then
  echo -e "${BORANGE}Keep in mind that the script to create the workspace ${BWHITE}$PROJECT${NC} ${BORANGE}will drop the one with the same name!${NC}"
  fi
}


function remove2envsql() {
  rm -f "${basepath}/${targetpath}/env.sql"
}

function install() {
  local yes=${1:-"NO"}

  if [[ ! -d "${targetpath}" ]]; then
     echo_error "Project setup folder does not exists, so nothing to install. Run \"$0 --generate <project>\" at first!"
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
    [[ "${PROJECT_INSTALLED}" == *"true"* ]] && echo -e "${BORANGE}One or more schemas exist${NC}"
    [[ "${WORKSPACE_INSTALLED}" == *"true"* ]] && echo -e "${BORANGE}Workspace exists${NC}"
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
     echo_error "Project setup folder does not exists, so nothing to copy. Run \"$0 --generate <project>\" at first!"
     exit 1
  fi

  [[ -d "${target_path}/${targetpath}" ]] || mkdir -p "${target_path}/db"
  echo "copy ${targetpath} to ${target_path}"
  cp -r ./${targetpath} "${target_path}"/db

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
  echo -e "${YELLOW}.dbFlow/setup.sh install${NC}"
  echo "to install your base dependencies"
}


function wizard() {
  wiz_project_name="${1}"
  env_only=${2}

  if [[ ${env_only} == "NO" ]]; then
    echo -e "Generate Project: ${BWHITE}${wiz_project_name}${NC}"
  else
    echo -e "Configure Project: ${BWHITE}${wiz_project_name}${NC} (Environment only option)"
  fi

  local local_project_mode=${PROJECT_MODE-"M"}
  read -r -p "$(echo -e "Which dbFLow project type do you want to create? ${BUNLINE}S${NC}ingle, ${BUNLINE}M${NC}ulti or ${BUNLINE}F${NC}lex [${BGRAY}${local_project_mode:0:1}${NC}]: ")" wiz_project_mode
  wiz_project_mode=${wiz_project_mode:-"${local_project_mode:0:1}"}

  local local_build_branch=${BUILD_BRANCH-"build"}
  read -r -p "$(echo -e "When running release tests, what is your prefered branch name [${BGRAY}${local_build_branch}${NC}]: ")" wiz_build_branch
  wiz_build_branch=${wiz_build_branch:-"${local_build_branch}"}

  if [[ -z ${CHANGELOG_SCHEMA} ]]; then
    local_gen_chlog_yn="N"
  else
    local_gen_chlog_yn="Y"
  fi
  read -r -p "$(echo -e "Would you like to process changelogs during deployment [${BGRAY}${local_gen_chlog_yn}${NC}]: ")" wiz_create_changelogs
  wiz_create_changelogs=${wiz_create_changelogs:-"${local_gen_chlog_yn}"}

  if [[ $(toLowerCase "${wiz_create_changelogs:-${local_gen_chlog_yn}}") == "y" ]]; then
    if [[ $(toLowerCase "${wiz_project_mode}") == "s" ]]; then
      # when SingleSchema then there is only one possibility
      wiz_chl_schema=${wiz_project_name}
    elif [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
      local_default_chlog_schema=${CHANGELOG_SCHEMA:-"${wiz_project_name}_app"}
      read -r -p "$(echo -e "What is the schema name the changelog is processed with [${BGRAY}${local_default_chlog_schema}${NC}]: ")" wiz_chl_schema
      wiz_chl_schema=${wiz_chl_schema:-"${local_default_chlog_schema}"}
    elif [[ $(toLowerCase "${wiz_project_mode}") == "m" ]]; then
      local_default_chlog_schema=${CHANGELOG_SCHEMA:-"${wiz_project_name}_app"}
      read -r -p "$(echo -e "What is the schema the changelog is processed with (${BUNLINE}${wiz_project_name}_data${NC}, ${BUNLINE}${wiz_project_name}_logic${NC}, ${BUNLINE}${wiz_project_name}_app${NC}) [${BGRAY}${local_default_chlog_schema}${NC}]: ")" wiz_chl_schema
      wiz_chl_schema=${wiz_chl_schema:-"${local_default_chlog_schema}"}
    fi
  fi

  local local_db_tns=${DB_TNS-"localhost:1521/xepdb1"}
  read -r -p "$(echo -e "Enter database connections [${BGRAY}${local_db_tns}${NC}]: ")" wiz_db_tns
  wiz_db_tns=${wiz_db_tns:-"${local_db_tns}"}

  local local_db_admin_user=${DB_ADMIN_USER-"sys"}
  read -r -p "$(echo -e "Enter username of admin user (${BUNLINE}admin${NC}, ${BUNLINE}sys${NC}, ...) [${BGRAY}${local_db_admin_user}${NC}]: ")" wiz_db_admin_user
  wiz_db_admin_user=${wiz_db_admin_user:-"${local_db_admin_user}"}

  ask4pwd "$(echo -e "Enter password for ${BUNLINE}${wiz_db_admin_user}${NC} [${BGRAY}leave blank and you will be asked for${NC}]: ")"
  if [[ ${pass} != "" ]]; then
    wiz_db_admin_pwd=`echo "${pass}" | base64`
  fi

  if [[ $(toLowerCase "${wiz_project_mode}") != "s" ]]; then
    wiz_db_app_user=${DB_APP_USER-"${wiz_project_name}_depl"}
    ask4pwd "$(echo -e "Enter password for deployment_user (proxyuser: ${BUNLINE}${wiz_db_app_user}${NC}) [${BGRAY}leave blank and you will be asked for${NC}]: ")"
  else
    wiz_db_app_user=${DB_APP_USER-"${wiz_project_name}"}
    ask4pwd "$(echo -e "Enter password for user ${BUNLINE}${wiz_db_app_user}${NC} [${BGRAY}leave blank and you will be asked for${NC}]: ")"
  fi
  if [[ ${pass} != "" ]]; then
    wiz_db_app_pwd=`echo "${pass}" | base64`
  fi

  local local_depot_path=${DEPOT_PATH-"_depot"}
  read -r -p "$(echo -e "Enter path to depot [${BGRAY}${local_depot_path}${NC}]: ")" wiz_depot_path
  wiz_depot_path=${wiz_depot_path:-"${local_depot_path}"}

  local local_stage=${STAGE-"develop"}
  read -r -p "$(echo -e "Enter stage of this configuration mapped to branch (${BUNLINE}develop${NC}, ${BUNLINE}test${NC}, ${BUNLINE}master${NC}) [${BGRAY}${local_stage}${NC}]: ")" wiz_stage
  wiz_stage=${wiz_stage:-"${local_stage}"}

  if [[ ${env_only} == "NO" ]]; then
    read -r -p "$(echo -e "Do you wish to generate and install default tooling? (Logger, utPLSQL, teplsql, tapi) [${BGRAY}Y${NC}]: ")" wiz_with_tools
    wiz_with_tools=${wiz_with_tools:-"Y"}
  else
    wiz_with_tools="N"
  fi

  local local_sqlcli=${SQLCLI-"sqlplus"}
  read -r -p "$(echo -e "Install with ${BUNLINE}sql(cl)${NC} or ${BUNLINE}sqlplus${NC}? [${BGRAY}${local_sqlcli}${NC}]: ")" wiz_sqlcli
  wiz_sqlcli=${wiz_sqlcli:-"${local_sqlcli}"}

  if [[ ${env_only} == "NO" ]]; then
  # ask for application IDs
    wiz_apex_ids=""
    read -r -p "Enter application IDs (comma separated) you wish to use initialy (100,101,...): " wiz_apex_ids

    # ask for restful Modulsa
    wiz_rest_modules=""
    read -r -p "Enter restful Moduls (comma separated) you wish to use initialy (api,test,...): " wiz_rest_modules
  fi
}

function generate() {
  # TODO: Check all necessary vars before doining anything
  echo "wiz_project_name: ${wiz_project_name+x}"
  echo "wiz_project_mode: ${wiz_project_mode+x}"
  echo "wiz_build_branch: ${wiz_build_branch+x}"
  echo "wiz_create_changelogs: ${wiz_create_changelogs+x}"
  echo "wiz_db_tns: ${wiz_db_tns+x}"
  echo "wiz_db_app_user: ${wiz_db_app_user+x}"
  echo "wiz_db_admin_user: ${wiz_db_admin_user+x}"
  echo "wiz_depot_path: ${wiz_depot_path+x}"
  echo "wiz_stage: ${wiz_stage+x}"
  echo "wiz_sqlcli: ${wiz_sqlcli+x}"
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

  # create directories :: wiz_project_mode
  if [[ ${env_only} == "NO" ]]; then
    if [[ $(toLowerCase "${wiz_project_mode}") == "m" ]]; then
      mkdir -p db/{.hooks/{pre,post},"${wiz_project_name}"_data/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
      mkdir -p db/{.hooks/{pre,post},"${wiz_project_name}"_logic/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
      mkdir -p db/{.hooks/{pre,post},"${wiz_project_name}"_app/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
    elif [[ $(toLowerCase "${wiz_project_mode}") == "s" ]]; then
      mkdir -p db/{.hooks/{pre,post},"${wiz_project_name}"/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
    elif [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
      mkdir -p db/{.hooks/{pre,post},"${wiz_project_name}"_app/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
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

      if [[ ${env_only} == "NO" ]]; then
        echo "INTENT_PREFIXES=( Feat Fix )"
        echo "INTENT_NAMES=( Features Fixes )"
        echo "INTENT_ELSE=\"Others\""
        echo "TICKET_MATCH=\"[A-Z]\+-[0-9]\+\""
        echo "TICKET_URL=\"https://url-to-your-issue-tracker-like-jira/browse\""

        chltemplate=reports/changelog/template.sql
        if [[ ! -f ${chltemplate} ]]; then
          [[ -d reports/changelog ]] || mkdir -p reports/changelog
          cp ".dbFlow/scripts/changelog_template.sql" ${chltemplate}
        fi
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
  } > build.env

  # apply.env
  {
    echo "# DB Connection"
    echo "DB_TNS=${wiz_db_tns}"
    echo ""
    echo "# Deployment User"
    echo "DB_APP_USER=${wiz_db_app_user}"
    if [[ ${wiz_db_app_pwd} != "" ]]; then
      echo "DB_APP_PWD=\"!${wiz_db_app_pwd}\""
    else
      echo "DB_APP_PWD="
    fi
    echo ""
    echo "# SYS/ADMIN Pass"
    echo "DB_ADMIN_USER=${wiz_db_admin_user}"
    if [[ ${wiz_db_admin_pwd} != "" ]]; then
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
  } > apply.env

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

  if [[ ${wiz_depot_path} != ".."* ]]; then
    echo "" >> .gitignore
    write_line_if_not_exists "# depot inside wording dir" .gitignore
    write_line_if_not_exists "${wiz_depot_path}" .gitignore
  fi

  if [[ ${env_only} == "NO" ]]; then
    # create targetpath directory
    mkdir -p "${targetpath}"/{tablespaces,directories,users,features,workspaces/"${wiz_project_name}",acls}
    mkdir -p "${wiz_depot_path}"

    # copy some examples into it
    cp -rf .dbFlow/scripts/setup/workspaces/workspace/* "${targetpath}/workspaces/${wiz_project_name}"
    cp -rf .dbFlow/scripts/setup/workspaces/*.* "${targetpath}/workspaces"
    cp -rf .dbFlow/scripts/setup/acls/* "${targetpath}/acls"

    if [[ $(toLowerCase "${wiz_with_tools}") == "y" ]]; then
      cp -rf .dbFlow/scripts/setup/features/* "${targetpath}/features"
      chmod +x "${targetpath}"/features/*.sh
    else
      mkdir -p "${targetpath}"/features
    fi

    # create gen_users..
    if [[ $(toLowerCase "${wiz_project_mode}") == "m" ]]; then
      sed "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" .dbFlow/scripts/setup/users/00_depl.sql > "${targetpath}/users/00_create_${wiz_project_name}_depl.sql"

      sed "s/\^schema_name/${wiz_project_name}_data/g" .dbFlow/scripts/setup/users/01_schema.sql > "${targetpath}/users/01_create_${wiz_project_name}_data.sql"
      sed "s/\^schema_name/${wiz_project_name}_logic/g" .dbFlow/scripts/setup/users/01_schema.sql > "${targetpath}/users/02_create_${wiz_project_name}_logic.sql"
      sed "s/\^schema_name/${wiz_project_name}_app/g" .dbFlow/scripts/setup/users/01_schema.sql > "${targetpath}/users/03_create_${wiz_project_name}_app.sql"

      sed -i "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" "${targetpath}/users/01_create_${wiz_project_name}_data.sql"
      sed -i "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" "${targetpath}/users/02_create_${wiz_project_name}_logic.sql"
      sed -i "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" "${targetpath}/users/03_create_${wiz_project_name}_app.sql"

    elif [[ $(toLowerCase "${wiz_project_mode}") == "s" ]]; then
      sed "s/\^wiz_db_app_user/${wiz_project_name}/g" .dbFlow/scripts/setup/users/00_depl.sql > "${targetpath}/users/00_create_${wiz_project_name}.sql"
      sed "s/\^schema_name/${wiz_project_name}/g" .dbFlow/scripts/setup/users/02_grants.sql >> "${targetpath}/users/00_create_${wiz_project_name}.sql"
    elif [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
      sed "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" .dbFlow/scripts/setup/users/00_depl.sql > "${targetpath}/users/00_create_${wiz_project_name}_depl.sql"
      sed "s/\^schema_name/${wiz_project_name}_app/g" .dbFlow/scripts/setup/users/01_schema.sql > "${targetpath}/users/01_create_${wiz_project_name}_app.sql"
      sed -i "s/\^wiz_db_app_user/${wiz_project_name}_depl/g" "${targetpath}/users/01_create_${wiz_project_name}_app.sql"
    fi

    # static files
    mkdir -p {apex,static,rest,reports,.hooks/{pre,post}}
    if [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
      mkdir -p apex/"${wiz_project_name}"_app/"${wiz_project_name}"
      mkdir -p static/"${wiz_project_name}"_app/"${wiz_project_name}"
      mkdir -p rest/"${wiz_project_name}"_app
    fi

    # default directories
    # split ids gen directories
    apexids=(`echo "${wiz_apex_ids}" | sed 's/,/\n/g'`)
    for apxID in "${apexids[@]}"
    do
      if [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
        mkdir -p apex/"${wiz_project_name}"_app/"${wiz_project_name}"/f"${apxID}"
        mkdir -p static/"${wiz_project_name}"_app/"${wiz_project_name}"/f"${apxID}"/{dist/{css,img,js},src/{css,img,js}}
      else
        mkdir -p apex/f"${apxID}"
        mkdir -p static/f"${apxID}"/{dist/{css,img,js},src/{css,img,js}}
      fi
    done


    # default directories
    # split modules
    restmodules=(`echo "${wiz_rest_modules}" | sed 's/,/\n/g'`)
    for restMOD in "${restmodules[@]}"
    do
      if [[ $(toLowerCase "${wiz_project_mode}") == "f" ]]; then
        mkdir -p rest/"${wiz_project_name}"_app/modules/"${restMOD}"
        mkdir -p rest/"${wiz_project_name}"_app/access/{privileges,roles,mapping}
      else
        mkdir -p rest/modules/"${restMOD}"
        mkdir -p rest/access/{privileges,roles,mapping}
      fi
    done

    # workspace files
    sed -i "s/\^workspace/${wiz_project_name}/g" "${targetpath}/workspaces/${wiz_project_name}/create_00_workspace.sql"
    sed -i "s/\^workspace/${wiz_project_name}/g" "${targetpath}/workspaces/${wiz_project_name}/create_01_user_wsadmin.sql"
    if [[ $(toLowerCase "${wiz_project_mode}") == "s" ]]; then
      sed -i "s/\^app_schema/${wiz_project_name}/g" "${targetpath}/workspaces/${wiz_project_name}/create_00_workspace.sql"
      sed -i "s/\^app_schema/${wiz_project_name}/g" "${targetpath}/workspaces/${wiz_project_name}/create_01_user_wsadmin.sql"
    else
      sed -i "s/\^app_schema/${wiz_project_name}_app/g" "${targetpath}/workspaces/${wiz_project_name}/create_00_workspace.sql"
      sed -i "s/\^app_schema/${wiz_project_name}_app/g" "${targetpath}/workspaces/${wiz_project_name}/create_01_user_wsadmin.sql"
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


function check_params_and_run_command() {
  debug="n" help="h" gen="n" inst="n" pname="-" cptfld="-" envonly="NO" force="NO" withenvoption="NO"

  while getopts_long 'dhg:ic:ef debug help generate: install copyto: envonly force' OPTKEY "${@}"; do
      case ${OPTKEY} in
          'd'|'debug')
              d="y"
              ;;
          'h'|'help')
              h="y"
              ;;
          'g'|'generate')
              g="y"
              pname="${OPTARG}"
              ;;
          'i'|'install')
              i="y"
              ;;
          'c'|'copyto')
              c="y"
              cptfld="${OPTARG}"
              ;;
          'e'|'envonly')
              envonly="YES"
              withenvoption="YES"
              ;;
          'f'|'force')
              force="YES"
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

  if [[ $# -lt 1 ]]; then
    echo -e "${RED}No parameters found${NC}" 1>&2
    usage
  fi

  if [[ -n $g ]] && [[ ${pname} == "-" ]]; then
    echo -e "${RED}Missing argument project name for command generate${NC}" 1>&2
    usage
  fi

  if [[ -n $c ]] && [[ ${cptfld} == "-" ]]; then
    echo -e "${RED}Missing argument target folder for command copyto${NC}" 1>&2
    usage
  fi

    ####
  if [[ -n $g ]] && [[ ${pname} != "-" ]]; then
    if [[ $# -gt 2 ]] && [[ ${withenvoption} == "NO" ]]; then
      echo -e "${RED}Unknown argument(s) detected${NC}" 1>&2
      usage
    else
      if [[ "${pname}" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        wizard ${pname} ${envonly}
        generate
        exit 0
      else
        echo -e "${RED}Invalid project name! Project name must be a valid schema name.${NC}" 1>&2
        exit 1
      fi
    fi
  fi

  if [[ -n $c ]] && [[ ${cptfld} != "-" ]]; then
    copytopath ${cptfld}
    exit 0
  fi

  if [[ -n $i ]]; then
    install ${force}
    exit 0
  fi

  ####

  if [[ $# -gt 0 ]]; then
    echo -e "${RED}Unknown arguments${NC}" 1>&2
    usage
  fi
}

# validate params this script was called with
check_params_and_run_command "$@"
