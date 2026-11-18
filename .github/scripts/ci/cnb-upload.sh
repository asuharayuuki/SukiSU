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
#   CNB_BODY_FILE            release notes (also copied as an asset)
#   CNB_PRERELEASE           true/false, default false
#   CNB_MAKE_LATEST          true/false, default false
#   CNB_TARGET_COMMITISH     branch/commit for a new tag, default main
#   CNB_ASSET_PREFIX         optional asset name prefix
set -euo pipefail

if [ -z "${CNB_TOKEN:-}" ]; then
  echo "CNB_TOKEN is not configured; skipping CNB upload"
  exit 0
fi

API="${CNB_API:-https://api.cnb.cool}"
REPO="${CNB_REPO:-shirkneko/sukisu-result}"
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

BODY=""
[ -n "$BODY_FILE" ] && [ -f "$BODY_FILE" ] && BODY="$(cat "$BODY_FILE")"

AUTH=(-H "Authorization: Bearer ${CNB_TOKEN}" -H "Accept: application/vnd.cnb.api+json")
BASE="${API}/${REPO}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

release_json="$WORK/release.json"
release_url="${BASE}/-/releases/tags/${TAG}"
status="$(curl -sS --connect-timeout 10 --max-time 60 -o "$release_json" \
  -w '%{http_code}' "${AUTH[@]}" "$release_url" || true)"
echo "CNB release ${TAG}: HTTP ${status}"

release_id=""
if [ "$status" = "200" ]; then
  release_id="$(jq -r '.id // empty' "$release_json")"
  echo "CNB release existing id=${release_id}"
else
  create_payload="$(jq -nc \
    --arg tag "$TAG" --arg target "$TARGET_COMMITISH" --arg name "$NAME" \
    --arg body "$BODY" --arg latest "$MAKE_LATEST" \
    --argjson pre "$PRERELEASE" \
    '{tag_name:$tag,target_commitish:$target,name:$name,body:$body,
      draft:false,prerelease:$pre,make_latest:$latest}')"
  status="$(curl -sS --connect-timeout 10 --max-time 60 -o "$release_json" \
    -w '%{http_code}' "${AUTH[@]}" -H 'Content-Type: application/json' \
    -X POST -d "$create_payload" "${BASE}/-/releases" || true)"
  echo "CNB release create: HTTP ${status}"
  release_id="$(jq -r '.id // empty' "$release_json" 2>/dev/null || true)"
  if [ -z "$release_id" ]; then
    # A concurrent run may have created it first.
    curl -sS --connect-timeout 10 --max-time 60 "${AUTH[@]}" \
      "$release_url" -o "$release_json"
    release_id="$(jq -r '.id // empty' "$release_json" 2>/dev/null || true)"
  fi
fi
test -n "$release_id" && [ "$release_id" != "null" ] || {
  echo "could not resolve CNB release id" >&2
  head -c 500 "$release_json" >&2 || true
  exit 1
}

if [ "$status" = "200" ] || [ -n "${BODY_FILE:-}" ] || [ "$NAME" != "$TAG" ]; then
  patch_payload="$(jq -nc --arg name "$NAME" --arg body "$BODY" \
    --arg latest "$MAKE_LATEST" --argjson pre "$PRERELEASE" \
    '{name:$name,body:$body,prerelease:$pre,make_latest:$latest}')"
  code="$(curl -sS --connect-timeout 10 --max-time 60 -o "$WORK/patch.json" \
    -w '%{http_code}' "${AUTH[@]}" -H 'Content-Type: application/json' \
    -X PATCH -d "$patch_payload" "${BASE}/-/releases/${release_id}" || true)"
  echo "CNB release update: HTTP ${code}"
  [ "$code" = "200" ] || {
    head -c 500 "$WORK/patch.json" >&2 || true
    exit 1
  }
fi

if [ "${CNB_CLEAR_ASSETS:-true}" != "false" ]; then
  echo "clearing existing CNB release assets"
  curl -sS --connect-timeout 10 --max-time 60 "${AUTH[@]}" \
    "${BASE}/-/releases/${release_id}" -o "$release_json"
  for asset_id in $(jq -r '.assets[]?.id' "$release_json"); do
    code="$(curl -sS --connect-timeout 10 --max-time 60 -o /dev/null \
      -w '%{http_code}' "${AUTH[@]}" \
      -X DELETE "${BASE}/-/releases/${release_id}/assets/${asset_id}" || true)"
    case "$code" in
      200|204|404) ;;
      *) echo "failed to delete CNB asset ${asset_id}: HTTP ${code}" >&2; exit 1 ;;
    esac
  done
fi

upload_one() {
  local file="$1" rel name size url_json upload_url verify_url code
  rel="${file#"$ASSETS"/}"
  name="${PREFIX}${rel//\//__}"
  size="$(stat -c%s "$file")"
  url_json="$WORK/upload-url.json"
  code="$(curl -sS --connect-timeout 10 --max-time 60 -o "$url_json" \
    -w '%{http_code}' "${AUTH[@]}" -H 'Content-Type: application/json' \
    -X POST -d "$(jq -nc --arg name "$name" --argjson size "$size" \
      '{asset_name:$name,size:$size,overwrite:true}')" \
    "${BASE}/-/releases/${release_id}/asset-upload-url" || true)"
  [ "$code" = "201" ] || [ "$code" = "200" ] || {
    echo "upload-url failed for ${name}: HTTP ${code}" >&2
    head -c 500 "$url_json" >&2 || true
    return 1
  }
  upload_url="$(jq -r '.upload_url // empty' "$url_json")"
  verify_url="$(jq -r '.verify_url // empty' "$url_json")"
  test -n "$upload_url" && test -n "$verify_url" || {
    echo "upload URL missing for ${name}" >&2
    return 1
  }
  curl -fsS --retry 4 --retry-all-errors --connect-timeout 20 --max-time 3600 \
    -X PUT -H 'Content-Type: application/octet-stream' \
    --data-binary @"$file" "$upload_url" >/dev/null
  case "$verify_url" in
    http://* | https://*) ;;
    *) verify_url="${API}${verify_url}" ;;
  esac
  code="$(curl -sS --connect-timeout 10 --max-time 120 -o "$WORK/verify.json" \
    -w '%{http_code}' "${AUTH[@]}" -X POST "$verify_url" || true)"
  [ "$code" = "200" ] || [ "$code" = "201" ] || {
    echo "verify failed for ${name}: HTTP ${code}" >&2
    head -c 500 "$WORK/verify.json" >&2 || true
    return 1
  }
  echo "uploaded ${name} (${size} bytes)"
}

echo "uploading CNB assets from ${ASSETS}"
while IFS= read -r -d '' file; do
  upload_one "$file"
done < <(find "$ASSETS" -type f -print0 | sort -z)
echo "CNB upload complete: ${TAG}"
