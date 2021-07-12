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
array=( tablespaces directories users features workspaces workspace_users acls )

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
  echo define app_schema=${APP_SCHEMA} >> $targetpath/env.sql
  echo define data_schema=${DATA_SCHEMA} >> $targetpath/env.sql
  echo define logic_schema=${LOGIC_SCHEMA} >> $targetpath/env.sql
  echo define workspace=${WORKSPACE} >> $targetpath/env.sql
  echo define db_app_pwd=${DB_APP_PWD} >> $targetpath/env.sql
  echo define db_app_user=${DB_APP_USER} >> $targetpath/env.sql
  echo define apex_user=${APEX_USER} >> $targetpath/env.sql

  if [[ ${DB_ADMINUSER} != "sys" ]]; then
    echo define deftablespace=data >> $targetpath/env.sql
  else
    echo define deftablespace=users >> $targetpath/env.sql
  fi
}

show_generate_summary() {
  echo -e
  echo -e
  echo -e "Your project ${YELLOW}$1${NC} has just been created ${GREEN}successfully${NC}."
  echo -e "APEX applications are stored in the ${CYAN}apex${NC} directory. "
  echo -e "If you use REST servies, you can store them in the ${CYAN}rest${NC} directory. "
  echo -e "Both can be exported to VSCode with our VSCode Exctension (dbFlow-vsce)"
  echo -e
  echo -e "The ${CYAN}db${NC} directory contains all your database objects, whereas the ${CYAN}_setup${NC} folder contains "
  echo -e "objects / dependencies whose installation requires ${PURPLE}sys${NC} permissions."
  echo -e "So before you start installing the components, you can edit or add them in the respective directories. "
  echo -e "Features are stored in the directory with the same name. "
  echo -e "At the beginning these are logger, utPlsql, teplsql and tapi."
  echo -e "You can also find more information in the readme: ${BYELLOW}.dbFlow/readme.md${NC}"

}

remove2envsql() {
  rm -f ${basepath}/${targetpath}/env.sql
}

install() {
  local yes=${1:-"NO"}

  if [ $yes == "YES" ]; then
    echo_warning "Force option detected!"
  fi

  if [ -z "$DB_ADMINUSER" ]
  then
    read -p "Enter username of admin user (admin, sys, ...) [sys]: " DB_ADMINUSER
    DB_ADMINUSER=${DB_ADMINUSER:-"sys"}
  fi

  if [[ ${DB_ADMINUSER,,} != "sys" ]]; then
   DBA_OPTION=""
  fi

  if [ -z "$DB_PASSWORD" ]
  then
    ask4pwd "Enter password für user ${DB_ADMINUSER}: "
    DB_PASSWORD=${pass}
  fi

  if [ -z "$DB_APP_PWD" ]
  then
    ask4pwd "Enter password für user ${DB_APP_USER}: "
    DB_APP_PWD=${pass}
  fi

  PROJECT_INSTALLED=$(is_any_schema_installed)
  echo "PROJECT_INSTALLED = $PROJECT_INSTALLED"
  if [ "${PROJECT_INSTALLED}" == "true" ] && [ ${yes} == "NO" ]
  then
    echo_error "Project allready installed and option force not recoginized. \nTry option -f to force overwrite (drop + create)"
    usage
  fi

  print2envsql
  #-----------------------------------------------------------#

  # check every path in given order
  for path in "${array[@]}"
  do
    if [[ -d "$targetpath"/$path ]]
    then
      echo "Installing $path"
      for file in $(ls "$targetpath"/$path | sort )
      do
        if [ -f "$targetpath"/$path/${file} ]
        then
          BASEFL=$(basename -- "${file}")
          EXTENSION="${BASEFL##*.}"

          if [ $EXTENSION == "sql" ]
          then
            cd $targetpath/$path
            echo "Calling $targetpath/$path/${file}"
            exit | sqlplus -s ${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION} @${file}
            cd ../../..
          elif [ $EXTENSION == "sh" ]
          then
            cd $targetpath/$path
            echo "Executing $targetpath/$path/${file}"
            ./${file} ${yes} ${DB_PASSWORD}
            cd ../../..
          fi
        fi
      done #file

    fi
  done #path

  #-----------------------------------------------------------#

  remove2envsql

  echo_success "Installation done"

} # install

