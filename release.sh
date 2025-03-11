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

function retry() {
  local cnt=0;
  while [[ $cnt -lt 10 ]]; do
    if [[ -f ".git/index.lock" ]]; then
      echo -n ".";
      sleep 0.5;
      ((cnt++));
    else
      "$@"; # do the command params
      return; # quit the function
    fi
  done

  echo  ".git/index.lock exists and is locked!"
  exit 1;
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
  echo -e "                          - Set <label> to major, minor or patch and the next semantic version is calculated automatically"
  echo -e "                          - Set <label> to current to keep the latest semantic version"
  echo ""
  echo -e "  -b | --build            - Optional buildflag to create 3 artifact for using as nighlybuilds"
  echo -e "  -a | --apply <folder>   - Optional path to apply the build(s) when buildflag is set"
  echo -e "  -k | --keep             - Optional flag to keep folders in depot path (will be passed to build.sh)"
  echo -e "  -f | --forceddl         - Optional flag to switch off checking for new table-file through git itself."
  echo -e "                            This will run table_ddl scripts when matching table is present in patch mode"
  echo ""
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  $0 --target release --version 1.2.3"
  echo -e "  $0 --source release --target test --version 1.2.3"
  echo -e "  $0 --source develop --target master -b"
  echo -e "  $0 --source develop --gate release --target test --version 2.0.3 --apply ../instances/test"
  echo ""
  echo -e "${BWHITE}TIPP:${NC} You can activate autocompletion by calling: ${BORANGE}source .dbFlow/activate_autocomplete.sh${NC}"
  exit 1
}

log() {
  branch=$(git branch --show-current)
  echo -e "${YELLOW}OnBranch: ${NC}${PURPLE}$branch${NC} ${YELLOW}>>> ${NC}${BLUE}${1}${NC}"
}

get_next_version() {
  local inc_by_type="$1"
  local regexp='[^0-9]*\([0-9]*\)[.]\([0-9]*\)[.]\([0-9]*\)\([0-9A-Za-z-]*\)'

  if [ -z "$inc_by_type" ]; then
    inc_by_type="patch"
  fi

  local last_version=$(git describe --tags $(git rev-list --tags --max-count=1))

  local MAJOR=$(echo $last_version | sed -e "s#$regexp#\1#")
  local MINOR=$(echo $last_version | sed -e "s#$regexp#\2#")
  local PATCH=$(echo $last_version | sed -e "s#$regexp#\3#")

  case "$inc_by_type" in
    "major")
      ((MAJOR += 1))
      ((MINOR = 0))
      ((PATCH = 0))
      ;;
    "minor")
      ((MINOR += 1))
      ((PATCH = 0))
      ;;
    "patch")
      ((PATCH += 1))
      ;;
    "current")
      ((PATCH += 0))
      ;;
  esac

  local NEXT_VERSION="$MAJOR.$MINOR.$PATCH"
  echo "$NEXT_VERSION"
}

