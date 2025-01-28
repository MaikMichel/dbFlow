#!/usr/bin/env bash
# echo "Your script args ($#) are: $@"

function usage() {
  echo -e "${BWHITE}.dbFlow/build.sh${NC} - build an installable artifact with eiter"
  echo -e "                   all (${BWHITE}init${NC}) or only with changed (${BWHITE}patch${NC}) files"
  echo ""
  echo -e "${BWHITE}Usage:${NC}"
  echo -e "  ${0} --init --version <label>"
  echo -e "  ${0} --patch --version <label> [--start <hash|tag>] [--end <hash|tag>]"
  echo ""
  echo -e "${BWHITE}Options:${NC}"
  echo -e "  -h | --help             - Show this screen"
  echo -e ""
  echo -e "  -i | --init             - Flag to build a full installable artifact "
  echo -e "                            this will delete all objects in target schemas upon install"
  echo -e "  -p | --patch            - Flag to build an update/patch as artifact "
  echo -e "                            This will apply on top of the target schemas and consists"
  echo -e "                            of the difference between the starthash/tag and endhash/tag"
  echo -e "  -v | --version <label>  - Required label of version this artifact represents"
  echo -e "  -s | --start <hash|tag> - Optional hash or tag to determine the diff to the end, defaults to ORIG_HEAD"
  echo -e "  -e | --end <hash|tag>   - Optional hash or tag to determine the diff to the start, defaults to HEAD"
  echo -e "  -c | --cached           - Optional flag to determine the diff of Stage to HEAD, won't work with -s, -e"
  echo ""
  echo -e "  -t | --transferall      - Optional transfer (copy) all folders [mode=patch]"
  echo -e "  -k | --keepfolder       - Optional keep buildfolder inside depot"
  echo -e "  -l | --listfiles        - Optional flag to list files which will be a part of the patch"
  echo -e "  -a | --apply            - Optional flag to call apply directly after patch is build."
  echo -e "                            This will install the artifact in current environment."
  echo -e "  -f | --forceddl         - Optional flag to switch off checking for new table-file through git itself."
  echo -e "                            This will run table_ddl scripts when matching table is present in patch mode"
  echo ""
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  ${0} --init --version 1.0.0"
  echo -e "  ${0} --patch --version 1.1.0"
  echo -e "  ${0} --patch --version 1.2.0 --start 1.0.0"
  echo -e "  ${0} --patch --version 1.3.0 --start 71563f65 --end ba12010a"
  echo -e "  ${0} --patch --version 1.4.0 --start ORIG_HEAD --end HEAD"

  exit $1
}


# get required functions and vars
source ./.dbFlow/lib.sh

# set project-settings from build.env if exists
if [[ -e ./build.env ]]; then
  source ./build.env
fi

# set target-env settings from file if exists
# only relevant to get depot_path... this var should
# exist in both files
if [[ -e ./apply.env ]]; then
  source ./apply.env

  validate_passes
fi

function notify() {
    [[ ${1} = 0 ]] || echo ❌ EXIT "${1}"
    # you can notify some external services here,
    # ie. Slack webhook, Github commit/PR etc.
}

trap '(exit 130)' INT
trap '(exit 143)' TERM
trap 'rc=$?; notify $rc; exit $rc' EXIT

function check_vars() {
  # check require vars from build.env
  do_exit="NO"
  if [[ -z ${PROJECT:-} ]]; then
    echo_error "undefined var: PROJECT"
    do_exit="YES"
  fi

  # when MultisSchema or SingleSchema, this vars are required
  if [[ ${PROJECT_MODE:-"MULTI"} != "FLEX" ]]; then
    if [[ -z ${APP_SCHEMA:-} ]]; then
      echo_error "undefined var: APP_SCHEMA"
      do_exit="YES"
    fi

    if [[ ${PROJECT_MODE:-"MULTI"} != "SINGLE" ]]; then
      if [[ -z ${DATA_SCHEMA:-} ]]; then
        DATA_SCHEMA=${APP_SCHEMA}
      fi
      if [[ -z ${LOGIC_SCHEMA:-} ]]; then
        LOGIC_SCHEMA=${APP_SCHEMA}
      fi
    fi
    if [[ -z ${WORKSPACE:-} ]]; then
      echo_error "undefined var: WORKSPACE"
      do_exit="YES"
    fi
  fi

  if [[ -z ${DEPOT_PATH+x} ]]; then
    echo_error "undefined var: DEPOT_PATH"
    do_exit="YES"
  fi

  ####
  if [[ ${do_exit} == "YES" ]]; then
    echo_warning "aborting"
    exit 1;
  fi
}

