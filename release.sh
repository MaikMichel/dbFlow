#!/usr/bin/env bash
# echo "Your script args ($#) are: $@"

# get required functions and vars
source ./.dbFlow/lib.sh

# set project-settings from build.env if exists
if [[ -e ./build.env ]]; then
  source ./build.env
fi

CUR_DIRECTORY=$(pwd)

# Log Location on Server.
LOG_LOCATION=${CUR_DIRECTORY}
LOG_FILENAME=release.log
rm -f "${LOG_LOCATION}/${LOG_FILENAME}"
exec > >( tee >( sed 's/\x1B\[[0-9;]*[JKmsu]//g' >> "${LOG_LOCATION}/${LOG_FILENAME}" ) )

RLS_BUILDBRANCH=${BUILD_BRANCH:-build}


# get branch name
{ #try
  current_branch=$(git branch --show-current)
} || { # catch
  current_branch="develop"
}

exec 2>&1
notify() {
    [[ ${1} = 0 ]] || echo ❌ EXIT "${1}"
    # you can notify some external services here,
    # ie. Slack webhook, Github commit/PR etc.
}


function check_vars() {
  # check require vars from build.env
  do_exit="NO"

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
  echo -e "  -g | --gate             - Optional Gate branch to free source branch. If this is set, then the source branch will be merged into that"
  echo -e "  -v | --version <label>  - Required label of version this artifact represents (optional when buildflag is submitted)"
  echo ""
  echo -e "  -b | --build            - Optional buildflag to create 3 artifact for using as nighlybuilds"
  echo -e "  -a | --apply <folder>   - Optional path to apply the build(s) when buildflag is set"
  echo -e "  -k | --keep             - Optional flag to keep folders in depot path (will be passed to build.sh)"
  echo ""
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  $0 --target release --version 1.2.3"
  echo -e "  $0 --source release --target test --version 1.2.3"
  echo -e "  $0 --source develop --target master -b"
  echo -e "  $0 --source develop --gate release --target test --version 2.0.3 --apply ../instances/test"
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
  log "${BWHITE}Gatebranch:     ${NC}${RLS_GATE_BRANCH}"
  log "${BWHITE}Targetbranch:   ${NC}${RLS_TARGET_BRANCH}"
  log "${BWHITE}Version:        ${NC}${RLS_VERSION}"
  log "${BWHITE}Buildtest:      ${NC}${RLS_BUILD}"

  if [[ ${RLS_BUILD} == 'Y' ]]; then
    log "${BWHITE}Buildbranch:    ${NC}${RLS_BUILDBRANCH}"
    version_next="0.0.1"
  fi

  # switch to source branch
  log "change to Branch: ${RLS_SOURCE_BRANCH}"
  git checkout "${RLS_SOURCE_BRANCH}"
  { #try
    pulled=$(git pull)
  } || { # catch
    pulled="no"
  }
  log "Head is $(git rev-parse --short HEAD)"

  # merge through gate
  if [[ ${RLS_GATE_BRANCH} != ${RLS_SOURCE_BRANCH} ]]; then
    log "change to Branch: ${RLS_GATE_BRANCH}"

    if git show-ref --quiet refs/heads/"${RLS_GATE_BRANCH}"; then
      # exists
      git checkout "${RLS_GATE_BRANCH}"

      { #try
        pulled=$(git pull)
      } || { # catch
        pulled="no"
      }

      log "merging changes from $RLS_SOURCE_BRANCH"
      git merge "${RLS_SOURCE_BRANCH}"
      git push
    else
      git checkout -b "${RLS_GATE_BRANCH}"
      git push --set-upstream origin release
    fi

  fi

  # switch to target branch
  log "change to Branch: ${RLS_TARGET_BRANCH}"
  git checkout "${RLS_TARGET_BRANCH}"
  { #try
    pulled=$(git pull)
  } || { # catch
    pulled="no"
  }
  log "Head is $(git rev-parse --short HEAD)"

  if [[ ${RLS_BUILD} == 'Y' ]]; then
    # remove build branch
    if git show-ref --quiet refs/heads/"${RLS_BUILDBRANCH}"; then
      log "Removing branch ${RLS_BUILDBRANCH}"
      git branch -D "${RLS_BUILDBRANCH}"
    fi

    # create a new build branch out of target branch
    log "Checkout new Branch ${RLS_BUILDBRANCH}"
    git checkout -b "${RLS_BUILDBRANCH}"

    # build initial patch
    log "building initial install ${version_previous} (previous version)"
    .dbFlow/build.sh -i -v "${version_previous}" "${keep}"
    apply_tasks+=( ".dbFlow/apply.sh -i -v ${version_previous}" )
  fi

  # following makes only sense when source not the same as target
  if [[ $RLS_GATE_BRANCH != "${RLS_TARGET_BRANCH}" ]]; then
    # merging target with source
    log "merging changes from $RLS_GATE_BRANCH"
    git merge "${RLS_GATE_BRANCH}"

    # build diff patch
    log "build patch upgrade ${version_next} (current version)"
    .dbFlow/build.sh -p -v "${version_next}" "${keep}"
    build_patch_worked=$?
    apply_tasks+=( ".dbFlow/apply.sh --patch --version ${version_next}" )

    # when buildtest then test new initial patch
    if [[ ${RLS_BUILD} == 'Y' ]]; then
      # und den initial Build des aktuellen Stand
      log "building initial install $version_next (current version)"
      .dbFlow/build.sh -i -v "${version_next}" "${keep}"
      apply_tasks+=( ".dbFlow/apply.sh --init --version ${version_next}" )
    else
      git push
      git tag "${version_next}"
      git push origin "${version_next}"
    fi
  fi

  # some summarizings
  log "${GREEN}Done${NC}"
  git checkout "${starting_branch}"

  log "${GREEN}go to your instance directory where you host $RLS_TARGET_BRANCH and apply the following commands/patches${NC}"

  if [[ ${RLS_TOFOLDER} != '-' ]]; then
    cd "${RLS_TOFOLDER}" || exit
    if [[ -d ".dbFlow" ]]; then
      cd ".dbFlow" || exit
      { #try
        sub_pulled=$(git pull)
      } || { # catch
        sub_pulled="no"
      }
      cd ..
    fi
  fi

  for task in "${apply_tasks[@]}"
  do
    echo -e "${GREEN}${task}${NC}"
    if [[ ${RLS_TOFOLDER} != '-' ]]; then
      ${task}

      # if is git and we are not on build then commit
      if [[ ${RLS_BUILD} != 'Y' ]] && [[ -d ".git" ]]; then
        git add --all
        git commit -m "${version_next}"
        git push
      fi
    fi
  done

  if [[ ${RLS_TOFOLDER} != '-' ]]; then
    cd "${CUR_DIRECTORY}" || exit
  fi

}



