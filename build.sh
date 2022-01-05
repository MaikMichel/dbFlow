#!/bin/bash
# echo "Your script args ($#) are: $@"

usage() {
  echo -e "${BYELLOW}build [dbFlow]${NC} - build a patch with eiter all or only with changed files"
  echo -e "-----------------------------------------------------------------------------"
  echo -e "  If mode is init a build file from the current directory is build and placed "
  echo -e "  inside the depot directory. If mode is patch then only the files which differ"
  echo -e "  to the HEAD are taken into the build"
  echo
  echo -e "${BWHITE}USAGE${NC}"
  echo -e "\t$0 <MODE>"
  echo
  echo -e "${BWHITE}MODE${NC}"
  echo -e "\tinit <version>           creates an inital build from current project "
  echo -e "\t                         ${PURPLE}all objects in target-schemas will be dropped before install${NC}"
  echo -e "\t     <version>           label of new version the build is named"
  echo -e "\t                         if version is \"install\" apply script will be called directy after build is finished"
  echo
  echo -e "\tpatch <from> <version>   creates an patch build from git diff by tag/commit with current index"
  echo -e "\t      <from>             tag or commit hash or any other Git hash ex. ORIG_HEAD"
  echo -e "\t      <version>          label of new version the build is named"
  echo -e "\t                         if current branch is \"master\" you a tag is created"
  echo
  echo

  echo -e "${BWHITE}EXAMPLE${NC}"
  echo -e "  $0 init 1.0.0"
  echo -e "  $0 init install"
  echo -e "  $0 patch 1.0.0 1.0.1"
  echo -e "  $0 patch ORIG_HEAD 1.0.1"
  echo
  echo
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

  if [[ -z ${APP_SCHEMA:-} ]]; then
    echo_error "undefined var: APP_SCHEMA"
    do_exit="YES"
  fi
  if [[ -z ${DATA_SCHEMA:-} ]]; then
    echo_error "undefined var: DATA_SCHEMA"
    do_exit="YES"
  fi
  if [[ -z ${LOGIC_SCHEMA:-} ]]; then
    echo_error "undefined var: LOGIC_SCHEMA"
    do_exit="YES"
  fi

  if [[ -z ${WORKSPACE:-} ]]; then
    echo_error "undefined var: WORKSPACE"
    do_exit="YES"
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
      echo 'I’m sorry, `getopt --test` failed in this environment.'
      exit 1
  fi

  OPTIONS=dipv:s:e:
  LONGOPTS=debug,init,patch,version:,startcommit:,endcommit:

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

  debug="n" init="n" patch="n" version="-" startcommit=HEAD endcommit=ORIG_HEAD

  # now enjoy the options in order and nicely split until we see --
  while true; do
      case "$1" in
          -d|--debug)
              d=y
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
          -s|--startcommit)
              startcommit="$2"
              shift 2
              ;;
          -e|--endcommit)
              endcommit="$2"
              shift 2
              ;;
          --)
              shift
              break
              ;;
          *)
              echo "Programming error"
              exit 3
              ;;
      esac
  done

  # handle non-option arguments
  # if [[ $# -ne 1 ]]; then
  #     echo "$0: A single input file is required."
  #     exit 4
  # fi


  echo "debug: $d, init: $i, patch: $p, version: $version, startcommit: $startcommit, endcommit: $endcommit"

  # Rule 1: init or patch
  if [[ -z $i ]] && [[ -z $p ]]; then
    echo_error "Missing build mode, init or patch using flags -i or -p"
    usage
  fi

  if [[ $i == "y" ]] && [[ $p == "y" ]]; then
    echo_error "Build mode can only be init or patch, not both"
    usage
  fi

  # Rule 2: we always need a version
  if [[ -z $version ]] || [[ $version == "-" ]]; then
    echo_error "Missing version"
    usage
  fi

  # now check dependent params
  if [[ $i == "y" ]]; then
    mode="init"
  elif [[ $p == "y" ]]; then
    mode="patch"
  fi

    # Rule 3: When patch, we need git tags or hashes to build the diff
  if [[ $mode == "patch" ]]; then
    if git cat-file -e $startcommit 2> /dev/null; then
      a="a"
    else
      echo_error "Start Commit or Tag $startcommit not found"
      exit 1
    fi

    if git cat-file -e $endcommit 2> /dev/null; then
      a="a"
    else
      echo_error "End Commit or Tag $endcommit not found"
      exit 1
    fi
  fi
}

