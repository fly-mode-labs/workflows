#!/usr/bin/env bash

set -euo pipefail

assert_contains() {
  local file="$1"
  local text="$2"
  if ! grep -Fq -- "${text}" "${file}"; then
    echo "Missing expected macOS workflow contract in ${file}: ${text}" >&2
    exit 1
  fi
}

main='.github/workflows/main.yml'
build='.github/workflows/flutter-build.yml'
release='.github/workflows/flutter-release.yml'
macos_release='.github/workflows/release-integration-macos.yml'
docs='docs/flutter.md'
template='templates/flutter/.github/workflows/main.yml'

assert_contains "${main}" 'android|ios|web|macos)'
assert_contains "${main}" 'for platform in android ios web macos; do'
assert_contains "${main}" "build-macos: \${{ needs.validate.outputs.macos == 'true' }}"
assert_contains "${main}" "release-macos: \${{ inputs.release-macos && needs.validate.outputs.macos == 'true' }}"
assert_contains "${build}" "if: inputs.build-macos && inputs.delivery-mode == 'artifact'"
assert_contains "${build}" 'run: flutter build macos --release'
assert_contains "${build}" 'build/macos/Build/Products/Release/*.app'
assert_contains "${release}" 'release-integration-macos.yml@main'
assert_contains "${macos_release}" 'bundle exec fastlane mac beta'
assert_contains "${macos_release}" 'bundle exec fastlane mac release'
assert_contains "${macos_release}" 'SOURCE_SHA: ${{ inputs.source-sha }}'
assert_contains "${macos_release}" 'APP_STORE_CONNECT_API_KEY_BASE64:'
assert_contains "${template}" 'default: android,ios'
assert_contains "${template}" 'default: false'
assert_contains "${template}" "platforms: \${{ inputs.platforms || 'android,ios' }}"
assert_contains "${template}" "release-macos: \${{ inputs.release-macos || false }}"
release_platform_count="$(grep -Fc "release-macos: \${{ inputs.release-macos || false }}" "${template}")"
if [[ "${release_platform_count}" -ne 2 ]]; then
  echo 'The Flutter caller template must pass the macOS release opt-in to both CI and CD.' >&2
  exit 1
fi
assert_contains "${docs}" 'release-macos: true'
assert_contains "${docs}" 'no se sube a Firebase'
assert_contains "${docs}" 'TestFlight'

echo 'macOS build and Apple distribution contract checks passed.'
