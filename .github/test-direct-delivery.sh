#!/usr/bin/env bash

set -euo pipefail

assert_contains() {
  local file="$1"
  local text="$2"
  local message="$3"
  if ! grep -Fq -- "${text}" "${file}"; then
    echo "${message}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local text="$2"
  local message="$3"
  if grep -Fq -- "${text}" "${file}"; then
    echo "${message}" >&2
    exit 1
  fi
}

main='.github/workflows/main.yml'
build='.github/workflows/flutter-build.yml'
release='.github/workflows/flutter-release.yml'
ios_integration='.github/workflows/release-integration-app-store.yml'
android_integration='.github/workflows/release-integration-google-play.yml'
android_release='.github/actions/flutter/release-android/action.yml'
ios_release='.github/actions/flutter/release-ios/action.yml'
ios_build='.github/actions/flutter/build-ios/action.yml'
android_build='.github/actions/flutter/build-android/action.yml'
template='templates/flutter/.github/workflows/main.yml'

assert_contains "${main}" 'delivery-mode:' 'The public workflow must expose delivery-mode.'
assert_contains "${main}" 'default: artifact' 'Artifact delivery must remain the public default.'
assert_contains "${main}" 'artifact|direct)' 'Configuration validation must accept only artifact and direct delivery.'
assert_contains "${main}" "inputs.delivery-mode == 'direct' && github.event.action == 'synchronize'" 'Direct non-draft synchronize events must rebuild and republish beta.'
assert_contains "${main}" 'source-sha: ${{ github.event.pull_request.head.sha || github.sha }}' 'Release orchestration must use the exact source SHA.'
assert_contains "${main}" 'ANDROID_PUBLISHER_CREDENTIALS:' 'The public workflow must declare the Google Play secret contract.'
assert_not_contains "${main}" 'secrets: inherit' 'The public workflow must pass secrets explicitly to nested workflows.'
assert_not_contains "${release}" 'secrets: inherit' 'The release workflow must pass only store-specific secrets to integrations.'

beta_release_contract="$(sed -n '/^  flutter-beta-release:/,/^  flutter-production-release:/p' "${main}")"
production_release_contract="$(sed -n '/^  flutter-production-release:/,$p' "${main}")"
for signing_secret in \
  ANDROID_KEYSTORE_BASE64 \
  KEYALIAS \
  STOREPASSWORD \
  KEYPASSWORD \
  MATCH_PASSWORD \
  MATCH_GIT_BASIC_AUTHORIZATION; do
  if ! grep -Fq "${signing_secret}:" <<< "${beta_release_contract}"; then
    echo "Direct beta release must receive ${signing_secret} for local signed builds." >&2
    exit 1
  fi
  if grep -Fq "${signing_secret}:" <<< "${production_release_contract}"; then
    echo "Production promotion must not receive unused signing secret ${signing_secret}." >&2
    exit 1
  fi
done

direct_opt_ins="$(grep -Fc 'delivery-mode: direct' "${template}")"
if [[ "${direct_opt_ins}" -ne 2 ]]; then
  echo 'The Flutter template must select direct delivery in both CI and CD calls.' >&2
  exit 1
fi
if grep -Fq 'actions: read' "${template}"; then
  echo 'The direct Flutter template must not request artifact API permission.' >&2
  exit 1
fi
assert_contains "${template}" 'default: github-hosted' 'The direct template must default to an ephemeral GitHub-hosted runner.'
assert_contains "${template}" "inputs.runner || 'github-hosted'" 'Automatic direct delivery must use GitHub-hosted runners by default.'
assert_contains "${template}" 'ANDROID_PUBLISHER_CREDENTIALS: ${{ secrets.ANDROID_PUBLISHER_CREDENTIALS }}' 'The caller template must pass Google Play credentials explicitly.'
assert_not_contains "${template}" 'secrets: inherit' 'The caller template must support explicit cross-owner secret passing.'

assert_contains "${build}" "upload-artifact: \${{ inputs.delivery-mode == 'artifact' }}" 'Direct CI builds must skip artifact uploads.'
assert_contains "${release}" "inputs.delivery-mode == 'artifact' &&" 'Artifact resolution must be gated to artifact delivery.'
assert_contains "${release}" 'group: flutter-release-${{ github.repository }}' 'Release concurrency must serialize beta and production together.'
assert_contains "${ios_integration}" 'Build signed IPA for direct beta delivery' 'Direct iOS beta must build inside the integration job.'
assert_contains "${ios_integration}" 'ipa-path: ${{ steps.build.outputs.ipa-path }}' 'Direct iOS beta must pass its local IPA path to release.'
assert_contains "${android_integration}" 'build-format: appbundle' 'Direct Android beta must force an App Bundle build.'
assert_contains "${android_integration}" 'local-aab-path: ${{ steps.build.outputs.aab-path }}' 'Direct Android beta must pass its local App Bundle path to release.'
assert_contains "${android_release}" "if: inputs.delivery-mode == 'artifact'" 'Legacy Android artifact download must remain available.'
assert_contains "${ios_release}" "inputs.stage == 'beta' && inputs.delivery-mode == 'artifact'" 'Direct iOS beta must skip artifact download.'
assert_contains "${android_release}" "inputs.stage == 'production' && inputs.delivery-mode == 'direct'" 'Direct Android production must use its promotion path.'
assert_contains "${android_release}" 'VERSION_CODE: ${{ inputs.version-code }}' 'Direct Android production must promote the exact Flutter build number.'
assert_contains "${android_release}" 'uses: r0adkll/upload-google-play@v1.1.5' 'Legacy artifact upload must remain pinned and functional.'
assert_contains "${android_release}" 'SOURCE_SHA: ${{ inputs.source-sha }}' 'Android direct delivery must bind releases to the source SHA.'
assert_contains "${android_release}" 'create_credentials_file: false' 'Direct Google authentication must not write a credential file.'
assert_contains "${android_release}" 'export_environment_variables: false' 'Direct Google authentication must not export credential environment variables.'
assert_contains "${android_release}" 'google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093' 'Secret-bearing Google authentication must be pinned to the verified v3 commit.'
assert_contains "${ios_release}" 'SOURCE_PROVENANCE_SUPPORTED' 'Direct iOS delivery must fail without consumer provenance support.'
assert_contains "${ios_release}" 'SOURCE_SHA: ${{ inputs.source-sha }}' 'Both iOS Fastlane lanes must receive the source SHA.'
assert_contains "${ios_build}" 'build/ios/archive/*.xcarchive' 'Artifact-mode iOS uploads must retain the XCArchive.'
assert_contains "${ios_build}" "always() && inputs.cleanup-output == 'true'" 'Direct iOS validation must always clean signed outputs.'
assert_contains "${android_build}" "always() && inputs.cleanup-output == 'true'" 'Direct Android validation must always clean signed outputs.'
assert_contains "${ios_integration}" 'persist-credentials: false' 'Direct iOS release checkout must not persist Git credentials.'
assert_contains "${android_integration}" 'persist-credentials: false' 'Direct Android release checkout must not persist Git credentials.'
assert_contains "${ios_integration}" 'Remove direct iOS beta binaries' 'Direct iOS beta must clean local signed outputs.'
assert_contains "${android_integration}" 'Remove direct Android beta binaries' 'Direct Android beta must clean local signed outputs.'

echo 'Direct and artifact delivery contract checks passed.'
