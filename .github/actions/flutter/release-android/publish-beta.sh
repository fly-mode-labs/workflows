#!/usr/bin/env bash

set -euo pipefail

for variable_name in GOOGLE_PLAY_ACCESS_TOKEN PACKAGE_NAME SOURCE_TRACK SOURCE_SHA VERSION_CODE AAB_PATH; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "${variable_name} is required for direct Google Play beta delivery." >&2
    exit 1
  fi
done
[[ "${SOURCE_SHA}" =~ ^[0-9a-f]{40}$ ]] || { echo 'SOURCE_SHA must be an exact 40-character commit SHA.' >&2; exit 1; }
[[ "${VERSION_CODE}" =~ ^[1-9][0-9]*$ ]] || { echo 'VERSION_CODE must be positive and numeric.' >&2; exit 1; }
[[ -f "${AAB_PATH}" ]] || { echo "App Bundle not found: ${AAB_PATH}" >&2; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/google-play-api.sh"
play_api_initialize
temporary_directory="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/google-play-beta.XXXXXX")"
edit_id=''
edit_finished=false
cleanup() {
  local status=$?
  if [[ -n "${edit_id}" && "${edit_finished}" != 'true' ]]; then
    play_delete_edit "${edit_id}" "${temporary_directory}/delete.json" >/dev/null 2>&1 || true
  fi
  rm -rf -- "${temporary_directory}"
  exit "${status}"
}
trap cleanup EXIT

printf '{}\n' > "${temporary_directory}/empty.json"
edit_id="$(play_create_edit "${temporary_directory}/edit.json" "${temporary_directory}/empty.json")"
play_get_track "${edit_id}" "${SOURCE_TRACK}" "${temporary_directory}/track.json"

version_matches="$(jq --arg version "${VERSION_CODE}" '[.releases[]? | select(any(.versionCodes[]?; tostring == $version))] | length' "${temporary_directory}/track.json")"
exact_matches="$(jq --arg version "${VERSION_CODE}" --arg source "${SOURCE_SHA}" '[.releases[]? | select(.status == "completed" and .name == $source and any(.versionCodes[]?; tostring == $version))] | length' "${temporary_directory}/track.json")"
if [[ "${exact_matches}" -eq 1 ]]; then
  play_delete_edit "${edit_id}" "${temporary_directory}/delete.json"
  edit_finished=true
  echo "Google Play beta already contains version code ${VERSION_CODE} for source ${SOURCE_SHA}."
  exit 0
fi

play_list_bundles "${edit_id}" "${temporary_directory}/bundles.json"
bundle_version_matches="$(jq --arg version "${VERSION_CODE}" '[.bundles[]? | select(.versionCode | tostring == $version)] | length' "${temporary_directory}/bundles.json")"
if [[ "${bundle_version_matches}" -ne 0 ]]; then
  if [[ "${version_matches}" -ne 0 ]]; then
    echo "Google Play track '${SOURCE_TRACK}' already contains version code ${VERSION_CODE} with different source provenance. Increment the application build number before publishing another beta." >&2
  else
    echo "Google Play already contains App Bundle version code ${VERSION_CODE}. Increment the application build number before publishing another beta." >&2
  fi
  exit 1
fi
if [[ "${version_matches}" -ne 0 ]]; then
  echo "Google Play track '${SOURCE_TRACK}' already contains version code ${VERSION_CODE} with different source provenance. Increment the application build number before publishing another beta." >&2
  exit 1
fi

play_upload_bundle "${edit_id}" "${AAB_PATH}" "${temporary_directory}/bundle.json"
uploaded_version="$(jq -er '.versionCode | tostring' "${temporary_directory}/bundle.json")"
if [[ "${uploaded_version}" != "${VERSION_CODE}" ]]; then
  echo "Uploaded App Bundle version code ${uploaded_version} does not match expected ${VERSION_CODE}." >&2
  exit 1
fi

jq -n --arg track "${SOURCE_TRACK}" --arg source "${SOURCE_SHA}" --arg version "${VERSION_CODE}" \
  '{track: $track, releases: [{name: $source, versionCodes: [$version], status: "completed"}]}' \
  > "${temporary_directory}/updated-track.json"
encoded_track="$(jq -rn --arg value "${SOURCE_TRACK}" '$value | @uri')"
play_api_request PUT "${PLAY_API_BASE}/edits/${edit_id}/tracks/${encoded_track}" "${temporary_directory}/update.json" "${temporary_directory}/updated-track.json" true

if ! play_commit_edit "${edit_id}" "${temporary_directory}/commit.json"; then
  echo 'Google Play beta commit response was uncertain; a subsequent run will reconcile by exact version and source SHA.' >&2
  exit 1
fi
edit_finished=true
echo "Published Google Play beta version code ${VERSION_CODE} for source ${SOURCE_SHA}."
