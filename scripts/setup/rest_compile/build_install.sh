#!/usr/bin/env bash

set -euo pipefail

DEF_FILE="${1:-db/_setup/rest_compile/install.def}"
OUT_FILE="${2:-db/_setup/rest_compile/install.sql}"

if [[ ! -f "$DEF_FILE" ]]; then
  echo "ERROR: Definition file not found: $DEF_FILE" >&2
  exit 1
fi

OUT_DIR="$(dirname "$OUT_FILE")"
mkdir -p "$OUT_DIR"

{
  echo "-- Auto-generated install script"
  echo "-- Source definition: $DEF_FILE"
  echo "-- Generated at: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo
  echo "set define off"
  echo
} > "$OUT_FILE"

found_any=0

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^[[:space:]]*--[[:space:]]*File:[[:space:]]*(.+)$ ]]; then
    src_file="${BASH_REMATCH[1]}"
    src_file="${src_file%$'\r'}"
    src_file="${src_file#"${src_file%%[![:space:]]*}"}"
    src_file="${src_file%"${src_file##*[![:space:]]}"}"

    if [[ ! -f "$src_file" ]]; then
      echo "ERROR: Referenced file not found: $src_file" >&2
      exit 1
    fi

    found_any=1
    {
      echo
      echo "prompt >> Executing $src_file"
      echo "-- ====================================================================="
      echo "-- Begin File: $src_file"
      echo "-- ====================================================================="
      cat "$src_file"
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
