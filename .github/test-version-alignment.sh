#!/usr/bin/env bash

set -euo pipefail

repository='fly-mode-labs/workflows'
major="v$(cut -d. -f1 VERSION)"

legacy_references="$(grep -RInE \
  '(Juanpabedoyav|juanpbedoya|YOUR_GITHUB_USER)/workflows' \
  .github templates README.md || true)"
if [[ -n "${legacy_references}" ]]; then
  echo "First-party workflow references must use ${repository}:" >&2
  printf '%s\n' "${legacy_references}" >&2
  exit 1
fi

references="$({
  grep -RInE "uses:[[:space:]]+${repository}/.+@v[0-9]+([[:space:]]|$)" \
    .github/actions .github/workflows | grep '/.github/actions/' || true
})"

mismatches="$(printf '%s\n' "${references}" | grep -vE "@${major}([[:space:]]|$)" || true)"
if [[ -n "${mismatches}" ]]; then
  echo "First-party workflow references must use @${major}:" >&2
  printf '%s\n' "${mismatches}" >&2
  exit 1
fi

if ! grep -Fq 'main.yml@v4' templates/flutter/.github/workflows/main.yml; then
  echo 'The Flutter caller template must use the supported @v4 reusable workflow contract.' >&2
  exit 1
fi

workflow_references="$(grep -RhoE 'uses:[[:space:]]+fly-mode-labs/workflows/\.github/workflows/[^[:space:]]+' .github/workflows templates || true)"
unexpected_workflow_references="$(grep -vF '@v4' <<< "${workflow_references}" | grep -vF 'release-integration-app-store.yml@v5' || true)"
if [[ -z "${workflow_references}" || -n "${unexpected_workflow_references}" ]] ||
  ! grep -Fq 'release-integration-app-store.yml@v5' <<< "${workflow_references}"; then
  echo 'Central and Google Play reusable workflows must use @v4; retain the existing App Store @v5 route.' >&2
  printf '%s\n' "${unexpected_workflow_references}" >&2
  exit 1
fi

for pipeline in ci cd; do
  if ! grep -Eq "^[[:space:]]+${pipeline}:$" templates/flutter/.github/workflows/main.yml ||
    ! grep -Eq "^[[:space:]]+pipeline:[[:space:]]+${pipeline}$" templates/flutter/.github/workflows/main.yml; then
    echo "The Flutter caller template must define the ${pipeline} job and pipeline scope." >&2
    exit 1
  fi
done

if ! grep -Eq '^[[:space:]]+needs:[[:space:]]+ci$' templates/flutter/.github/workflows/main.yml; then
  echo 'The Flutter CD job must depend on CI.' >&2
  exit 1
fi

echo "Composite actions are aligned with ${major}; reusable workflow refs use the v4/v5 contracts."
