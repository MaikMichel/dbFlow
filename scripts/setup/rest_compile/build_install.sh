#!/usr/bin/env bash

set -euo pipefail

START_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEF_FILE="${SCRIPT_DIR}/install.def"
OUT_FILE="${SCRIPT_DIR}/install.sql"
DEF_FILE_DISPLAY="${DEF_FILE}"

if [[ "${DEF_FILE}" == "${START_DIR}/"* ]]; then
  DEF_FILE_DISPLAY="${DEF_FILE#${START_DIR}/}"
elif [[ "${DEF_FILE}" == "${START_DIR}" ]]; then
  DEF_FILE_DISPLAY="."
fi

if [[ ! -f "$DEF_FILE" ]]; then
  echo "ERROR: Definition file not found: $DEF_FILE" >&2
  exit 1
fi

OUT_DIR="$(dirname "$OUT_FILE")"
mkdir -p "$OUT_DIR"

{
  echo "-- Auto-generated install script"
  echo "-- Source definition: $DEF_FILE_DISPLAY"
  echo "-- Generated at: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo
  echo "set define off"
  echo
} > "$OUT_FILE"

found_any=0

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^[[:space:]]*--[[:space:]]*File:[[:space:]]*(.+)$ ]]; then
    src_file="${BASH_REMATCH[1]}"
    src_path=""
    src_file="${src_file%$'\r'}"
    src_file="${src_file#"${src_file%%[![:space:]]*}"}"
    src_file="${src_file%"${src_file##*[![:space:]]}"}"

    if [[ "${src_file}" = /* ]]; then
      src_path="${src_file}"
    else
      src_path="${SCRIPT_DIR}/${src_file}"
    fi

    if [[ ! -f "$src_path" ]]; then
      echo "ERROR: Referenced file not found: $src_path" >&2
      exit 1
    fi

    found_any=1
    {
      echo
      echo "prompt >> Executing $src_file"
      echo "-- ====================================================================="
      echo "-- Begin File: $src_file"
      echo "-- ====================================================================="
      cat "$src_path"
      echo
      echo "-- ====================================================================="
      echo "-- End File: $src_file"
      echo "-- ====================================================================="
      echo
    } >> "$OUT_FILE"
  fi
done < "$DEF_FILE"

if [[ "$found_any" -eq 0 ]]; then
  echo "ERROR: No '-- File:' entries found in $DEF_FILE" >&2
  exit 1
fi

echo "Generated: $OUT_FILE"
