#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
selector="${script_directory}/select-properties-file.sh"
test_directory="$(mktemp -d)"
trap 'rm -rf -- "${test_directory}"' EXIT

assert_selection() {
  local expected="$1"
  local android_path="$2"
  local actual

  actual="$(bash "${selector}" "${android_path}")"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Expected ${expected}, selected ${actual}." >&2
    exit 1
  fi
}

mkdir -p "${test_directory}/standard/app"
printf '%s\n' "def propertiesFile = rootProject.file('key.properties')" \
  > "${test_directory}/standard/app/build.gradle"
assert_selection 'key.properties' "${test_directory}/standard"

mkdir -p "${test_directory}/legacy/app"
printf '%s\n' "def keystorePropertiesFile = rootProject.file('keystore.properties')" \
  > "${test_directory}/legacy/app/build.gradle"
assert_selection 'keystore.properties' "${test_directory}/legacy"

mkdir -p "${test_directory}/default/app"
printf '%s\n' 'plugins { id("com.android.application") }' \
  > "${test_directory}/default/app/build.gradle.kts"
assert_selection 'key.properties' "${test_directory}/default"

echo 'Android signing properties selector tests passed.'
