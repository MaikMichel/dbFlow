#!/bin/bash
# echo "Your script args ($#) are: $@"

# get required functions and vars
source ./.dbFlow/lib.sh

# set project-settings from build.env if exists
if [[ -e ./build.env ]]; then
  source ./build.env
fi


usage() {
  echo -e "${BWHITE}${0}${NC} - generate files to be build and applied for testing dbFLow"
  echo ""
  echo -e "${BWHITE}Usage:${NC}"
  echo -e "  $0 --init"
  echo -e "  $0 --patch"
  echo ""
  echo -e "${BWHITE}Options:${NC}"
  echo -e "  -h | --help             - Show this screen"
  echo -e "  -d | --debug            - Show additionaly output messages"
  echo -e "  -i | --init             - Flag to build all files relevant for an initial deployment "
  echo -e "  -p | --patch            - Flag to build only files relevant for an patch deployment "
  echo -e "                            This will apply on top of the initial created files"
  echo ""
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  $0 --init"
  echo -e "  $0 --patch"


  exit 1
}

MAINFOLDERS=( apex db reports rest .hooks )
SCHEMAS=()

if [[ ${PROJECT_MODE} == "FLEX" ]]; then
  SCHEMAS=(${DBFOLDERS[@]})
else
  ALL_SCHEMAS=( ${DATA_SCHEMA} ${LOGIC_SCHEMA} ${APP_SCHEMA} )
  SCHEMAS=($(printf "%s\n" "${ALL_SCHEMAS[@]}" | sort -u))

  # if length is equal than ALL_SCHEMAS, otherwise distinct
  if [[ ${#SCHEMAS[@]} == ${#ALL_SCHEMAS[@]} ]]; then
    SCHEMAS=(${ALL_SCHEMAS[@]})
  fi
fi

# folders for REST
rest_array=( access/roles access/privileges access/mapping modules )

# all folders (init and patch)

all_folders=( .hooks/pre sequences tables indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies sources/types sources/packages sources/functions sources/procedures views mviews sources/triggers jobs tests/packages dml/base .hooks/post )
init_folders=( ${all_folders[@]} )
init_folders+=( ddl/init dml/init )

patch_folders=( ${all_folders[@]} )
patch_folders+=( ddl/patch/pre dml/patch/pre ddl/patch/post dml/patch/post )


# was ist zu tun
#
# - in jedes bekannte Verzeichnis eine Datei erzeugen, die einen Eintrag in einer
#   Testtabelle anlegt.
# - Testtabelle im PreHook anlegen,vorher löschen, wenn vorhanden
# - im PostHook einen Test ausführne, der die Anzahl und Reihenfolge der Einträgen
#   überprüft
# - aufteilen des Tests in init und patch
# - "install" apex und rest



function check_params() {
  ! getopt --test > /dev/null
  if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
      echo_fatal 'I’m sorry, `getopt --test` failed in this environment.'
      exit 1
  fi

  OPTIONS=dhip
  LONGOPTS=debug,help,init,patch

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

  debug="n" help="n" init="n" patch="n"

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
          --)
              shift
              break
              ;;
          *)
              echo_fatal "Programming error"
              exit 3
              ;;
      esac
  done

  # help first
  if [[ -n $h ]] && [[ $h == "y" ]]; then
    usage
  fi

  # Rule 1: init or patch
  if [[ -z $i ]] && [[ -z $p ]]; then
    echo_error "Missing build mode, init or patch using flags -i or -p"
    usage
    exit 1
  fi

  if [[ $i == "y" ]] && [[ $p == "y" ]]; then
    echo_error "Build mode can only be init or patch, not both"
    usage
    exit 1
  fi

  # now check dependent params
  if [[ $i == "y" ]]; then
    mode="init"
  elif [[ $p == "y" ]]; then
    mode="patch"
  fi

}

function gen_init_scripts() {
  # loop through schemas and all possible folder and write inserts
  # to the new table
  for schema in "${SCHEMAS[@]}"
  do
    # pro Schema eine HookDatei erzeugen

    [[ -d ".hooks/pre/${mode}" ]] || mkdir -p ".hooks/pre/${mode}"
    cat ".dbFlow/scripts/test/tbl_dbflow_test.sql" > ".hooks/pre/${mode}/test_${schema}.sql"


    CNT_IDX_INIT=0
    # check every path in given order
    for path in "${init_folders[@]}"
    do
      [[ -d db/${schema}/${path} ]] || mkdir -p db/${schema}/${path}
      echo "insert into dbflow_test(dft_mainfolder, dft_mode, dft_schema, dft_file) values ('db', '${mode}', '${schema}', 'db/${schema}/${path}');" > "db/${schema}/${path}/${mode}_dbflow_test.sql"

      ((CNT_IDX_INIT=CNT_IDX_INIT+1))
    done
    TESTLINE="ut.expect(l_check_init)\.to_equal(0);"
    TESTLINE2="ut.expect(l_check_init)\.to_equal(${CNT_IDX_INIT});"
    sed "s/${TESTLINE}/${TESTLINE2}/g" .dbFlow/scripts/test/pck_test_dbflow.sql > ".hooks/post/utest_${schema}.sql"
  done
}

function gen_patch_scripts() {
  # loop through schemas and all possible folder and write inserts
  # to the new table
  for schema in "${SCHEMAS[@]}"
  do
    # remove init hooks, to keep test clean
    rm -f db/${schema}/.hooks/pre/init_dbflow_test.sql
    rm -f db/${schema}/.hooks/post/init_dbflow_test.sql

    CNT_IDX_PATCH=0
    # check every path in given order
    for path in "${patch_folders[@]}"
    do
      [[ -d db/${schema}/${path} ]] || mkdir -p db/${schema}/${path}
      echo "insert into dbflow_test(dft_mainfolder, dft_mode, dft_schema, dft_file) values ('db', '${mode}', '${schema}', 'db/${schema}/${path}');" > "db/${schema}/${path}/${mode}_dbflow_test.sql"

      ((CNT_IDX_PATCH=CNT_IDX_PATCH+1))

      if [[ ${path} == "tables" ]]; then
        echo "insert into dbflow_test(dft_mainfolder, dft_mode, dft_schema, dft_file) values ('db', '${mode}', '${schema}', 'db/${schema}/${path}/tables_ddl/1');" > "db/${schema}/${path}/tables_ddl/${mode}_dbflow_test.1.sql"
        echo "insert into dbflow_test(dft_mainfolder, dft_mode, dft_schema, dft_file) values ('db', '${mode}', '${schema}', 'db/${schema}/${path}/tables_ddl/2');" > "db/${schema}/${path}/tables_ddl/${mode}_dbflow_test.2.sql"
        ((CNT_IDX_PATCH=CNT_IDX_PATCH+1))
      fi
    done

    TESTLINE="ut.expect(l_check_patch)\.to_equal(0);"
    TESTLINE2="ut.expect(l_check_patch)\.to_equal(${CNT_IDX_PATCH});"
    sed -i "s/${TESTLINE}/${TESTLINE2}/g" ".hooks/post/utest_${schema}.sql"
  done
}

# depth=$1

# for d in $(find apex -maxdepth ${depth} -mindepth ${depth} -type d)
# do
#   #Do something, the directory is accessible with $d:
#   echo "Prompt EXECUTING: $d/install.sql" > $d/install.sql
# done

# for d in $(find rest -maxdepth ${depth} -mindepth ${depth} -type d)
# do
#   #Do something, the directory is accessible with $d:
#   echo "Prompt EXECUTING: $d/install.sql" > $d/install.sql
# done

# for d in $(find db -not -path 'db/_setup*/*'  -type d)
# do
#   #Do something, the directory is accessible with $d:
#   if [[ $d != "db/_setup" ]]; then
#     echo "Prompt EXECUTING: $d/install.sql" > $d/install.sql
#   fi
# done

# for d in $(find .hooks -type d)
# do
#   #Do something, the directory is accessible with $d:
#   echo "Prompt EXECUTING: $d/install.sql" > $d/install.sql
# done

check_params "$@"

echo "mode: $mode"
if [[ ${mode} == "init" ]]; then
  gen_init_scripts
elif [[ ${mode} == "patch" ]]; then
  gen_patch_scripts
else
  echo_error "unknown mode"
fi

