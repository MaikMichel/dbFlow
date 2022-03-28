#!/bin/bash
# echo "Your script args ($#) are: $@"


usage() {
  echo -e "${BYELLOW}setup [dbFlow]${NC} - generate project structure and install dependencies. "

  echo
  echo -e "${BWHITE}USAGE${NC}"
  echo -e "  $0 <COMMAND>"
  echo
  echo -e "${BWHITE}COMMANDS${NC}"
  echo -e "  generate <project-name>                    generates project structure                         ${BWHITE}*required${NC}"
  echo -e ""
  echo -e "  install                                    installs project dependencies to db"
  echo -e "    -f (force overwrite)                     features will be reinstalled if exists"
  echo -e "                                             schemas/users will be dropped if exists"
  echo -e "                                             and recreated"
  echo
  echo -e "  export <target-schema>|ALL                 exports targetschema or ${BWHITE}ALL${NC} to filesystem  ${BWHITE}*required${NC}"
  echo -e "    -o                                       specific object (emp)"
  echo
  echo

  echo -e "${BWHITE}EXAMPLE${NC}"
  echo -e "  $0 generate example"
  echo -e "  $0 install"
  echo -e "  $0 export ALL"
  echo -e "  $0 export hr_data -o dept"
  echo
  echo
  exit 1
}

# get required functions and vars
source ./.dbFlow/lib.sh

# target environment
[ ! -f ./build.env ] || source ./build.env
[ ! -f ./apply.env ] || source ./apply.env

# name of setup directory
targetpath="db/_setup"
basepath=$(pwd)

# array of subdirectories inside $targetpath to scan for executables (sh/sql)
array=( tablespaces directories users features workspaces acls )

notify() {
    [[ $1 = 0 ]] || echo ❌ EXIT $1
    # you can notify some external services here,
    # ie. Slack webhook, Github commit/PR etc.
    remove2envsql
}

trap '(exit 130)' INT
trap '(exit 143)' TERM
trap 'rc=$?; notify $rc; exit $rc' EXIT

print2envsql() {
  echo define project=${PROJECT} > $targetpath/env.sql

  if [[ -n ${APP_SCHEMA} ]]; then
    echo define app_schema=${APP_SCHEMA} >> $targetpath/env.sql
  fi
  if [[ -n ${DATA_SCHEMA} ]]; then
    echo define data_schema=${DATA_SCHEMA} >> $targetpath/env.sql
  fi
  if [[ -n ${LOGIC_SCHEMA} ]]; then
    echo define logic_schema=${LOGIC_SCHEMA} >> $targetpath/env.sql
  fi
  if [[ -n ${WORKSPACE} ]]; then
    echo define workspace=${WORKSPACE} >> $targetpath/env.sql
  fi
  if [[ -n ${DB_APP_PWD} ]]; then
    echo define db_app_pwd=${DB_APP_PWD} >> $targetpath/env.sql
  fi

  echo define db_app_user=${DB_APP_USER} >> $targetpath/env.sql

  if [[ ${DB_ADMIN_USER} != "sys" ]]; then
    echo define deftablespace=data >> $targetpath/env.sql
  else
    echo define deftablespace=users >> $targetpath/env.sql
  fi
}

