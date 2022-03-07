#!/bin/bash

# get required functions and vars
source ./.dbFlow/lib.sh

# set project-settings from build.env if exists
if [[ -e ./build.env ]]; then
  source ./build.env
fi


# Log Location on Server.
LOG_LOCATION=$(pwd)
LOG_FILENAME=release.log
rm -f $LOG_LOCATION/$LOG_FILENAME
echo "Log Location should be: [ $LOG_LOCATION/$LOG_FILENAME ]"
exec > >( tee >( sed 's/\x1B\[[0-9;]*[JKmsu]//g' >> $LOG_LOCATION/$LOG_FILENAME ) )

RLS_BUILDBRANCH=${BUILD_BRANCH:-build}

# get branch name
{ #try
  current_branch=$(git branch --show-current)
} || { # catch
  current_branch="develop"
}

exec 2>&1
notify() {
    [[ $1 = 0 ]] || echo ❌ EXIT $1
    # you can notify some external services here,
    # ie. Slack webhook, Github commit/PR etc.
}


function check_vars() {
  # check require vars from build.env
  do_exit="NO"


  if [[ -z ${BRANCHES} ]]; then
    echo_error "undefined var: BRANCHES"
    do_exit="YES"
  fi

  ####
  if [[ ${do_exit} == "YES" ]]; then
    echo_warning "aborting"
    exit 1;
  fi
}

usage() {
  echo -e "${BWHITE}.dbFlow/release.sh${NC} - creates a release artifact for targetbranch and place it into depot"
  echo ""
  echo -e "This script will help you to create a release in no time. You only have to specify the target branch. "
  echo -e "The source branch will be the current one or the one you selected by option. "
  echo -e "If you specify the -b / --build flag, the target branch is cloned into it and the initial release "
  echo -e "of the predecessor, as well as the patch of the current and the initial of the current release are built."
  echo ""
  echo -e "${BWHITE}Usage:${NC}"
  echo -e "  $0 --source <branch> --target <branch> --version <label> [--build]"
  echo ""
  echo -e "${BWHITE}Options:${NC}"
  echo -e "  -h | --help             - Show this screen"
  echo -e "  -d | --debug            - Show additionaly output messages"
  echo -e "  -s | --source <branch>  - Optional Source branch (default current)to merge target branch into and determine the files to include in patch"
  echo -e "  -t | --target <branch>  - Required Target branch to reflect the predecessor of the source branch"
  echo -e "  -v | --version <label>  - Required label of version this artifact represents (optional when buildflag is submitted)"
  echo ""
  echo -e "  -b | --build            - Optional buildflag to create 3 artifact for using as nighlybuilds"
  echo -e "  -k | --keep             - Optional flag to keep folders in depot path (will be passed to build.sh)"
  echo ""
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  $0 --target release --version 1.2.3"
  echo -e "  $0 --source release --target test --version 1.2.3"
  echo -e "  $0 --source develop --target master -b"
  exit 1
}

log() {
  branch=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)
  echo -e "${YELLOW}OnBranch: ${NC}${PURPLE}$branch${NC} ${YELLOW}>>> ${NC}${BLUE}${1}${NC}"
}

