#!/usr/bin/env bash

set -euo pipefail

version_output="$(cat)"

# Flutter's human-readable output can contain update notices whose text also
# includes "Flutter <word>". The machine output provides an unambiguous field
# and remains safe even if a persistent runner prepends an update notice.
if [[ "${version_output}" =~ \"frameworkVersion\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  printf '%s\n' "${BASH_REMATCH[1]}"
  exit 0
fi

echo 'The Flutter machine output does not contain frameworkVersion.' >&2
exit 1
