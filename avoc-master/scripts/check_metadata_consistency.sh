#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CANONICAL_REPO_URL="https://github.com/AkeroGit/AvocCompleteTest"

readonly CHECK_FILES=(
  "README.md"
  "pyproject.toml"
)

readonly DISALLOWED_PATTERNS=(
  "github.com/develOseven"
  "\bAUR\b"
)

errors=0

for rel_path in "${CHECK_FILES[@]}"; do
  file_path="${PROJECT_ROOT}/${rel_path}"
  if [[ ! -f "${file_path}" ]]; then
    echo "ERROR: Missing required file: ${rel_path}" >&2
    errors=1
  fi
done

if [[ "${errors}" -ne 0 ]]; then
  exit 1
fi

for rel_path in "${CHECK_FILES[@]}"; do
  file_path="${PROJECT_ROOT}/${rel_path}"

  for pattern in "${DISALLOWED_PATTERNS[@]}"; do
    if rg -n --pcre2 "${pattern}" "${file_path}"; then
      echo "ERROR: Disallowed metadata pattern '${pattern}' found in ${rel_path}" >&2
      errors=1
    fi
  done

  if ! rg -q --fixed-strings "${CANONICAL_REPO_URL}" "${file_path}"; then
    echo "ERROR: Canonical URL '${CANONICAL_REPO_URL}' is missing from ${rel_path}" >&2
    errors=1
  fi
done

if [[ "${errors}" -ne 0 ]]; then
  echo "Metadata consistency check failed." >&2
  exit 1
fi

echo "Metadata consistency check passed."
