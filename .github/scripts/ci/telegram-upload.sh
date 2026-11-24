#!/usr/bin/env bash
# Deliver this build's APKs to Telegram, at most once per build.
#
# Runs on the runner, where the signed split APKs already are, so the bytes never
# travel through CNB: the old path triggered a CNB build per publish, pulled the
# assets back out of the release and relayed them to Telegram, which is exactly
# the traffic pattern that got the artifact repository removed.
#
# A delivery failure must not fail the publish (the artifacts are already
# published); the callers mark the step continue-on-error. The marker keeps a
# re-run of the same build from posting twice, even though a re-run rebuilds it.
#
# Env:
#   TELEGRAM_APK_DIR  directory holding the *.apk to send (required)
#   TITLE             e.g. "Manager CI" or "Release" (required)
#   MESSAGE_THREAD_ID topic id; empty posts to the main thread
#   BOT_TOKEN CHAT_ID required; the script exits quietly when either is missing
#   TG_API_BASE       Bot API base, normally the proxy (default api.telegram.org)
#   VERSION BRANCH RUN_URL COMMIT_TEXT CHANGES_URL   passed to the caption
set -euo pipefail

if [ -z "${BOT_TOKEN:-}" ] || [ -z "${CHAT_ID:-}" ]; then
	echo "telegram: BOT_TOKEN/CHAT_ID are not configured; skipping delivery"
	exit 0
fi

dir="${TELEGRAM_APK_DIR:?TELEGRAM_APK_DIR is required}"
title="${TITLE:?TITLE is required}"
branch="${BRANCH:?BRANCH is required}"
run_url="${RUN_URL:?RUN_URL is required}"

APKS=()
while IFS= read -r -d '' file; do
	APKS+=("$file")
done < <(find "$dir" -maxdepth 1 -type f -name '*.apk' -print0 | sort -z)
[ "${#APKS[@]}" -gt 0 ] || {
	echo "telegram: no .apk in ${dir}" >&2
	exit 1
}

export TITLE="$title"
export BRANCH="$branch"
export RUN_URL="$run_url"
export MESSAGE_THREAD_ID="${MESSAGE_THREAD_ID:-}"
export TG_API_BASE="${TG_API_BASE:-https://api.telegram.org}"
export VERSION="${VERSION:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"

# The identity of a build is the topic, the ref, the commit AND the bytes of the
# APK:
#   - the version code is derived from the commit count, so it goes backwards on
#     a revert and must not be the key
#   - the ref keeps dev, main, tags and pull requests in separate slots
#   - the hash means a rebuild of the same commit (different signer, different
#     toolchain, changed files in the APK) still uploads
code="$(basename "${APKS[0]}" | sed -E 's/.*_([0-9]+)-[a-z0-9_-]+-release\.apk$/\1/')"
sha="$(git rev-parse --short=8 HEAD 2>/dev/null || printf '%s' "${GITHUB_SHA:-unknown}" | cut -c1-8)"
ref="$(printf '%s' "${GITHUB_REF_NAME:-${GITHUB_REF:-unknown}}" | tr '/' '-')"
apk_hash="$(sha256sum "${APKS[0]}" | cut -c1-16)"
topic="${MESSAGE_THREAD_ID:-default}"
state_dir="${TELEGRAM_STATE_DIR:-/ci/state}"
marker="${state_dir}/telegram-${topic}-${ref}-${sha}-${apk_hash}.sent"

mkdir -p "$(dirname "$marker")"
# markers are only useful while the commit is still recent
find "$(dirname "$marker")" -type f -mtime +30 -delete 2>/dev/null || true
if [ -f "$marker" ]; then
	echo "build ${ref}@${sha} apk ${apk_hash} (version ${code}) was already uploaded to topic ${topic} ($(cat "$marker")), skipping"
	exit 0
fi

bash "$(dirname "$0")/../upload-telegram.sh" "${APKS[@]}"
date -u +%FT%TZ >"$marker"
echo "telegram: delivered ${#APKS[@]} APK(s) to topic ${topic}"
