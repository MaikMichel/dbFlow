#!/usr/bin/env bash
# echo "Your script args ($#) are: $@"

# get required functions and vars
source ./.dbFlow/lib.sh

if [ $# -eq 0 ]; then
    printf "${BWHITE}USAGE${NC}\n"
    printf "  ${0} -t | --target_branch ${BORANGE}branch${NC}  > List commits until last merge on targe branch\n"
    printf "\n"
    printf "${PURPLE}Examle${NC}\n"
    printf "  ${0} --target_branch ${BORANGE}origin/master${NC}"
    printf "\n"
    exit 1
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --target_branch|-t) TARGET_BRANCH="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

echo "Using target branch: $TARGET_BRANCH"

git log --graph --decorate --oneline $(git log --merges --pretty=format:"%H" -n 1 $TARGET_BRANCH)..HEAD