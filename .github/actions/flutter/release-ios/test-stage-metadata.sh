#!/usr/bin/env bash

set -euo pipefail

test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

export RUNNER_TEMP="${test_root}/runner"
export GITHUB_OUTPUT="${test_root}/github-output"
export APP_STORE_LOCALE='es-ES'
export APP_STORE_DESCRIPTION=$'Descripción completa\ncon segunda línea.'
export APP_STORE_KEYWORDS='entrenamiento,bienestar,fitness'
export APP_STORE_SUPPORT_URL='https://example.com/soporte'
export APP_STORE_RELEASE_NOTES='Mejoras y correcciones.'

mkdir -p "${RUNNER_TEMP}"
bash "$(dirname "${BASH_SOURCE[0]}")/stage-metadata.sh"

metadata_path="$(sed -n 's/^path=//p' "${GITHUB_OUTPUT}")"
[[ -d "${metadata_path}/es-ES" ]]
[[ "$(cat "${metadata_path}/es-ES/description.txt")" == "${APP_STORE_DESCRIPTION}" ]]
[[ "$(cat "${metadata_path}/es-ES/keywords.txt")" == "${APP_STORE_KEYWORDS}" ]]
[[ "$(cat "${metadata_path}/es-ES/support_url.txt")" == "${APP_STORE_SUPPORT_URL}" ]]
[[ "$(cat "${metadata_path}/es-ES/release_notes.txt")" == "${APP_STORE_RELEASE_NOTES}" ]]

if ruby -e 'require "deliver/upload_metadata"' >/dev/null 2>&1; then
  ruby - "${metadata_path}" <<'RUBY'
require "deliver/upload_metadata"

options = { skip_metadata: false, metadata_path: ARGV.fetch(0) }
Deliver::UploadMetadata.new(options).load_from_filesystem

expected = {
  description: "Descripción completa\ncon segunda línea.",
  keywords: "entrenamiento,bienestar,fitness",
  support_url: "https://example.com/soporte",
  release_notes: "Mejoras y correcciones."
}

expected.each do |key, value|
  raise "deliver did not load #{key}" unless options.dig(key, "es-ES") == value
end
RUBY
fi

echo 'App Store metadata staging tests passed.'
