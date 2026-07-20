#!/usr/bin/env bash

set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${APP_STORE_LOCALE:?APP_STORE_LOCALE is required}"
: "${APP_STORE_DESCRIPTION:?APP_STORE_DESCRIPTION is required}"
: "${APP_STORE_KEYWORDS:?APP_STORE_KEYWORDS is required}"
: "${APP_STORE_SUPPORT_URL:?APP_STORE_SUPPORT_URL is required}"
: "${APP_STORE_RELEASE_NOTES:?APP_STORE_RELEASE_NOTES is required}"

if [[ ! "${APP_STORE_LOCALE}" =~ ^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$ ]]; then
  echo "APP_STORE_LOCALE contains unsupported path characters: ${APP_STORE_LOCALE}" >&2
  exit 1
fi

metadata_path="$(mktemp -d "${RUNNER_TEMP}/app-store-metadata.XXXXXX")"
locale_path="${metadata_path}/${APP_STORE_LOCALE}"
mkdir -p "${locale_path}"

printf '%s' "${APP_STORE_DESCRIPTION}" > "${locale_path}/description.txt"
printf '%s' "${APP_STORE_KEYWORDS}" > "${locale_path}/keywords.txt"
printf '%s' "${APP_STORE_SUPPORT_URL}" > "${locale_path}/support_url.txt"
printf '%s' "${APP_STORE_RELEASE_NOTES}" > "${locale_path}/release_notes.txt"

printf 'path=%s\n' "${metadata_path}" >> "${GITHUB_OUTPUT}"
