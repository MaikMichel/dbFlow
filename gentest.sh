#!/usr/bin/env bash
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
  echo -e "  -k | --hooks            - Option to create files in all schema object folder hooks"
  echo ""
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  $0 --init"
  echo -e "  $0 --init --hooks"
  echo -e "  $0 --patch"
  echo -e "  $0 --patch --hooks"


  exit 1
}

function check_params() {
  debug="n" help="n" init="n" patch="n" hooks="n"

  while getopts_long 'dhipk debug help init patch hooks' OPTKEY "${@}"; do
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
          'k'|'hooks')
              hooks="y"
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
    echo_error "Missing build mode, init or patch using flags -i or -p"
    usage
  fi

  if [[ $i == "y" ]] && [[ $p == "y" ]]; then
    echo_error "Build mode can only be init or patch, not both"
    usage
  fi

  # now check dependent params
  if [[ $i == "y" ]]; then
    mode="init"
  elif [[ $p == "y" ]]; then
    mode="patch"
  fi

}



# MAINFOLDERS=( apex db reports rest .hooks )
# SCHEMAS=()

# if [[ ${PROJECT_MODE} == "FLEX" ]]; then
#   SCHEMAS=(${DBFOLDERS[@]})
# else
#   ALL_SCHEMAS=( ${DATA_SCHEMA} ${LOGIC_SCHEMA} ${APP_SCHEMA} )
#   SCHEMAS=($(printf "%s\n" "${ALL_SCHEMAS[@]}" | sort -u))

#   # if length is equal than ALL_SCHEMAS, otherwise distinct
#   if [[ ${#SCHEMAS[@]} == ${#ALL_SCHEMAS[@]} ]]; then
#     SCHEMAS=(${ALL_SCHEMAS[@]})
#   fi
# fi

# folders for REST
# rest_array=( access/roles access/privileges access/mapping modules )




# # all folders (init and patch)

# all_folders=( .hooks/pre sequences tables indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies sources/types sources/packages sources/functions sources/procedures views mviews sources/triggers jobs tests/packages dml/base .hooks/post )
# init_folders=( ${all_folders[@]} )
# init_folders+=( ddl/init dml/init )

# patch_folders=( ${all_folders[@]} )
# patch_folders+=( ddl/patch/pre dml/patch/pre ddl/patch/post dml/patch/post )


# was ist zu tun
#
# - in jedes bekannte Verzeichnis eine Datei erzeugen, die einen Eintrag in einer
#   Testtabelle anlegt.
# - Testtabelle im PreHook anlegen,vorher löschen, wenn vorhanden
# - im PostHook einen Test ausführne, der die Anzahl und Reihenfolge der Einträgen
#   überprüft
# - aufteilen des Tests in init und patch
# - "install" apex und rest




