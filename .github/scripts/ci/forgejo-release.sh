#!/usr/bin/env bash
# Point a Forgejo release page at its CNB assets, and drop any stale copies.
#
# No build bytes pass through the tunnel any more: the release body carries one
# CNB link and the files stay on CNB. The title is what the manager parses its
# version from, so a title that does not match afterwards is a hard failure, as
# is any asset left behind.
#
# Env: API_TOKEN RELEASE_TAG RELEASE_NAME RELEASE_BODY RELEASE_PRERELEASE
#      GITHUB_REPOSITORY GITHUB_SHA
set -euo pipefail

site="${FORGEJO_PUBLIC_URL:-https://git.zako.shirkneko.top:20004}"
api="${site}/api/v1/repos/${GITHUB_REPOSITORY}"
auth="Authorization: token ${API_TOKEN}"
tag="${RELEASE_TAG:?}"
name="${RELEASE_NAME:?}"
body="${RELEASE_BODY:-}"
prerelease="${RELEASE_PRERELEASE:-true}"

echo "api=${api} token_len=${#API_TOKEN} tag=${tag}"

net() {
	curl -sS --retry 5 --retry-all-errors --retry-delay 2 \
		--connect-timeout 10 --max-time 120 "$@"
}
net_once() {
	curl -sS --retry 5 --retry-connrefused --retry-delay 2 \
		--connect-timeout 10 --max-time 120 "$@"
}

json="$(mktemp)"
trap 'rm -f "$json"' EXIT

payload() {
	jq -nc --arg tag "$tag" --arg sha "${GITHUB_SHA:-}" --arg name "$name" \
		--arg body "$body" --argjson pre "$prerelease" \
		'{tag_name: $tag, target_commitish: $sha, name: $name,
		  prerelease: $pre, body: $body}'
}

release="$api/releases/tags/$tag"
status="$(curl -sS --connect-timeout 10 --max-time 60 -o "$json" \
	-w '%{http_code}' -H "$auth" "$release" || true)"
echo "existing release: HTTP ${status}"
if [ "$status" = "200" ]; then
	id="$(jq -r '.id' "$json")"
else
	net_once -X POST -H "$auth" -H 'Content-Type: application/json' \
		-d "$(payload)" "$api/releases" -o /dev/null \
		-w 'create: HTTP %{http_code}\n' || true
	# A lost response can leave the release behind anyway; read it back.
	curl -sS --connect-timeout 10 --max-time 60 -H "$auth" "$release" -o "$json"
	id="$(jq -r '.id' "$json")"
fi
test -n "$id" && [ "$id" != "null" ]

# Drop the copies from previous builds: they are stale, and the link in the body
# is the only download this release offers now.
for asset_id in $(jq -r '.assets[]?.id' "$json"); do
	# Forgejo 17 nests the asset under its release; /releases/assets/{id} is 404.
	net -f -X DELETE -H "$auth" "$api/releases/${id}/assets/$asset_id" >/dev/null
done

net -f -X PATCH -H "$auth" -H 'Content-Type: application/json' \
	-d "$(payload)" "$api/releases/${id}" >/dev/null

# Never leave a stale title or a stale asset behind silently.
curl -sS --connect-timeout 10 --max-time 60 -H "$auth" \
	"$api/releases/tags/${tag}" -o "$json"
actual="$(jq -r '.name // ""' "$json")"
left="$(jq -r '.assets | length' "$json")"
test "$actual" = "$name" || {
	echo "release title mismatch: got '${actual}', expected '${name}'" >&2
	exit 1
}
test "$left" = "0" || {
	echo "release still carries ${left} asset(s); stale builds must not stay" >&2
	exit 1
}
echo "release ${tag} updated: ${actual}"