build_release() {
  starting_branch=$(git branch --show-current)
  version_previous="0.0.0"
  version_next="${RLS_VERSION}"
  apply_tasks=()

  log "${BWHITE}Sourcebranch:   ${NC}${RLS_SOURCE_BRANCH}"
  log "${BWHITE}Targetbranch:   ${NC}${RLS_TARGET_BRANCH}"
  log "${BWHITE}Version:        ${NC}${RLS_VERSION}"
  log "${BWHITE}Buildtest:      ${NC}${RLS_BUILD}"

  if [[ ${RLS_BUILD} == 'Y' ]]; then
    log "${BWHITE}Buildbranch:    ${NC}${RLS_BUILDBRANCH}"
    version_next="0.0.1"
  fi

  # switch to source branch
  log "change to Branch: $RLS_SOURCE_BRANCH"
  git checkout $RLS_SOURCE_BRANCH
  { #try
    pulled=$(git pull)
  } || { # catch
    pulled="no"
  }
  log "Head is $(git rev-parse --short HEAD)"

  # switch to target branch
  log "change to Branch: $RLS_TARGET_BRANCH"
  git checkout $RLS_TARGET_BRANCH
  { #try
    pulled=$(git pull)
  } || { # catch
    pulled="no"
  }
  log "Head is $(git rev-parse --short HEAD)"

  if [[ ${RLS_BUILD} == 'Y' ]]; then
    # remove build branch
    if git show-ref --quiet refs/heads/$RLS_BUILDBRANCH; then
      log "Removing branch $RLS_BUILDBRANCH"
      git branch -D $RLS_BUILDBRANCH
    fi

    # create a new build branch out of target branch
    log "Checkout new Branch $RLS_BUILDBRANCH"
    git checkout -b $RLS_BUILDBRANCH

    # build initial patch
    log "building initial install $version_previous (previous version)"
    .dbFlow/build.sh -i -v $version_previous $keep
    apply_tasks+=( ".dbFlow/apply.sh -i -v $version_previous" )
  fi

  # following makes only sense when source not the same as target
  if [[ $RLS_SOURCE_BRANCH != $RLS_TARGET_BRANCH ]]; then
    # merging target with source
    log "merging changes from $RLS_SOURCE_BRANCH"
    git merge $RLS_SOURCE_BRANCH

    # build diff patch
    log "build patch upgrade $version_next (current version)"
    .dbFlow/build.sh -p -v $version_next $keep
    apply_tasks+=( ".dbFlow/apply.sh -p -v $version_next" )

    # when buildtest then test new initial patch
    if [[ ${RLS_BUILD} == 'Y' ]]; then
      # und den initial Build des aktuellen Stand
      log "building initial install $version_next (current version)"
      .dbFlow/build.sh -i -v $version_next $keep
      apply_tasks+=( ".dbFlow/apply.sh -i -v $version_next" )
    fi
  fi

  # some summarizings
  log "${GREEN}Done${NC}"

  log "${GREEN}go to your instance directory where you host $RLS_TARGET_BRANCH and apply the following commands/patches${NC}"
  for task in "${apply_tasks[@]}"
  do
    log "${GREEN}${task}${NC}"
  done

  git checkout ${starting_branch}


}



trap '(exit 130)' INT
trap '(exit 143)' TERM
trap 'rc=$?; notify $rc; exit $rc' EXIT




function check_params() {
  ! getopt --test > /dev/null
  if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
      echo_fatal 'I’m sorry, `getopt --test` failed in this environment.'
      exit 1
  fi

  OPTIONS=dhv:s:t:bk
  LONGOPTS=debug,help,version:,source:,target:,build,keep

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

  debug="n" help="n" version="-" source_branch="-" target_branch="-" build="n"
  d=$debug h=$help v=$version s=$source_branch t=$target_branch b=$build

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
          -v|--version)
              version="$2"
              shift 2
              ;;
          -s|--source)
              source_branch="$2"
              shift 2
              ;;
          -t|--target)
              target_branch="$2"
              shift 2
              ;;
          -b|--build)
              build=y
              shift
              ;;
          -k|--keep)
              keep="-k"
              shift
              ;;
          --)
              shift
              break
              ;;
          *)
              echo_fatal "Programming error: $1"
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

  # Rule 1: source_branch is current when not given...
  if [[ -z $source_branch ]] || [[ $source_branch == "-" ]]; then
    RLS_SOURCE_BRANCH=$current_branch
  else
    RLS_SOURCE_BRANCH=$source_branch
  fi

  # Rule 2: we always need a target
  if [[ -z $target_branch ]] || [[ $target_branch == "-" ]]; then
    echo_error "Missing target branch, use --target <target branchname>"
    usage
    exit 1
  else
    RLS_TARGET_BRANCH=$target_branch
  fi


    # Rule 3: When no build test, we need a version
  if [[ $build == "n" ]] && [[ $version == "-" ]]; then
    echo_error "Missing version, use --verion 1.2.3 or --build $build"
    usage
    exit 1
  fi
  RLS_VERSION=$version
  RLS_BUILD=${build^^}
}



check_params "$@"

build_release