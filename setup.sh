#!/bin/bash

source ./.bash4xcl/lib.sh

# TODO: Löschen des Applications array. Das brauchen wir nicht. Hier loopen wir einfach durch die Verzeichnisse



usage() {
  echo -e "setup [bash4xcl] - generate project structure and install dependencies"
  echo
  echo -e "${BWHITE}VERSION${NC}"
  echo -e "\t0.0.1"
  echo
  echo -e "${BWHITE}USAGE${NC}"
  echo -e "\t$0 [COMMAND]"
  echo
  echo -e "${BWHITE}COMMANDS${NC}"
  echo -e "\tgenerate <project-name>  generates project structure"
  echo -e "\tinstall                  installs project dependencies to db"
  echo -e "\texport                   exports schema to filesystem"
  echo -e "\t    -c                   connection (localhost:1521/xepdb1) *required"
  echo -e "\t    -t                   targetpath (db/prj_data)            optional"
  echo
  echo
}

# target environment
[ ! -f ./build.env ] || source ./build.env
[ ! -f ./apply.env ] || source ./apply.env

# name of setup directory
targetpath="db/_setup"

# array of subdirectories inside $targetpath to scan for executables (sh/sql)
array=( tablespaces directories users features workspaces workspace_users acls )



print2envsql() {
  echo define project=${PROJECT} > $targetpath/env.sql
  echo define app_schema=${APP_SCHEMA} >> $targetpath/env.sql
  echo define data_schema=${DATA_SCHEMA} >> $targetpath/env.sql
  echo define logic_schema=${LOGIC_SCHEMA} >> $targetpath/env.sql
  echo define workspace=${WORKSPACE} >> $targetpath/env.sql
  echo define db_app_pwd=${DB_APP_PWD} >> $targetpath/env.sql
  echo define db_app_user=${DB_APP_USER} >> $targetpath/env.sql
  echo define apex_user=${APEX_USER} >> $targetpath/env.sql
}

remove2envsql() {
  rm -f $targetpath/env.sql
}

