#!/usr/bin/env bash

set -euo pipefail

repository='fly-mode-labs/workflows'

legacy_references="$(grep -RInE \
  '(Juanpabedoyav|juanpbedoya|YOUR_GITHUB_USER)/workflows' \
  .github templates README.md || true)"
if [[ -n "${legacy_references}" ]]; then
  echo "First-party workflow references must use ${repository}:" >&2
  printf '%s\n' "${legacy_references}" >&2
  exit 1
fi

references="$(grep -RInE \
  "uses:[[:space:]]+${repository}/[^[:space:]]+" \
  .github/actions .github/workflows templates || true)"

non_main_references="$(printf '%s\n' "${references}" | grep -vF '@main' || true)"
if [[ -z "${references}" || -n "${non_main_references}" ]]; then
  echo 'First-party workflow and action references must use @main:' >&2
  printf '%s\n' "${non_main_references}" >&2
  exit 1
fi

if ! grep -Fq 'main.yml@main' templates/flutter/.github/workflows/main.yml; then
  echo 'The Flutter caller template must use the shared main branch.' >&2
  exit 1
fi

workflow_references="$(grep -RhoE 'uses:[[:space:]]+fly-mode-labs/workflows/\.github/workflows/[^[:space:]]+' .github/workflows templates || true)"
unexpected_workflow_references="$(grep -vF '@main' <<< "${workflow_references}" || true)"
if [[ -z "${workflow_references}" || -n "${unexpected_workflow_references}" ]]; then
  echo 'Reusable workflows must use the shared main branch:' >&2
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

echo 'First-party workflow and action references use @main.'
