#!/usr/bin/env bash
#echo "$0 Your script args ($#) are: $@"

# delta to diplay messages is from
#   a) HEAD to latest tag
#   b) Tag and previous tag

# Params needed
# 1: Tag/Commit Hash as current
# 2: Filename to write

# EnvVars needed
# PROJECT          > Projectname used in Heading
# INTENT_PREFIXES  > Bash Array ( sss sss sss ) with prefixes to look fo ( Feat Fix )
#                    Fix: Error when deviding by zero #KEY-123
# INTENT_NAMES     > Bash Array ( sss sss sss ) with Full names for prefixes eg ( Features Fixes )
# TICKET_URL       > URL to concat with fouond ticket
# TICKET_MATCH     > regexp to match ticketkey eg: "[A-Z]\+-[0-9]\+"

usage() {
  echo -e "${BWHITE}$0${NC} - generate a markdown file which represents"
  echo -e "                      your changes grouped by defined prefixes"
  echo ""
  echo -e "${BWHITE}Usage:${NC}"
  echo -e "  $0 --end <hash|tag> [--start <hash|tag>] --file reports/changelog/changelog.md"
  echo ""
  echo -e "${BWHITE}Configuration${NC} (required when using this feature build.env)"
  echo -e "  PROJECT          > Projectname used in Heading"
  echo -e "  INTENT_PREFIXES  > Bash Array ( String String String ) with prefixes to look fo ( Feat Fix )"
  echo -e "                     Fix: Error when deviding by zero #KEY-123"
  echo -e "  INTENT_NAMES     > Bash Array ( String String String ) with Full names for prefixes eg ( Features Fixes )"
  echo -e "  INTENT_ELSE      > When no intent in matched or INTENT_PREFIXES is not defined"
  echo -e "                     All other staff goes hier"
  echo -e "  TICKET_URL       > URL to concat with found ticket"
  echo -e "  TICKET_MATCH     > regexp to match ticketkey eg: \"[A-Z]\+-[0-9]\+\""
  echo ""
  echo -e "${BWHITE}Options:${NC}"
  echo -e "  -h | --help               - Show this screen"
  echo -e "  -d | --debug              - Show additionaly output messages"
  echo -e "  -e | --end <hash|tag>     - Optional hash or tag to determine the difference to the start, defaults to HEAD"
  echo -e "  -s | --start <hash|tag>   - Optional hash or tag to determine the difference to the end, defaults to previous tag found"
  echo -e "  -f | --file <filename.md> - Required filename the changelog get written to"
  echo ""
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  $0 --file changelog.md"
  echo -e "  $0 --end ba12010a --file reports/changelog/changelog.md"
  echo -e "  $0 --end HEAD --start 1.0.0 --file reports/changelog/changelog.md"

  exit 1
}

# get required functions and vars
if [[ $LIBSOURCED != "TRUE" ]]; then
  source ./.dbFlow/lib.sh
fi

# set project-settings from build.env if exists
if [[ -e ./build.env ]]; then
  source ./build.env
fi

function check_vars() {
  timelog "Checking Vars" ${info}

  # check require vars from build.env
  do_exit="NO"
  if [[ -z ${PROJECT:-} ]]; then
    echo_error "undefined var: PROJECT"
    do_exit="YES"
  fi

  ####
  if [[ ${do_exit} == "YES" ]]; then
    echo_warning "aborting"
    exit 1;
  fi
}


function check_params() {
  debug="n" help="n" start="-" end=HEAD file="changelog.md"

  while getopts_long 'dhs:e:f: debug help start: end: file:' OPTKEY "${@}"; do
    echo "OPTKEY: ${OPTKEY}"
      case ${OPTKEY} in
          'd'|'debug')
              d=y
              ;;
          'h'|'help')
              h=y
              ;;
          'f'|'file')
              file="${OPTARG}"
              ;;
          's'|'start')
              start="${OPTARG}"
              ;;
          'e'|'end')
              end="${OPTARG}"
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
  if [[ -n ${h} ]] && [[ ${h} == "y" ]]; then
    usage
  fi

  if git cat-file -e $end 2> /dev/null; then
    current_tag=$end
  else
    timelog "End Commit or Tag $end not found" ${failure}
    exit 1
  fi

  if [[ $start != "-" ]]; then
    if git cat-file -e $start 2> /dev/null; then
      previous_tag=$start
    else
      timelog "Start Commit or Tag $start not found" ${failure}
      exit 1
    fi
  else
    if [[ ${current_tag} == "HEAD" ]]; then
      previous_tag=$(git describe --tags --abbrev=0 --always)
    else
      previous_tag=$(git tag --sort=-creatordate | grep -A 1 ${current_tag} | tail -n 1) || true
    fi
  fi

  # if start and end are the same at head, we put all into the change log
  # otherwise we had to look for a previous commit: git log --format="%H" -n 2 | tail -1
  if [[ ${current_tag} == "HEAD" ]]; then
    current_commit=$(git rev-parse HEAD)
    if [[ ${current_commit} == ${previous_tag} ]]; then
      previous_tag=$(git log --max-parents=0 HEAD --pretty=format:%H)
    fi
  fi
  targetfile=${file}
}



function gen_changelog() {
  timelog "Generating Changelog ${current_tag}...${previous_tag}" ${info}

  # define log
  changetime=`date "+%Y%m%d%H%M%S"`
  logf=changelog_${changetime}.md
  tag_date=$(git log -1 --format=%as "${current_tag}")


  if [[ -n ${INTENT_PREFIXES} ]]; then

    # gen associative array
    declare -A temp_files

    # gen tempfile for each intent
    for intent in "${INTENT_PREFIXES[@]}"; do
      temp_files[$intent]=$(mktemp)
    done
    other_file=$(mktemp)

    # for each commit
    git log ${current_tag}...${previous_tag} --pretty="%s" --reverse --no-merges | while read -r line; do
      TICKET_ID=$(echo "$line" | sed -n "s/.*$TICKET_MATCH*/\1/p")
      if [[ -n ${TICKET_ID} ]]; then
        line="$line [${TICKET_ID}](${TICKET_URL}/${TICKET_ID})"
      fi
      matched=false
      for intent in "${!INTENT_PREFIXES[@]}"; do
        if [[ $line == ${INTENT_PREFIXES[$intent]}:* ]]; then
          echo "- ${line} " >> "${temp_files[${INTENT_PREFIXES[$intent]}]}"
          matched=true
          break
        fi
      done

      # when nothing matched
      if [ "$matched" = false ]; then
        echo "- ${line}" >> "${other_file}"
      fi
    done

    # gen full file
    {
      echo "# Changelog"
      echo ""

      for intent in "${!INTENT_PREFIXES[@]}"; do
          if [ -s "${temp_files[${INTENT_PREFIXES[$intent]}]}" ]; then
              echo "## ${INTENT_NAMES[$intent]}"
              cat "${temp_files[${INTENT_PREFIXES[$intent]}]}"
              echo ""
          fi
      done

      if [ -s "$other_file" ]; then
          echo "## ${INTENT_ELSE}"
          cat "$other_file"
          echo ""
      fi

    } > "$targetfile"

    # Temporäre Dateien löschen
    for intent in "${INTENT_PREFIXES[@]}"; do
        rm -f "${temp_files[$intent]}"
    done

    rm -f "$other_file"
  fi
  timelog "Changelog written to ${targetfile}" ${success}
}

# First check params
check_params "$@"

# now lets check config
check_vars

# now gen the log
gen_changelog
