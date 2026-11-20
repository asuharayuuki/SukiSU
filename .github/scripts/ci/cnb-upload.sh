#!/usr/bin/env bash
# Upload a release bundle to CNB (cnb.cool) through its OpenAPI.
#
# Required environment:
#   CNB_TOKEN       access token with repo-release:rw (and repo-contents:rw for
#                   creating the tag/release in a repository that has none)
#   CNB_TAG         release tag, e.g. manager-ci or v3.0.0
#   CNB_ASSETS_DIR  directory whose files become release assets
# Optional:
#   CNB_REPO                 default shirkneko/sukisu-result
#   CNB_API                  default https://api.cnb.cool
#   CNB_NAME                 default CNB_TAG
#   CNB_BODY_FILE            release notes
#   CNB_PRERELEASE           true/false, default false
#   CNB_MAKE_LATEST          true/false, default false
#   CNB_TARGET_COMMITISH     branch/commit for a new tag, default main
#   CNB_ASSET_PREFIX         optional asset name prefix
#   CNB_CLEAR_ASSETS         true/false, default true; false keeps existing assets
set -euo pipefail

if [ -z "${CNB_TOKEN:-}" ]; then
  echo "CNB_TOKEN is not configured; skipping CNB upload"
  exit 0
fi

TAG="${CNB_TAG:?CNB_TAG is required}"
NAME="${CNB_NAME:-$TAG}"
ASSETS="${CNB_ASSETS_DIR:?CNB_ASSETS_DIR is required}"
BODY_FILE="${CNB_BODY_FILE:-}"
PRERELEASE="${CNB_PRERELEASE:-false}"
MAKE_LATEST="${CNB_MAKE_LATEST:-false}"
TARGET_COMMITISH="${CNB_TARGET_COMMITISH:-main}"
PREFIX="${CNB_ASSET_PREFIX:-}"

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
test -d "$ASSETS" || { echo "asset directory missing: $ASSETS" >&2; exit 1; }

# The API calls live in cnb.sh, shared with the artifact transport in common.sh.
# shellcheck disable=SC1091  # path is computed from $0; cnb.sh is checked alone
. "$(dirname "$0")/cnb.sh"

BODY=""
[ -n "$BODY_FILE" ] && [ -f "$BODY_FILE" ] && BODY="$(cat "$BODY_FILE")"

release_id="$(cnb_release_ensure "$TAG" "$NAME" "$TARGET_COMMITISH" "$BODY" \
  "$PRERELEASE" "$MAKE_LATEST")"
echo "CNB release ${TAG} id=${release_id}"

# Re-runs replace the previous content instead of piling up assets.
if [ "${CNB_CLEAR_ASSETS:-true}" != "false" ]; then
  cnb_clear_assets "$TAG"
fi

echo "uploading CNB assets from ${ASSETS}"
find "$ASSETS" -type f -print0 | sort -z | while IFS= read -r -d '' file; do
  rel="${file#"$ASSETS"/}"
  # Subdirectories are flattened with __ so every asset name stays one segment.
  asset="${PREFIX}${rel//\//__}"
  size="$(wc -c <"$file" | tr -d ' ')"
  cnb_asset_put "$file" "$asset" "$release_id"
  echo "uploaded ${asset} (${size} bytes)"
done

# Keep the title and body in step with the build even when the release already
# existed; the app parses the version out of the name.
if [ "$NAME" != "$TAG" ] || [ -n "$BODY_FILE" ]; then
  cnb_release_patch "$TAG" "$NAME" "$BODY" "$PRERELEASE" "$MAKE_LATEST"
fi

echo "CNB upload complete: ${TAG}"
