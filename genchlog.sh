#!/bin/bash
# echo "Your script args ($#) are: $@"

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
  echo_debug "Checking Vars" | write_log

  # check require vars from build.env
  do_exit="NO"
  if [[ -z ${PROJECT:-} ]]; then
    echo_error "undefined var: PROJECT"
    do_exit="YES"
  fi

  # when MultisSchema or SingleSchema, this vars are required

  # if [[ -z ${INTENT_ELSE:-} ]] && [[ -z ${INTENT_PREFIXES:-} ]]; then
  #   echo_error "INTENT_ELSE or INTENT_PREFIXES has to be defined"
  #   do_exit="YES"
  # fi


  ####
  if [[ ${do_exit} == "YES" ]]; then
    echo_warning "aborting"
    exit 1;
  fi
}


function check_params() {
  echo_debug "Checking Params" | write_log

  ! getopt --test > /dev/null
  if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
      echo_fatal 'I’m sorry, `getopt --test` failed in this environment.'
      exit 1
  fi

  OPTIONS=dhs:e:f:
  LONGOPTS=debug,help,start:,end:,file:

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

  debug="n" help="n" start="-" end=HEAD file="changelog.md"

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
          -f|--file)
              file="$2"
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
  if [[ -n ${h} ]] && [[ ${h} == "y" ]]; then
    usage
  fi

  if git cat-file -e $end 2> /dev/null; then
    current_tag=$end
  else
    echo_error "End Commit or Tag $end not found" | write_log
    exit 1
  fi

  if [[ $start != "-" ]]; then
    if git cat-file -e $start 2> /dev/null; then
      previous_tag=$start
    else
      echo_error "Start Commit or Tag $start not found" | write_log
      exit 1
    fi
  else
    if [[ ${current_tag} == "HEAD" ]]; then
      previous_tag=$(git describe --tags --abbrev=0)
    else
      previous_tag=$(git tag --sort=-creatordate | grep -A 1 ${current_tag} | tail -n 1) || true
    fi
  fi
  targetfile=${file}
}


rem_trailing_slash() {
    echo "$1" | sed 's/\/*$//g'
}

force_trailing_slash() {
    echo "$(rem_trailing_slash "$1")/"
}


function gen_changelog() {
  echo_debug "Generating Changelog" | write_log

  # define log
  changetime=`date "+%Y%m%d%H%M%S"`
  logf=changelog_${changetime}.md
  tag_date=$(git log -1 --pretty=format:'%ad' --date=short ${current_tag})

  printf "# ${PROJECT} - Changelog\n\n" > ${logf}
  printf "## ${current_tag} (${tag_date})\n\n" >> ${logf}

  if [[ -n ${INTENT_PREFIXES} ]]; then
    for intent in "${!INTENT_PREFIXES[@]}"; do
      readarray -t fixes <<< $(git log ${current_tag}...${previous_tag} --pretty="%s" --reverse | grep -v Merge | grep "^${INTENT_PREFIXES[$intent]}: *")
      eval fixes=($(printf "%q\n" "${fixes[@]}" | sort -u))

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

    readarray -t fixes <<< $(git log ${current_tag}...${previous_tag} --pretty="%s" --reverse | grep -v Merge | grep -v -E "^${intent_pipes}: *")
    eval fixes=($(printf "%q\n" "${fixes[@]}" | sort -u))

    if [[ ${#fixes[@]} -gt 0 ]] && [[ ${fixes[0]} != "" ]]; then
      if [[ -n ${INTENT_PREFIXES} ]]; then
        printf "### ${INTENT_ELSE}\n\n" >> ${logf}
      fi

      for fix in "${fixes[@]}"; do
        fix_line=${fix}
        fix_issue=$(echo "${fix_line}" | grep -e "${TICKET_MATCH}" -o || true)

        if [[ $fix_issue != "" ]]; then
          printf "* ${fix_line} [View]($(force_trailing_slash ${TICKET_URL})${fix_issue})\n" >> ${logf}
        else
          printf "* ${fix_line}\n" >> ${logf}
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
  echo_success "Changelog written to ${targetfile}" | write_log
}



# First check params
check_params "$@"

# now lets check config
check_vars

# now gen the log
gen_changelog