generate() {
  local project_name=$1

  read -p "Would you like to have a single or multi scheme app (S/M) [M]: " db_scheme_type
  db_scheme_type=${db_scheme_type:-"M"}

  # create directories
  if [ ${db_scheme_type,,} == "m" ]; then
    mkdir -p db/{.hooks/{pre,post},${project_name}_data/{.hooks/{pre,post},sequences,tables,tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,views,triggers},jobs,tests/{packages},ddl/{init,pre,post},dml/{init,pre,post}}}
    mkdir -p db/{.hooks/{pre,post},${project_name}_logic/{.hooks/{pre,post},sequences,tables,tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,views,triggers},jobs,tests/{packages},ddl/{init,pre,post},dml/{init,pre,post}}}
    mkdir -p db/{.hooks/{pre,post},${project_name}_app/{.hooks/{pre,post},sequences,tables,tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,views,triggers},jobs,tests/{packages},ddl/{init,pre,post},dml/{init,pre,post}}}
  elif [ ${db_scheme_type,,} == "s" ]; then
    mkdir -p db/{.hooks/{pre,post},${project_name}/{.hooks/{pre,post},sequences,tables,tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,views,triggers},jobs,tests/{packages},ddl/{init,pre,post},dml/{init,pre,post}}}
  else
    echo_error "unknown type ${db_scheme_type}"
    exit 1
  fi

  # write .env files
  # build.env
  echo "# project name" > build.env
  echo "PROJECT=${project_name}" >> build.env
  echo "" >> build.env
  echo "# what are the schema-names" >> build.env
  if [ ${db_scheme_type,,} == "m" ]; then
    echo "APP_SCHEMA=${project_name}_app" >> build.env
    echo "DATA_SCHEMA=${project_name}_data" >> build.env
    echo "LOGIC_SCHEMA=${project_name}_logic" >> build.env
  else
    echo "APP_SCHEMA=${project_name}" >> build.env
    echo "DATA_SCHEMA=${project_name}" >> build.env
    echo "LOGIC_SCHEMA=${project_name}" >> build.env
  fi
  echo "" >> build.env
  echo "" >> build.env
  echo "# Use DB_USER as Proxy to multischemas, otherwise connect directly" >> build.env
  if [ ${db_scheme_type,,} == "m" ]; then
    echo "USE_PROXY=TRUE" >> build.env
  else
    echo "USE_PROXY=FALSE" >> build.env
  fi

  echo "" >> build.env
  echo "# workspace app belongs to" >> build.env
  echo "WORKSPACE=${project_name}" >> build.env
  echo "" >> build.env
  echo "# array of schemas" >> build.env
  if [ ${db_scheme_type,,} == "m" ]; then
    echo "SCHEMAS=( \$DATA_SCHEMA \$LOGIC_SCHEMA \$APP_SCHEMA )" >> build.env
  else
    echo "SCHEMAS=( \$APP_SCHEMA )" >> build.env
  fi

  # ask for some vars to put into file
  read -p "Enter database connections [localhost:1521/xepdb1]: " db_tns
  db_tns=${db_tns:-"localhost:1521/xepdb1"}

  read -p "Enter username of admin user (admin, sys, ...) [sys]: " db_adminuser
  db_adminuser=${db_adminuser:-"sys"}

  ask4pwd "Enter password for ${db_adminuser} [leave blank and you will be asked for]: "
  db_password=${pass}

  if [ ${db_scheme_type,,} == "m" ]; then
    ask4pwd "Enter password for deployment_user (proxyuser: ${project_name}_depl) [leave blank and you will be asked for]: "
  else
    ask4pwd "Enter password for application_user (user: ${project_name}) [leave blank and you will be asked for]: "
  fi
  db_app_pwd=${pass}


  read -p "Enter path to depot [_depot]: " depot_path
  depot_path=${depot_path:-"_depot"}

  read -p "Enter apex schema [APEX_200200]: " apex_user
  apex_user=${apex_user:-"APEX_200200"}

  read -p "Do you wish to generate and install default tooling? (Logger, utPLSQL, teplsql, tapi) [Y]: " with_tools
  with_tools=${with_tools:-"Y"}

  # apply.env
  echo "# DB Connection" > apply.env
  echo "DB_TNS=${db_tns}" >> apply.env
  echo "" >> apply.env
  echo "# Deployment User" >> apply.env
  if [ ${db_scheme_type,,} == "m" ]; then
    echo "DB_APP_USER=${project_name}_depl" >> apply.env
  else
    echo "DB_APP_USER=${project_name}" >> apply.env
  fi
  echo "DB_APP_PWD=${db_app_pwd}" >> apply.env
  echo "" >> apply.env
  echo "# SYS/ADMIN Pass" >> apply.env
  echo "DB_ADMINUSER=${db_adminuser}" >> apply.env
  echo "DB_PASSWORD=${db_password}" >> apply.env
  echo "" >> apply.env
  echo "# Path to Depot" >> apply.env
  echo "DEPOT_PATH=${depot_path}" >> apply.env
  echo "" >> apply.env
  echo "# Stage mapped to source branch ( develop test master )" >> apply.env
  echo "# this is used to get artifact from depot_path" >> apply.env
  echo "STAGE=develop" >> apply.env
  echo "" >> apply.env
  echo "" >> apply.env
  echo "# ADD this to original APP-NUM" >> apply.env
  echo "APP_OFFSET=0" >> apply.env
  echo "" >> apply.env
  echo "# What is the APEX Owner" >> apply.env
  echo "APEX_USER=${apex_user}" >> apply.env

  # write gitignore
  echo "# dbFlow target infos" >> .gitignore
  echo "apply.env" >> .gitignore

  echo "" >> .gitignore
  echo "static files" >> .gitignore
  echo "static/f*/dist" >> .gitignore




  # create targetpath directory
  mkdir -p ${targetpath}/{tablespaces,directories,users,features,workspaces,workspace_users,acls}
  mkdir -p ${depot_path}

  # copy some examples into it
  cp -rf .dbFlow/scripts/setup/workspaces/* ${targetpath}/workspaces
  cp -rf .dbFlow/scripts/setup/workspace_users/* ${targetpath}/workspace_users
  cp -rf .dbFlow/scripts/setup/acls/* ${targetpath}/acls

  if [ ${with_tools,,} == "y" ]; then
    cp -rf .dbFlow/scripts/setup/features/* ${targetpath}/features
    chmod +x ${targetpath}/features/*.sh
  else
    mkdir -p ${targetpath}/features
  fi


  # create gen_users..
  if [ ${db_scheme_type,,} == "m" ]; then
    cp -rf .dbFlow/scripts/setup/users/01_data.sql ${targetpath}/users/01_${project_name}_data.sql
    cp -rf .dbFlow/scripts/setup/users/02_logic.sql ${targetpath}/users/02_${project_name}_logic.sql
    cp -rf .dbFlow/scripts/setup/users/03_app.sql ${targetpath}/users/03_${project_name}_app.sql
    cp -rf .dbFlow/scripts/setup/users/04_depl.sql ${targetpath}/users/04_${project_name}_depl.sql
  else
    cp -rf .dbFlow/scripts/setup/users/03_app.sql ${targetpath}/users/03_${project_name}_app.sql
  fi


  # ask for application IDs
  read -p "Enter application IDs (comma separated) you wish to use initialy [1000,2000]: " apex_ids
  apex_ids=${apex_ids:-"1000,2000"}

  # ask for restful Modulsa
  read -p "Enter restful Moduls (comma separated) you wish to use initialy [com.${project_name}.api.version,com.${project_name}.api.test]: " rest_modules
  rest_modules=${rest_modules:-"com.${project_name}.api.version,com.${project_name}.api.test"}


  # split ids gen directories
  apexids=(`echo $apex_ids | sed 's/,/\n/g'`)
  apexidsquotes="\""${apex_ids/,/"\",\""}"\""
  for apxID in "${apexids[@]}"
  do
      mkdir -p apex/f"$apxID"
      mkdir -p static/f"$apxID"/{dist/{css,img,js},src/{css,img,js}}
  done

  # split modules
  restmodules=(`echo $rest_modules | sed 's/,/\n/g'`)
  restmodulesquotes="\""${rest_modules/,/"\",\""}"\""
  for restMOD in "${restmodules[@]}"
  do
      mkdir -p rest/modules/"$restMOD"
  done
  mkdir -p rest/privileges
  mkdir -p rest/roles


  show_generate_summary ${project_name}
} # generate

is_any_schema_installed () {
    sqlplus -s ${DB_ADMINUSER}/${DB_PASSWORD}@${DB_TNS}${DBA_OPTION} <<!
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

  echo "targetschema: $targetschema"
  echo "object_name:  $object_name"

  # export file wegräumen
  for file in $(ls db | grep 'exp.zip')
  do
    rm "db/${file}"
  done


  if [ -z "$DB_APP_PWD" ]
  then
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
      fi
    done
  else
    echo_warning " ... exporting $targetschema"
    exit | sql -s "$(get_connect_string $targetschema)" @.dbFlow/scripts/schema_export/export.sql ${object_name}
    if [[ -f "db/$targetschema.exp.zip" ]]; then
      unzip -qo "db/$targetschema.exp.zip" -d "db/${targetschema}"
      rm "db/$targetschema.exp.zip"
    fi
  fi

  # for file in $(ls db | grep 'exp.zip')
  # do
  #   unzip -qo "db/${file}" -d "db/${targetschema}"

  #   rm "db/${file}"
  # done

  echo -e "${GREEN}Done${NC}"
} # export_schema


if [ $# -lt 1 ]; then
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
      targetschema=$1

      if [[ $targetschema != "ALL" ]]; then
        if [[ ! " ${SCHEMAS[@]} " =~ " ${targetschema} " ]]; then
          echo_error "ERROR: unknown targetschema $targetschema (use ALL or anything of: ${SCHEMAS[*]})"
          exit 1
        fi
      fi

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