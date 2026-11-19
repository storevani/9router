#!/usr/bin/env bash
# Inspect GHCR tags before updating master. This script never writes to GHCR.
set -euo pipefail

: "${GHCR_IMAGE:?GHCR_IMAGE must be set}"
: "${VERSION:?VERSION must be set}"
: "${REVISION:?REVISION must be set}"

inspect_revision() {
  local reference="$1" error_file output result
  error_file="$(mktemp)"
  if output="$(docker buildx imagetools inspect "$reference" --format '{{json .Image}}' 2>"$error_file")"; then
    rm -f "$error_file"
    if ! result="$(jq -er '.config.Labels["org.opencontainers.image.revision"] // ""' <<< "$output")"; then
      echo "::error::Invalid image metadata from $reference" >&2
      return 1
    fi
    printf '%s\n' "$result"
  else
    # Be conservative: a bare 404 can hide inaccessible packages. Only recognize
    # registry-specific missing-manifest errors, never auth/network failures.
    if grep -Eqi 'manifest unknown|manifest[^[:cntrl:]]*not found|name unknown' "$error_file" &&
      ! grep -Eqi '401|403|unauthorized|denied|forbidden|timeout|tls|connection' "$error_file"; then
      echo "No manifest at $reference; build required." >&2
      rm -f "$error_file"
      printf '\n'
    else
      echo "::error::Cannot reliably inspect $reference; refusing to continue" >&2
      cat "$error_file" >&2
      rm -f "$error_file"
      return 1
    fi
  fi
}

current_latest="$(inspect_revision "${GHCR_IMAGE}:latest")"
current_version="$(inspect_revision "${GHCR_IMAGE}:${VERSION}")"
if [[ -n "$current_latest" && "$current_latest" == "$REVISION" && "$current_version" == "$REVISION" ]]; then
  needed=false
else
  needed=true
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "needed=$needed" >> "$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "GHCR preflight: latest and ${VERSION}; build needed: $needed" >> "$GITHUB_STEP_SUMMARY"
fi
echo "GHCR_BUILD_NEEDED=$needed"