show_generate_summary() {
  # target environment
[ ! -f ./build.env ] || source ./build.env
[ ! -f ./apply.env ] || source ./apply.env

  echo -e
  echo -e
  echo -e "${BGREEN}Congratulations${NC}"
  echo -e "Your project ${BYELLOW}$PROJECT${NC} has been ${GREEN}successfully${NC} created. "
  echo -e "Scripts have been added inside directory: ${CYAN}db/_setup${NC} that allow you "
  echo -e "to create the respective schemas, workspaces as well as ACLs and features, as long "
  echo -e "as you specified them during the configuration. "

  echo
  echo -e "${BWHITE}${PROJECT} - directory structure${NC}"
  printf "|-- %-22b %b\n" ${DEPOT_PATH} ">> Path to store your build artifacts"
  printf "|-- ${CYAN}%-22b${NC} %b\n" ".dbFlow" ">> ${CYAN}dbFlow itself${NC}"
  printf "|-- %-22b %b\n" ".hooks" ">> Scripts/Tasks to run pre or post deployment"
  printf "|-- %-22b %b\n" "apex" ">> APEX applications"
  if [[ -z ${FLEX_MODE} ]] || [[ ${FLEX_MODE} != TRUE ]]; then
    printf "|   %-22b %b\n" "|-- f123" ">> APEX application 123 for Example"
  else
    printf "|   %-22b %b\n" "|-- ${PROJECT}_app" ">> Example DB Schema assigned to workspace"
    printf "|   %-22b %b\n" "|   |-- ${PROJECT}" ">> Example Workspace assigned to apps"
    printf "|   %-22b %b\n" "|   |   |-- f123" ">> APEX application 123 for Example"
  fi
  printf "|-- %-22b %b\n" "db" ">> All DB Schemas used"
  printf "|   %-22b %b\n" "|-- _setup" ">> Scripts to create schemas, features, workspaces, ..."
  printf "|   %-22b %b\n" "|-- .hooks" ">> Scripts/Tasks to run pre or post db schema deployments"
  if [[ -z ${FLEX_MODE} ]] || [[ ${FLEX_MODE} != TRUE ]]; then
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
  if [[ -z ${FLEX_MODE} ]] || [[ ${FLEX_MODE} != TRUE ]]; then
    printf "|   %-22b %b\n" "|-- access" ">> Place all your privileges, roles and clients here (plsql)"
    printf "|   %-22b %b\n" "|-- modules" ">> The REST modules inside seperate folders"
  else
    printf "|   %-22b %b\n" "|-- schema" ">> DB Schema responible for running this RESTservice"
    printf "|   %-22b %b\n" "|   |-- access" ">> Place all your privileges, roles and clients here (plsql)"
    printf "|   %-22b %b\n" "|   |-- module" ">> The REST modules inside seperate folders"
  fi
  printf "|-- %-22b %b\n" "static" ">> StaticFiles used to uploads go here (managed by dbFlux)"
  printf "%-26b %b\n" "apply.env" ">> Environment configuration added to .gitignore"
  printf "%-26b %b\n" "build.env" ">> Project configuration"
  echo
  echo -e "To execute the installation just run: ${CYAN}.dbFlow/setup.sh install${NC}"
  echo
  echo -e "For your daily work I recommend the use of the extension: "
  echo -e "${BWHITE}dbFlux - https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow${NC}"
  echo -e "For more information refer to readme: ${CYAN}.dbFlow/readme.md${NC}"
  echo
  echo -e "To configure changelog settings, just modify corresponding parameters in build.env"
}


remove2envsql() {
  rm -f ${basepath}/${targetpath}/env.sql
}

