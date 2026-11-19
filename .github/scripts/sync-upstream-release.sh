#!/usr/bin/env bash
# Sync the newest stable upstream release into this fork without rewriting fork automation.
set -euo pipefail

upstream_url="${UPSTREAM_URL:-https://github.com/decolua/9router.git}"
remote="${UPSTREAM_REMOTE:-upstream}"
git config user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
git config user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"

if ! git remote get-url "$remote" >/dev/null 2>&1; then
  git remote add "$remote" "$upstream_url"
fi

# Prefer tags over master: upstream may bump package.json only in the tag commit.
latest_tag="$(
  git ls-remote --tags --refs "$remote" 'refs/tags/v*' |
    awk '{print $2}' |
    sed 's#refs/tags/##' |
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' |
    sort -V | tail -n 1
)"
if [[ -z "$latest_tag" ]]; then
  echo "::error::No stable upstream release tag found" >&2
  exit 1
fi
version="${latest_tag#v}"
git fetch --no-tags "$remote" "refs/tags/$latest_tag:refs/tags/$latest_tag"
tag_commit="$(git rev-parse "$latest_tag^{commit}")"
tag_package_version="$(git show "$tag_commit:package.json" | node -e 'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>console.log(JSON.parse(s).version))')"
if [[ "$tag_package_version" != "$version" ]]; then
  echo "::error::Tag $latest_tag contains package.json version $tag_package_version, expected $version" >&2
  exit 1
fi

# Never silently blend incompatible upstream histories.
# A new release must descend from the last synced upstream commit; diverged
# release histories require manual review instead of an automatic merge.
if git merge-base --is-ancestor "$tag_commit" HEAD; then
  echo "Already contains $latest_tag"
else
  if ! git merge-base HEAD "$tag_commit" >/dev/null; then
    echo "::error::No common history with $latest_tag; manual review required" >&2
    exit 1
  fi
  if ! git merge --no-ff --no-commit "$tag_commit"; then
    mapfile -t conflicts < <(git diff --name-only --diff-filter=U)
    for path in "${conflicts[@]}"; do
      case "$path" in
        Dockerfile|.github/*) ;;
        *)
          echo "::error::Unresolved application conflict: $path" >&2
          git merge --abort || true
          exit 1
          ;;
      esac
    done
  fi

  # Keep both conflicting and cleanly merged fork-owned automation unchanged.
  git restore --source=HEAD --staged --worktree -- .github Dockerfile
  if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
    echo "::error::Unresolved conflicts remain" >&2
    git merge --abort || true
    exit 1
  fi
  git commit --no-edit
fi

actual_version="$(node -p 'require("./package.json").version')"
if [[ "$actual_version" != "$version" ]]; then
  echo "::error::Merged package version $actual_version != upstream release $version" >&2
  exit 1
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "version=$version" >> "$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "Synced upstream release $latest_tag (commit $tag_commit)." >> "$GITHUB_STEP_SUMMARY"
fi
echo "Release $latest_tag verified at $(git rev-parse HEAD)"
