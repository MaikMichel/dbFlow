#!/bin/bash
# echo "Your script args ($#) are: $@"

usage() {
  echo -e "${BWHITE}.dbFlow/build.sh${NC} - build an installable artifact with eiter"
  echo -e "                   all (${BYELLOW}init${NC}) or only with changed (${BYELLOW}patch${NC}) files"
  echo ""
  echo -e "${BWHITE}Usage:${NC}"
  echo -e "  $0 --init --version <label>"
  echo -e "  $0 --patch --version <label> [--start <hash|tag>] [--end <hash|tag>]"
  echo ""
  echo -e "${BWHITE}Options:${NC}"
  echo -e "  -h | --help             - Show this screen"
  echo -e "  -d | --debug            - Show additionaly output messages"
  echo -e "  -i | --init             - Flag to build a full installable artifact "
  echo -e "                            this will delete all objects in target schemas upon install"
  echo -e "  -p | --patch            - Flag to build an update/patch as artifact "
  echo -e "                            This will apply on top of the target schemas and consists"
  echo -e "                            of the difference between the starthash/tag and endhash/tag"
  echo -e "  -v | --version <label>  - Required label of version this artifact represents"
  echo -e "  -s | --start <hash|tag> - Optional hash or tag to determine the difference to the end, defaults to ORIG_HEAD"
  echo -e "  -e | --end <hash|tag>   - Optional hash or tag to determine the difference to the start, defaults to HEAD"
  echo ""
  echo -e "  -a | --shipall          - Optional ship all folders [mode=patch]"
  echo -e "  -k | --keepfolder       - Optional keep buildfolder inside depot"
  echo -e "  -l | --listfiles        - Optional flag to list files which will be a part of the patch"
  echo ""
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  $0 --init --version 1.0.0"
  echo -e "  $0 --patch --version 1.1.0"
  echo -e "  $0 --patch --version 1.2.0 --start 1.0.0"
  echo -e "  $0 --patch --version 1.3.0 --start 71563f65 --end ba12010a"
  echo -e "  $0 --patch --version 1.4.0 --start ORIG_HEAD --end HEAD"

  exit 1
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
fi



function check_vars() {
  # check require vars from build.env
  do_exit="NO"
  if [[ -z ${PROJECT:-} ]]; then
    echo_error "undefined var: PROJECT"
    do_exit="YES"
  fi

  # when MultisSchema or SingleSchema, this vars are required
  if [[ ${PROJECT_MODE:"MULTI"} != "FLEX" ]]; then
    if [[ -z ${APP_SCHEMA:-} ]]; then
      echo_error "undefined var: APP_SCHEMA"
      do_exit="YES"
    fi

    if [[ ${PROJECT_MODE:"MULTI"} != "SINGLE" ]]; then
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
  ! getopt --test > /dev/null
  if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
      echo_fatal 'I’m sorry, `getopt --test` failed in this environment.'
      exit 1
  fi

  OPTIONS=dhipv:s:e:kal
  LONGOPTS=debug,help,init,patch,version:,start:,end:,keepfolder,shipall,listfiles

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

  debug="n" help="n" init="n" patch="n" version="-" start=ORIG_HEAD end=HEAD k="n" a="n" l="n"

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
          -v|--version)
              version="$2"
              shift 2
              ;;
          -s|--start)
              start="$2"
              shift 2
              ;;
          -e|--end)
              end="$2"
              shift 2
              ;;
          -k|--keepfolder)
              k=y
              shift
              ;;
          -a|--shipall)
              a=y
              shift
              ;;
          -l|--listfiles)
              l=y
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

  # handle non-option arguments
  # if [[ $# -ne 1 ]]; then
  #     echo "$0: A single input file is required."
  #     exit 4
  # fi


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

  # Rule 2: we always need a version
  if [[ -z $version ]] || [[ $version == "-" ]]; then
    echo_error "Missing version"
    usage
    exit 1
  fi

  # now check dependent params
  if [[ $i == "y" ]]; then
    mode="init"
  elif [[ $p == "y" ]]; then
    mode="patch"
  fi

    # Rule 3: When patch, we need git tags or hashes to build the diff
  if [[ $mode == "patch" ]]; then
    if git cat-file -e $start 2> /dev/null; then
      from_commit=$start
    else
      echo_error "Start Commit or Tag $start not found"
      exit 1
    fi

    if git cat-file -e $end 2> /dev/null; then
      until_commit=$end
    else
      echo_error "End Commit or Tag $end not found"
      exit 1
    fi
  fi

  # now check keep folder
  if [[ $k == "y" ]]; then
    KEEP_FOLDER="TRUE"
  elif [[ $p == "y" ]]; then
    KEEP_FOLDER="FALSE"
  fi

  # now check ship all files
  if [[ $a == "y" ]]; then
    SHIP_ALL="TRUE"
  elif [[ $p == "y" ]]; then
    SHIP_ALL="FALSE"
  fi

  if [[ $l == "y" ]] && [[ $p == "y" ]]; then
    echo -e "${PURPLE}Listing changed files (build.env .gitignore apex db reports rest .hooks)${NC}"

    git --no-pager diff -r --compact-summary --dirstat --stat-width=120 --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB  -- build.env .gitignore apex db reports rest .hooks
    exit 0
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

  # at INIT there is no pretreatment or an evaluation of the table_ddl
  if [[ "${mode}" == "init" ]]; then
    array=( .hooks/pre sequences tables indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies sources/types sources/packages sources/functions sources/procedures views mviews sources/triggers jobs tests/packages ddl/init dml/init dml/base .hooks/post)
  else
    # building pre and post based on branches
    pres=( .hooks/pre ddl/patch/pre_${branch} dml/patch/pre_${branch} ddl/patch/pre dml/patch/pre )
    post=( ddl/patch/post_${branch} dml/patch/post_${branch} ddl/patch/post dml/base dml/patch/post .hooks/post )

    array=( ${pres[@]} )
    array+=( sequences tables tables/tables_ddl indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies sources/types sources/packages sources/functions sources/procedures views mviews sources/triggers jobs tests/packages )
    array+=( ${post[@]} )
  fi


  # if table changes are inside release, we have to call special-functionalities
  table_changes="FALSE"

  # folder outside git repo
  depotpath="$(pwd)/$DEPOT_PATH/$branch"
  targetpath=$depotpath/${mode}_${version}
  sourcepath="."

  # initialize logfile
  MDATE=`date "+%Y%m%d%H%M%S"`
  log_file="${MDATE}_bld_${mode}_${version}.log"

  touch $log_file
  full_log_file="$( cd "$( dirname "${log_file}" )" >/dev/null 2>&1 && pwd )/${log_file}"


  echo -e "Building ${BWHITE}${mode}${NC} deployment version: ${BWHITE}${version}${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "project:       ${BWHITE}${PROJECT}${NC}" | write_log
  echo -e "branch:        ${BWHITE}${branch}${NC}" | write_log
  if [[ $mode == "patch" ]];then
    display_from=`git rev-parse --short ${from_commit}`
    display_until=`git rev-parse --short ${until_commit}`
    echo -e "from:          ${BWHITE}${from_commit} (${display_from})${NC}" | write_log
    echo -e "until:         ${BWHITE}${until_commit} (${display_until})${NC}" | write_log
    echo -e "shipall:       ${BWHITE}${SHIP_ALL}${NC}" | write_log
  fi
  echo -e "keepfolder:    ${BWHITE}${KEEP_FOLDER}${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  if [[ ${PROJECT_MODE} != "FLEX" ]]; then
    echo -e "app_schema:    ${BWHITE}${APP_SCHEMA}${NC}" | write_log
    if [[ ${PROJECT_MODE} == "MULTI" ]]; then
      echo -e "data_schema:   ${BWHITE}${DATA_SCHEMA}${NC}" | write_log
      echo -e "logic_schema:  ${BWHITE}${LOGIC_SCHEMA}${NC}" | write_log
    fi
  fi
  echo -e "schemas:      (${BWHITE}${SCHEMAS[@]}${NC})" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "depotpath:     ${BWHITE}${depotpath}${NC}"  | write_log
  echo -e "targetpath:    ${BWHITE}${targetpath}${NC}" | write_log
  echo -e "sourcepath:    ${BWHITE}${sourcepath}${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "----------------------------------------------------------" | write_log
}