install() {
  local yes=${1:-"NO"}

  if [[ $yes == "YES" ]]; then
    echo_warning "Force option detected!"
  fi

  if [[ -z "$DB_ADMIN_USER" ]]; then
    read -p "Enter username of admin user (admin, sys, ...) [sys]: " DB_ADMIN_USER
    DB_ADMIN_USER=${DB_ADMIN_USER:-"sys"}
  fi

  if [[ $(toLowerCase $DB_ADMIN_USER) != "sys" ]]; then
   DBA_OPTION=""
  fi

  if [[ -z "$DB_ADMIN_PWD" ]]; then
    ask4pwd "Enter password für user ${DB_ADMIN_USER}: "
    DB_ADMIN_PWD=${pass}
  fi

  if [[ -z "$DB_APP_PWD" ]]; then
    ask4pwd "Enter password für user ${DB_APP_USER}: "
    DB_APP_PWD=${pass}
  fi

  # validate connection and exit when not working
  check_admin_connection

  PROJECT_INSTALLED=$(is_any_schema_installed)
  if [[ "${PROJECT_INSTALLED}" == *"true"* ]] && [[ ${yes} == "NO" ]]; then
    echo_error "Project allready installed and option force not recoginized. \nTry option -f to force overwrite (drop + create)"

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
            cd ${level1_dir}
            echo "Calling ${level1_dir}/${file}"
            exit | ${SQLCLI} -s ${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION} @${file}
            cd ../../..
          elif [[ $EXTENSION == "sh" ]]; then
            cd ${level1_dir}
            echo "Executing ${level1_dir}/${file}"
            ./${file} ${yes} ${DB_ADMIN_PWD}
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
                cd ${level2_dir}
                echo "Calling ${level2_dir}/${file2}"
                exit | ${SQLCLI} -s ${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION} @${file2}
                cd ../../../..
              elif [[ $EXTENSION == "sh" ]]; then
                cd ${level2_dir}
                echo "Executing ${level2_dir}/${file2}"
                ./${file2} ${yes} ${DB_ADMIN_PWD}
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

generate() {
  # ! Das mus noch weg
  rm -rf .hooks
  rm -rf apex
  rm -rf db
  rm -rf rest
  rm -rf reports
  rm -rf static
  rm -f apply.env
  rm -f build.env

  local project_name=$1

  read -p "Would you like to have a single, multi or flex scheme app (S/M/F) [M]: " db_scheme_type
  db_scheme_type=${db_scheme_type:-"M"}

  # create directories
  if [[ $(toLowerCase $db_scheme_type) == "m" ]]; then
    mkdir -p db/{.hooks/{pre,post},${project_name}_data/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
    mkdir -p db/{.hooks/{pre,post},${project_name}_logic/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
    mkdir -p db/{.hooks/{pre,post},${project_name}_app/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
  elif [[ $(toLowerCase $db_scheme_type) == "s" ]]; then
    mkdir -p db/{.hooks/{pre,post},${project_name}/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
  elif [[ $(toLowerCase $db_scheme_type) == "f" ]]; then
    mkdir -p db/{.hooks/{pre,post},${project_name}_app/{.hooks/{pre,post},sequences,tables/tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,triggers},jobs,views,mviews,tests/packages,ddl/{init,patch/{pre,post}},dml/{base,init,patch/{pre,post}}}}
  else
    echo_error "unknown type ${db_scheme_type}"
    exit 1
  fi

  # write .env files
  # build.env
  echo "# project name" > build.env
  echo "PROJECT=${project_name}" >> build.env
  echo "" >> build.env
  echo "" >> build.env
  if [[ $(toLowerCase $db_scheme_type) == "m" ]]; then
    echo "# In MultiSchema Mode, we have a classic 3 Tier model" >> build.env
    echo "APP_SCHEMA=${project_name}_app" >> build.env
    echo "DATA_SCHEMA=${project_name}_data" >> build.env
    echo "LOGIC_SCHEMA=${project_name}_logic" >> build.env
  elif [[ $(toLowerCase $db_scheme_type) == "s" ]]; then
    echo "# In SingleSchema Mode, we have a only one" >> build.env
    echo "# what are the schema-names" >> build.env
    echo "APP_SCHEMA=${project_name}" >> build.env
  elif [[ $(toLowerCase $db_scheme_type) == "f" ]]; then
    echo "# In FlexSchema Mode, you have to create the schemas by your own" >> build.env
    echo "# and don't forget to grant connect through proxy_user " >> build.env
    echo "FLEX_MODE=TRUE" >> build.env
  fi
  echo "" >> build.env

  if [[ $(toLowerCase $db_scheme_type) != "f" ]]; then
    echo "" >> build.env
    echo "# workspace app belongs to" >> build.env
    echo "WORKSPACE=${project_name}" >> build.env
    echo "" >> build.env
  fi

  read -p "When running release tests, what is your prefered branch name [build]: " build_branch
  echo "" >> build.env
  echo "# Name of the branch, where release tests are build" >> build.env
  echo "BUILD_BRANCH=${build_branch:-build}" >> build.env
  echo "" >> build.env


  echo "" >> build.env
  echo "# Generate a changelog with these settings" >> build.env
  echo "# When template.sql file found in reports/changelog then it will be" >> build.env
  echo "# executed on apply with the CHANGELOG_SCHEMA ." >> build.env
  echo "# The changelog itself is structured using INTENT_PREFIXES to look" >> build.env
  echo "# for in commits and to place them in corresponding INTENT_NAMES inside" >> build.env
  echo "# the file itself. You can define a regexp in TICKET_MATCH to look for" >> build.env
  echo "# keys to link directly to your ticketsystem using TICKET_URL" >> build.env

  read -p "Would you like to process changelogs during deployment [Y]: " create_changelogs
  if [[ $(toLowerCase ${create_changelogs:-y}) == "y" ]]; then
    read -p "What is the schema name the changelog are processed with [${project_name}_app]: " chl_schema
    echo "CHANGELOG_SCHEMA=${chl_schema:-${project_name}_app}" >> build.env
    echo "INTENT_PREFIXES=( Feat Fix )" >> build.env
    echo "INTENT_NAMES=( Features Fixes )" >> build.env
    echo "INTENT_ELSE=\"Others\"" >> build.env
    echo "TICKET_MATCH=\"[A-Z]\+-[0-9]\+\"" >> build.env
    echo "TICKET_URL=\"https://url-to-your-issue-tracker-like-jira/browse\"" >> build.env

    chltemplate=reports/changelog/template.sql
    if [[ ! -f ${chltemplate} ]]; then
      [[ -d reports/changelog ]] || mkdir -p reports/changelog
      cp ".dbFlow/scripts/changelog_template.sql" ${chltemplate}
    fi
  else
    echo "# copy template to reports/changelog folder"
    echo "# cp .dbFlow/scripts/changelog_template.sql ${chltemplate}"
    echo "# CHANGELOG_SCHEMA=${project_name}_app}" >> build.env
    echo "# INTENT_PREFIXES=( Feat Fix )" >> build.env
    echo "# INTENT_NAMES=( Features Fixes )" >> build.env
    echo "# INTENT_ELSE=\"Others\"" >> build.env
    echo "# TICKET_MATCH=\"[A-Z]\+-[0-9]\+\"" >> build.env
    echo "# TICKET_URL=\"https://url-to-your-issue-tracker-like-jira/browse\"" >> build.env
  fi
  echo "" >> build.env


  # ask for some vars to put into file
  read -p "Enter database connections [localhost:1521/xepdb1]: " db_tns
  db_tns=${db_tns:-"localhost:1521/xepdb1"}

  read -p "Enter username of admin user (admin, sys, ...) [sys]: " db_admin_user
  db_admin_user=${db_admin_user:-"sys"}

  ask4pwd "Enter password for ${db_admin_user} [leave blank and you will be asked for]: "
  db_admin_pwd=${pass}

  if [[ $(toLowerCase $db_scheme_type) != "s" ]]; then
    ask4pwd "Enter password for deployment_user (proxyuser: ${project_name}_depl) [leave blank and you will be asked for]: "
  else
    ask4pwd "Enter password for application_user (user: ${project_name}) [leave blank and you will be asked for]: "
  fi
  db_app_pwd=${pass}


  read -p "Enter path to depot [_depot]: " depot_path
  depot_path=${depot_path:-"_depot"}

  read -p "Enter stage of this configuration mapped to branch (develop, test, master) [develop]: " stage
  stage=${stage:-"develop"}

  read -p "Do you wish to generate and install default tooling? (Logger, utPLSQL, teplsql, tapi) [Y]: " with_tools
  with_tools=${with_tools:-"Y"}

  # apply.env
  echo "# DB Connection" > apply.env
  echo "DB_TNS=${db_tns}" >> apply.env
  echo "" >> apply.env
  echo "# Deployment User" >> apply.env
  if [[ $(toLowerCase $db_scheme_type) != "s" ]]; then
    echo "DB_APP_USER=${project_name}_depl" >> apply.env
  else
    echo "DB_APP_USER=${project_name}" >> apply.env
  fi
  echo "DB_APP_PWD=${db_app_pwd}" >> apply.env
  echo "" >> apply.env
  echo "# SYS/ADMIN Pass" >> apply.env
  echo "DB_ADMIN_USER=${db_admin_user}" >> apply.env
  echo "DB_ADMIN_PWD=${db_admin_pwd}" >> apply.env
  echo "" >> apply.env
  echo "# Path to Depot" >> apply.env
  echo "DEPOT_PATH=${depot_path}" >> apply.env
  echo "" >> apply.env
  echo "# Stage mapped to source branch ( develop test master )" >> apply.env
  echo "# this is used to get artifacts from depot_path" >> apply.env
  echo "STAGE=${stage}" >> apply.env
  echo "" >> apply.env
  echo "" >> apply.env
  echo "# ADD this to original APP-NUM" >> apply.env
  echo "APP_OFFSET=0" >> apply.env
  echo "" >> apply.env
  read -p "Install with sql(cl) or sqlplus? [sqlplus]: " SQLCLI
  SQLCLI=${SQLCLI:-"sqlplus"}
  echo "# Scripts are executed with" >> apply.env
  echo "SQLCLI=${SQLCLI}" >> apply.env


  # write gitignore
  write_line_if_not_exists "# dbFlow target infos" .gitignore
  write_line_if_not_exists "apply.env" .gitignore

  write_line_if_not_exists "" .gitignore
  write_line_if_not_exists "# static files" .gitignore
  if [[ $(toLowerCase $db_scheme_type) == "f" ]]; then
    write_line_if_not_exists "static/**/f*/dist" .gitignore
  else
    write_line_if_not_exists "static/f*/dist" .gitignore
  fi

  write_line_if_not_exists "" .gitignore
  write_line_if_not_exists "# vscode configuration" .gitignore
  write_line_if_not_exists ".vscode" .gitignore

  if [[ $depot_path != ".."* ]]; then
    write_line_if_not_exists "" .gitignore
    write_line_if_not_exists "# depot inside wording dir" .gitignore
    write_line_if_not_exists $depot_path .gitignore
  fi


  # create targetpath directory
  mkdir -p ${targetpath}/{tablespaces,directories,users,features,workspaces,acls}
  mkdir -p ${depot_path}

  # copy some examples into it

  cp -rf .dbFlow/scripts/setup/workspaces/* ${targetpath}/workspaces
  cp -rf .dbFlow/scripts/setup/acls/* ${targetpath}/acls
  mv ${targetpath}/workspaces/workspace ${targetpath}/workspaces/${project_name}

  if [[ $(toLowerCase $with_tools) == "y" ]]; then
    cp -rf .dbFlow/scripts/setup/features/* ${targetpath}/features
    chmod +x ${targetpath}/features/*.sh
  else
    mkdir -p ${targetpath}/features
  fi


  # create gen_users..
  if [[ $(toLowerCase $db_scheme_type) == "m" ]]; then
    sed "s/\^db_app_user/${project_name}_depl/g" .dbFlow/scripts/setup/users/00_depl.sql > ${targetpath}/users/00_create_${project_name}_depl.sql

    sed "s/\^schema_name/${project_name}_data/g" .dbFlow/scripts/setup/users/01_schema.sql > ${targetpath}/users/01_create_${project_name}_data.sql
    sed "s/\^schema_name/${project_name}_logic/g" .dbFlow/scripts/setup/users/01_schema.sql > ${targetpath}/users/02_create_${project_name}_logic.sql
    sed "s/\^schema_name/${project_name}_app/g" .dbFlow/scripts/setup/users/01_schema.sql > ${targetpath}/users/03_create_${project_name}_app.sql

    sed -i "s/\^db_app_user/${project_name}_depl/g" ${targetpath}/users/01_create_${project_name}_data.sql
    sed -i "s/\^db_app_user/${project_name}_depl/g" ${targetpath}/users/02_create_${project_name}_logic.sql
    sed -i "s/\^db_app_user/${project_name}_depl/g" ${targetpath}/users/03_create_${project_name}_app.sql


  elif [[ $(toLowerCase $db_scheme_type) == "s" ]]; then
    sed "s/\^db_app_user/${project_name}/g" .dbFlow/scripts/setup/users/00_depl.sql > ${targetpath}/users/00_create_${project_name}.sql
    sed "s/\^schema_name/${project_name}/g" .dbFlow/scripts/setup/users/02_grants.sql >> ${targetpath}/users/00_create_${project_name}.sql
  elif [[ $(toLowerCase $db_scheme_type) == "f" ]]; then
    sed "s/\^db_app_user/${project_name}_depl/g" .dbFlow/scripts/setup/users/00_depl.sql > ${targetpath}/users/00_create_${project_name}_depl.sql
    sed "s/\^schema_name/${project_name}_app/g" .dbFlow/scripts/setup/users/01_schema.sql > ${targetpath}/users/01_create_${project_name}_app.sql
    sed -i "s/\^db_app_user/${project_name}_depl/g" ${targetpath}/users/01_create_${project_name}_app.sql
  fi


  mkdir -p {apex,static,rest,reports,.hooks/{pre,post}}
  if [[ $(toLowerCase $db_scheme_type) == "f" ]]; then
    mkdir -p apex/${project_name}_app/${project_name}
    mkdir -p static/${project_name}_app/${project_name}
    mkdir -p rest/${project_name}_app
  fi


  # ask for application IDs
  apex_ids=""
  read -p "Enter application IDs (comma separated) you wish to use initialy (100,101,...): " apex_ids

  # split ids gen directories
  apexids=(`echo $apex_ids | sed 's/,/\n/g'`)
  apexidsquotes="\""${apex_ids/,/"\",\""}"\""
  for apxID in "${apexids[@]}"
  do
    if [[ $(toLowerCase $db_scheme_type) == "f" ]]; then
      mkdir -p apex/${project_name}_app/${project_name}/f"$apxID"
      mkdir -p static/${project_name}_app/${project_name}/f"$apxID"/{dist/{css,img,js},src/{css,img,js}}
    else
      mkdir -p apex/f"$apxID"
      mkdir -p static/f"$apxID"/{dist/{css,img,js},src/{css,img,js}}
    fi
  done

  # ask for restful Modulsa
  rest_modules=""
  read -p "Enter restful Moduls (comma separated) you wish to use initialy (api,test,...): " rest_modules

  # split modules
  restmodules=(`echo $rest_modules | sed 's/,/\n/g'`)
  restmodulesquotes="\""${rest_modules/,/"\",\""}"\""
  for restMOD in "${restmodules[@]}"
  do
    if [[ $(toLowerCase $db_scheme_type) == "f" ]]; then
      mkdir -p rest/${project_name}_app/modules/"$restMOD"
      mkdir -p rest/${project_name}_app/access/{privileges,roles,mapping}
    else
      mkdir -p rest/modules/"$restMOD"
      mkdir -p rest/access/{privileges,roles,mapping}
    fi
  done

  # workspace files
  sed -i "s/\^workspace/${project_name}/g" ${targetpath}/workspaces/${project_name}/create_00_workspace.sql
  sed -i "s/\^workspace/${project_name}/g" ${targetpath}/workspaces/${project_name}/create_01_user_wsadmin.sql
  if [[ $(toLowerCase $db_scheme_type) == "s" ]]; then
    sed -i "s/\^app_schema/${project_name}/g" ${targetpath}/workspaces/${project_name}/create_00_workspace.sql
    sed -i "s/\^app_schema/${project_name}/g" ${targetpath}/workspaces/${project_name}/create_01_user_wsadmin.sql
  else
    sed -i "s/\^app_schema/${project_name}_app/g" ${targetpath}/workspaces/${project_name}/create_00_workspace.sql
    sed -i "s/\^app_schema/${project_name}_app/g" ${targetpath}/workspaces/${project_name}/create_01_user_wsadmin.sql
  fi

  show_generate_summary ${project_name}
} # generate

is_any_schema_installed () {
    ${SQLCLI} -s ${DB_ADMIN_USER}/${DB_ADMIN_PWD}@${DB_TNS}${DBA_OPTION} <<!
    set heading off
    set feedback off
    set pages 0
    with checksql as (select count(1) cnt
  from all_users
 where username in (upper('$DATA_SCHEMA'), upper('$LOGIC_SCHEMA'), upper('$APP_SCHEMA') ))
 select case when cnt > 1 then 'true' else 'false' end ding
   from checksql;
!
}

export_schema() {
  local targetschema=${1:-"ALL"}
  local object_name=${2:-"ALL"}


  # when defined get it
  ALL_SCHEMAS=( ${DATA_SCHEMA} ${LOGIC_SCHEMA} ${APP_SCHEMA} )
  SCHEMAS=($(printf "%s\n" "${ALL_SCHEMAS[@]}" | sort -u))
  # if length is equal than ALL_SCHEMAS, otherwise distinct
  if [[ ${#SCHEMAS[@]} == ${#ALL_SCHEMAS[@]} ]]; then
    SCHEMAS=(${ALL_SCHEMAS[@]})
  fi
  if [[ $targetschema != "ALL" ]]; then
    if [[ ! " ${SCHEMAS[@]} " =~ " ${targetschema} " ]]; then
      echo_error "ERROR: unknown targetschema $targetschema (use ALL or anything of: ${SCHEMAS[*]})"
      exit 1
    fi
  fi

  echo "targetschema: $targetschema"
  echo "object_name:  $object_name"

  # export file wegräumen
  for file in $(ls db | grep 'exp.zip')
  do
    rm "db/${file}"
  done


  if [[ -z "$DB_APP_PWD" ]]; then
    ask4pwd "Enter password für user ${DB_APP_USER}: "
    DB_APP_PWD=${pass}
  fi

  if [[ $targetschema == "ALL" ]]; then
    for schema in "${SCHEMAS[@]}"
    do
      echo_warning " ... exporting $schema"
      exit | sql -s "$(get_connect_string $schema)" @.dbFlow/scripts/schema_export/export.sql ${object_name}
      if [[ -f "db/$schema.exp.zip" ]]; then
        unzip -qo "db/$schema.exp.zip" -d "db/${schema}"
        rm "db/$schema.exp.zip"
      else
        echo_error "no export artifacts found!"
      fi
    done
  else
    echo_warning " ... exporting $targetschema"
    exit | sql -s "$(get_connect_string $targetschema)" @.dbFlow/scripts/schema_export/export.sql ${object_name}
    if [[ -f "db/$targetschema.exp.zip" ]]; then
      unzip -qo "db/$targetschema.exp.zip" -d "db/${targetschema}"
      rm "db/$targetschema.exp.zip"
    else
      echo_error "no export artifacts found!"
    fi
  fi

  # for file in $(ls db | grep 'exp.zip')
  # do
  #   unzip -qo "db/${file}" -d "db/${targetschema}"

  #   rm "db/${file}"
  # done

  echo -e "${GREEN}Done${NC}"
} # export_schema


if [[ $# -lt 1 ]]; then
  echo -e "${RED}No parameters found${NC}" 1>&2
  usage
  exit 1
else

  # Parse options to the `setup` command
  while getopts ":h" opt; do
    case ${opt} in
      h | help)
        usage
        exit 0
        ;;
      \? )
        echo -e  "${RED}Invalid Option: -$OPTARG${NC}" 1>&2
        usage
        exit 1
      ;;
    esac
  done
  shift $((OPTIND -1))

  subcommand=$1; shift  # Remove 'setup' from the argument list
  case "$subcommand" in
    # Parse options to the install sub command
    generate)
      [[ -z ${1-} ]] \
        && echo -e  "${RED}ERROR: You have to specify a project${NC}" \
        && exit 1 \

      project=$1; shift  # Remove 'generate' from the argument list

      # Process package options
      while getopts ":t:" opt; do
        case ${opt} in
          t )
            target=$OPTARG
            ;;
          \? )
            echo_error  "Invalid Option: -$OPTARG"
            usage
            ;;
          : )
            echo_error "Invalid Option: -$OPTARG requires an argument" 1>&2
            usage
            ;;
        esac
      done
      shift $((OPTIND -1))

      generate $project
      ;;
    install)
      force="NO"

       # Process install options
      while getopts ":f" opt; do
        case ${opt} in
          f )
            force="YES"
            ;;
          \? )
            echo_error "Invalid Option: -$OPTARG"
            usage
            ;;
        esac
      done
      shift $((OPTIND -1))

      install $force

      ;;

    export)
      [[ -z ${1-} ]] \
        && echo_error "ERROR: You have to specify a target-schema or ALL" \
        && exit 1
      targetschema=$1; shift

      object=""
      # Process package options
      while getopts ":o:" opt; do
        case ${opt} in
          o )
            object=$OPTARG
            if [[ $targetschema == "ALL" ]]; then
              echo_error  "specific object export requires a target-schema"
              exit 1
            fi
            ;;
          \? )
            echo_error  "Invalid Option: -$OPTARG"
            usage
            ;;
          : )
            echo_error  "Invalid Option: -$OPTARG requires an argument"
            usage
            ;;
        esac
      done
      shift $((OPTIND -1))

      export_schema $targetschema $object

      ;;
    *)
      echo_error "Invalid Argument see help"
      usage
      ;;
  esac
fi