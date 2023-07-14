#!/usr/bin/env bash
# echo "Your script args ($#) are: $@"

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

# A better class of script...
# set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
# set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline

# null value in array
shopt -s nullglob

# Reset
NC="\033[0m"       # Text Reset

# Regular Colors
BLACK="\033[0;30m"        # Black
RED="\033[0;31m"          # Red
REDB="\033[1;41m"         # BoldRedBack
GREEN="\033[0;32m"        # Green
BGREEN="\033[1;32m"        # Green
YELLOW="\033[0;33m"       # Yellow
BLUE="\033[0;34m"         # Blue
PURPLE="\033[0;35m"       # Purple
CYAN="\033[0;36m"         # Cyan
BCYAN="\033[1;36m"         # Cyan
BWHITE="\033[1;97m"       # White
WHITE="\033[0;97m"        # White
LWHITE="\033[1;30m"       # White
BYELLOW="\e[30;48;5;82m"  # Yellow
BORANGE="\e[38;5;208m"    # Orange
BUNLINE="\e[1;4m"
BGRAY="\e[0;90m"
BLBACK="\e[30;48;5;81m"

DBFLOW_RUNNING_OS=$(uname)

git --version 2>&1 >/dev/null
GIT_IS_AVAILABLE=$?

function errcho() {
    >&2 echo -e "${RED}$@${NC}";
}

function usage() {
  echo -e "${BWHITE}install [${CYAN}dbFlow${NC}${BWHITE}]${NC} - prepare project folder and download dbFlow as submodul "
  # Tree chars └ ─ ├ ─ │
  echo
  echo -e "${BWHITE}USAGE${NC}"
  echo -e "  ${0} --generate <project-name> [--envonly]"
  echo
  echo -e "${BWHITE}Examples:${NC}"
  echo -e "  ${0} --generate mytest"
  echo
  echo
  exit $1
}

if [[ $GIT_IS_AVAILABLE > 0 ]]; then
  errcho ""
  errcho " ⚠ Please install git before running this command."
  errcho ""
  exit 1
fi

TARGET_PATH=.
if [[ $# > 0 ]]; then
    if [[ $# > 1 ]]; then
      errcho ""
      errcho " ⚠ Too many arguments. Make sure you use just one argument when you want to create a new folder or install dbFlow in this one."
      errcho ""
      exit 2
    fi
    TARGET_PATH=${1}
fi

echo -e "${CYAN}Installing dbFlow in Folder: ${TARGET_PATH}${NC}"

if [[ ! -d "${TARGET_PATH}" ]]; then
  mkdir -p "${TARGET_PATH}"
fi

cd "${TARGET_PATH}"

# init your project with git
if [[ ! -d ".git" ]]; then
  echo -e "${CYAN}Initializing git${NC}"
  git init
  echo
fi

echo -e "${CYAN}clone dbFlow as submodule${NC}"
git submodule add https://github.com/MaikMichel/dbFlow.git .dbFlow
echo

echo -e "${GREEN}dbFlow installed in Folder: ${BUNLINE}${TARGET_PATH}${NC}"
echo

if [[ ${TARGET_PATH} != "." ]]; then
  echo -e "${BGREEN}Go to your project folder ${TARGET_PATH} and enjoy working${NC}"
  echo -e "${BWHITE}cd ${TARGET_PATH}${NC}"
fi

echo -e "${BGRAY}to generate and switch to your development branch type:${NC}"
echo -e "${WHITE}git checkout -b develop${NC}"
echo -e ""
echo -e "${BGRAY}to generate the project it self type:${NC}"
echo -e "${WHITE}.dbFlow/setup.sh --generate $(basename "$PWD")${NC}"
echo -e ""
echo -e "${BGRAY}after processing the wizard steps, just use the install flag${NC}"
echo -e "${WHITE}.dbFlow/setup.sh --install${NC}"
echo -e ""
echo -e "${BORANGE}To learn more about dbFlow, see the docs: ${BUNLINE}https://maikmichel.github.io/dbFlow/${NC}"
