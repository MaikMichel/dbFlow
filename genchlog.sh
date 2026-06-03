#!/usr/bin/env bash

# Generate a markdown changelog from git commits using build.env settings.

# get required functions and vars
if [[ ${LIBSOURCED:-} != "TRUE" ]]; then
  source ./.dbFlow/lib.sh
fi

# set project-settings from build.env if exists
if [[ -e ./build.env ]]; then
  source ./build.env
fi

usage() {
  echo -e "${BWHITE}$0${NC} - generate a markdown changelog grouped by configured commit prefixes"
  echo ""
  echo -e "${BWHITE}Usage:${NC}"
  echo -e "  $0 [--end <hash|tag>] [--start <hash|tag>] [--label <version>] [--file <filename.md>] [--append-existing]"
  echo ""
  echo -e "${BWHITE}Configuration${NC} (from build.env)"
  echo -e "  INTENT_PREFIXES  > Bash array with prefixes to group, for example ( Feat Fix )"
  echo -e "  INTENT_NAMES     > Bash array with group names, for example ( Features Fixes )"
  echo -e "  INTENT_ELSE      > Group name for commits without a configured prefix"
  echo -e "  TICKET_URL       > Base URL for ticket links"
  echo -e "  TICKET_MATCH     > regexp to match ticket keys, for example \"[A-Z]\\+-[0-9]\\+\""
  echo ""
  echo -e "${BWHITE}Options:${NC}"
  echo -e "  -h | --help               - Show this screen"
  echo -e "  -d | --debug              - Show additional output messages"
  echo -e "  -e | --end <hash|tag>     - Optional end hash or tag, defaults to HEAD"
  echo -e "  -s | --start <hash|tag>   - Optional start hash or tag, defaults to previous tag or root commit"
  echo -e "  -l | --label <version>    - Optional heading label, defaults to the end hash or tag"
  echo -e "  -f | --file <filename.md> - Optional filename; without it, the changelog is printed to stdout"
  echo -e "       --append-existing    - Put the new changelog entry above an existing target file"
  echo ""
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  $0"
  echo -e "  $0 --file changelog.md"
  echo -e "  $0 --end ba12010a --file reports/changelog/changelog.md"
  echo -e "  $0 --end HEAD --start 1.0.0 --label 1.2.3 --file reports/changelog/changelog.md --append-existing"

  exit "${1:-1}"
}

function check_vars() {
  do_exit="NO"

  if [[ ${do_exit} == "YES" ]]; then
    echo_warning "aborting"
    exit 1;
  fi
}

function resolve_default_start() {
  local end_ref=${1}
  local default_start=""

  if [[ ${end_ref} == "HEAD" ]]; then
    default_start=$(git describe --tags --abbrev=0 --always 2> /dev/null || true)
  else
    default_start=$(git tag --sort=-creatordate | grep -A 1 "^${end_ref}$" | tail -n 1 || true)
  fi

  if [[ -z ${default_start} ]]; then
    default_start=$(git log --max-parents=0 "${end_ref}" --pretty=format:%H)
  fi

  if [[ ${end_ref} == "HEAD" ]]; then
    local current_commit
    current_commit=$(git rev-parse HEAD)
    if [[ ${current_commit} == "${default_start}" ]]; then
      default_start=$(git log --max-parents=0 HEAD --pretty=format:%H)
    fi
  fi

  echo "${default_start}"
}

function check_params() {
  debug="NO"
  help="NO"
  start="-"
  end="HEAD"
  label=""
  file=""
  append_existing="NO"

  while getopts_long 'dhs:e:l:f: debug help start: end: label: file: append-existing' OPTKEY "${@}"; do
    case ${OPTKEY} in
      'd'|'debug')
        debug="YES"
        ;;
      'h'|'help')
        help="YES"
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
      'l'|'label')
        label="${OPTARG}"
        ;;
      'append-existing')
        append_existing="YES"
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

  if [[ ${help} == "YES" ]]; then
    usage 0
  fi

  if git cat-file -e "${end}" 2> /dev/null; then
    current_tag=${end}
  else
    timelog "End Commit or Tag ${end} not found" "${failure}"
    exit 1
  fi

  if [[ ${start} != "-" ]]; then
    if git cat-file -e "${start}" 2> /dev/null; then
      previous_tag=${start}
    else
      timelog "Start Commit or Tag ${start} not found" "${failure}"
      exit 1
    fi
  else
    previous_tag=$(resolve_default_start "${current_tag}")
  fi

  targetfile=${file}
  heading_label=${label:-${current_tag}}
  log_args="${previous_tag}...${current_tag}"

  if [[ ${append_existing} == "YES" ]] && [[ -z ${targetfile} ]]; then
    echo_error "--append-existing requires --file" >&2
    exit 1
  fi

  if [[ ${debug} == "YES" ]]; then
    timelog "current_tag=${current_tag}" "${info}"
    timelog "previous_tag=${previous_tag}" "${info}"
    timelog "heading_label=${heading_label}" "${info}"
    timelog "targetfile=${targetfile}" "${info}"
  fi
}

