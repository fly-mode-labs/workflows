#!/usr/bin/env bash

set -euo pipefail

action_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT
mkdir -p "${test_root}/bin" "${test_root}/runner"
touch "${test_root}/app.aab"

cat > "${test_root}/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
method=GET; body=''; content_type=''; url=''
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --request) method="$2"; shift 2 ;;
    --header) [[ "$2" == Content-Type:* ]] && content_type="$2"; shift 2 ;;
    --connect-timeout|--max-time) shift 2 ;;
    --data-binary) body="${2#@}"; shift 2 ;;
    --silent|--show-error|--fail-with-body) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\t%s\t%s\n' "${method}" "${url}" "${content_type}" >> "${TEST_LOG}"
case "${method} ${url}" in
  POST\ */edits) printf '{"id":"edit-1"}\n' ;;
  GET\ */tracks/internal) printf '%s\n' "${TEST_TRACK}" ;;
  POST\ *bundles*) printf '{"versionCode":47}\n' ;;
  PUT\ */tracks/internal) cp "${body}" "${TEST_PUT_BODY}"; cat "${body}" ;;
  POST\ *:commit*) [[ -z "${body}" ]] || exit 90; printf '{}\n' ;;
  DELETE\ */edits/*) printf '{}\n' ;;
  *) exit 91 ;;
esac
MOCK
chmod +x "${test_root}/bin/curl"

export PATH="${test_root}/bin:${PATH}" RUNNER_TEMP="${test_root}/runner"
export GOOGLE_PLAY_ACCESS_TOKEN=test PACKAGE_NAME=com.example.app SOURCE_TRACK=internal
export SOURCE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa VERSION_CODE=47 AAB_PATH="${test_root}/app.aab"
export PLAY_RETRY_DELAY_SECONDS=0 TEST_LOG="${test_root}/requests.log" TEST_PUT_BODY="${test_root}/put.json"

export TEST_TRACK='{"track":"internal","releases":[]}'
bash "${action_directory}/publish-beta.sh"
jq -e '.releases[0].name == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and .releases[0].versionCodes == ["47"]' "${TEST_PUT_BODY}" >/dev/null

: > "${TEST_LOG}"
export TEST_TRACK='{"track":"internal","releases":[{"name":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","versionCodes":["47"],"status":"completed"}]}'
bash "${action_directory}/publish-beta.sh"
if grep -Fq '/bundles' "${TEST_LOG}"; then exit 1; fi

: > "${TEST_LOG}"
export TEST_TRACK='{"track":"internal","releases":[{"name":"different","versionCodes":["47"],"status":"completed"}]}'
if bash "${action_directory}/publish-beta.sh" >/dev/null 2>"${test_root}/mismatch.err"; then exit 1; fi
grep -Fq 'different source provenance' "${test_root}/mismatch.err"

echo 'Google Play beta provenance and idempotency tests passed.'
