#!/usr/bin/env bash

set -euo pipefail

android_path="${1:?Android project directory is required}"
gradle_files=()

for candidate in \
  "${android_path}/app/build.gradle" \
  "${android_path}/app/build.gradle.kts"; do
  if [[ -f "${candidate}" ]]; then
    gradle_files+=("${candidate}")
  fi
done

# key.properties is Flutter's current project-template convention. Some older
# applications use keystore.properties instead, so honor that name when it is
# the only convention referenced by the application module.
if ((${#gradle_files[@]} > 0)) &&
  grep -Eq "['\"]keystore\.properties['\"]" "${gradle_files[@]}" &&
  ! grep -Eq "['\"]key\.properties['\"]" "${gradle_files[@]}"; then
  printf '%s\n' 'keystore.properties'
else
  printf '%s\n' 'key.properties'
fi
