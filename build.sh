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
if [ -e ./build.env ]
then
  source ./build.env
fi
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

if [ -z ${SCHEMAS:-} ]
then
  if [ -z ${SCHEMASDELIMITED:-} ]
  then
    echo_error "undefined var: SCHEMAS"
    usage
  else
    SCHEMAS=(`echo ${SCHEMASDELIMITED} | sed 's/,/\n/g'`)
  fi
fi

if [[ -z ${BRANCHES:-} ]]; then
  echo_error "undefined var: BRANCHES"
  do_exit="YES"
fi

####
if [[ ${do_exit} == "YES" ]]; then
  echo_warning "aborting"
  exit 1;
fi


# set target-env settings from file if exists
if [ -e ./apply.env ]
then
  source ./apply.env
fi

# check require vars from apply.env
do_exit="NO"
if [[ -z ${DEPOT_PATH+x} ]]; then
  echo_error "undefined var: DEPOT_PATH"
  do_exit="YES"
fi


####
if [[ ${do_exit} == "YES" ]]; then
  echo_warning "aborting"
  exit 1;
fi


# validate parameters
mode=${1:-""}

if [ "${mode}" == "patch" ]; then
  # all params are required
  if [ $# -ne 3 ]; then
    echo_error "missing parameter <from> and <version>"
    usage
  fi
  from=$2
  version=$3
else
  if [ "${mode}" == "init" ]; then
    if [ $# -ne 2 ]; then
      echo_error "missing parameter <version>"
      usage
    fi
    version=$2
  else
    echo_error "unkown mode ${mode}"
    usage
  fi
fi

# TODO: Hier kommt es zu einem Fehler, wenn nichts im HEAD
# get branch name
branch=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)

# do we know the branch???
if [[ ! " ${BRANCHES[@]} " =~ " ${branch} " ]]; then
    echo_error "unknown branch $branch - add it to build.env"
    exit 1
fi

# at INIT there is no pretreatment or an evaluation of the table_ddl
if [ "${mode}" == "init" ]; then
  array=( sequences tables indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies types sources/packages sources/functions sources/procedures views sources/triggers jobs tests/packages ddl/base ddl/init dml/base dml/init)
else
  # building pre and post based on branches
  pres=()
  for i in ${!BRANCHES[@]}; do
    if [ $i -gt 0 ]
    then
      pres+=( ddl/pre_${BRANCHES[$i]} )
      pres+=( dml/pre_${BRANCHES[$i]} )
    fi
  done
  pres+=( ddl/pre )
  pres+=( dml/pre )

  post=( ddl/base dml/base ddl/post dml/post  )
  for i in ${!BRANCHES[@]}; do
    if [ $i -gt 0 ]
    then
      post+=( ddl/post_${BRANCHES[$i]} )
      post+=( dml/post_${BRANCHES[$i]} )
    fi
  done

  array=${pres[@]}
  array+=( sequences tables tables_ddl indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies types sources/packages sources/functions sources/procedures views sources/triggers jobs tests/packages )
  array+=( ${post[@]} )
fi

# if table changes are inside release, we have to call special-functionalities
table_changes="FALSE"

# define diff indexes
from_commit=${from:-""} #ORIG_HEAD #61485daabff5f71fb0334b64dc54e65dd0cae9c9
until_commit=HEAD

# create a folder outside the git repo
depotpath="$(pwd)/$DEPOT_PATH/$branch"
targetpath=$depotpath/${mode}_${version}
sourcepath="."

echo -e "Building ${BWHITE}${mode}${NC} deployment version: ${BWHITE}${version}${NC}"
echo -e "----------------------------------------"
echo -e "project:       ${BWHITE}${PROJECT}${NC}"
echo -e "branch:        ${BWHITE}${branch}${NC}"
echo
echo -e "app_schema:    ${BWHITE}${APP_SCHEMA}${NC}"
echo -e "data_schema:   ${BWHITE}${DATA_SCHEMA}${NC}"
echo -e "logic_schema:  ${BWHITE}${LOGIC_SCHEMA}${NC}"
echo -e "schemas:      (${BWHITE}${SCHEMAS[@]}${NC})"
echo
echo -e "depotpath:     ${BWHITE}${depotpath}${NC}"
echo -e "targetpath:    ${BWHITE}${targetpath}${NC}"
echo -e "sourcepath:    ${BWHITE}${sourcepath}${NC}"
echo -e "----------------------------------------"


echo "Creating directory $targetpath"
mkdir -p $targetpath

# getting updated files, and
# copy (and overwrite forcefully) in exact directory structure as in git repo
echo "Copy files ..."
if [ "${mode}" == "init" ]; then
 cp -R .dbFlow $targetpath
 cp -R db $targetpath
 cp -R apex $targetpath
 cp -R rest $targetpath
 [ ! -f build.env ] || cp build.env $targetpath
 [ ! -f .gitignore ] || cp .gitignore $targetpath
else

  if [ $(uname) == "Darwin" ]; then
    rsync -R $(git diff-tree -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB) ${targetpath}
  else
    cp --parents -rf $(git diff-tree -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB) ${targetpath}
  fi

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
          if [ -e "$f" ];
          then
              # yes, so copy it...
              if [ $(uname) == "Darwin" ]; then
                rsync -R $f $targetpath
              else
                yes | cp --parents -rf $f $targetpath
              fi

              echo "Additionaly add $f"
          fi
        done
      done
    fi
  done
fi

# if patch mode we remove unnecessary files
if [ "${mode}" == "patch" ]; then
  target_drop_file="$targetpath"/remove_files_$version.lst

  # to avoid dead-files
  echo "@echo removing dead-files"
  for line in $(git diff-tree -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=D)
  do
    echo "${line}" >> $target_drop_file
  done
fi

# loop through schemas
for schema in "${SCHEMAS[@]}"
do
  if [[ -d "$targetpath"/db/$schema ]]
  then
    # file to write to
    target_install_base=${mode}_${schema}_${version}.sql
    target_install_file="$targetpath"/db/$schema/$target_install_base

    # write some infos
    echo "set define '^'" > "$target_install_file"
    echo "set concat on" >> "$target_install_file"
    echo "set concat ." >> "$target_install_file"
    echo "set verify off" >> "$target_install_file"
    echo "WHENEVER SQLERROR EXIT SQL.SQLCODE" >> "$target_install_file"

     # define spooling
    echo "" >> "$target_install_file"
    echo "define LOGFILE = '^1'" >> "$target_install_file"
    echo "define VERSION = '^2'" >> "$target_install_file"
    echo "set timing on" >> "$target_install_file"
    echo "set trim off" >> "$target_install_file"
    echo "set linesize 2000" >> "$target_install_file"
    #echo "set sqlblanklines on" >> "$target_install_file"
    echo "set tab off" >> "$target_install_file"
    echo "set pagesize 9999" >> "$target_install_file"
    echo "set trimspool off" >> "$target_install_file"
    echo "SPOOL ^LOGFILE append;" >> "$target_install_file"
    echo "" >> "$target_install_file"

    echo "Prompt .............................................................................. " >> "$target_install_file"
    echo "Prompt .............................................................................. " >> "$target_install_file"
    echo "Prompt .. Start Installation for schema: $schema " >> "$target_install_file"
    echo "Prompt ..                       Version: ^VERSION " >> "$target_install_file"
    echo "Prompt .............................................................................. " >> "$target_install_file"
    echo "set scan off" >> "$target_install_file"
    echo "set define off" >> "$target_install_file"
    echo "set serveroutput on" >> "$target_install_file"
    echo "" >> "$target_install_file"

    if [ "${mode}" == "patch" ]; then
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
      if [[ -d "$targetpath"/db/$schema/$path ]]
      then

        echo "Writing calls for $path"
        echo "Prompt Installing $path ..." >> "$target_install_file"

        if [ "$path" == "ddl/pre" ] || [ "$path" == "ddl/pre_tst" ] || [ "$path" == "ddl/pre_uat" ] || [ "$path" == "views" ]
        then
          echo "WHENEVER SQLERROR CONTINUE" >> "$target_install_file"
        fi

        # if packages then sort descending
        sortdirection=""
        if [ "$path" == "sources/packages" ] || [ "$path" == "tests/packages" ]
        then
          sortdirection="-r"
        fi

        for file in $(ls "$targetpath"/db/$schema/$path | sort $sortdirection )
        do
          # if tables_ddl, this is only written in install if there is no
          # matching table in the branch
          if [ "$path" == "tables" ]
          then
            skipfile="FALSE"
            table_changes="TRUE"

            if [ "${mode}" == "patch" ]; then
              if [ -d "${targetpath}/db/$schema/tables_ddl" ]
              then

                for f in ${targetpath}/db/$schema/tables_ddl/${file%%.*}.*; do
                  if [ -e "$f" ];
                  then
                      skipfile="TRUE"
                  fi
                done
              fi
            fi


            if [ "$skipfile" == "TRUE" ]
            then
              echo "Skipping $file"
              echo "Prompt ... skipped $file" >> "$target_install_file"
            else
              echo "Prompt ... $file" >> "$target_install_file"
              echo "@@$path/$file" >> "$target_install_file"
            fi
          else
            echo "Prompt ... $file" >> "$target_install_file"
            if [ "$path" == "ddl/pre_tst" ] && [ "${mode}" == "patch" ]
            then
              echo "--tst@@$path/$file" >> "$target_install_file"
            elif [ "$path" == "ddl/pre_uat" ] && [ "${mode}" == "patch" ]
            then
              echo "--uat@@$path/$file" >> "$target_install_file"
            else
              echo "@@$path/$file" >> "$target_install_file"
            fi
          fi
        done

        if [ "$path" == "ddl/pre" ] || [ "$path" == "ddl/pre_tst" ] || [ "$path" == "ddl/pre_uat" ] || [ "$path" == "views" ]
        then
          echo "WHENEVER SQLERROR EXIT SQL.SQLCODE" >> "$target_install_file"
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


# loop through applications
target_apex_file="$targetpath"/apex_files_$version.lst
[ -f $target_apex_file ] && rm $target_apex_file

for appid in apex/*/ ; do
  echo "${appid%/}" >> $target_apex_file
done

# pack directoy
tar -C $targetpath -czvf $targetpath.tar.gz .
rm -rf $targetpath


function make_a_new_version() {
  # Merge pushen
  git push

  # Tag erstellen und pushen
  git tag -a V$version -m "neue Version V$version angelegt"
  git push origin V$version

}

function push_to_depot() {
  local current_path=$(pwd)

  cd $depotpath
  git pull
  git add $targetpath.tar.gz
  git commit -m "Adds $targetpath.tar.gz"
  git push

  cd $current_path
}

if [ $branch != "master" ] && [ $version != "install" ]
then
  echo
  echo "Do you wish to push changes to depot remote?"
  echo "  Y - $targetpath.tar.gz will be commited and pushed"
  echo "  N - Nothing will happen..."

  read modus

  shopt -s nocasematch
  case "$modus" in
    "Y" )
      push_to_depot
      ;;
    *)
      echo "no push to depot"
      ;;
  esac
fi

# on branch master ask if we should tag current version and conmmit
if [ $branch == "masterX" ]
then
  echo
  echo "Do you wish to commit, tag and push the new version to origin"
  echo "  Y - current version will be commited, tagged and pushed"
  echo "  N - Nothing will happen, all generated files won't be touched"

  read modus

  shopt -s nocasematch
  case "$modus" in
    "Y" )
      make_a_new_version
      push_to_depot
      ;;
    *)
      echo "Nothing has happened"
      ;;
  esac
fi

echo "All files are placed in $depotpath"

if [ $version == "install" ]
then
  echo "calling apply"

  export SQLCL=sqlplus
  .dbFlow/apply.sh ${mode} ${version}
fi

echo "Done"