trap '(exit 130)' INT
trap '(exit 143)' TERM
trap 'rc=$?; notify $rc; exit $rc' EXIT




function check_params() {
  debug="n" help="n" version="-" source_branch="-" target_branch="-" build="n" apply_folder="-" gate_branch="-"
  d=$debug h=$help v=$version s=$source_branch t=$target_branch b=$build a=$apply_folder g=$gate_branch

  while getopts_long 'dhv:s:t:g:ba:k debug help version: source: target: gate: build apply: keep' OPTKEY "${@}"; do
      case ${OPTKEY} in
          'd'|'debug')
              d=y
              ;;
          'h'|'help')
              h=y
              ;;
          'v'|'version')
              version="${OPTARG}"
              ;;
          's'|'source')
              source_branch="${OPTARG}"
              ;;
          't'|'target')
              target_branch="${OPTARG}"
              ;;
          'g'|'gate')
              gate_branch="${OPTARG}"
              ;;
          'b'|'build')
              build=y
              ;;
          'a'|'apply')
              apply_folder="${OPTARG}"
              ;;
          'k'|'keep')
              keep="-k"
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
  else
    RLS_TARGET_BRANCH=$target_branch
  fi


    # Rule 3: When no build test, we need a version
  if [[ $build == "n" ]] && [[ $version == "-" ]]; then
    echo_error "Missing version, use --verion 1.2.3 or --build $build"
    usage
  fi
  RLS_VERSION=$version
  RLS_BUILD=${build^^}

  if [[ ${apply_folder} != '-' ]] && [[ ! -d ${apply_folder} ]]; then
    echo_error "Folder to apply to does not exist!"
    usage
  else
    RLS_TOFOLDER=${apply_folder}
  fi

  if [[ -z $gate_branch ]] || [[ $gate_branch == "-" ]]; then
    RLS_GATE_BRANCH=${RLS_SOURCE_BRANCH}
  else
    RLS_GATE_BRANCH=${gate_branch}
  fi
}



check_params "$@"

build_release