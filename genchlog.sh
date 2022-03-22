#!/bin/bash

# set project-settings from build.env if exists
if [[ -e ./build.env ]]; then
  source ./build.env
fi

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

current_tag=${1:-HEAD}
targetfile=${2:-changelog.md}


if [[ ${current_tag} == "HEAD" ]]; then
  previous_tag=$(git describe --tags --abbrev=0)
else
  previous_tag=$(git tag --sort=-creatordate | grep -A 1 ${current_tag} | tail -n 1)
fi


rem_trailing_slash() {
    echo "$1" | sed 's/\/*$//g'
}

force_trailing_slash() {
    echo "$(rem_trailing_slash "$1")/"
}


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
        fix_issue=$(echo "${fix_line}" | grep -e "${TICKET_MATCH}" -o || true)

        if [[ $fix_issue != "" ]]; then
          printf "* ${fix_line} [View]($(force_trailing_slash ${TICKET_URL})${fix_issue})\n" >> ${logf}
        else
          printf "* ${fix_line}\n" >> ${logf}
        fi
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


