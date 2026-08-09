#!/usr/bin/env bash

set -euo pipefail

for variable_name in GOOGLE_PLAY_ACCESS_TOKEN PACKAGE_NAME SOURCE_TRACK SOURCE_SHA VERSION_CODE; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "${variable_name} is required for direct Google Play promotion." >&2
    exit 1
  fi
done
[[ "${SOURCE_SHA}" =~ ^[0-9a-f]{40}$ ]] || { echo 'SOURCE_SHA must be an exact 40-character commit SHA.' >&2; exit 1; }
[[ "${VERSION_CODE}" =~ ^[1-9][0-9]*$ ]] || { echo 'VERSION_CODE must be positive and numeric.' >&2; exit 1; }
[[ "${SOURCE_TRACK}" != 'production' ]] || { echo 'The testing track must not be production.' >&2; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/google-play-api.sh"
play_api_initialize
temporary_directory="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/google-play-promotion.XXXXXX")"
edit_id=''
reconcile_edit_id=''
edit_finished=false
cleanup() {
  local status=$?
  if [[ -n "${edit_id}" && "${edit_finished}" != 'true' ]]; then
    play_delete_edit "${edit_id}" "${temporary_directory}/delete.json" >/dev/null 2>&1 || true
  fi
  if [[ -n "${reconcile_edit_id}" ]]; then
    play_delete_edit "${reconcile_edit_id}" "${temporary_directory}/reconcile-delete.json" >/dev/null 2>&1 || true
  fi
  rm -rf -- "${temporary_directory}"
  exit "${status}"
}
trap cleanup EXIT

printf '{}\n' > "${temporary_directory}/empty.json"
edit_id="$(play_create_edit "${temporary_directory}/edit.json" "${temporary_directory}/empty.json")"
play_get_track "${edit_id}" "${SOURCE_TRACK}" "${temporary_directory}/source.json"
play_get_track "${edit_id}" production "${temporary_directory}/production.json"

version_matches="$(jq --arg version "${VERSION_CODE}" '[.releases[]? | select(.status == "completed" and any(.versionCodes[]?; tostring == $version))] | length' "${temporary_directory}/source.json")"
exact_matches="$(jq --arg version "${VERSION_CODE}" --arg source "${SOURCE_SHA}" '[.releases[]? | select(.status == "completed" and .name == $source and any(.versionCodes[]?; tostring == $version))] | length' "${temporary_directory}/source.json")"
if [[ "${version_matches}" -ne 1 || "${exact_matches}" -ne 1 ]]; then
  echo "Testing track '${SOURCE_TRACK}' must contain exactly one completed release for version code ${VERSION_CODE} named ${SOURCE_SHA}; version matches=${version_matches}, provenance matches=${exact_matches}." >&2
  exit 1
fi
jq --arg version "${VERSION_CODE}" --arg source "${SOURCE_SHA}" \
  '[.releases[]? | select(.status == "completed" and .name == $source and any(.versionCodes[]?; tostring == $version))][0]' \
  "${temporary_directory}/source.json" > "${temporary_directory}/selected-source.json"

unsafe_production="$(jq '[.releases[]? | select(.status != "completed")] | length' "${temporary_directory}/production.json")"
if [[ "${unsafe_production}" -ne 0 ]]; then
  echo "Production contains ${unsafe_production} draft, inProgress, or halted release(s); refusing to overwrite an active rollout." >&2
  exit 1
fi
production_version_matches="$(jq --arg version "${VERSION_CODE}" '[.releases[]? | select(any(.versionCodes[]?; tostring == $version))] | length' "${temporary_directory}/production.json")"
production_exact_matches="$(jq --arg version "${VERSION_CODE}" --arg source "${SOURCE_SHA}" '[.releases[]? | select(.status == "completed" and .name == $source and any(.versionCodes[]?; tostring == $version))] | length' "${temporary_directory}/production.json")"
if [[ "${production_exact_matches}" -eq 1 ]]; then
  play_delete_edit "${edit_id}" "${temporary_directory}/delete.json"
  edit_finished=true
  echo "Google Play production already contains version code ${VERSION_CODE} for source ${SOURCE_SHA}."
  exit 0
fi
if [[ "${production_version_matches}" -ne 0 ]]; then
  echo "Production already contains version code ${VERSION_CODE} with different source provenance." >&2
  exit 1
fi

jq --arg version "${VERSION_CODE}" --arg source "${SOURCE_SHA}" --slurpfile production "${temporary_directory}/production.json" '
  .releases[0]
  | .versionCodes = [$version]
  | .name = $source
  | .status = "completed"
  | del(.userFraction, .countryTargeting)
  | {track: "production", releases: ([.] + ($production[0].releases // []))}
' "${temporary_directory}/selected-source.json" > "${temporary_directory}/updated-track.json"
play_api_request PUT "${PLAY_API_BASE}/edits/${edit_id}/tracks/production" "${temporary_directory}/update.json" "${temporary_directory}/updated-track.json" true

if play_commit_edit "${edit_id}" "${temporary_directory}/commit.json"; then
  edit_finished=true
  echo "Promoted Google Play version code ${VERSION_CODE} for source ${SOURCE_SHA} to production."
  exit 0
fi

echo 'Commit response was uncertain; reconciling production state.' >&2
reconcile_edit_id="$(play_create_edit "${temporary_directory}/reconcile-edit.json" "${temporary_directory}/empty.json")"
play_get_track "${reconcile_edit_id}" production "${temporary_directory}/reconciled-production.json"
reconciled_exact="$(jq --arg version "${VERSION_CODE}" --arg source "${SOURCE_SHA}" '[.releases[]? | select(.status == "completed" and .name == $source and any(.versionCodes[]?; tostring == $version))] | length' "${temporary_directory}/reconciled-production.json")"
if [[ "${reconciled_exact}" -eq 1 ]]; then
  edit_finished=true
  echo "Reconciled committed Google Play version code ${VERSION_CODE} for source ${SOURCE_SHA}."
  exit 0
fi
echo 'Unable to prove whether the Google Play production commit succeeded.' >&2
exit 1
