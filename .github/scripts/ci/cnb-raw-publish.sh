#!/usr/bin/env bash
# Publish build files as ordinary files in a CNB repository.
#
# CNB no longer offers a release API we can use for this workflow, and the
# manager only needs stable raw URLs plus a manifest. Every channel gets its
# own branch:
#
#   manager-ci/   rolling main build   (manifest.json + apks/<files>)
#   manager-dev/  rolling dev build
#   release-<tag>/ tagged release      (manifest.json + apks/<files>)
#   stable/       manifest pointing at the newest release-<tag> branch
#
# Rolling branches are replaced (force-pushed) so the repository never grows a
# binary blob per build; tagged branches are also replaceable on a workflow
# re-run. The stable branch only carries the manifest, so its asset URLs point
# at the corresponding release-<tag> branch.
#
# Required:
#   CNB_RAW_TOKEN          token with write access to CNB_RAW_REPO
#                          (CNB_TOKEN is accepted as a fallback)
#   CNB_RAW_BRANCH         branch to write (e.g. manager-ci)
#   CNB_RAW_TAG            tag/manifest identifier (e.g. manager-ci)
#   CNB_RAW_ASSETS_DIR     directory whose files are published
#
# Optional:
#   CNB_RAW_REPO           default sukisu-nova/Release
#   CNB_RAW_ASSET_BRANCH   branch used in asset URLs (default: CNB_RAW_BRANCH)
#   CNB_RAW_MANIFEST_ONLY  true = write only manifest.json (stable alias)
#   CNB_RAW_FORCE          true = replace the branch history (rolling builds)
#   CNB_RAW_NAME           manifest display name
#   CNB_RAW_BODY_FILE      markdown release notes
#   CNB_RAW_PRERELEASE     true/false
#   CNB_WEB                default https://cnb.cool
set -euo pipefail

# CNB_RAW_TOKEN lets the publication account differ from the account used for
# the internal artifact transport; CNB_TOKEN remains the fallback.
TOKEN="${CNB_RAW_TOKEN:-${CNB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  echo "CNB_RAW_TOKEN / CNB_TOKEN is not configured; skipping raw publish"
  exit 0
fi

REPO="${CNB_RAW_REPO:-sukisu-nova/Release}"
REPO="${REPO%.git}"
BRANCH="${CNB_RAW_BRANCH:?CNB_RAW_BRANCH is required}"
TAG="${CNB_RAW_TAG:?CNB_RAW_TAG is required}"
ASSETS="${CNB_RAW_ASSETS_DIR:?CNB_RAW_ASSETS_DIR is required}"
ASSET_BRANCH="${CNB_RAW_ASSET_BRANCH:-$BRANCH}"
MANIFEST_ONLY="${CNB_RAW_MANIFEST_ONLY:-false}"
FORCE="${CNB_RAW_FORCE:-false}"
WEB="${CNB_WEB:-https://cnb.cool}"
PRERELEASE="${CNB_RAW_PRERELEASE:-false}"

case "$PRERELEASE" in
true | false) ;;
*)
  echo "CNB_RAW_PRERELEASE must be true or false" >&2
  exit 1
  ;;
esac
case "$MANIFEST_ONLY" in true | false) ;; *) echo "CNB_RAW_MANIFEST_ONLY must be true or false" >&2; exit 1 ;; esac
case "$FORCE" in true | false) ;; *) echo "CNB_RAW_FORCE must be true or false" >&2; exit 1 ;; esac

test -d "$ASSETS" || {
  echo "asset directory missing: ${ASSETS}" >&2
  exit 1
}

repo_url="${WEB%/}/${REPO}.git"
work="$(mktemp -d)"
askpass="$(mktemp)"
trap 'rm -rf "$work" "$askpass" 2>/dev/null || true' EXIT

# The token never appears in a command line or in a git URL. CNB accepts the
# literal user name `cnb` and the access token as the password.
cat >"$askpass" <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' cnb ;;
  *) printf '%s\n' "$CNB_TOKEN" ;;
esac
EOF
chmod 700 "$askpass"

export CNB_TOKEN="$TOKEN"
export GIT_ASKPASS="$askpass"
export GIT_TERMINAL_PROMPT=0
export GIT_LFS_SKIP_SMUDGE=1

git init -q "$work"
git -C "$work" config user.name "SukiSU CI"
git -C "$work" config user.email "ci@sukisu.local"
git -C "$work" remote add origin "$repo_url"

if git -C "$work" fetch --quiet --depth 1 origin "refs/heads/$BRANCH"; then
  git -C "$work" checkout -q -B "$BRANCH" FETCH_HEAD
else
  git -C "$work" checkout -q --orphan "$BRANCH"
fi

# A branch is a complete snapshot of the channel, not a growing archive. `git
# rm` removes both the index entry and the work-tree file, so the next commit
# does not carry the previous build's APKs.
git -C "$work" rm -rf . >/dev/null 2>&1 || true

if [ "$MANIFEST_ONLY" != "true" ]; then
  mkdir -p "$work/apks"
  cp -a "$ASSETS"/. "$work/apks"/
fi

manifest_args=(
  --assets-dir "$ASSETS"
  --repo "$REPO"
  --asset-branch "$ASSET_BRANCH"
  --base-url "$WEB"
  --tag "$TAG"
  --name "${CNB_RAW_NAME:-$TAG}"
  --body-file "${CNB_RAW_BODY_FILE:-}"
  --output "$work/manifest.json"
)
# An array, not `$( ... )`: a command substitution here would be word-split, and
# an unset PRERELEASE would leave an empty argument behind.
if [ "$PRERELEASE" = "true" ]; then
  manifest_args+=(--prerelease)
fi

python3 "$(dirname "$0")/cnb-raw-manifest.py" "${manifest_args[@]}"

git -C "$work" add -A
git -C "$work" commit -q -m "publish ${TAG}"

refspec="HEAD:refs/heads/$BRANCH"
if [ "$FORCE" = "true" ]; then
  git -C "$work" push --quiet --force origin "$refspec"
else
  git -C "$work" push --quiet origin "$refspec"
fi

base="${WEB%/}/${REPO}/-/git/raw/${BRANCH}"
echo "CNB raw publish complete: ${REPO} ${BRANCH}"
echo "manifest: ${base}/manifest.json"
if [ "$MANIFEST_ONLY" != "true" ]; then
  echo "assets:   ${base}/apks/"
fi
