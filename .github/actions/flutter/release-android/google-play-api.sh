#!/usr/bin/env bash

play_api_initialize() {
  : "${GOOGLE_PLAY_ACCESS_TOKEN:?GOOGLE_PLAY_ACCESS_TOKEN is required}"
  : "${PACKAGE_NAME:?PACKAGE_NAME is required}"
  PLAY_CONNECT_TIMEOUT_SECONDS="${PLAY_CONNECT_TIMEOUT_SECONDS:-10}"
  PLAY_REQUEST_TIMEOUT_SECONDS="${PLAY_REQUEST_TIMEOUT_SECONDS:-60}"
  PLAY_UPLOAD_TIMEOUT_SECONDS="${PLAY_UPLOAD_TIMEOUT_SECONDS:-900}"
  PLAY_MAX_ATTEMPTS="${PLAY_MAX_ATTEMPTS:-3}"
  PLAY_RETRY_DELAY_SECONDS="${PLAY_RETRY_DELAY_SECONDS:-2}"
  PLAY_ENCODED_PACKAGE="$(jq -rn --arg value "${PACKAGE_NAME}" '$value | @uri')"
  PLAY_API_BASE="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PLAY_ENCODED_PACKAGE}"
  PLAY_UPLOAD_BASE="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${PLAY_ENCODED_PACKAGE}"
}

play_api_request() {
  local method="$1"
  local url="$2"
  local output_file="$3"
  local body_file="${4:-}"
  local retryable="${5:-true}"
  local attempt=1

  while true; do
    local arguments=(
      --silent --show-error --fail-with-body
      --connect-timeout "${PLAY_CONNECT_TIMEOUT_SECONDS}"
      --max-time "${PLAY_REQUEST_TIMEOUT_SECONDS}"
      --request "${method}"
      --header "Authorization: Bearer ${GOOGLE_PLAY_ACCESS_TOKEN}"
      --header 'Content-Type: application/json'
    )
    if [[ -n "${body_file}" ]]; then
      arguments+=(--data-binary "@${body_file}")
    fi
    if curl "${arguments[@]}" "${url}" > "${output_file}"; then
      return 0
    fi

    if [[ "${retryable}" != 'true' || "${attempt}" -ge "${PLAY_MAX_ATTEMPTS}" ]]; then
      local error_message
      error_message="$(jq -r '.error.message // empty' "${output_file}" 2>/dev/null || true)"
      echo "Android Publisher request failed after ${attempt} attempt(s): ${method} ${url}" >&2
      [[ -z "${error_message}" ]] || echo "Google Play: ${error_message}" >&2
      return 1
    fi
    sleep "$((PLAY_RETRY_DELAY_SECONDS * attempt))"
    attempt=$((attempt + 1))
  done
}

play_create_edit() {
  local output_file="$1"
  local empty_body_file="$2"
  play_api_request POST "${PLAY_API_BASE}/edits" "${output_file}" "${empty_body_file}" true || return 1
  jq -er '.id | select(type == "string" and length > 0)' "${output_file}"
}

play_get_track() {
  local edit_id="$1"
  local track="$2"
  local output_file="$3"
  local encoded_track
  encoded_track="$(jq -rn --arg value "${track}" '$value | @uri')"
  play_api_request GET "${PLAY_API_BASE}/edits/${edit_id}/tracks/${encoded_track}" "${output_file}" '' true
}

play_list_bundles() {
  local edit_id="$1"
  local output_file="$2"
  play_api_request GET "${PLAY_API_BASE}/edits/${edit_id}/bundles" "${output_file}" '' true
}

play_delete_edit() {
  local edit_id="$1"
  local output_file="$2"
  play_api_request DELETE "${PLAY_API_BASE}/edits/${edit_id}" "${output_file}" '' true
}

play_commit_edit() {
  local edit_id="$1"
  local output_file="$2"
  play_api_request POST "${PLAY_API_BASE}/edits/${edit_id}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW" "${output_file}" '' false
}

play_upload_bundle() {
  local edit_id="$1"
  local bundle_path="$2"
  local output_file="$3"
  local url="${PLAY_UPLOAD_BASE}/edits/${edit_id}/bundles?uploadType=media"

  if curl \
    --silent --show-error --fail-with-body \
    --connect-timeout "${PLAY_CONNECT_TIMEOUT_SECONDS}" \
    --max-time "${PLAY_UPLOAD_TIMEOUT_SECONDS}" \
    --request POST \
    --header "Authorization: Bearer ${GOOGLE_PLAY_ACCESS_TOKEN}" \
    --header 'Content-Type: application/octet-stream' \
    --data-binary "@${bundle_path}" \
    "${url}" > "${output_file}"; then
    return 0
  fi

  local error_message
  error_message="$(jq -r '.error.message // empty' "${output_file}" 2>/dev/null || true)"
  echo "Android Publisher bundle upload failed: POST ${url}" >&2
  [[ -z "${error_message}" ]] || echo "Google Play: ${error_message}" >&2
  return 1
}