function copy_all_files() {
  echo "Copy all files ..." | write_log
  for folder in "${MAINFOLDERS[@]}"
  do
    if [[ -d ${folder} ]]; then
      cp -R ${folder} $targetpath
    fi
  done

  [ ! -f build.env ] || cp build.env $targetpath
  [ ! -f .gitignore ] || cp .gitignore $targetpath
}

function copy_files {
  echo " ==== Checking Files and Folders ====" | write_log
  [[ ! -d ${targetpath} ]] || rm -rf ${targetpath}
  echo " " | write_log
  # getting updated files, and
  # copy (and overwrite forcefully) in exact directory structure as in git repo
  if [[ "${mode}" == "init" ]]; then
    echo "Creating directory $targetpath" | write_log
    mkdir -p ${targetpath}

    copy_all_files
  else
    # Changes on configs?
    num_changes=`git diff -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB  -- build.env .gitignore | wc -l | xargs`
    if [[ $num_changes > 0 ]]; then
      if [ ! -d "${targetpath}" ]; then
        echo "Creating directory '${targetpath}'" | write_log
        mkdir -p "${targetpath}"
      fi

      if [[ $(uname) == "Darwin" ]]; then
        rsync -R `git diff -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB -- build.env .gitignore` ${targetpath}
      else
        cp --parents -Rf `git diff -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB -- build.env .gitignore` ${targetpath}
      fi
    fi

    # Patch
    for folder in "${MAINFOLDERS[@]}"
    do

      num_changes=`git diff -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB -- ${folder} | wc -l | xargs`

      if [[ $num_changes > 0 ]]; then

        if [ ! -d "${targetpath}" ]; then
          echo "Creating directory '${targetpath}'" | write_log
          mkdir -p "${targetpath}"
        fi

        echo "Copy files ..." | write_log
        if [[ $(uname) == "Darwin" ]]; then
          rsync -R `git diff -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB -- ${folder}` ${targetpath}
        else
          cp --parents -Rf `git diff -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB -- ${folder}` ${targetpath}
        fi
      else
        echo_warning "No changes in folder: ${folder}" | write_log
      fi

    done




    # additionaly we need all triggers belonging to views
    # loop through schemas
    for schema in "${SCHEMAS[@]}"
    do
      # any views?
      if [[ -d "$targetpath"/db/$schema/views ]]
      then
        # get view files
        for file in $(ls "$targetpath"/db/$schema/views | sort )
        do
          # check if there is any file like viewfile_*.sql
          myfile=${file//./"_*."}
          for f in ${sourcepath}/db/$schema/sources/triggers/${myfile}; do
            if [[ -e "$f" ]];
            then
                # yes, so copy it...
                if [[ $(uname) == "Darwin" ]]; then
                  rsync -R $f $targetpath
                else
                  cp --parents -Rf $f $targetpath
                fi

                echo "Additionaly add $f" | write_log
            fi
          done
        done
      fi
    done

    # additionaly we need all condtions beloning to REST
    if [[ -d "$targetpath"/rest ]]; then
      folders=()
      if [[ ${PROJECT_MODE} == "FLEX" ]]; then
        for d in $(find $targetpath/rest -maxdepth 1 -mindepth 1 -type d | sort -f)
        do
          folders+=( $(basename $d) )
        done
      else
        folders=( . )
      fi


      for fldr in "${folders[@]}"
      do
        path=modules

        if [[ -d "$targetpath"/rest/$fldr/$path ]]; then
          depth=1
          if [[ $path == "modules" ]]; then
            depth=2
          fi

          for file in $(find "$targetpath"/rest/$fldr/$path/ -maxdepth $depth -mindepth $depth -type f | sort )
          do

            base=$targetpath/rest/$fldr/
            part=${file#$base}

            if [[ "${part}" == *".sql" ]] && [[ "${part}" != *".condition.sql" ]]; then
              srcf=${sourcepath}/rest/$fldr/$part

              if [[ -f ${srcf/.sql/.condition.sql} ]]; then

                # yes, so copy it...
                if [[ $(uname) == "Darwin" ]]; then
                  rsync -R ${srcf/.sql/.condition.sql} $targetpath
                else
                  cp --parents -Rf ${srcf/.sql/.condition.sql} $targetpath
                fi
              fi

            fi
          done
        fi
      done

    fi


    ## and we need all hooks
    for schema in "${SCHEMAS[@]}"
    do
      # yes, so copy it...
      if [[ $(uname) == "Darwin" ]]; then
        rsync -R ${sourcepath}/db/$schema/.hooks $targetpath
      else
        if [[ -d ${sourcepath}/db/$schema/.hooks ]]; then
          cp --parents -Rf ${sourcepath}/db/$schema/.hooks $targetpath
        fi
      fi
    done


    if [[ $(uname) == "Darwin" ]]; then
      rsync -R ${sourcepath}/.hooks $targetpath
    else
      if [[ -d ${sourcepath}/.hooks ]]; then
        cp --parents -Rf ${sourcepath}/.hooks $targetpath
      fi
    fi
  fi

  echo " " | write_log
}

function list_files_to_remove() {
  # if patch mode we remove unnecessary files
  if [[ "${mode}" == "patch" ]]; then
    target_drop_file="$targetpath"/remove_files_$version.lst

    for folder in "${MAINFOLDERS[@]}"
    do

      # to avoid dead-files
      num_changes=`git diff -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=D -- ${folder} | wc -l | xargs`

      if [[ $num_changes > 0 ]]; then
        echo "removing dead-files" | write_log

        for line in `git diff -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=D -- ${folder}`
        do
          echo "${line}" >> $target_drop_file
        done
      else
        echo_warning "No deleted files in folder: ${folder}" | write_log
      fi
    done
  fi
}

function write_install_schemas(){
  if [[ -d "$targetpath"/db ]]; then
    echo " ==== Checking Schemas ${SCHEMAS[@]} ====" | write_log
    echo "" | write_log

    # loop through schemas
    for schema in "${SCHEMAS[@]}"
    do
      if [[ -d "$targetpath"/db/$schema ]]; then
        # file to write to
        target_install_base=${mode}_${schema}_${version}.sql
        target_install_file="$targetpath"/db/$schema/$target_install_base

        echo "" | write_log
        echo " ==== Schema: ${schema} - /db/$schema/$target_install_base ====" | write_log
        echo "" | write_log

        # write some infos
        echo "set define '^'" > "$target_install_file"
        echo "set concat on" >> "$target_install_file"
        echo "set concat ." >> "$target_install_file"
        echo "set verify off" >> "$target_install_file"
        echo "WHENEVER SQLERROR EXIT SQL.SQLCODE" >> "$target_install_file"

        echo "" >> "$target_install_file"

        echo "define VERSION = '^1'" >> "$target_install_file"
        echo "define MODE = '^2'" >> "$target_install_file"

        echo "set timing on" >> "$target_install_file"
        echo "set trim off" >> "$target_install_file"
        echo "set linesize 2000" >> "$target_install_file"
        echo "set sqlblanklines on" >> "$target_install_file"
        echo "set tab off" >> "$target_install_file"
        echo "set pagesize 9999" >> "$target_install_file"
        echo "set trimspool off" >> "$target_install_file"
        echo "" >> "$target_install_file"

        echo "Prompt .............................................................................. " >> "$target_install_file"
        echo "Prompt .............................................................................. " >> "$target_install_file"
        echo "Prompt .. Start Installation for schema: $schema " >> "$target_install_file"
        echo "Prompt ..                       Version: $mode $version " >> "$target_install_file"
        echo "Prompt .............................................................................. " >> "$target_install_file"
        # echo "set scan off" >> "$target_install_file"
        # echo "set define off" >> "$target_install_file"
        echo "set serveroutput on" >> "$target_install_file"
        echo "" >> "$target_install_file"

        if [[ "${mode}" == "patch" ]]; then
          echo "Prompt .. Commit-History to install: " >> "$target_install_file"
          git log --pretty=format:'Prompt ..   %h %s <%an>' ${from_commit}...${until_commit} -- db/$schema >> "$target_install_file"
          echo " " >> "$target_install_file"
          echo "Prompt .. " >> "$target_install_file"
        # echo "Prompt " >> "$target_install_file"
          echo "Prompt .............................................................................. " >> "$target_install_file"

          echo "Prompt " >> "$target_install_file"
          echo "Prompt " >> "$target_install_file"
        fi


        # check every path in given order
        for path in "${array[@]}"
        do
          if [[ -d "$targetpath"/db/$schema/$path ]]; then
            echo "Writing calls for $path" | write_log
            echo "Prompt Installing $path ..." >> "$target_install_file"

            # pre hook
            if [[ -d "${targetpath}/db/${schema}/.hooks/pre/${path}" ]]; then
              for file in $(ls "${targetpath}/db/${schema}/.hooks/pre/${path}" | sort )
              do
                if [[ -f "${targetpath}/db/${schema}/.hooks/pre/${path}/${file}" ]]; then
                  echo "Prompt >>> db/${schema}/.hooks/pre/${path}/${file}" >> "$target_install_file"
                  echo "@@.hooks/pre/${path}/$file" >> "$target_install_file"
                  echo "Prompt <<< db/${schema}/.hooks/pre/${path}/${file}" >> "$target_install_file"
                fi
              done
            fi

            echo "Prompt" >> "$target_install_file"

            if [[ "$path" == "ddl/patch/pre" ]] || [[ "$path" == "ddl/patch/pre_tst" ]] || [[ "$path" == "ddl/patch/pre_uat" ]] || [[ "$path" == "views" ]]; then
              echo "WHENEVER SQLERROR CONTINUE" >> "$target_install_file"
            fi

            # if packages then sort descending
            sortdirection=""
            if [[ "$path" == "sources/packages" ]] || [[ "$path" == "tests/packages" ]]; then
              sortdirection="-r"
            fi

            for file in $(ls "$targetpath"/db/$schema/$path | sort $sortdirection )
            do
              if [[ -f "${targetpath}/db/${schema}/${path}/${file}" ]]; then
                # if tables_ddl, this is only written in install if there is no
                # matching table in the branch
                if [[ "$path" == "tables" ]]; then
                  skipfile="FALSE"
                  table_changes="TRUE"

                  if [[ "${mode}" == "patch" ]]; then
                    if [[ -d "${targetpath}/db/$schema/tables/tables_ddl" ]]; then
                      for f in ${targetpath}/db/$schema/tables/tables_ddl/${file%%.*}.*; do
                        if [[ -e "$f" ]]; then
                          skipfile="TRUE"
                        fi
                      done
                    fi
                  fi

                  if [[ "$skipfile" == "TRUE" ]]; then
                    echo "Prompt ... skipped $file" >> "$target_install_file"
                  else
                    echo "Prompt >>> db/${schema}/${path}/${file}" >> "$target_install_file"
                    echo "@@$path/$file" >> "$target_install_file"
                    echo "Prompt <<< db/${schema}/${path}/${file}" >> "$target_install_file"
                  fi
                else
                  echo "Prompt >>> db/${schema}/${path}/${file}" >> "$target_install_file"
                  if [[ "$path" == "ddl/pre_tst" ]] && [[ "${mode}" == "patch" ]]; then
                    echo "--tst@@$path/$file" >> "$target_install_file"
                  elif [[ "$path" == "ddl/pre_uat" ]] && [[ "${mode}" == "patch" ]]; then
                    echo "--uat@@$path/$file" >> "$target_install_file"
                  else
                    echo "@@$path/$file" >> "$target_install_file"
                    if [[ "$path" != ".hooks/pre" ]] && [[ "$path" != ".hooks/post" ]]; then
                      echo "Prompt <<< db/${schema}/${path}/${file}" >> "$target_install_file"
                    fi
                  fi
                fi
              fi
            done

            if [[ "$path" == "ddl/patch/pre" ]] || [[ "$path" == "ddl/patch/pre_tst" ]] || [[ "$path" == "ddl/patch/pre_uat" ]]|| [[ "$path" == "views" ]]
            then
              echo "WHENEVER SQLERROR EXIT SQL.SQLCODE" >> "$target_install_file"
            fi



            # post hook
            echo "Prompt" >> "$target_install_file"
            if [[ -d "${targetpath}/db/${schema}/.hooks/post/${path}" ]]; then
              for file in $(ls "${targetpath}/db/${schema}/.hooks/post/${path}" | sort )
              do
                if [[ -f "${targetpath}/db/${schema}/.hooks/post/${path}/${file}" ]]; then
                  echo "Prompt >>> db/${schema}/.hooks/post/${path}/${file}" >> "$target_install_file"
                  echo "@@.hooks/post/${path}/$file" >> "$target_install_file"
                  echo "Prompt <<< db/${schema}/.hooks/post/${path}/${file}" >> "$target_install_file"
                fi
              done
            fi

            echo "Prompt" >> "$target_install_file"
            echo "Prompt" >> "$target_install_file"
            echo "" >> "$target_install_file"
          fi
        done #path

        echo "prompt compiling schema" >> "$target_install_file"
        echo "exec dbms_utility.compile_schema(schema => USER);" >> "$target_install_file"
        echo "exec dbms_session.reset_package" >> "$target_install_file"

        echo "Prompt" >> "$target_install_file"
        echo "Prompt" >> "$target_install_file"
        echo "exit" >> "$target_install_file"


      else
        echo "  .. db/$schema does not exists in $targetpath"
      fi
    done
  else
    echo " ... no db folder" | write_log
  fi
}

function write_install_apps() {
  # loop through applications
  if [[ -d "$targetpath"/apex ]]; then
    echo "" | write_log
    echo " ==== Checking APEX Applications ====" | write_log
    echo "" | write_log

    # file to write to
    target_apex_file="$targetpath"/apex_files_$version.lst
    [ -f $target_apex_file ] && rm $target_apex_file

    depth=1
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      depth=3
    fi

    for d in $(find apex -maxdepth ${depth} -mindepth ${depth} -type d)
    do
      echo "${d}" >> $target_apex_file
      echo "Writing call to install APP: ${d} " | write_log
    done
  fi
}

function write_install_rest() {
  # check rest
  if [[ -d "$targetpath"/rest ]]; then
    echo "" | write_log
    echo " ==== Checking REST Modules ====" | write_log
    echo "" | write_log

    folders=()
    if [[ ${PROJECT_MODE} == "FLEX" ]]; then
      for d in $(find rest -maxdepth 1 -mindepth 1 -type d | sort -f)
      do
        folders+=( $(basename $d) )
      done
    else
      folders=( . )
    fi

    for fldr in "${folders[@]}"
    do
      echo " == Schema: $fldr" | write_log

      # file to write to
      target_install_base=rest_${mode}_${version}.sql
      target_install_file="$targetpath"/rest/$fldr/$target_install_base
      [ -f $target_install_file ] && rm $target_install_file
      rest_to_install="FALSE"

      # write some infos
      echo "Prompt .............................................................................. " >> "$target_install_file"
      echo "Prompt .............................................................................. " >> "$target_install_file"
      echo "Prompt .. Start REST installation " >> "$target_install_file"
      echo "Prompt .. Version: $mode $version " >> "$target_install_file"
      echo "Prompt .. Folder:  $fldr " >> "$target_install_file"
      echo "Prompt .............................................................................. " >> "$target_install_file"
      echo "set serveroutput on" >> "$target_install_file"
      echo "" >> "$target_install_file"

      # check every path in given order
      for path in "${rest_array[@]}"
      do
        if [[ -d "$targetpath"/rest/$fldr/$path ]]; then
          depth=1
          if [[ $path == "modules" ]]; then
            depth=2
          fi

          for file in $(find "$targetpath"/rest/$fldr/$path/ -maxdepth $depth -mindepth $depth -type f | sort )
          do
            rest_to_install="TRUE"
            base=$targetpath/rest/$fldr/
            part=${file#$base}

            echo "Writing call to install RESTModul: ${part} " | write_log

            if [[ "${part}" == *".sql" ]] && [[ "${part}" != *".condition.sql" ]]; then
              echo "Prompt ... $part" >> "$target_install_file"

              if [[ -f ${file/.sql/.condition.sql} ]]; then
                echo "begin" >> "$target_install_file"
                echo "  if" >> "$target_install_file"
                echo "  @@${part/.sql/.condition.sql}" >> "$target_install_file"
                echo "  then" >> "$target_install_file"
                echo "    @@${part}" >> "$target_install_file"
                echo "  else" >> "$target_install_file"
                echo "    dbms_output.put_line('!!! ${part} not installed cause condition did not match');" >> "$target_install_file"
                echo "  end if;" >> "$target_install_file"
                echo "end;" >> "$target_install_file"
              else
                echo "@@${part}" >> "$target_install_file"
              fi
              echo "/" >> "$target_install_file"
            fi
          done

          echo "Prompt" >> "$target_install_file"
          echo "Prompt" >> "$target_install_file"
          echo "" >> "$target_install_file"

        fi
      done

      # nothing to install, just remove empty file
      if [[ ${rest_to_install} == "FALSE" ]]; then
        rm $target_install_file
        echo " ... nothing found " | write_log
      fi
    done
  fi
}

function write_changelog() {
  echo "" | write_log
  current_tag=
  previous_tag=
  . .dbFlow/genchlog.sh -e ${until_commit:-HEAD} -f "changelog_${mode}_${version}.md"

  echo "ChangeLog generated: ${current_tag} -- ${previous_tag}" | write_log
}


function copy_all_when_defined_on_patch() {
  if [[ ${mode} == "patch" ]] && [[ ${SHIP_ALL} == "TRUE" ]]; then
    copy_all_files
  fi
}

function manage_artifact () {
  # Output files to logfile
  find $targetpath | sed -e 's/[^-][^\/]*\//--/g;s/--/ |-/' >> ${full_log_file}

  echo "" | write_log
  echo_success "==== .......... .......... .......... ==== " | write_log
  echo "All files are placed in $DEPOT_PATH/$branch" | write_log
  echo_success "==== ..........    DONE    .......... ==== " | write_log

  # remove colorcodes from logfile
  cat ${full_log_file} | sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" > ${full_log_file}.colorless
  rm ${full_log_file}
  mv ${full_log_file}.colorless ${full_log_file}

  # create artifact
  if [[ -d $targetpath ]]; then

    mv ${full_log_file} $targetpath/
    [[ -f changelog_${mode}_${version}.md ]] && mv changelog_${mode}_${version}.md $targetpath/

    # pack directoy
    tar -C $targetpath -czf $targetpath.tar.gz .

    if [[ ${KEEP_FOLDER} != "TRUE" ]]; then
      rm -rf $targetpath
    fi
  else
    echo_error "Nothing to release, aborting"
    exit 1
  fi
}

function make_a_new_version() {
  # Merge pushen
  git push

  # Tag erstellen und pushen
  git tag -a V$version -m "neue Version V$version angelegt"
  git push origin V$version

}

function check_push_to_depot() {
  local force_push=${1:-"FALSE"}
  local current_path=$(pwd)

  if [[ $branch != "master" ]] && [[ $version != "install" ]]; then
    cd $depotpath

    if [[ -d ".git" ]]; then
      if [[ "$force_push" == "FALSE" ]]; then
        echo
        echo "Do you wish to push changes to depot remote?"
        echo "  Y - $targetpath.tar.gz will be commited and pushed"
        echo "  N - Nothing will happen..."

        read modus

        shopt -s nocasematch
        case "$modus" in
          "Y" )
            force_push="TRUE"
            ;;
          *)
            echo "no push to depot"
            ;;
        esac
      fi

      if [[ "$force_push" == "TRUE" ]]; then
        git pull
        git add $targetpath.tar.gz
        git commit -m "Adds $targetpath.tar.gz"
        git push
      fi

    fi # git path

    cd $current_path
  fi
}


function check_make_new_version() {
  # on branch master ask if we should tag current version and conmmit
  if [[ $branch == "master" ]] && [[ $version != "install" ]]; then
    echo
    echo "Do you wish to commit, tag and push the new version to origin"
    echo "  Y - current version will be commited, tagged and pushed"
    echo "  N - Nothing will happen, all generated files won't be touched"

    read modus

    shopt -s nocasematch
    case "$modus" in
      "Y" )
        make_a_new_version
        check_push_to_depot
        ;;
      *)
        echo "Nothing has happened"
        ;;
    esac
  fi
}


function call_apply_on_install() {
  if [[ $version == "install" ]]; then
    echo "calling apply"

    .dbFlow/apply.sh --${mode} --version ${version}
  else
    echo -e "${LWHITE}just call ${NC}${BWHITE}.dbFlow/apply.sh --${mode} --version ${version}${NC} ${LWHITE}inside your instance folder${NC}"
  fi
}

# validate and check existence of vars defined in build.env
check_vars

# validate params this script was called with
check_params "$@"

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

# if all files should be included
copy_all_when_defined_on_patch

# zip files and clear logs
manage_artifact

# ask if artifact should be pushed
check_push_to_depot

# ask if this version should be there as tag too
check_make_new_version

# if you name vour version install, then just do it
call_apply_on_install