function check_params() {
  help_option="NO"
  init_option="NO"
  patch_option="NO"
  version_option="NO"
  version_argument="-"
  start_option="NO"
  start_argument=ORIG_HEAD
  end_option="NO"
  end_argument=HEAD
  keep_option="NO"
  all_option="NO"
  list_option="NO"
  cached_option="NO"
  apply_option="NO"
  forceddl_option="NO"

  # echo "check_params: ${@}"
  while getopts_long 'hipv:s:e:cktlaf help init patch version: start: end: cached keepfolder transferall listfiles apply forceddl' OPTKEY "${@}"; do
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
          's'|'start')
              start_option="YES"
              start_argument="${OPTARG}"
              ;;
          'e'|'end')
              end_option="YES"
              end_argument="${OPTARG}"
              ;;
          'c'|'cached')
              cached_option="YES"
              ;;
          'k'|'keepfolder')
              keep_option="YES"
              ;;
          't'|'transferall')
              all_option="YES"
              ;;
          'l'|'listfiles')
              list_option="YES"
              ;;
          'a'|'apply')
              apply_option="YES"
              ;;
          'f'|'forceddl')
              forceddl_option="YES"
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
    echo_error "Missing arguments"
    usage 1
  fi

  # Rule 1: init or patch
  if [[ ${init_option} == "NO" ]] && [[ ${patch_option} == "NO" ]]; then
    echo_error "Missing build mode, init or patch using flags -i or -p"
    usage 2
  fi
  if [[ ${init_option} == "YES" ]] && [[ ${patch_option} == "YES" ]]; then
    echo_error "Build mode can only be init or patch, not both"
    usage 3
  fi

  # Rule 2: we always need a version
  if [[ ${version_option} == "NO" ]] || [[ ${version_argument} == "-" ]]; then
    echo_error "Missing version"
    usage 4
  else
    version=${version_argument}
  fi

  if [[ ${init_option} == "YES" ]] && ([[ ${start_option} == "YES" ]] || [[ ${end_option} == "YES" ]] || [[ ${cached_option} == "YES" ]]); then
    echo_error "Start, End or Cached are only valid in patch mode"
    usage 5
  fi

  if [[ ${patch_option} == "YES" ]] && ( ( [[ ${start_option} == "YES" ]] || [[ ${end_option} == "YES" ]] ) && [[ ${cached_option} == "YES" ]] ); then
    echo_error "You can use start and/or end OR cached! Not both"
    usage 5
  fi

  # now check dependent params
  if [[ ${init_option} == "YES" ]]; then
    mode="init"
  elif [[ ${patch_option} == "YES" ]]; then
    mode="patch"
  fi



    # Rule 3: When patch, we need git tags or hashes to build the diff
  if [[ $mode == "patch" ]]; then
    if [[ $cached_option == "YES" ]]; then
      diff_args="--cached"
      log_args=""
    else
      if git cat-file -e "${start_argument}" 2> /dev/null; then
        from_commit="${start_argument}"
      else
        echo_error "Start Commit or Tag ${start_argument} not found"
        exit 6
      fi

      if git cat-file -e "${end_argument}" 2> /dev/null; then
        until_commit="${end_argument}"
      else
        echo_error "End Commit or Tag ${end_argument} not found"
        exit 7
      fi

      diff_args="${from_commit} ${until_commit}"
      log_args="${from_commit}...${until_commit}"
    fi
  fi


  # now check keep folder
  if [[ ${keep_option} == "YES" ]]; then
    KEEP_FOLDER="TRUE"
  else
    KEEP_FOLDER="FALSE"
  fi

  # now check ship all files
  if [[ ${all_option} == "YES" ]]; then
    SHIP_ALL="TRUE"
  else
    SHIP_ALL="FALSE"
  fi

  # should build.sh run apply.sh
  if [[ ${apply_option} == "YES" ]]; then
    APPLY_DIRECTLY="TRUE"
  else
    APPLY_DIRECTLY="FALSE"
  fi

  # if true, we won't strip table_ddls from patch when a new table file is present
  if [[ ${forceddl_option} == "YES" ]]; then
    FORCE_TABLE_DDL="TRUE"
  else
    FORCE_TABLE_DDL="FALSE"
  fi

  if [[ ${list_option} == "YES" ]] && [[ $mode == "patch" ]]; then
    echo -e "${PURPLE}Listing changed files (build.env .gitignore apex db reports rest .hooks)${NC}"
    git --no-pager diff -r --compact-summary --dirstat --stat-width=120 --no-commit-id ${diff_args} --diff-filter=ACMRTUXB -- build.env .gitignore apex db reports rest .hooks
    exit 0
  elif [[ ${list_option} == "YES" ]] && [[ $mode == "init" ]]; then
    echo_error "Flag -l|--list is not valid on init mode, cause nothing to list as delta"
    usage 8
  fi
}

function setup_env() {
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

  # get branch name
  { #try
    branch=$(git branch --show-current)
  } || { # catch
    branch="develop"
  }

  # set all folder names which has to be parsed for files to deploy in array SCAN_PATHES
  define_folders ${mode} ${branch}

  # if table changes are inside release, we have to call special-functionalities
  table_changes="FALSE"
  table_array=()
  table_set=()

  # folder outside git repo
  depotpath="$(pwd)/$DEPOT_PATH/$branch"
  targetpath="${depotpath}"/${mode}_${version}
  sourcepath="."

  rel_depotpath="$DEPOT_PATH/$branch"
  rel_targetpath="${rel_depotpath}"/${mode}_${version}

  # initialize logfile
  MDATE=`date "+%Y%m%d%H%M%S"`
  log_file="${MDATE}_bld_${mode}_${version}.log"

  touch "${log_file}"
  full_log_file="$( cd "$( dirname "${log_file}" )" >/dev/null 2>&1 && pwd )/${log_file}"

  exec &> >(tee -a "${log_file}")


  timelog "Building ${BWHITE}${mode}${NC} deployment version: ${BWHITE}${version}${NC}"
  timelog "----------------------------------------------------------"
  timelog "Mode:          ${BWHITE}${mode}${NC}"
  timelog "Version        ${BWHITE}${version}${NC}"
  timelog "Log File:      ${BWHITE}${log_file}${NC}"
  timelog "Branch:        ${BWHITE}${branch}${NC}"
  if [[ $mode == "patch" ]];then
    if [[ ${diff_args} == "--cached" ]]; then

  timelog "cached:        ${BWHITE}yes${NC}"
    else
    display_from=`git rev-parse --short "${from_commit}"`
    display_until=`git rev-parse --short "${until_commit}"`
  timelog "from:          ${BWHITE}${from_commit} (${display_from})${NC}"
  timelog "until:         ${BWHITE}${until_commit} (${display_until})${NC}"
  timelog "transfer all:  ${BWHITE}${SHIP_ALL}${NC}"
  timelog "forceddl       ${BWHITE}${FORCE_TABLE_DDL}${NC}"
    fi
  fi
  timelog "Bash-Version:  ${BWHITE}${BASH_VERSION}${NC}"
  timelog "----------------------------------------------------------"
  timelog "Project        ${BWHITE}${PROJECT}${NC}"
  if [[ ${PROJECT_MODE} != "FLEX" ]]; then
    timelog "App Schema:    ${BWHITE}${APP_SCHEMA}${NC}"
    if [[ ${PROJECT_MODE} != "SINGLE" ]]; then
    timelog "Data Schema:   ${BWHITE}${DATA_SCHEMA}${NC}"
    timelog "Logic Schema:  ${BWHITE}${LOGIC_SCHEMA}${NC}"
    fi
    timelog "Workspace:     ${BWHITE}${WORKSPACE}${NC}"
  fi
  timelog "Schemas:       (${BWHITE}${SCHEMAS[*]}${NC})"
  timelog "----------------------------------------------------------"
  timelog "Depotpath:     ${BWHITE}${rel_depotpath}${NC}"
  timelog "Targetpath:    ${BWHITE}${rel_targetpath}${NC}"
  timelog "Sourcepath:    ${BWHITE}${sourcepath}${NC}"
  timelog "Keepfolder:    ${BWHITE}${KEEP_FOLDER}${NC}"
  timelog "----------------------------------------------------------"
  timelog "----------------------------------------------------------"
  timelog "----------------------------------------------------------"
}

