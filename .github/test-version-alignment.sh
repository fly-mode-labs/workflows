#!/usr/bin/env bash

set -euo pipefail

repository='Juanpabedoyav/workflows'
version="v$(tr -d '[:space:]' < VERSION)"
major="${version%%.*}"

references="$({
  grep -RInE "uses:[[:space:]]+${repository}/\.github/actions/.+@[^[:space:]]+" \
    .github/actions .github/workflows || true
})"

mismatches="$(printf '%s\n' "${references}" | grep -vE "@${version}([[:space:]]|$)" || true)"
if [[ -n "${mismatches}" ]]; then
  echo "First-party composite action references must use immutable @${version}:" >&2
  printf '%s\n' "${mismatches}" >&2
  exit 1
fi

if grep -RInE 'uses:[[:space:]]+Juanpabedoyav/workflows/.github/workflows/' \
  .github/workflows; then
  echo 'Reusable workflows in this repository must use local paths so they stay on the caller commit.' >&2
  exit 1
fi

if ! grep -Fq "main.yml@${major}" templates/flutter/.github/workflows/main.yml; then
  echo "The Flutter caller template must use @${major}." >&2
  exit 1
fi

echo "First-party composite actions use ${version}; the caller template uses ${major}."