install() {

  if [ -z "$DB_PASSWORD" ]
  then
    ask4pwd "Enter password für user sys: "
    DB_PASSWORD=${pass}
  fi

  if [ -z "$DB_APP_PWD" ]
  then
    ask4pwd "Enter password für user ${DB_APP_USER}: "
    DB_APP_PWD=${pass}
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
            exit | sqlplus -s sys/${DB_PASSWORD}@$DB_TNS as sysdba @${file}
            cd ../../..
          elif [ $EXTENSION == "sh" ]
          then
            cd $targetpath/$path
            echo "Executing $targetpath/$path/${file}"
            ./${file}
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
    mkdir -p db/${project_name}_data/{sequences,tables,tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,views,triggers},jobs,tests/{packages},ddl/{init,pre,post},dml/{init,pre,post}}
    mkdir -p db/${project_name}_logic/{sequences,tables,tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,views,triggers},jobs,tests/{packages},ddl/{init,pre,post},dml/{init,pre,post}}
    mkdir -p db/${project_name}_app/{sequences,tables,tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,views,triggers},jobs,tests/{packages},ddl/{init,pre,post},dml/{init,pre,post}}
  elif [ ${db_scheme_type,,} == "s" ]; then
    mkdir -p db/${project_name}/{sequences,tables,tables_ddl,indexes/{primaries,uniques,defaults},constraints/{primaries,foreigns,checks,uniques},contexts,policies,sources/{types,packages,functions,procedures,views,triggers},jobs,tests/{packages},ddl/{init,pre,post},dml/{init,pre,post}}
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
    echo "APP_SCHEMA=\${PROJECT}_app" >> build.env
    echo "DATA_SCHEMA=\${PROJECT}_data" >> build.env
    echo "LOGIC_SCHEMA=\${PROJECT}_logic" >> build.env
  else
    echo "APP_SCHEMA=\${PROJECT}" >> build.env
    echo "DATA_SCHEMA=\${PROJECT}" >> build.env
    echo "LOGIC_SCHEMA=\${PROJECT}" >> build.env
  fi

  echo "" >> build.env
  echo "# workspace app belongs to" >> build.env
  echo "WORKSPACE=\${PROJECT}" >> build.env
  echo "" >> build.env
  echo "# array of schemas" >> build.env
  if [ ${db_scheme_type,,} == "m" ]; then
    echo "SCHEMAS=( \$DATA_SCHEMA \$LOGIC_SCHEMA \$APP_SCHEMA )" >> build.env
  else
    echo "SCHEMAS=( \$APP_SCHEMA )" >> build.env
  fi
  echo "" >> build.env
  echo "# array of branches" >> build.env
  echo "BRANCHES=( develop test master )" >> build.env

  # ask for some vars to put into file
  read -p "Enter database connections [localhost:1521/xepdb1]: " db_tns
  db_tns=${db_tns:-"localhost:1521/xepdb1"}

  ask4pwd "Enter password for sys [leave blank and you will be asked for]: "
  db_password=${pass}

  if [ ${db_scheme_type,,} == "m" ]; then
    ask4pwd "Enter password for deployment_user (proxyuser: ${project_name}_depl) [leave blank and you will be asked for]: "
  else
    ask4pwd "Enter password for application_user (user: ${project_name}) [leave blank and you will be asked for]: "
  fi
  db_app_pwd=${pass}


  read -p "Enter path to depot [_depot]: " depot_path
  depot_path=${depot_path:-"_depot"}

  read -p "Enter apex schema [APEX_200100]: " apex_user
  apex_user=${apex_user:-"APEX_200100"}

  # apply.env
  echo "# DB Connection" > apply.env
  echo "DB_TNS=${db_tns}" >> apply.env
  echo "" >> apply.env
  echo "# Deployment User" >> apply.env
  if [ ${db_scheme_type,,} == "m" ]; then
    echo "DB_APP_USER=\${PROJECT}_depl" >> apply.env
  else
    echo "DB_APP_USER=\${PROJECT}" >> apply.env
  fi
  echo "DB_APP_PWD=${db_app_pwd}" >> apply.env
  echo "" >> apply.env
  echo "# SYS Pass" >> apply.env
  echo "DB_PASSWORD=${db_password}" >> apply.env
  echo "" >> apply.env
  echo "# Path to Depot" >> apply.env
  echo "DEPOT_PATH=${depot_path}" >> apply.env
  echo "" >> apply.env
  echo "# Stage mapped to source branch ( develop test master )" >> apply.env
  echo "# this is used to get artifact from depot_path" >> apply.env
  echo "STAGE=develop" >> apply.env
  echo "" >> apply.env
  echo "# Use DB_USER as Proxy to multischemas, otherwise connect directly" >> apply.env
  if [ ${db_scheme_type,,} == "m" ]; then
    echo "USE_PROXY=TRUE" >> apply.env
  else
    echo "USE_PROXY=FALSE" >> apply.env
  fi
  echo "" >> apply.env
  echo "# ADD this to original APP-NUM" >> apply.env
  echo "APP_OFFSET=0" >> apply.env
  echo "" >> apply.env
  echo "# What is the APEX Owner" >> apply.env
  echo "APEX_USER=${apex_user}" >> apply.env


  # create targetpath directory
  mkdir -p ${targetpath}/{tablespaces,directories,users,features,workspaces,workspace_users,acls}
  mkdir -p ${depot_path}

  # copy some examples into it
  cp -rf .bash4xcl/scripts/setup/users/* ${targetpath}/users
  cp -rf .bash4xcl/scripts/setup/workspaces/* ${targetpath}/workspaces
  cp -rf .bash4xcl/scripts/setup/workspace_users/* ${targetpath}/workspace_users
  cp -rf .bash4xcl/scripts/setup/acls/* ${targetpath}/acls
  cp -rf .bash4xcl/scripts/setup/features/* ${targetpath}/features
  chmod +x ${targetpath}/features

  # create gen_users..
  echo "set define '^'" > ${targetpath}/users/gen_users.sql
  echo "set concat on" >> ${targetpath}/users/gen_users.sql
  echo "set concat ." >> ${targetpath}/users/gen_users.sql
  echo "set verify off" >> ${targetpath}/users/gen_users.sql
  echo "" >> ${targetpath}/users/gen_users.sql
  echo "@../env.sql" >> ${targetpath}/users/gen_users.sql
  echo "" >> ${targetpath}/users/gen_users.sql
  echo "-------------------------------------------------------------------------------------" >> ${targetpath}/users/gen_users.sql
  echo "PROMPT  =============================================================================" >> ${targetpath}/users/gen_users.sql
  echo "PROMPT  ==   CREATE USERS / SCHEMAS" >> ${targetpath}/users/gen_users.sql
  echo "PROMPT  =============================================================================" >> ${targetpath}/users/gen_users.sql
  echo "PROMPT" >> ${targetpath}/users/gen_users.sql
  echo "" >> ${targetpath}/users/gen_users.sql
  echo "" >> ${targetpath}/users/gen_users.sql
  echo "Prompt creating users" >> ${targetpath}/users/gen_users.sql
  if [ ${db_scheme_type,,} == "m" ]; then
    echo "@@templates/create_schema_users.sql ^data_schema ^db_app_pwd" >> ${targetpath}/users/gen_users.sql
    echo "@@templates/create_schema_users.sql ^logic_schema ^db_app_pwd" >> ${targetpath}/users/gen_users.sql
    echo "@@templates/create_schema_users.sql ^app_schema ^db_app_pwd" >> ${targetpath}/users/gen_users.sql
    echo "@@templates/create_deployment_user.sql ^db_app_user ^db_app_pwd ^data_schema ^logic_schema ^app_schema" >> ${targetpath}/users/gen_users.sql
  else
    echo "@@templates/create_schema_users.sql ^app_schema ^db_app_pwd" >> ${targetpath}/users/gen_users.sql
  fi
  echo "" >> ${targetpath}/users/gen_users.sql
  echo "Prompt" >> ${targetpath}/users/gen_users.sql
  echo "grant execute on sys.dbms_rls to public;" >> ${targetpath}/users/gen_users.sql

  # copy vscode files
  [ -d .vscode ] || mkdir .vscode
  # TODO backup existing tasks.json
  cp -rf .bash4xcl/vscode/tasks.json .vscode/

  # ask for application IDs
  read -p "Enter application IDs (comma separated) you wish to use initialy [1000,2000]: " apex_ids
  apex_ids=${apex_ids:-"1000,2000"}

  # split ids gen directories
  apexids=(`echo $apex_ids | sed 's/,/\n/g'`)
  apexidsquotes="\""${apex_ids/,/"\",\""}"\""
  for apxID in "${apexids[@]}"
  do
      mkdir -p apex/f"$apxID"
      mkdir -p static/f"$apxID"
  done

  # add application IDs to vscode task
  lineNum="`grep -Fn -m 1 DEFAULT_APP_ID .vscode/tasks.json | grep -Po '^[0-9]+'`"
  sed -i ${lineNum}s/.*/"            \"default\": \"${apexids[0]}\", \/\/ \$DEFAULT_APP_ID"/ .vscode/tasks.json

  lineNum="`grep -Fn -m 1 ARRAY_OF_AVAILABLE_APP_IDS .vscode/tasks.json | grep -Po '^[0-9]+'`"
  sed -i ${lineNum}s/.*/"            \"options\": [${apexidsquotes}], \/\/ \$DEFAULT_APP_ID"/ .vscode/tasks.json


} # generate


