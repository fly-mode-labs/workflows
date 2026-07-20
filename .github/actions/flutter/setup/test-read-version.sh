#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
parser="${script_directory}/read-version.sh"

assert_version() {
  local expected="$1"
  local version_output="$2"
  local actual

  actual="$(printf '%s\n' "${version_output}" | bash "${parser}")"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Expected ${expected}, parsed ${actual}." >&2
    exit 1
  fi
}

assert_version \
  '3.41.4' \
  $'┌─────────────────────────────────────────────┐\n│ A new version of Flutter is available!      │\n└─────────────────────────────────────────────┘\n{"frameworkVersion":"3.41.4","channel":"stable"}'

assert_version \
  '3.42.0-0.1.pre' \
  $'{\n  "channel": "beta",\n  "frameworkVersion": "3.42.0-0.1.pre"\n}'

if printf '%s\n' '{"channel":"stable"}' | bash "${parser}" >/dev/null 2>&1; then
  echo 'The parser accepted output without frameworkVersion.' >&2
  exit 1
fi

echo 'Flutter version parser tests passed.'
