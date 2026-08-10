#!/usr/bin/env bash

set -euo pipefail

for variable_name in GOOGLE_PLAY_ACCESS_TOKEN PACKAGE_NAME SOURCE_TRACK; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "${variable_name} is required for direct Google Play promotion." >&2
    exit 1
  fi
done
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

if ! jq -e '
  [
    .releases[]?
    | select(.status == "completed") as $release
    | $release.versionCodes[]?
    | tostring
    | select(test("^[1-9][0-9]*$"))
    | {versionCode: ., release: $release}
  ]
  | if length == 0 then empty else max_by(.versionCode | tonumber) end
' "${temporary_directory}/source.json" > "${temporary_directory}/selected-source.json"; then
  echo "Testing track '${SOURCE_TRACK}' must contain at least one completed release with a positive numeric version code." >&2
  exit 1
fi
selected_version="$(jq -er '.versionCode' "${temporary_directory}/selected-source.json")"
selected_name="$(jq -r '.release.name // empty' "${temporary_directory}/selected-source.json")"

unsafe_production="$(jq '[.releases[]? | select(.status != "completed")] | length' "${temporary_directory}/production.json")"
if [[ "${unsafe_production}" -ne 0 ]]; then
  echo "Production contains ${unsafe_production} draft, inProgress, or halted release(s); refusing to overwrite an active rollout." >&2
  exit 1
fi
production_max_version="$(jq -r '
  [.releases[]?.versionCodes[]? | tostring | select(test("^[1-9][0-9]*$")) | tonumber]
  | if length == 0 then empty else max end
' "${temporary_directory}/production.json")"
if [[ -n "${production_max_version}" && "${production_max_version}" -gt "${selected_version}" ]]; then
  echo "Production already contains higher version code ${production_max_version}; refusing to promote version code ${selected_version}." >&2
  exit 1
fi
production_version_matches="$(jq --arg version "${selected_version}" '[.releases[]? | select(.status == "completed" and any(.versionCodes[]?; tostring == $version))] | length' "${temporary_directory}/production.json")"
if [[ "${production_version_matches}" -ne 0 ]]; then
  play_delete_edit "${edit_id}" "${temporary_directory}/delete.json"
  edit_finished=true
  echo "Google Play production already contains latest completed testing version code ${selected_version}."
  exit 0
fi

jq --arg version "${selected_version}" --slurpfile production "${temporary_directory}/production.json" '
  .release
  | .versionCodes = (
      [$version] + [$production[0].releases[]?.versionCodes[]? | tostring]
      | unique_by(tonumber)
    )
  | .status = "completed"
  | del(.userFraction, .countryTargeting)
  | {track: "production", releases: [.]}
' "${temporary_directory}/selected-source.json" > "${temporary_directory}/updated-track.json"
play_api_request PUT "${PLAY_API_BASE}/edits/${edit_id}/tracks/production" "${temporary_directory}/update.json" "${temporary_directory}/updated-track.json" true

if play_commit_edit "${edit_id}" "${temporary_directory}/commit.json"; then
  edit_finished=true
  echo "Promoted latest completed Google Play ${SOURCE_TRACK} version code ${selected_version}${selected_name:+ (${selected_name})} to production."
  exit 0
fi

echo 'Commit response was uncertain; reconciling production state.' >&2
reconcile_edit_id="$(play_create_edit "${temporary_directory}/reconcile-edit.json" "${temporary_directory}/empty.json")"
play_get_track "${reconcile_edit_id}" production "${temporary_directory}/reconciled-production.json"
reconciled_version_matches="$(jq --arg version "${selected_version}" '[.releases[]? | select(.status == "completed" and any(.versionCodes[]?; tostring == $version))] | length' "${temporary_directory}/reconciled-production.json")"
if [[ "${reconciled_version_matches}" -ne 0 ]]; then
  edit_finished=true
  echo "Reconciled committed Google Play version code ${selected_version}."
  exit 0
fi
echo 'Unable to prove whether the Google Play production commit succeeded.' >&2
exit 1