export_schema() {
  local connection=${1:-""}
  local tarpath=${2:-""}


  for file in $(ls db | grep 'exp.zip')
  do
    rm "db/${file}"
  done


  if [ -z $connection ]; then
    # ask for some vars
    read -p "Enter database connections [${DB_TNS:-"localhost:1521/xepdb1"}]: " db_tns
    db_tns=${db_tns:-${DB_TNS:-"localhost:1521/xepdb1"}}

    read -p "Enter username/schema to export: " exp_schema
    exp_schema=${exp_schema}


    ask4pwd "Enter password for username/schema to export: "
    exp_pwd=${pass}

    connection=${exp_schema}/${exp_pwd}@$db_tns
  fi

  exit | sql -s ${connection} @.bash4xcl/scripts/schema_export/export.sql

  for file in $(ls db | grep 'exp.zip')
  do
    if [ -z $tarpath ]; then
      unzip -qo "db/${file}" -d db/${file/".exp.zip"/}
    else
      unzip -qo "db/${file}" -d $tarpath
    fi
    rm "db/${file}"
  done

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
            echo -e  "${RED}Invalid Option: -$OPTARG${NC}" 1>&2
            exit 1
            ;;
          : )
            echo -e  "${RED}Invalid Option: -$OPTARG requires an argument${NC}" 1>&2
            exit 1
            ;;
        esac
      done
      shift $((OPTIND -1))

      generate $project
      ;;
    install)
      install
      ;;
    export)
      conn=""
      target=""
      # Process package options
      while getopts ":c:t:" opt; do
        case ${opt} in
          c )
            conn=$OPTARG
            ;;
          \? )
            echo -e  "${RED}Invalid Option: -$OPTARG${NC}" 1>&2
            exit 1
            ;;
          : )
            echo -e  "${RED}Invalid Option: -$OPTARG requires an argument${NC}" 1>&2
            exit 1
            ;;
          t )
            target=$OPTARG
            ;;
          \? )
            echo -e  "${RED}Invalid Option: -$OPTARG${NC}" 1>&2
            exit 1
            ;;
          : )
            echo -e  "${RED}Invalid Option: -$OPTARG requires an argument${NC}" 1>&2
            exit 1
            ;;
        esac
      done
      shift $((OPTIND -1))



      export_schema $conn $target

      ;;
    *)
      echo -e  "${RED}Invalid Argument see help${NC}" 1>&2
      usage
      exit 1
      ;;
  esac
fi