#!/usr/bin/env bash
echo "Your script args ($#) are: $@"


# get required functions and vars
source ./.dbFlow/lib.sh


# set target-env settings from file if exists
if [[ -e ./apply.env ]]; then
  source ./apply.env
fi

# Default values
TITLE="dbFlow - Webhook Default Titel"
TEXT="This is just a message"
COLOR="4CCC3B"

# Function to display help
function display_help {
  echo "Usage: $0 [options]"
  echo
  echo "   -i, --title      Title of the message"
  echo "   -t, --text       Text message to send"
  echo "   -c, --color      Color code of the message"
  echo "   -h, --help       Display this help message"
  exit 0
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -i|--title) TITLE="$2"; shift ;;
    -t|--text) TEXT="$2"; shift ;;
    -c|--color) COLOR="$2"; shift ;;
    -h|--help) display_help ;;
    *) echo_error "Unknown parameter passed: $1"; display_help ;;
  esac
  shift
done


# Convert formating.
MESSAGE=$( echo "${TEXT}" | sed 's/"/\"/g' | sed "s/'/\'/g" )
JSON="{\"title\": \"${TITLE}\", \"themeColor\": \"${COLOR}\", \"text\": \"${MESSAGE}\" }"


# Validate if TEAMS_WEBHOOK_URL is set and points to a URL
if [[ -z "${TEAMS_WEBHOOK_URL}" ]]; then
  echo_error "Error: TEAMS_WEBHOOK_URL is not set."
  exit 1
fi

if ! [[ "${TEAMS_WEBHOOK_URL}" =~ ^https?:// ]]; then
  echo_error "Error: TEAMS_WEBHOOK_URL is not a valid URL."
  exit 1
fi

# Post to Microsoft Teams.
echo_success "Posting to url: ${JSON}"

curl -H "Content-Type: application/json" -d "${JSON}" "${TEAMS_WEBHOOK_URL}"