function append_ticket_link() {
  local commit_line=${1}
  local ticket_id=""

  if [[ -n ${TICKET_MATCH:-} ]]; then
    ticket_id=$(printf '%s\n' "${commit_line}" | grep -e "${TICKET_MATCH}" -o | head -n 1 || true)
  fi

  if [[ -n ${ticket_id} ]] && [[ -n ${TICKET_URL:-} ]]; then
    printf '%s [View](%s%s)' "${commit_line}" "$(force_trailing_slash "${TICKET_URL}")" "${ticket_id}"
  else
    printf '%s' "${commit_line}"
  fi
}

function strip_intent_prefix() {
  local commit_line=${1}
  local intent_prefix=${2}

  printf '%s\n' "${commit_line}" | sed "s/^${intent_prefix}: *//"
}

function write_commit_lines() {
  local commit_file=${1}
  local intent_prefix=${2:-}
  local commit_line
  local fixed_line

  sort -u "${commit_file}" | while IFS= read -r commit_line; do
    [[ -n ${commit_line} ]] || continue

    if [[ -n ${intent_prefix} ]]; then
      fixed_line=$(strip_intent_prefix "${commit_line}" "${intent_prefix}")
    else
      fixed_line=${commit_line}
    fi

    printf '* %s\n' "$(append_ticket_link "${fixed_line}")"
  done
}

function gen_changelog() {
  if [[ -n ${targetfile} ]]; then
    timelog "Generating Changelog ${previous_tag}...${current_tag} to ${targetfile}" "${info}"
  fi

  local changetime
  local logf
  local tag_date
  local other_file
  local line
  local matched
  local intent

  changetime=$(date "+%Y%m%d%H%M%S")
  logf=$(mktemp "changelog_${changetime}.XXXXXX")
  tag_date=$(git log -1 --pretty=format:'%ad' --date=short "${current_tag}")

  printf "# Changelog\n\n" > "${logf}"
  printf "## ${heading_label} (${tag_date})\n\n" >> "${logf}"

  declare -a temp_files

  if [[ ${#INTENT_PREFIXES[@]} -gt 0 ]]; then
    for intent in "${!INTENT_PREFIXES[@]}"; do
      temp_files[$intent]=$(mktemp)
    done
  fi

  other_file=$(mktemp)

  git log ${log_args} --pretty="%s" --reverse --no-merges | while IFS= read -r line; do
    matched="FALSE"

    if [[ ${#INTENT_PREFIXES[@]} -gt 0 ]]; then
      for intent in "${!INTENT_PREFIXES[@]}"; do
        if [[ ${line} == "${INTENT_PREFIXES[$intent]}:"* ]]; then
          printf '%s\n' "${line}" >> "${temp_files[$intent]}"
          matched="TRUE"
          break
        fi
      done
    fi

    if [[ ${matched} == "FALSE" ]]; then
      printf '%s\n' "${line}" >> "${other_file}"
    fi
  done

  if [[ ${#INTENT_PREFIXES[@]} -gt 0 ]]; then
    for intent in "${!INTENT_PREFIXES[@]}"; do
      if [[ -s ${temp_files[$intent]} ]]; then
        printf "### ${INTENT_NAMES[$intent]}\n\n" >> "${logf}"
        write_commit_lines "${temp_files[$intent]}" "${INTENT_PREFIXES[$intent]}" >> "${logf}"
        printf "\n\n" >> "${logf}"
      fi
    done
  fi

  if [[ -n ${INTENT_ELSE:-} ]] && [[ -s ${other_file} ]]; then
    if [[ ${#INTENT_PREFIXES[@]} -gt 0 ]]; then
      printf "### ${INTENT_ELSE}\n\n" >> "${logf}"
    fi

    write_commit_lines "${other_file}" >> "${logf}"
    printf "\n\n" >> "${logf}"
  fi

  printf -- "---\n" >> "${logf}"

  if [[ -n ${targetfile} ]]; then
    if [[ ${append_existing} == "YES" ]] && [[ -f ${targetfile} ]]; then
      sed '1d' "${targetfile}" > "${targetfile}.tmp" && mv "${targetfile}.tmp" "${targetfile}"
      cat "${targetfile}" >> "${logf}"
      rm "${targetfile}"
    fi

    mv "${logf}" "${targetfile}"
  else
    cat "${logf}"
    rm -f "${logf}"
  fi

  if [[ ${#INTENT_PREFIXES[@]} -gt 0 ]]; then
    for intent in "${!INTENT_PREFIXES[@]}"; do
      rm -f "${temp_files[$intent]}"
    done
  fi

  rm -f "${other_file}"

  if [[ -n ${targetfile} ]]; then
    timelog "Changelog written to ${targetfile}" "${success}"
  fi
}

# First check params
check_params "$@"

# now lets check config
check_vars

# now gen the log
gen_changelog
