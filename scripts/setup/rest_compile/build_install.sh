#!/usr/bin/env bash

set -euo pipefail

START_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function build_one() {
  local def_file="$1"
  local out_file="$2"

  local def_display="${def_file}"
  if [[ "${def_file}" == "${START_DIR}/"* ]]; then
    def_display="${def_file#${START_DIR}/}"
  elif [[ "${def_file}" == "${START_DIR}" ]]; then
    def_display="."
  fi

  if [[ ! -f "${def_file}" ]]; then
    echo "ERROR: Definition file not found: ${def_file}" >&2
    exit 1
  fi

  mkdir -p "$(dirname "${out_file}")"

  {
    echo "-- Auto-generated install script"
    echo "-- Source definition: ${def_display}"
    echo "-- Generated at: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo
    echo "set define off"
    echo
  } > "${out_file}"

  local found_any=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*--[[:space:]]*File:[[:space:]]*(.+)$ ]]; then
      local src_file="${BASH_REMATCH[1]}"
      src_file="${src_file%$'\r'}"
      src_file="${src_file#"${src_file%%[![:space:]]*}"}"
      src_file="${src_file%"${src_file##*[![:space:]]}"}"

      local src_path
      if [[ "${src_file}" = /* ]]; then
        src_path="${src_file}"
      else
        src_path="${SCRIPT_DIR}/${src_file}"
      fi

      if [[ ! -f "${src_path}" ]]; then
        echo "ERROR: Referenced file not found: ${src_path}" >&2
        exit 1
      fi

      found_any=1
      {
        echo
        echo "prompt >> Executing ${src_file}"
        echo "-- ====================================================================="
        echo "-- Begin File: ${src_file}"
        echo "-- ====================================================================="
        cat "${src_path}"
        echo
        echo "-- ====================================================================="
        echo "-- End File: ${src_file}"
        echo "-- ====================================================================="
        echo
      } >> "${out_file}"
    fi
  done < "${def_file}"

  if [[ "${found_any}" -eq 0 ]]; then
    echo "ERROR: No '-- File:' entries found in ${def_file}" >&2
    exit 1
  fi

  echo "Generated: ${out_file}"
}

build_one "${SCRIPT_DIR}/install.def"          "${SCRIPT_DIR}/install.sql"
build_one "${SCRIPT_DIR}/install_no_oauth.def" "${SCRIPT_DIR}/install_no_oauth.sql"
