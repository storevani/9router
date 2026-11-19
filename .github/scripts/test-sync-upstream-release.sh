#!/usr/bin/env bash
# Negative tests: do not mutate branches, publish packages, or use credentials.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sync-upstream-release.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
upstream="$tmp/upstream"
fork="$tmp/fork"

write_version() {
  printf '{"name":"sync-test","version":"%s"}\n' "$2" > "$1/package.json"
}
commit_version() {
  write_version "$1" "$2"
  git -C "$1" add package.json
  git -C "$1" commit -qm "Version $2"
}

git init -q -b master "$upstream"
git -C "$upstream" config user.name "CI Test"
git -C "$upstream" config user.email "ci@example.invalid"
mkdir -p "$upstream/.github/workflows"
printf 'name: fork fixture\n' > "$upstream/.github/workflows/fixture.yml"
printf 'FROM scratch\n' > "$upstream/Dockerfile"
write_version "$upstream" "1.0.0"
git -C "$upstream" add .
git -C "$upstream" commit -qm "Initial release"
git -C "$upstream" tag v1.0.0

commit_version "$upstream" "1.1.0"
git -C "$upstream" tag v1.1.0

# Higher tag that shares an older ancestor but does not descend from v1.1.0.
git -C "$upstream" checkout -qb separate-release v1.0.0
commit_version "$upstream" "2.0.0"
git -C "$upstream" tag v2.0.0

git clone -q -b master "$upstream" "$fork"
git -C "$fork" config user.name "CI Test"
git -C "$fork" config user.email "ci@example.invalid"

expect_rejection() {
  local label="$1" expected="$2"
  local before after
  before="$(git -C "$fork" rev-parse HEAD)"
  if (cd "$fork" && UPSTREAM_URL="$upstream" GITHUB_OUTPUT= GITHUB_STEP_SUMMARY= bash "$script") > "$tmp/attempt.log" 2>&1; then
    echo "FAIL: $label unexpectedly succeeded" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$tmp/attempt.log"; then
    echo "FAIL: $label did not produce the expected error '$expected'" >&2
    cat "$tmp/attempt.log" >&2
    exit 1
  fi
  after="$(git -C "$fork" rev-parse HEAD)"
  test "$before" = "$after" || { echo "FAIL: $label changed HEAD" >&2; exit 1; }
  test -z "$(git -C "$fork" status --porcelain)" || { echo "FAIL: $label left working changes" >&2; exit 1; }
  echo "PASS: $label"
}

expect_rejection "divergent release" "does not descend from previous release v1.1.0"

commit_version "$fork" "3.0.0"
expect_rejection "version downgrade" "Refusing to downgrade from v3.0.0 to v2.0.0"

git -C "$fork" checkout -qb invalid-anchor v1.0.0
commit_version "$fork" "1.1.0"
expect_rejection "fork version without release ancestry" "Fork HEAD does not contain previous release v1.1.0"

echo "All negative ancestry tests passed."
