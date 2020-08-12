#!/bin/bash

mode=$1

function print_help() {
  echo "Please call script with following parameters"
  echo "  1 - mode: patch or init"
  echo "    init "
  echo "      2 - new version like >0.0.6<"
  echo "      2 - direkt full install with >install<"
  echo ""
  echo "    patch "
  echo "      2 - patch from version-num(tag or commit) e.g. 0.0.5 or ORIG_HEAD"
  echo "      3 - new version-num e.g. 0.0.6"

  echo ""
  echo "Example"
  echo "  init:  ./build.sh init 1.0.0"
  echo "  init:  ./build.sh init install"
  echo "  patch: ./build.sh patch 1.0.0 1.0.1"
  echo "  patch: ./build.sh patch ORIG_HEAD 1.0.1"
  echo ""
  echo ""
  exit 1
}

if [ "${mode}" == "patch" ]; then
  # all params are required
  if [ $# -ne 3 ]; then
    print_help
  fi
  from=$2
  version=$3
else
  if [ "${mode}" == "init" ]; then
    if [ $# -ne 2 ]; then
      print_help
    fi
    version=$2
  else
    print_help
  fi
fi

# read configuration
source build.env

# set target-env settings from file if exists
if [ -e apply.env ]
then
  source ./apply.env
fi

# get branch name
branch=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)

if [[ "$branch" =~ ^(develop|test|acceptance|master)$ ]]; then
    echo "$branch is known"
else
    echo "$branch is not in the list using develop"
    branch=develop
fi

# beim INIT gibts kein Vorbehandlung oder eine Auswertung des table_ddls
if [ "${mode}" == "init" ]; then
  array=( sequences tables indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies types sources/packages sources/functions sources/procedures views sources/triggers jobs tests/packages ddl/init dml/init )
else
  # pre and post stages build arrays
  # loop through schemas
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

  post=( dml/post ddl/post )
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

# if policies are inside release, we have to enable them
policies="FALSE"

# if table changes are inside release, we have to call api-functionalities
table_changes="FALSE"

# from_commit
from_commit=${from} #ORIG_HEAD #61485daabff5f71fb0334b64dc54e65dd0cae9c9
until_commit=HEAD #ba68fb4481f863b1096413c4489acbc2baa68e0a

# create a folder outside the git repo
# you can skip this step, if you want a static location
depotpath="$(pwd)/$DEPOT_PATH/$branch"
targetpath=$depotpath/${mode}_${version}
sourcepath="."

echo "building patch with listed configuration"
echo "----------------------------------------"
echo "project:       ${PROJECT}"
echo "branch:        ${branch}"
echo
echo "app_schema:    ${APP_SCHEMA}"
echo "data_schema:   ${DATA_SCHEMA}"
echo "logic_schema:  ${LOGIC_SCHEMA}"
echo "schemas:      (${SCHEMAS[@]})"
echo
echo "depotpath:     ${depotpath}"
echo "targetpath:    ${targetpath}"
echo "sourcepath:    ${sourcepath}"
echo "----------------------------------------"


echo "Creating directory $targetpath"
mkdir -p $targetpath

# getting updated files, and
# copy (and overwrite forcefully) in exact directory structure as in git repo
echo "Copy files ..."
if [ "${mode}" == "init" ]; then
 cp -R .bash4xcl $targetpath
 cp -R db $targetpath
 cp -R apex $targetpath
 cp build.sh $targetpath
 cp build.env $targetpath
 cp apply.sh $targetpath
 cp .gitignore $targetpath
else
  if [ $(uname) == "Darwin" ]; then
    rsync -R $(git diff-tree -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB) $targetpath
  else
    yes | cp --parents -rf $(git diff-tree -r --name-only --no-commit-id ${from_commit} ${until_commit} --diff-filter=ACMRTUXB) $targetpath
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
    echo "Prompt Start Installation for schema: $schema" >> "$target_install_file"
    echo "Prompt --------------------------------------" >> "$target_install_file"
    echo "" >> "$target_install_file"

    if [ "${mode}" == "patch" ]; then
      echo "Prompt Commit-History to install" >> "$target_install_file"
      echo "Prompt --------------------------------------" >> "$target_install_file"
      git log --pretty=format:'Prompt %h %s <%an>' ${from_commit}...${until_commit} -- db/$schema >> "$target_install_file"
      echo "" >> "$target_install_file"
      echo "" >> "$target_install_file"
    fi

    # define spooling
    echo "" >> "$target_install_file"
    echo "define LOGFILE = '^1'" >> "$target_install_file"
    echo "set timing on;" >> "$target_install_file"
    echo "SPOOL ^LOGFILE append;" >> "$target_install_file"
    echo "set scan off" >> "$target_install_file"
    echo "" >> "$target_install_file"

    # check every path in given order
    for path in "${array[@]}"
    do
      if [[ -d "$targetpath"/db/$schema/$path ]]
      then

        # policies are created as disabled. we will enable them at the end
        if [ "$path" == "policies" ]
        then
          policies="TRUE"
        fi

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
          # wenn tables_ddl, wird das nur in install geschrieben, wenn es keine
          # passende Tabelle im Branch gibt
          if [ "$path" == "tables" ]
          then
            skipfile="FALSE"
            table_changes="TRUE"

            if [ "${mode}" == "patch" ]; then
              if [ -d "${targetpath}/db/$schema/tables_ddl" ]
              then

                for f in ${targetpath}/db/$schema/tables_ddl/${file}*; do
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
    echo "exec dbms_utility.compile_schema(schema => user, compile_all => false);" >> "$target_install_file"
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

# Packen des Verzeichnisses
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
  local current_path=${pwd}

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
if [ $branch == "master" ]
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

  export SQLCL=sql
  ./apply.sh ${mode} ${version}
fi

echo "Done"
