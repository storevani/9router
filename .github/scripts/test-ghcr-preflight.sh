#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ghcr-preflight.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != buildx || "${2:-}" != imagetools || "${3:-}" != inspect ]]; then
  echo "Unexpected docker command; test must never build or publish" >&2
  exit 88
fi
case "${MOCK_MODE:-matching}" in
  matching) printf '{"config":{"Labels":{"org.opencontainers.image.revision":"commit-good"}}}\n' ;;
  mismatched) printf '{"config":{"Labels":{"org.opencontainers.image.revision":"commit-old"}}}\n' ;;
  missing-version)
    if [[ "$4" == *:1.2.3 ]]; then
      echo 'manifest unknown' >&2
      exit 1
    fi
    printf '{"config":{"Labels":{"org.opencontainers.image.revision":"commit-good"}}}\n' ;;
  missing-latest)
    if [[ "$4" == *:latest ]]; then
      echo 'manifest unknown' >&2
      exit 1
    fi
    printf '{"config":{"Labels":{"org.opencontainers.image.revision":"commit-good"}}}\n' ;;
  unauthorized) echo '401 Unauthorized' >&2; exit 1 ;;
  forbidden) echo '403 Forbidden' >&2; exit 1 ;;
  ambiguous404) echo 'unexpected status 404 Not Found' >&2; exit 1 ;;
  connection) echo 'connection reset by peer' >&2; exit 1 ;;
  badjson) echo 'not-json' ;;
  *) echo "Unexpected mock mode" >&2; exit 89 ;;
esac
MOCK
chmod +x "$tmp/bin/docker"

check_success() {
  local mode="$1" expected="$2"
  : > "$tmp/output"
  if ! PATH="$tmp/bin:$PATH" GHCR_IMAGE=ghcr.io/storevani/9router VERSION=1.2.3 REVISION=commit-good MOCK_MODE="$mode" GITHUB_OUTPUT="$tmp/output" bash "$script" >"$tmp/log" 2>&1; then
    echo "FAIL: $mode unexpectedly rejected" >&2
    cat "$tmp/log" >&2
    exit 1
  fi
  grep -Fx "needed=$expected" "$tmp/output" >/dev/null || {
    echo "FAIL: $mode expected needed=$expected" >&2
    cat "$tmp/output" >&2
    exit 1
  }
  echo "PASS: $mode -> needed=$expected"
}

check_failure() {
  local mode="$1"
  : > "$tmp/output"
  if PATH="$tmp/bin:$PATH" GHCR_IMAGE=ghcr.io/storevani/9router VERSION=1.2.3 REVISION=commit-good MOCK_MODE="$mode" GITHUB_OUTPUT="$tmp/output" bash "$script" >"$tmp/log" 2>&1; then
    echo "FAIL: $mode unexpectedly allowed publication" >&2
    exit 1
  fi
  if [[ -s "$tmp/output" ]]; then
    echo "FAIL: $mode emitted build decision despite error" >&2
    exit 1
  fi
  echo "PASS: $mode rejected"
}

check_success matching false
check_success mismatched true
check_success missing-version true
check_success missing-latest true
check_failure unauthorized
check_failure forbidden
check_failure ambiguous404
check_failure connection
check_failure badjson
echo "GHCR preflight tests passed; no image was published."
