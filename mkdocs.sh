#!/usr/bin/env bash
# echo "Your script args ($#) are: $@"

MSYS_NO_PATHCONV=1 docker run --rm -it -p 8000:8000 -v ${PWD}:/docs squidfunk/mkdocs-material "$@"