function gen_scripts() {
  local unmode="init"
  if [[ ${mode} == "init" ]]; then
    unmode="patch"
  fi


  # loop through schemas and all possible folder and write inserts
  # to the new table
  for schema in "${DBSCHEMAS[@]}"
  do
    echo "processing Schema: ${schema}"
    CNT_IDX_INIT=0
    DBUNION=()

    # remove unmode file if exists to keep consistent
    [[ ! -f ".hooks/pre/${unmode}/test_${schema}.sql" ]] || rm ".hooks/pre/${unmode}/test_${schema}.sql"

    # one hook file per schema
    [[ -d ".hooks/pre/${mode}" ]] || mkdir -p ".hooks/pre/${mode}"
    cat ".dbFlow/scripts/test/tbl_dbflow_test.sql" > ".hooks/pre/${mode}/test_${schema}.sql"

    # check every path in given order
    for path in "${SCAN_PATHES[@]}"
    do
      echo "processing Folder: ${path}"

      # when hook option is enabled, do the same inside hooks
      if [[ ${hooks} == "y" ]] && [[ ${path} != ".hooks/"* ]]; then
        # pre folder-hooks (something like db/schema/.hooks/pre/tables)
        targetfolder="db/${schema}/.hooks/pre/${path}"
        # create targetfolder if not exists
        [[ -d ${targetfolder} ]] || mkdir -p "${targetfolder}"

        # remove init file if exists to keep consistent
        [[ ! -f "${targetfolder}/${unmode}_dbflow_test.sql" ]] || rm "${targetfolder}/${unmode}_dbflow_test.sql"

        echo "insert into dbflow_test(dft_mainfolder, dft_mode, dft_schema, dft_file) values ('db', '${mode}', '${schema}', '${targetfolder}/${mode}_dbflow_test.sql');" > "${targetfolder}/${mode}_dbflow_test.sql"

        ((CNT_IDX_INIT=CNT_IDX_INIT+1))

        # if [[ ${path} == "tables" ]] && [[ ${mode} == "patch" ]]; then
        #   echo "skipping tables"
        # else
          DBUNION+=( "${targetfolder}/${mode}_dbflow_test.sql" )
        # fi
      fi

      targetfolder="db/${schema}/${path}"

      # create targetfolder if not exists
      [[ -d ${targetfolder} ]] || mkdir -p "${targetfolder}"

      # remove init file if exists to keep consistent
      [[ ! -f "${targetfolder}/${unmode}_dbflow_test.sql" ]] || rm "${targetfolder}/${unmode}_dbflow_test.sql"

      echo "insert into dbflow_test(dft_mainfolder, dft_mode, dft_schema, dft_file) values ('db', '${mode}', '${schema}', '${targetfolder}/${mode}_dbflow_test.sql');" > "${targetfolder}/${mode}_dbflow_test.sql"

      ((CNT_IDX_INIT=CNT_IDX_INIT+1))

      if [[ ${path} == "tables" ]] && [[ ${mode} == "patch" ]]; then
        echo "skipping tables"
      else
        DBUNION+=( "${targetfolder}/${mode}_dbflow_test.sql" )
      fi


      # when hook option is enabled, do the same inside hooks
      if [[ ${hooks} == "y" ]] && [[ ${path} != ".hooks/"* ]]; then
        # post folder-hooks (something like db/schema/.hooks/post/tables)
        targetfolder="db/${schema}/.hooks/post/${path}"
        # create targetfolder if not exists
        [[ -d ${targetfolder} ]] || mkdir -p "${targetfolder}"

        # remove init file if exists to keep consistent
        [[ ! -f "${targetfolder}/${unmode}_dbflow_test.sql" ]] || rm "${targetfolder}/${unmode}_dbflow_test.sql"

        echo "insert into dbflow_test(dft_mainfolder, dft_mode, dft_schema, dft_file) values ('db', '${mode}', '${schema}', '${targetfolder}/${mode}_dbflow_test.sql');" > "${targetfolder}/${mode}_dbflow_test.sql"

        ((CNT_IDX_INIT=CNT_IDX_INIT+1))

        # if [[ ${path} == "tables" ]] && [[ ${mode} == "patch" ]]; then
        #   echo "skipping tables"
        # else
          DBUNION+=( "${targetfolder}/${mode}_dbflow_test.sql" )
        # fi
      fi


    done

    # loop through applications
    if [[ -d "apex" ]]; then


      depth=1
      this_app_schema=""
      if [[ ${PROJECT_MODE} == "FLEX" ]]; then
        depth=2
        this_app_schema=${schema}
      fi

      # only when MULTI and APP_SCHEMA, FLEX or SINGLE
      if [[ ${PROJECT_MODE} != "MULTI" ]] || [[ ${schema} == ${APP_SCHEMA} ]]; then
        items=()
        IFS=$'\n' read -r -d '' -a items < <( find "apex/${this_app_schema}" -maxdepth "${depth}" -mindepth "${depth}" -type d && printf '\0' )

        for dirname in "${items[@]}"
        do
          echo "processing APEX App: ${dirname}"
          echo "insert into dbflow_test(dft_mainfolder, dft_mode, dft_schema, dft_file) values ('apex', '${mode}', '???', '${dirname}/install.sql');" > "${dirname}/install.sql"
          DBUNION+=( "${dirname}/install.sql" )
        done
      fi

      echo
    fi


    # gen test package
    last_elem=${DBUNION[${#DBUNION[@]}-1]}

    # copy first to target file
    cat ".dbFlow/scripts/test/pck_test_dbflow_01.sql" > ".hooks/post/utest_${schema}.sql"

    # now build the cursor
    for file in "${DBUNION[@]}"
    do
      if [[ ${last_elem} == "${file}" ]]; then
        echo "      select '${file}' dft_file from dual; " >> ".hooks/post/utest_${schema}.sql"
      else
        echo "      select '${file}' dft_file from dual union all " >> ".hooks/post/utest_${schema}.sql"
      fi
    done

    # copy second to target file
    cat ".dbFlow/scripts/test/pck_test_dbflow_02.sql" >> ".hooks/post/utest_${schema}.sql"

    echo "exec ut.run('test_dbflow.check_scripts_${mode}', a_color_console => true);" >> ".hooks/post/utest_${schema}.sql"
    echo " -- drop package test_dbflow;" >> ".hooks/post/utest_${schema}.sql"
  done
}


# validate params
check_params "$@"

# get branch name
{ #try
  branch=$(git branch --show-current)
} || { # catch
  branch="develop"
}

# set all folder names which has to be parsed for files to deploy in array SCAN_PATHES
define_folders "${mode}" "${branch}"

echo "mode: $mode"
if [[ ${mode} == "init" || ${mode} == "patch" ]]; then
  gen_scripts
else
  echo_error "unknown mode"
fi