function copy_all_files() {
  timelog "Copy all files ..."
  for folder in "${MAINFOLDERS[@]}"
  do
    if [[ -d ${folder} ]]; then
      cp -R "${folder}" "${targetpath}"
    fi
  done

  [ ! -f build.env ] || cp build.env "${targetpath}"
  [ ! -f .gitignore ] || cp .gitignore "${targetpath}"
}

function copy_files {
  timelog " ==== Checking Files and Folders ===="
  [[ ! -d ${targetpath} ]] || rm -rf "${targetpath}"
  timelog " "
  # getting updated files, and
  # copy (and overwrite forcefully) in exact directory structure as in git repo
  if [[ "${mode}" == "init" ]]; then
    timelog "Creating directory ${targetpath}"
    mkdir -p "${targetpath}"

    copy_all_files
  else
    # Changes on configs?
    num_changes=`git diff -r --name-only --no-commit-id ${diff_args} --diff-filter=ACMRTUXB -- build.env .gitignore | wc -l | xargs`
    if [[ $num_changes -gt 0 ]]; then
      if [ ! -d "${targetpath}" ]; then
        timelog "Creating directory '${targetpath}'"
        mkdir -p "${targetpath}"
      fi

      if [[ $(uname) == "Darwin" ]]; then
        rsync -Rr `git diff -r --name-only --no-commit-id ${diff_args} --diff-filter=ACMRTUXB -- build.env .gitignore` "${targetpath}"
      else
        cp --parents -Rf `git diff -r --name-only --no-commit-id ${diff_args} --diff-filter=ACMRTUXB -- build.env .gitignore` "${targetpath}"
      fi
    fi

    # Patch
    for folder in "${MAINFOLDERS[@]}"
    do
      num_changes=`git diff -r --name-only --no-commit-id ${diff_args} --diff-filter=ACMRTUXB -- "${folder}" | wc -l | xargs`
      if [[ $num_changes -gt 0 ]]; then

        if [ ! -d "${targetpath}" ]; then
          timelog "Creating directory '${targetpath}'"
          mkdir -p "${targetpath}"
        fi

        timelog "Copy files in folder: ${folder}"
        if [[ $(uname) == "Darwin" ]]; then
          rsync -Rr `git diff -r --name-only --no-commit-id ${diff_args} --diff-filter=ACMRTUXB -- "${folder}"` "${targetpath}"
        else
          cp --parents -Rf `git diff -r --name-only --no-commit-id ${diff_args} --diff-filter=ACMRTUXB -- "${folder}"` "${targetpath}"
        fi
      else
        timelog "No changes in folder: ${folder}"
      fi

    done




    # additionaly we need all triggers belonging to views
    # loop through schemas
    for schema in "${SCHEMAS[@]}"
    do
      # any views?
      if [[ -d "${targetpath}"/db/${schema}/views ]]
      then
        # get view files
        for file in $(ls "${targetpath}/db/${schema}/views" | sort )
        do
          # check if there is any file like viewfile_*.sql
          myfile=${file//./"_*."}
          for f in ${sourcepath}/db/${schema}/sources/triggers/${myfile}; do
            if [[ -e "${f}" ]];
            then
                # yes, so copy it...
                if [[ $(uname) == "Darwin" ]]; then
                  rsync -Rr "${f}" "${targetpath}"
                else
                  cp --parents -Rf "${f}" "${targetpath}"
                fi

                timelog "Additionaly add ${f}"
            fi
          done
        done
      fi
    done



    # additionaly we need all conditions beloning to REST
    if [[ -d "${targetpath}"/rest ]]; then
      folders=()
      if [[ ${PROJECT_MODE} == "FLEX" ]]; then
        diritems=()
        IFS=$'\n' read -r -d '' -a diritems < <( find "${targetpath}/rest" -maxdepth 1 -mindepth 1 -type d | sort -f && printf '\0' )

        for dirname in "${diritems[@]}"
        do
          folders+=( $(basename "${dirname}") )
        done
      else
        folders=( . )
      fi


      for fldr in "${folders[@]}"
      do
        path=modules

        if [[ -d "${targetpath}"/rest/$fldr/$path ]]; then
          depth=1
          if [[ $path == "modules" ]]; then
            depth=2
          fi

          items=()
          IFS=$'\n' read -r -d '' -a items < <( find "${targetpath}/rest/${fldr}/${path}/" -maxdepth $depth -mindepth $depth -type f | sort && printf '\0' )

          for file in "${items[@]}"
          do

            base=${targetpath}/rest/${fldr}/
            part=${file#$base}

            if [[ "${part}" == *".sql" ]] && [[ "${part}" != *".condition.sql" ]]; then
              srcf=${sourcepath}/rest/$fldr/$part

              if [[ -f ${srcf/.sql/.condition.sql} ]]; then

                # yes, so copy it...
                if [[ $(uname) == "Darwin" ]]; then
                  rsync -Rr "${srcf/.sql/.condition.sql}" "${targetpath}"
                else
                  cp --parents -Rf "${srcf/.sql/.condition.sql}" "${targetpath}"
                fi
              fi

            fi
          done
        fi
      done
    fi


    if [ ! -d "${targetpath}" ]; then
      timelog "Creating directory '${targetpath}'"
      mkdir -p "${targetpath}"
    fi

    ## and we need all hooks
    for schema in "${SCHEMAS[@]}"
    do
      # yes, so copy it...
      if [[ $(uname) == "Darwin" ]]; then
        rsync -Rr "${sourcepath}/db/${schema}/.hooks" "${targetpath}"
      else
        if [[ -d "${sourcepath}/db/${schema}/.hooks" ]]; then
          cp --parents -Rf "${sourcepath}/db/${schema}/.hooks" "${targetpath}"
        fi
      fi
    done

    if [[ $(uname) == "Darwin" ]]; then
      rsync -Rr "${sourcepath}/.hooks" "${targetpath}"
    else
      if [[ -d "${sourcepath}/.hooks" ]]; then
        cp --parents -Rf "${sourcepath}/.hooks" "${targetpath}"
      fi
    fi

    # if there are table scripts that are new in this delta and there are also table_ddl scripts
    # for these new table scripts, we leave out the table_ddl scripts
    if [[ ${FORCE_TABLE_DDL} == "FALSE" ]]; then
      timelog " "
      for schema in "${SCHEMAS[@]}"
      do
        local table_folder="${sourcepath}/db/${schema}/tables"
        local table_files=`git diff -r --name-only --no-commit-id ${diff_args} --diff-filter=A -- "${table_folder}" ":!${table_folder}/tables_ddl"`

        # for each new (A) table file
        for file in $table_files; do
          local file_base=$(basename "${file}")
          for f in "${targetpath}/db/${schema}/tables/tables_ddl"/${file_base%%.*}.*; do
            timelog "New table detected: db/${schema}/tables/${file_base}"
            timelog "└─> removing table_ddl db/${schema}/tables/tables_ddl/$(basename ${f})" warning
            rm "$f"
          done
        done
      done
    fi
  fi

  timelog " "
}

function list_files_to_remove() {
  # if patch mode we remove unnecessary files
  if [[ "${mode}" == "patch" ]]; then
    target_drop_file="${targetpath}"/remove_files_$version.lst

    for folder in "${MAINFOLDERS[@]}"
    do

      # to avoid dead-files
      num_changes=`git diff -r --name-only --no-commit-id ${diff_args} --diff-filter=D -- "${folder}" | wc -l | xargs`

      if [[ $num_changes -gt 0 ]]; then
        timelog "removing dead-files"

        for line in `git diff -r --name-only --no-commit-id ${diff_args} --diff-filter=D -- "${folder}"`
        do
          echo "${line}" >> "${target_drop_file}"
        done
      else
        timelog "No deleted files in folder: ${folder}"
      fi
    done
  fi
}

function write_install_schemas(){
  if [[ -d "${targetpath}"/db ]]; then
    timelog " ==== Checking Schemas ${SCHEMAS[@]} ===="
    timelog ""

    # loop through schemas
    for schema in "${SCHEMAS[@]}"
    do
      if [[ -d "${targetpath}"/db/${schema} ]]; then
        # file to write to
        target_install_base=${mode}_${schema}_${version}.sql
        target_install_file="${targetpath}"/db/${schema}/$target_install_base

        timelog ""
        timelog " ==== Schema: ${schema} - /db/${schema}/$target_install_base ===="
        timelog ""

        # write some infos
        {
          echo "set define '^'"
          echo "set concat on"
          echo "set concat ."
          echo "set verify off"
          echo "WHENEVER SQLERROR EXIT SQL.SQLCODE"

          echo ""

          echo "define VERSION = '^1'"
          echo "define MODE = '^2'"

          echo "set timing on"
          echo "set trim on"
          echo "set linesize 2000"
          echo "set sqlblanklines on"
          echo "set tab off"
          echo "set pagesize 9999"
          echo "set trimspool on"
          echo ""

          echo "Prompt .............................................................................. "
          echo "Prompt .............................................................................. "
          echo "Prompt .. Start Installation for schema: ${schema} "
          echo "Prompt ..                       Version: $mode $version "
          echo "Prompt .............................................................................. "
          echo "set serveroutput on"
          echo "set scan off"
          echo ""

          if [[ "${mode}" == "patch" ]]; then
            echo "Prompt .. Commit-History to install: "
            if [[ ${diff_args} == "--cached" ]]; then
              echo "Prompt .. no logs availabe installing patch from cache"
            else
              git log --pretty=format:'Prompt ..   %h %s <%an>' ${log_args} -- "db/${schema}"
            fi
            echo " "
            echo "Prompt .. "
          # echo "Prompt "
            echo "Prompt .............................................................................. "

            echo "Prompt "
            echo "Prompt "
          fi
        } > "${target_install_file}"

        # check every path in given order
        for path in "${SCAN_PATHES[@]}"
        do
          ## if [[ -d "${targetpath}"/db/${schema}/${path} ]]; then
            timelog "Writing calls for ${path}"
            {

              # set scan to on, to make use of vars inside main schema-hooks
              if [[ "${path}" == ".hooks/pre" ]] || [[ "${path}" == ".hooks/post" ]]; then
                echo "set scan on"
              fi

              # pre folder-hooks (something like db/schema/.hooks/pre/tables)
              entries=("${targetpath}/db/${schema}/.hooks/pre/${path}"/*.*)
              if [[ ${#entries[@]} -gt 0 ]]; then
                for entry in "${entries[@]}"; do
                  file=$(basename "${entry}")
                  file_ext=${file#*.}

                  echo "set scan on"

                  if [[ "${file_ext}" == "tables.sql" ]]; then

                    if [ ${#table_set[@]} -gt 0 ]; then
                      echo "Prompt running .hooks/pre/${path}/${file} with table set"
                      for table_item in "${table_set[@]}"
                      do
                        echo "Prompt >>> db/${schema}/.hooks/pre/${path}/${file} ${version} ${mode} ${table_item}.sql"
                        echo "@@.hooks/pre/${path}/${file} ${version} ${mode} ${table_item}.sql"
                        echo "Prompt <<< db/${schema}/.hooks/pre/${path}/${file} ${version} ${mode} ${table_item}.sql"
                      done
                      echo "Prompt"
                      echo ""
                    fi

                  else
                    echo "Prompt >>> db/${schema}/.hooks/pre/${path}/${file}"
                    echo "@@.hooks/pre/${path}/${file}"
                    echo "Prompt <<< db/${schema}/.hooks/pre/${path}/${file}"
                  fi
                done
                echo "Prompt"
                echo ""
              fi

              # read files from folder
              # if packages then sort by extension descending
              if [[ "${path}" == "sources/packages" ]] || [[ "${path}" == "sources/types" ]] || [[ "${path}" == "tests/packages" ]]; then
                sorted=("${targetpath}/db/${schema}/${path}"/*.*ks) #pks|tks
                sorted+=("${targetpath}/db/${schema}/${path}"/*.*kb) #pkb|tkb
                sorted+=("${targetpath}/db/${schema}/${path}"/*.sql)
              else
                sorted=("${targetpath}/db/${schema}/${path}"/*.*)
              fi

              # nur wenn es files gibt
              if [[ ${#sorted[@]} -gt 0 ]]; then
                if [[ "${path}" == "ddl/patch/pre" ]] || [[ "${path}" == "ddl/patch/pre_*" ]] || [[ "${path}" == "views" ]]; then
                  echo ""
                  echo "WHENEVER SQLERROR CONTINUE"
                  echo ""
                fi
                echo "Prompt Installing ${path} ..."
                echo "Prompt"
                echo "set define off"
                for entry in "${sorted[@]}"; do
                  file=$(basename "${entry}")
                  file_ext=${file#*.}

                  if [[ "${path}" == "tables" ]]; then
                    skipfile="FALSE"
                    table_changes="TRUE"

                    # store tablename in array
                    table_name="${file%%.*}"
                    table_array+=( ${table_name} )

                    if [[ "${mode}" == "patch" ]]; then
                      # is there any matching file in tables_ddl
                      if [[ -d "${targetpath}/db/${schema}/tables/tables_ddl" ]]; then
                        for f in "${targetpath}/db/${schema}/tables/tables_ddl"/${file%%.*}.*; do
                          if [[ -e "$f" ]]; then
                            skipfile="TRUE"
                          fi
                        done
                      fi

                      # is there any matching file in tables_ddl defined just for the target branch?
                      if [[ -d "${targetpath}/db/${schema}/tables/tables_ddl/${branch}" ]]; then
                        for f in "${targetpath}/db/${schema}/tables/tables_ddl/${branch}"/${file%%.*}.*; do
                          if [[ -e "$f" ]]; then
                            skipfile="TRUE"
                          fi
                        done
                      fi
                    fi

                    if [[ "$skipfile" == "TRUE" ]]; then
                      echo "Prompt ... skipped ${file}"
                    else
                      echo "Prompt >>> db/${schema}/${path}/${file}"
                      echo "@@${path}/${file}"
                      echo "Prompt <<< db/${schema}/${path}/${file}"
                    fi
                  else

                    if ([[ "${path}" == ".hooks/pre" ]] || [[ "${path}" == ".hooks/post" ]]) && [[ "${file_ext}" == "tables.sql" ]]; then

                      if [ ${#table_set[@]} -gt 0 ]; then
                        echo "Prompt running ${path}/${file} with table set"
                        for table_item in "${table_set[@]}"
                        do
                          echo "Prompt >>> db/${schema}/${path}/${file} ${version} ${mode} ${table_item}.sql"
                          echo "@@${path}/${file} ${version} ${mode} ${table_item}.sql"
                          echo "Prompt <<< db/${schema}/${path}/${file} ${version} ${mode} ${table_item}.sql"
                        done
                        echo "Prompt"
                        echo ""
                      fi
                    else

                      echo "Prompt >>> db/${schema}/${path}/${file}"
                      if [[ "${path}" == "ddl/pre_*" ]] && [[ "${mode}" == "patch" ]]; then
                        target_stage="${path/'ddl/pre_'/}"
                        echo "--${target_stage}@@${path}/${file}"
                      else
                        echo "@@${path}/${file}"
                        echo "Prompt <<< db/${schema}/${path}/${file}"
                      fi

                    fi
                  fi
                done #files in folder (sorted)

                echo "set define '^'"
                echo "Prompt"
                echo "Prompt"
                echo ""

                if [[ "${path}" == "ddl/patch/pre" ]] || [[ "${path}" == "ddl/patch/pre_*" ]] || [[ "${path}" == "views" ]]
                then
                  echo "WHENEVER SQLERROR EXIT SQL.SQLCODE"
                  echo ""
                fi
              fi

              # union table names
              if [[ "${path}" == "tables" ]]; then
                # get distinct values of array
                table_set=($(printf "%s\n" "${table_array[@]}" | sort -u))
              fi



              # post folder hooks
              entries=("${targetpath}/db/${schema}/.hooks/post/${path}"/*.*)
              if [[ ${#entries[@]} -gt 0 ]]; then
                for entry in "${entries[@]}"; do
                  file=$(basename "${entry}")
                  file_ext=${file#*.}

                  if [[ "${file_ext}" == "tables.sql" ]]; then

                    if [ ${#table_set[@]} -gt 0 ]; then
                      echo "Prompt running .hooks/post/${path}/${file} with table set"
                      for table_item in "${table_set[@]}"
                      do
                        echo "Prompt >>> db/${schema}/.hooks/post/${path}/${file} ${version} ${mode} ${table_item}.sql"
                        echo "@@.hooks/post/${path}/${file} ${version} ${mode} ${table_item}.sql"
                        echo "Prompt <<< db/${schema}/.hooks/post/${path}/${file} ${version} ${mode} ${table_item}.sql"
                      done
                      echo "Prompt"
                      echo ""
                    fi

                  else
                    echo "Prompt >>> db/${schema}/.hooks/post/${path}/${file}"
                    echo "@@.hooks/post/${path}/${file}"
                    echo "Prompt <<< db/${schema}/.hooks/post/${path}/${file}"
                  fi
                done

                echo "Prompt"
                echo ""
              fi

              # set scan to off, to make use of vars inside main schema-hooks
              if [[ "${path}" == ".hooks/pre" ]] || [[ "${path}" == ".hooks/post" ]]; then
                echo "set scan off"
              fi

            } >> "${target_install_file}"
          ## fi #path exists
        done #paths

        {
          echo "prompt compiling schema"
          echo "exec dbms_utility.compile_schema(schema => user, compile_all => false);"
          echo "exec dbms_session.reset_package"

          echo "Prompt"
          echo "Prompt"
          echo "exit"
        } >> "${target_install_file}"
      else
        echo "  .. db/${schema} does not exist in ${targetpath}"
      fi
    done
  else
    timelog " ... no db folder"
  fi
}

function write_install_apps() {
  # loop through applications
  if [[ -d "${targetpath}/apex" ]]; then
    timelog ""
    timelog " ==== Checking APEX Applications ===="
    timelog ""

    # file to write to
    target_apex_file="${targetpath}/apex_files_$version.lst"
    [ -f "${target_apex_file}" ] && rm "${target_apex_file}"

    depth=1
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=3
    fi

    items=()
    IFS=$'\n' read -r -d '' -a items < <( find "${targetpath}/apex" -maxdepth "${depth}" -mindepth "${depth}" -type d && printf '\0' )

    for dirname in "${items[@]}"
    do
      echo "${dirname/${targetpath}\//}" >> "${target_apex_file}"
      timelog "Writing call to install APP: ${dirname/${targetpath}\//} "
    done
  fi
}

function write_install_rest() {
  # check rest
  if [[ -d "${targetpath}"/rest ]]; then
    timelog ""
    timelog " ==== Checking REST Modules ===="
    timelog ""

    folders=()
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      items=()
      IFS=$'\n' read -r -d '' -a items < <( find rest -maxdepth 1 -mindepth 1 -type d | sort -f && printf '\0' )

      for dirname in "${items[@]}"
      do
        folders+=( $(basename "${dirname}") )
      done
    else
      folders=( . )
    fi

    for fldr in "${folders[@]}"
    do
      if [[ ${fldr} != "." ]]; then
        timelog " == Schema: $fldr"
      fi
      rest_to_install="FALSE"

      # file to write to
      target_install_base=rest_${mode}_${version}.sql
      target_install_file="${targetpath}/rest/$fldr/$target_install_base"
      [ -f "${target_install_file}" ] && rm "${target_install_file}"

      # write some infos
      echo "Prompt .............................................................................. " >> "${target_install_file}"
      echo "Prompt .............................................................................. " >> "${target_install_file}"
      echo "Prompt .. Start REST installation " >> "${target_install_file}"
      echo "Prompt .. Version: $mode $version " >> "${target_install_file}"
      echo "Prompt .. Folder:  $fldr " >> "${target_install_file}"
      echo "Prompt .............................................................................. " >> "${target_install_file}"
      echo "set serveroutput on" >> "${target_install_file}"
      echo "" >> "${target_install_file}"

      # check every path in given order
      for path in "${rest_array[@]}"
      do
        if [[ -d "${targetpath}"/rest/$fldr/$path ]]; then
          depth=1
          if [[ $path == "modules" ]]; then
            depth=2
          fi

          items=()
          IFS=$'\n' read -r -d '' -a items < <( find "${targetpath}/rest/${fldr}/${path}/" -maxdepth $depth -mindepth $depth -type f | sort && printf '\0' )

          for file in "${items[@]}"
          do

            rest_to_install="TRUE"
            base="${targetpath}/rest/$fldr/"
            part=${file#$base}

            timelog "Writing call to install RESTModul: ${part} "

            if [[ "${part}" == *".sql" ]] && [[ "${part}" != *".condition.sql" ]]; then
              echo "Prompt ... $part" >> "${target_install_file}"

              if [[ -f ${file/.sql/.condition.sql} ]]; then
                echo "begin" >> "${target_install_file}"
                echo "  if" >> "${target_install_file}"
                echo "  @@${part/.sql/.condition.sql}" >> "${target_install_file}"
                echo "  then" >> "${target_install_file}"
                echo "    @@${part}" >> "${target_install_file}"
                echo "  else" >> "${target_install_file}"
                echo "    dbms_output.put_line('!!! ${part} not installed cause condition did not match');" >> "${target_install_file}"
                echo "  end if;" >> "${target_install_file}"
                echo "end;" >> "${target_install_file}"
              else
                echo "@@${part}" >> "${target_install_file}"
              fi
              echo "/" >> "${target_install_file}"
            fi

          done
          echo "" >> "${target_install_file}"

        fi
      done
      # nothing to install, just remove empty file
      if [[ "${rest_to_install}" == "FALSE" ]]; then
        rm "${target_install_file}"
        timelog " ... nothing found in ${path} "
      fi

    done
  fi
}

function gen_changelog() {
  local current_tag=${1}
  local previous_tag=${2}
  local targetfile=${3}
  timelog "Generating Changelog ${current_tag}...${previous_tag} to ${targetfile}" ${info}

  # define log
  changetime=`date "+%Y%m%d%H%M%S"`
  logf=changelog_${changetime}.md
  tag_date=$(git log -1 --pretty=format:'%ad' --date=short ${current_tag})

  printf "# ${PROJECT} - Changelog\n\n" > ${logf}
  printf "## ${current_tag} (${tag_date})\n\n" >> ${logf}

  if [[ -n ${INTENT_PREFIXES} ]]; then
    for intent in "${!INTENT_PREFIXES[@]}"; do
      readarray -t fixes <<< "$(git log ${log_args} --pretty="%s" --reverse | grep -v Merge | grep "^${INTENT_PREFIXES[$intent]}: *")"
      fixes=($(printf "%q\n" "${fixes[@]}" | sort -u))

      if [[ ${#fixes[@]} -gt 0 ]] && [[ ${fixes[0]} != "" ]]; then
        printf "### ${INTENT_NAMES[$intent]}\n\n" >> ${logf}

        for fix in "${fixes[@]}"; do
          fix_line=${fix/"${INTENT_PREFIXES[$intent]}: "/}
          fix_issue=""

          if [[ -n ${TICKET_MATCH} ]]; then
            fix_issue=$(echo "${fix_line}" | grep -e "${TICKET_MATCH}" -o || true)
          fi

          echo_line=""
          if [[ $fix_issue != "" ]] && [[ -n ${TICKET_URL} ]]; then
            echo_line="* ${fix_line} [View]($(force_trailing_slash ${TICKET_URL})${fix_issue})" >> ${logf}
          else
            echo_line="* ${fix_line}" >> ${logf}
          fi

          grep -qxF "${echo_line}" ${logf} || echo "${echo_line}" >> ${logf}
        done
        printf "\n\n" >> ${logf}
      fi;

    done
  fi

  # when INTENT_ELSE is defined output goes here
  if [[ -n ${INTENT_ELSE} ]]; then
    intent_pipes=$(printf '%s|' "${INTENT_PREFIXES[@]}" | sed 's/|$//')
    readarray -t fixes <<< "$(git log ${log_args} --pretty="%s" --reverse | grep -v Merge | grep -v -E "^${intent_pipes}: *")"
    fixes=($(printf "%q\n" "${fixes[@]}" | sort -u))

    if [[ ${#fixes[@]} -gt 0 ]] && [[ ${fixes[0]} != "" ]]; then
      if [[ -n ${INTENT_PREFIXES} ]]; then
        printf "### ${INTENT_ELSE}\n\n" >> ${logf}
      fi

      for fix in "${fixes[@]}"; do
        fix_line=${fix}
        fix_issue=$(echo "${fix_line}" | grep -e "${TICKET_MATCH}" -o || true)

        if [[ $fix_issue != "" ]]; then
          echo "* ${fix_line} [View]($(force_trailing_slash ${TICKET_URL})${fix_issue})\n" >> ${logf}
        else
          echo "* ${fix_line}\n" >> ${logf}
        fi
      done
      printf "\n\n" >> ${logf}
    fi;
  fi

  echo "---" >> ${logf}


  if [[ -f ${targetfile} ]]; then
    # remove first line
    sed -i '1d' ${targetfile}

    # append to new output
    cat ${targetfile} >> ${logf}
    rm ${targetfile}
  fi


  mv ${logf} ${targetfile}
  timelog "Changelog written to ${targetfile}" ${success}
}

function write_changelog() {
  if [[ ${diff_args} == "--cached" ]]; then
    timelog "No changelog cause installing from cache"
  else
    timelog ""
    count_commits=$(git rev-list --all --count)
    if [ "$count_commits" -gt "0" ]; then
      if git cat-file -e "${until_commit:-HEAD}" 2> /dev/null; then
        current_tag=${until_commit:-HEAD}
      else
        timelog "End Commit or Tag ${until_commit:-HEAD} not found" "${warning}"
        return
      fi

      if [[ ${current_tag} == "HEAD" ]]; then
        previous_tag=$(git describe --tags --abbrev=0 --always)
      else
        previous_tag=$(git tag --sort=-creatordate | grep -A 1 "${current_tag}" | tail -n 1) || true
      fi

      # if start and end are the same at head, we put all into the change log
      # otherwise we had to look for a previous commit: git log --format="%H" -n 2 | tail -1
      if [[ ${current_tag} == "HEAD" ]]; then
        current_commit=$(git rev-parse HEAD)
        if [[ ${current_commit} == "${previous_tag}" ]]; then
          previous_tag=$(git log --max-parents=0 HEAD --pretty=format:%H)
        fi
      fi

      gen_changelog "${current_tag}" "${previous_tag}" "changelog_${mode}_${version}.md"

      timelog "ChangeLog generated: ${current_tag} -- ${previous_tag}"
    else
      timelog "ChangeLog not generated: Nothing commited yet"
    fi
  fi
}

function write_release_notes() {
  # check if there is a release_notes folder in reports
  if [[ -d "${targetpath}/reports/release_notes" ]]; then
    timelog "Retrieving release notes"
    # copy all files (init = all, patch = changed) to a new file
    for f in "${targetpath}"/reports/release_notes/release_note_*.md; do (cat "${f}"; echo) >> ${targetpath}/release_notes_${mode}_${version}.md; done
  else
    timelog "no release notes found"
  fi
}

function copy_all_when_defined_on_patch() {
  if [[ ${mode} == "patch" ]] && [[ ${SHIP_ALL} == "TRUE" ]]; then
    copy_all_files
  fi
}

function manage_artifact () {
  # Output files to logfile
  find "${targetpath}" | sed -e 's/[^-][^\/]*\//--/g;s/--/ |-/' >> "${full_log_file}"

  timelog ""
  timelog "==== .......... .......... .......... ==== " "${success}"

  # remove colorcodes from logfile
  cat "${full_log_file}" | sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" > "${full_log_file}.colorless"
  rm "${full_log_file}"
  mv "${full_log_file}.colorless" "${full_log_file}"

  # create artifact
  if [[ -d ${targetpath} ]]; then

    mv "${full_log_file}" "${targetpath}"/
    [[ -f "changelog_${mode}_${version}.md" ]] && mv "changelog_${mode}_${version}.md" "${targetpath}"/

    # write dbFlow version info to control file
    sed '/^## \[./!d;q' .dbFlow/CHANGELOG.md > "${targetpath}"/dbFlow_${mode}_${version}.version

    # pack directoy
    tar -C "${targetpath}" -czf "${targetpath}.tar.gz" .

    timelog "Artifact writen to ${DEPOT_PATH}/${branch}/${mode}_${version}.tar.gz"
    if [[ ${KEEP_FOLDER} != "TRUE" ]]; then
      rm -rf "${targetpath}"
    fi
  else
    echo_error "Nothing to release, aborting"
    exit 1
  fi


  if [[ ${KEEP_FOLDER} == "TRUE" ]]; then
    timelog "Visit folder ${DEPOT_PATH}/${branch}/${mode}_${version} to view content of the artifact"
  fi
  timelog "==== ..........    DONE    .......... ==== " "${success}"

}

function make_a_new_version() {
  # is there a remote origin?
  if git remote -v | grep -q "^origin"; then
    git push
  fi

  # Tag erstellen und pushen
  git tag -a "V${version}" -m "new release with tag V${version} created"

  if [[ -n "$(git remote)" ]]; then
    git push origin "V${version}"
  fi

}

function check_push_to_depot() {
  local current_path=$(pwd)

  if [[ -z ${DBFLOW_JENKINS:-} ]]; then
    # go to depot
    cd "$(pwd)/$DEPOT_PATH"

    # is this a git repot?
    if [[ -d ".git" ]]; then

      # is there a remote?
      if [[ -n "$(git remote)" ]]; then

        if [[ -n $(git status -s) ]]; then
          git pull
          git add "${targetpath}.tar.gz"
          git commit -m "Adds ${targetpath}.tar.gz"
          git push
        fi # git status

      fi # git remote

    fi # git path

    # and back to start
    cd "${current_path}"

  fi # DBFLOW_JENKINS
}


function check_make_new_version() {
  if [[ -z ${DBFLOW_JENKINS:-} ]] && [[ -z ${DBFLOW_RELEASE_IS_RUNNUNG:-} ]]; then
    # on branch master ask if we should tag current version and conmmit
    prod_branches=( "master" "main" )
    if [[ " ${prod_branches[@]} " =~ " ${branch} " ]]; then

      echo
      echo "Do you wish to commit, tag and push the new version to origin"
      echo "  Y - current version will be commited, tagged and pushed"
      echo "  N - Nothing will happen, all generated files won't be touched"

      read -r modus

      shopt -s nocasematch
      case "$modus" in
        "Y" )
          make_a_new_version
          ;;
        *)
          echo "Nothing has happened"
          ;;
      esac

    fi
  fi # DBFLOW_JENKINS
}


function call_apply_when_flag_is_set() {
  if [[ -z ${DBFLOW_RELEASE_IS_RUNNUNG:-} ]]; then
    if [[ ${APPLY_DIRECTLY} == "TRUE" ]]; then
      echo "calling apply"

      .dbFlow/apply.sh --"${mode}" --version "${version}"
    else
      echo -e "${LWHITE}just call ${NC}${BWHITE}.dbFlow/apply.sh --${mode} --version ${version} ${NC}${LWHITE}inside your instance folder${NC}"
    fi
  fi
}

###############################################################################################
###############################################################################################
###############################################################################################


# validate params this script was called with
check_params "$@"

# validate and check existence of vars defined in build.env
check_vars

# define some vars
setup_env

# copy all or changed files, based ob mode
copy_files

# when something was removed, remove it in target too
list_files_to_remove

# write installation files
write_install_schemas
write_install_apps
write_install_rest

# changelog
write_changelog

# releasenotes
write_release_notes

# if all files should be included
copy_all_when_defined_on_patch

# zip files and clear logs
manage_artifact

# ask if artifact should be pushed
check_push_to_depot

# # ask if this version should be there as tag too
check_make_new_version

# if you used flag -a/--apply, then just do it
call_apply_when_flag_is_set