function setup_env() {
  MAINFOLDERS=( apex db reports rest .hooks )

  ALL_SCHEMAS=( ${DATA_SCHEMA} ${LOGIC_SCHEMA} ${APP_SCHEMA} )
  SCHEMAS=($(printf "%s\n" "${ALL_SCHEMAS[@]}" | sort -u))

  # if length is equal than ALL_SCHEMAS, otherwise distinct
  if [[ ${#SCHEMAS[@]} == ${#ALL_SCHEMAS[@]} ]]; then
    SCHEMAS=(${ALL_SCHEMAS[@]})
  fi

  # folders for REST
  rest_array=( access modules )

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
    pres=( .hooks/pre ddl/pre_${branch} dml/pre_${branch} ddl/pre dml/pre )
    post=( ddl/post_${branch} dml/post_${branch} ddl/post dml/base dml/post .hooks/post )

    array=${pres[@]}
    array+=( sequences tables tables_ddl indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies sources/types sources/packages sources/functions sources/procedures views mviews sources/triggers jobs tests/packages )
    array+=( ${post[@]} )
  fi


  # if table changes are inside release, we have to call special-functionalities
  table_changes="FALSE"

  # define diff indexes
  from_commit=${from:-""} #ORIG_HEAD #61485daabff5f71fb0334b64dc54e65dd0cae9c9
  until_commit=HEAD

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
  echo -e "----------------------------------------------------------" | write_log
  echo -e "app_schema:    ${BWHITE}${APP_SCHEMA}${NC}" | write_log
  echo -e "data_schema:   ${BWHITE}${DATA_SCHEMA}${NC}" | write_log
  echo -e "logic_schema:  ${BWHITE}${LOGIC_SCHEMA}${NC}" | write_log
  echo -e "schemas:      (${BWHITE}${SCHEMAS[@]}${NC})" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "depotpath:     ${BWHITE}${depotpath}${NC}"  | write_log
  echo -e "targetpath:    ${BWHITE}${targetpath}${NC}" | write_log
  echo -e "sourcepath:    ${BWHITE}${sourcepath}${NC}" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "----------------------------------------------------------" | write_log
  echo -e "----------------------------------------------------------" | write_log
}

function copy_files {
  # getting updated files, and
  # copy (and overwrite forcefully) in exact directory structure as in git repo
  if [[ "${mode}" == "init" ]]; then
    echo "Creating directory $targetpath" | write_log
    mkdir -p $targetpath

    echo "Copy files ..." | write_log
    for folder in "${MAINFOLDERS[@]}"
    do
      if [[ -d ${folder} ]]; then
        cp -R ${folder} $targetpath
      fi
    done

    [ ! -f build.env ] || cp build.env $targetpath
    [ ! -f .gitignore ] || cp .gitignore $targetpath
  else

    for folder in "${MAINFOLDERS[@]}"
    do

      num_changes=`git diff -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB -- ${folder} | wc -l | xargs`

      if [[ $num_changes > 0 ]]; then

        echo "Creating directory $targetpath" | write_log
        mkdir -p $targetpath

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
        echo "echo removing dead-files" | write_log

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
      #echo "set sqlblanklines on" >> "$target_install_file"
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

          if [[ "$path" == "ddl/pre" ]] || [[ "$path" == "ddl/pre_tst" ]] || [[ "$path" == "ddl/pre_uat" ]] || [[ "$path" == "views" ]]; then
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
                  if [[ -d "${targetpath}/db/$schema/tables_ddl" ]]; then
                    for f in ${targetpath}/db/$schema/tables_ddl/${file%%.*}.*; do
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

          if [[ "$path" == "ddl/pre" ]] || [[ "$path" == "ddl/pre_tst" ]] || [[ "$path" == "ddl/pre_uat" ]]|| [[ "$path" == "views" ]]
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

    fi
  done
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

    for appid in apex/*/ ; do
      if [[ -d "$appid" ]]; then
        echo "${appid%/}" >> $target_apex_file
        echo "Writing call to install APP: ${appid%/} " | write_log
      fi
    done
  fi
}

function write_install_rest() {
  # check rest
  if [[ -d "$targetpath"/rest ]]; then
    echo "" | write_log
    echo " ==== Checking REST Modules ====" | write_log
    echo "" | write_log

    # file to write to
    target_install_base=rest_${mode}_${version}.sql
    target_install_file="$targetpath"/rest/$target_install_base
    [ -f $target_install_file ] && rm $target_install_file
    rest_to_install="FALSE"

    # write some infos
      echo "Prompt .............................................................................. " >> "$target_install_file"
      echo "Prompt .............................................................................. " >> "$target_install_file"
      echo "Prompt .. Start REST installation " >> "$target_install_file"
      echo "Prompt .. Version: $mode $version " >> "$target_install_file"
      echo "Prompt .............................................................................. " >> "$target_install_file"
      # echo "set scan off" >> "$target_install_file"
      # echo "set define off" >> "$target_install_file"
      echo "set serveroutput on" >> "$target_install_file"
      echo "" >> "$target_install_file"


    # check every path in given order
    for path in "${rest_array[@]}"
    do
      if [[ -d "$targetpath"/rest/$path ]]; then
        for directory in $(ls -d -- "$targetpath"/rest/$path/*/ 2> /dev/null | sort )
        do
          rest_to_install="TRUE"
          dir="$path/"$(basename $directory)
          echo "Writing call to install to install $dir" | write_log
          echo "Prompt Installing $dir ..." >> "$target_install_file"

          for file in $(ls "$directory" | sort )
          do

            if [[ "${file}" == *".sql" ]] && [[ "${file}" != *".condition.sql" ]]; then

              echo "Prompt ... $file" >> "$target_install_file"

              if [[ -f $directory${file/.sql/.condition.sql} ]]; then
                echo "begin" >> "$target_install_file"
                echo "  if" >> "$target_install_file"
                echo "  @@$dir/${file/.sql/.condition.sql}" >> "$target_install_file"
                echo "  then" >> "$target_install_file"
                echo "    @@$dir/$file" >> "$target_install_file"
                echo "  else" >> "$target_install_file"
                echo "    dbms_output.put_line('!!! ${file} not installed cause condition did not match');" >> "$target_install_file"
                echo "  end if;" >> "$target_install_file"
                echo "end;" >> "$target_install_file"
              else
                echo "@@$dir/$file" >> "$target_install_file"
              fi
              echo "/" >> "$target_install_file"
            fi
          done
        done

        echo "Prompt" >> "$target_install_file"
        echo "Prompt" >> "$target_install_file"
        echo "" >> "$target_install_file"

      fi
    done

    # nothing to install, just remove empty file
    if [[ ${rest_to_install} == "FALSE" ]]; then
      rm $target_install_file
    fi
  fi
}


function manage_artifact () {
  # Output files to logfile
  find $targetpath | sed -e 's/[^-][^\/]*\//--/g;s/--/ |-/' >> ${full_log_file}

  echo "" | write_log
  echo_success "==== .......... .......... .......... ==== " | write_log
  echo "All files are placed in $depotpath" | write_log
  echo_success "==== ..........    DONE    .......... ==== " | write_log

  # remove colorcodes from logfile
  cat ${full_log_file} | sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" > ${full_log_file}.colorless
  rm ${full_log_file}
  mv ${full_log_file}.colorless ${full_log_file}

  # create artifact
  if [[ -d $targetpath ]]; then
    # pack directoy
    mv ${full_log_file} $targetpath/
    tar -C $targetpath -czf $targetpath.tar.gz .
    rm -rf $targetpath
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
  if [[ $branch == "master" ]]; then
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

    .dbFlow/apply.sh ${mode} ${version}
  else
    echo -e "just call ${BWHITE}.dbFlow/apply.sh ${mode} ${version}${NC} inside your instance folder"
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

# zip files and clear logs
manage_artifact

# ask if artifact should be pushed
check_push_to_depot

# ask if this version should be there as tag too
check_make_new_version

# if you name vour version install, then just do it
call_apply_on_install