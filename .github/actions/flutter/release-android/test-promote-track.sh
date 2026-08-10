#!/usr/bin/env bash

set -euo pipefail

action_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT
mkdir -p "${test_root}/bin" "${test_root}/runner"

cat > "${test_root}/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
method=GET
body=''
url=''
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --request) method="$2"; shift 2 ;;
    --header|--connect-timeout|--max-time) shift 2 ;;
    --data-binary) body="${2#@}"; shift 2 ;;
    --silent|--show-error|--fail-with-body) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\t%s\t%s\n' "${method}" "${url}" "${body:+body}" >> "${TEST_LOG}"
if [[ "${url}" == *':commit?'* && -n "${body}" ]]; then
  echo 'Commit request included a forbidden body.' >&2
  exit 90
fi
case "${method} ${url}" in
  POST\ */edits)
    count="$(($(cat "${TEST_EDIT_COUNT}" 2>/dev/null || printf 0) + 1))"
    printf '%s' "${count}" > "${TEST_EDIT_COUNT}"
    printf '{"id":"edit-%s"}\n' "${count}"
    ;;
  GET\ */tracks/alpha)
    if [[ "${TEST_FAIL_SOURCE_ALWAYS:-false}" == true ]]; then
      exit 22
    fi
    if [[ "${TEST_FAIL_SOURCE_ONCE:-false}" == true && ! -f "${TEST_FAILED_ONCE}" ]]; then
      touch "${TEST_FAILED_ONCE}"
      exit 22
    fi
    printf '%s\n' "${TEST_SOURCE}"
    ;;
  GET\ *edit-2/tracks/production)
    printf '%s\n' "${TEST_RECONCILED_PRODUCTION:-${TEST_PRODUCTION}}"
    ;;
  GET\ */tracks/production)
    printf '%s\n' "${TEST_PRODUCTION}"
    ;;
  PUT\ */tracks/production)
    if [[ "$(jq '[.releases[]? | select(.status == "completed")] | length' "${body}")" -ne 1 ]]; then
      printf '{"error":{"message":"Only one completed release is allowed."}}\n'
      exit 22
    fi
    cp "${body}" "${TEST_PUT_BODY}"
    cat "${body}"
    ;;
  POST\ *:commit*)
    if [[ "${TEST_COMMIT_FAIL:-false}" == true ]]; then exit 22; fi
    printf '{"id":"committed"}\n'
    ;;
  DELETE\ */edits/*) printf '{}\n' ;;
  *) echo "Unexpected request: ${method} ${url}" >&2; exit 91 ;;
esac
MOCK
chmod +x "${test_root}/bin/curl"

export PATH="${test_root}/bin:${PATH}"
export RUNNER_TEMP="${test_root}/runner"
export GOOGLE_PLAY_ACCESS_TOKEN=test
export PACKAGE_NAME=com.example.app
export SOURCE_TRACK=alpha
# These deliberately stale workflow values must not influence production selection.
export SOURCE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export VERSION_CODE=38
export PLAY_RETRY_DELAY_SECONDS=0
export TEST_LOG="${test_root}/requests.log"
export TEST_EDIT_COUNT="${test_root}/edit-count"
export TEST_FAILED_ONCE="${test_root}/failed-once"
export TEST_PUT_BODY="${test_root}/put.json"

reset_case() {
  rm -f -- "${TEST_LOG}" "${TEST_EDIT_COUNT}" "${TEST_FAILED_ONCE}" "${TEST_PUT_BODY}"
  unset TEST_COMMIT_FAIL TEST_FAIL_SOURCE_ONCE TEST_FAIL_SOURCE_ALWAYS TEST_RECONCILED_PRODUCTION
}

source_release='{"track":"alpha","releases":[{"name":"older-beta","versionCodes":["51"],"status":"completed"},{"name":"beta-latest","versionCodes":["49","52"],"status":"completed","releaseNotes":[{"language":"en-US","text":"Latest"}],"userFraction":0.4,"countryTargeting":{"countries":["CO"]}},{"name":"unfinished-newer","versionCodes":["99"],"status":"inProgress"}]}'
completed_production='{"track":"production","releases":[{"name":"previous","versionCodes":["50"],"status":"completed"}]}'

reset_case
export TEST_SOURCE="${source_release}" TEST_PRODUCTION="${completed_production}"
bash "${action_directory}/promote-track.sh"
jq -e '
  .releases | length == 1
  and .[0].versionCodes == ["50", "52"]
  and .[0].name == "beta-latest"
  and .[0].status == "completed"
  and .[0].releaseNotes[0].text == "Latest"
  and (.[0] | has("userFraction") | not)
  and (.[0] | has("countryTargeting") | not)
' "${TEST_PUT_BODY}" >/dev/null
grep -Fq 'changesInReviewBehavior=ERROR_IF_IN_REVIEW' "${TEST_LOG}"

reset_case
export TEST_SOURCE='{"track":"alpha","releases":[{"name":"unfinished","versionCodes":["53"],"status":"inProgress"},{"name":"invalid","versionCodes":["not-a-version"],"status":"completed"}]}' TEST_PRODUCTION="${completed_production}"
if bash "${action_directory}/promote-track.sh" >/dev/null 2>"${test_root}/no-completed.err"; then exit 1; fi
grep -Fq 'must contain at least one completed release' "${test_root}/no-completed.err"
grep -Fq $'DELETE\t' "${TEST_LOG}"

reset_case
export TEST_SOURCE="${source_release}" TEST_PRODUCTION='{"track":"production","releases":[{"name":"rollout","versionCodes":["51"],"status":"inProgress","userFraction":0.5}]}'
if bash "${action_directory}/promote-track.sh" >/dev/null 2>"${test_root}/rollout.err"; then exit 1; fi
grep -Fq 'refusing to overwrite an active rollout' "${test_root}/rollout.err"
if grep -Fq $'PUT\t' "${TEST_LOG}"; then exit 1; fi

reset_case
export TEST_SOURCE="${source_release}" TEST_PRODUCTION='{"track":"production","releases":[{"name":"renamed-in-production","versionCodes":["52"],"status":"completed"}]}'
bash "${action_directory}/promote-track.sh"
if grep -Eq $'PUT\t|:commit' "${TEST_LOG}"; then exit 1; fi

reset_case
export TEST_SOURCE="${source_release}" TEST_PRODUCTION='{"track":"production","releases":[{"name":"newer-production","versionCodes":["53"],"status":"completed"}]}'
if bash "${action_directory}/promote-track.sh" >/dev/null 2>"${test_root}/downgrade.err"; then exit 1; fi
grep -Fq 'already contains higher version code 53' "${test_root}/downgrade.err"
grep -Fq 'refusing to promote version code 52' "${test_root}/downgrade.err"
if grep -Fq $'PUT\t' "${TEST_LOG}"; then exit 1; fi

reset_case
export TEST_SOURCE="${source_release}" TEST_PRODUCTION="${completed_production}" TEST_FAIL_SOURCE_ONCE=true
bash "${action_directory}/promote-track.sh"
[[ "$(grep -Fc '/tracks/alpha' "${TEST_LOG}")" -eq 2 ]]

reset_case
export TEST_SOURCE="${source_release}" TEST_PRODUCTION="${completed_production}" TEST_FAIL_SOURCE_ALWAYS=true
if bash "${action_directory}/promote-track.sh" >/dev/null 2>"${test_root}/retry.err"; then exit 1; fi
[[ "$(grep -Fc '/tracks/alpha' "${TEST_LOG}")" -eq 3 ]]
grep -Fq $'DELETE\t' "${TEST_LOG}"

reset_case
export TEST_SOURCE="${source_release}" TEST_PRODUCTION="${completed_production}" TEST_COMMIT_FAIL=true
export TEST_RECONCILED_PRODUCTION='{"track":"production","releases":[{"name":"renamed-after-commit","versionCodes":["52"],"status":"completed"},{"name":"previous","versionCodes":["50"],"status":"completed"}]}'
bash "${action_directory}/promote-track.sh"

reset_case
export TEST_SOURCE="${source_release}" TEST_PRODUCTION="${completed_production}" TEST_COMMIT_FAIL=true
if bash "${action_directory}/promote-track.sh" >/dev/null 2>"${test_root}/reconcile.err"; then exit 1; fi
grep -Fq 'Unable to prove whether the Google Play production commit succeeded' "${test_root}/reconcile.err"
[[ "$(grep -Fc $'DELETE\t' "${TEST_LOG}")" -eq 2 ]]

echo 'Google Play production safety tests passed.'