build_release() {
  starting_branch=$(git branch --show-current)
  version_previous="0.0.0"
  version_next="${RLS_VERSION}"
  apply_tasks=()

  if [[ ${RLS_INC_TYPE} != "-" ]]; then
    RLS_INC_TYPE=" - (${RLS_INC_TYPE})"
  else
    RLS_INC_TYPE=""
  fi

  log "${BWHITE}Sourcebranch:   ${NC}${RLS_SOURCE_BRANCH}"
  log "${BWHITE}Gatebranch:     ${NC}${RLS_GATE_BRANCH}"
  log "${BWHITE}Targetbranch:   ${NC}${RLS_TARGET_BRANCH}"
  log "${BWHITE}Version:        ${NC}${RLS_VERSION}${RLS_INC_TYPE}"
  log "${BWHITE}Buildtest:      ${NC}${RLS_BUILD}"
  log "${BWHITE}Force TableDDL: ${NC}${RLS_FORCE_DDL}"

  if [[ ${RLS_BUILD} == 'Y' ]]; then
    log "${BWHITE}Buildbranch:    ${NC}${RLS_BUILDBRANCH}"
    version_next="0.0.1"
  fi

  # switch to source branch
  log "change to Branch: ${RLS_SOURCE_BRANCH}"
  retry git checkout "${RLS_SOURCE_BRANCH}"
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
      retry git checkout "${RLS_GATE_BRANCH}"

      { #try
        pulled=$(git pull)
      } || { # catch
        pulled="no"
      }

      log "merging changes from $RLS_SOURCE_BRANCH with : --strategy-option theirs"
      retry git merge "${RLS_SOURCE_BRANCH}" --strategy-option theirs
      retry git push
    else
      retry git checkout -b "${RLS_GATE_BRANCH}"
      retry git push --set-upstream origin ${RLS_GATE_BRANCH}
    fi

  fi

  # switch to target branch
  log "change to Branch: ${RLS_TARGET_BRANCH}"
  retry git checkout "${RLS_TARGET_BRANCH}"
  { #try
    pulled=$(git pull)
  } || { # catch
    pulled="no"
  }
  log "Head is $(git rev-parse --short HEAD)"

  local flags=()
  if [[ ${RLS_FORCE_DDL} != "-" ]]; then
    flags+=("${RLS_FORCE_DDL}")
  fi

  if [[ ${keep} != "-" ]]; then
    flags+=("${keep}")
  fi

  if [[ ${RLS_BUILD} == 'Y' ]]; then
    # remove build branch
    if git show-ref --quiet refs/heads/"${RLS_BUILDBRANCH}"; then
      log "Removing branch ${RLS_BUILDBRANCH}"
      retry git branch -D "${RLS_BUILDBRANCH}"
    fi

    # create a new build branch out of target branch
    log "Checkout new Branch ${RLS_BUILDBRANCH}"
    retry git checkout -b "${RLS_BUILDBRANCH}"

    # build initial patch
    log "building initial install ${version_previous} (previous version)"
    .dbFlow/build.sh --init --version "${version_previous}" "${flags[@]}"
    apply_tasks+=( ".dbFlow/apply.sh --init --version ${version_previous}" )
  fi

  # following makes only sense when source not the same as target
  if [[ $RLS_GATE_BRANCH != "${RLS_TARGET_BRANCH}" ]]; then
    # merging target with source
    log "merging changes from $RLS_GATE_BRANCH with : --strategy-option theirs"
    retry git merge "${RLS_GATE_BRANCH}" --strategy-option theirs

    # build diff patch
    log "build patch upgrade ${version_next} (current version) ${flags[@]}"
    export DBFLOW_RELEASE_IS_RUNNUNG="YES"
    .dbFlow/build.sh --patch --version "${version_next}" "${flags[@]}"
    unset export DBFLOW_RELEASE_IS_RUNNUNG
    build_patch_worked=$?
    apply_tasks+=( ".dbFlow/apply.sh --patch --version ${version_next}" )

    # when buildtest then test new initial patch
    if [[ ${RLS_BUILD} == 'Y' ]]; then
      # und den initial Build des aktuellen Stand
      log "building initial install $version_next (current version)"
      .dbFlow/build.sh --init --version "${version_next}" "${flags[@]}"
      apply_tasks+=( ".dbFlow/apply.sh --init --version ${version_next}" )
    else
      retry git push

      if [[ ${RLS_REMOVE_TAG} == "true" ]]; then
        log "Removing tag ${version_next}"
        retry git tag -d "${version_next}"
        retry git push origin --delete "${version_next}"
        RLS_TAG_EXISTS="false"
      fi

      if [[ ${RLS_TAG_EXISTS} == "false" ]]; then
        log "creating tag ${version_next}"
        # create tag on target branch
        retry git tag "${version_next}"
        retry git push origin "${version_next}"
      fi
    fi
  fi

  local check_branch=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)
  if [[ $check_branch != "${starting_branch}" ]]; then
    retry git checkout "${starting_branch}"
  fi

  # some summarizings
  log "${GREEN}Done${NC}"
  log "${GREEN}go to your instance directory where you host $RLS_TARGET_BRANCH and apply the following commands/patches${NC}"

  if [[ ${RLS_TOFOLDER} != '-' ]]; then
    # current dbFlow branch?
    local dbFlow_branch=$(git -C ".dbFlow" rev-parse --abbrev-ref HEAD)

    cd "${RLS_TOFOLDER}" || exit

    if [[ -d ".dbFlow" ]]; then
     git -C ".dbFlow" checkout ${dbFlow_branch}
     git -C ".dbFlow" pull origin ${dbFlow_branch}
    fi
  fi

  for task in "${apply_tasks[@]}"
  do
    echo -e "${CYAN}call ${BWHITE}${task}${NC} ${CYAN}from your instance folder${NC}"
    if [[ ${RLS_TOFOLDER} != '-' ]]; then
      ${task}
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
  debug="n" help="n" version="-" source_branch="-" target_branch="-" build="n" apply_folder="-" gate_branch="-" forceddl="-" keep="-"
  d=$debug h=$help v=$version s=$source_branch t=$target_branch b=$build a=$apply_folder g=$gate_branch

  while getopts_long 'dhv:s:t:g:ba:kf debug help version: source: target: gate: build apply: keep forceddl' OPTKEY "${@}"; do
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
          'f'|'forceddl')
              forceddl="--forceddl"
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

  # Rule 2.1: target branch must exist
  if ! git rev-parse --verify "$RLS_TARGET_BRANCH" >/dev/null 2>&1; then
    echo_error "Target branch: ${RLS_TARGET_BRANCH} doesn't exist"
    exit 1
  fi

  # Rule 2.2: target branch must have an upstream
  if ! git rev-parse --abbrev-ref "$RLS_TARGET_BRANCH"@{upstream} >/dev/null 2>&1; then
    echo_error "Branch $RLS_TARGET_BRANCH has no upstream"
    echo_error "You might call: git push --set-upstream origin ${RLS_TARGET_BRANCH}"
    exit 1
  fi

  # Rule 2.3: target and source branch must be different
  if [[ "${RLS_TARGET_BRANCH}" == "${RLS_SOURCE_BRANCH}" ]]; then
    echo_error "Source and Target Branch must be different!";
    exit 1
  fi;

  # Rule 3: When no build test, we need a version
  if [[ $build == "n" ]] && [[ $version == "-" ]]; then
    echo_error "Missing version, use --verion 1.2.3 or --build $build"
    usage
  fi

  RLS_INC_TYPE="-"
  local lowercase_version=$(toLowerCase "${version}")
  if [[ "$lowercase_version" == "current" ]] || [[ "$lowercase_version" == "patch" ]] || [[ "$lowercase_version" == "minor" ]] || [[ "$lowercase_version" == "major" ]]; then
    version=$(get_next_version "$lowercase_version")

    if [[ $version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
      RLS_INC_TYPE=${lowercase_version}
    else
      echo_error "Could not determine next version, based on git semantic tag informations. Is there any version tag? There has to be at least one!"
      exit 1
    fi
  fi


  RLS_TAG_EXISTS="false"
  RLS_REMOVE_TAG="false"

  if [[ $(git tag -l "$version") ]]; then
    # if this tag points to the same tag as the source commit, then everything should be ok
    TAG_COMMIT=$(git rev-parse "$version" 2>/dev/null)
    TARGET_COMMIT=$(git rev-parse "$RLS_TARGET_BRANCH" 2>/dev/null)

    if [[ "${TAG_COMMIT}" != "${TARGET_COMMIT}" ]]; then

      # Lokale Branches ermitteln, die diesen Commit enthalten
      TAG_BRANCHES=$(git branch --contains "$TAG_COMMIT")

      read -r -p "$(echo -e "${BORANGE}Target Version: ${version} exists already on branch ${TAG_BRANCHES}.${NC}\nPress y to recreate tag on target branch ${RLS_TARGET_BRANCH}, otherwise abort release! (y/n)" ) " -n 1
      echo    # (optional) move to a new line
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        if [[ "$0" = "$BASH_SOURCE" ]]; then
          echo_error "Aborted... \nThe version tag: $version is already used. And commit of $version and $RLS_TARGET_BRANCH are not equal. So, please use another one!"
          exit 1
        else
          echo_error "Aborted... \nThe version tag: $version is already used. And commit of $version and $RLS_TARGET_BRANCH are not equal. So, please use another one!"
          return 1 # handle exits from shell or function but don't exit interactive shell
        fi
      fi

      RLS_TAG_EXISTS="true"
      RLS_REMOVE_TAG="true"
    else
      # Target Tag exists, so we do not need to create it
      RLS_TAG_EXISTS="true"
    fi
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

  if [[ ${forceddl} != '-' ]]; then
    RLS_FORCE_DDL=${forceddl}
  fi
}


# valildate arguments
check_params "$@"

# something to remind you, ask to proceed
check_remind_me

# do the work
build_release