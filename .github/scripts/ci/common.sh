#!/usr/bin/env bash
# Shared helpers for the self-hosted Forgejo runner.
#
# The workflows were originally written for github.com hosted runners and used
# marketplace actions for checkout, toolchain setup and artifact passing. This
# runner has no access to github.com, so every one of those actions is replaced
# with a plain script. Artifacts are exchanged through a host directory that the
# runner mounts into each job container (see CI_ARTIFACT_ROOT), because the
# runner has no artifact service of its own in this setup.

set -eu
# The job shell differs per image (bash on the hosted-like images, dash in
# the ddk-min container), so only enable pipefail where it exists.
if [ -n "${BASH_VERSION:-}" ]; then
	set -o pipefail
fi

CI_REMOTE="${CI_REMOTE:-https://git.zako.shirkneko.top:20004}"
CI_ARTIFACT_ROOT="${CI_ARTIFACT_ROOT:-/ci/runs/${GITHUB_RUN_ID:-local}}"

# ci_checkout [depth]
#   depth 1 (default) fetches just the triggering commit. depth 0 fetches all
#   branches and tags, which the version-code and changelog steps need.
ci_checkout() {
	local depth="${1:-1}"
	local auth="${TOKEN:-${GITHUB_TOKEN:-}}"

	git init -q .
	if [ -n "$auth" ]; then
		# Kept in a config value so the credential never shows up in
		# `git remote -v` or in error output.
		git config "http.${CI_REMOTE}/.extraHeader" "Authorization: token ${auth}"
	fi
	git remote add origin "${CI_REMOTE}/${GITHUB_REPOSITORY}.git"

	if [ "$depth" = "0" ]; then
		git fetch -q origin "+refs/heads/*:refs/remotes/origin/*" "+refs/tags/*:refs/tags/*" "+refs/pull/*:refs/remotes/origin/pull/*"
	else
		git fetch -q --depth "$depth" origin "${GITHUB_SHA}"
	fi
	git checkout -q "${GITHUB_SHA}"
}

# ci_artifact_path NAME -> absolute directory for one artifact
ci_artifact_path() {
	printf '%s/%s\n' "$CI_ARTIFACT_ROOT" "$1"
}

# ci_artifact_put NAME PATH...
#   Copies files or directories into the artifact directory. Missing sources are
#   an error: a silent skip would hide a broken build.
ci_artifact_put() {
	local name="$1"
	shift
	local dest
	dest="$(ci_artifact_path "$name")"
	mkdir -p "$dest"
	local src
	for src in "$@"; do
		if [ ! -e "$src" ]; then
			echo "artifact source missing: $src" >&2
			return 1
		fi
		# Match upload-artifact: a directory contributes its contents, not
		# the directory itself.
		if [ -d "$src" ]; then
			cp -a "$src"/. "$dest"/
		else
			cp -a "$src" "$dest"/
		fi
	done
	ci_artifact_manifest "$dest"
	echo "stored artifact ${name} in ${dest}"
}

# ci_artifact_manifest DIR
#   Writes the file list consumed by the LAN peer downloader.
ci_artifact_manifest() {
	local dir="$1"
	local files escaped first
	files="$(cd "$dir" && find . -type f ! -name manifest.json | sed 's#^\./##' | sort)"
	{
		printf '{"files":['
		first=1
		printf '%s\n' "$files" | while IFS= read -r file; do
			[ -n "$file" ] || continue
			if [ "$first" = 1 ]; then
				first=0
			else
				printf ','
			fi
			escaped="$(printf '%s' "$file" | sed 's/\\/\\\\/g; s/"/\\"/g')"
			printf '"%s"' "$escaped"
		done
		printf ']}'
	} > "$dir/manifest.json"
}

# ci_artifact_get NAME DEST
ci_artifact_get() {
	local name="$1"
	local dest="$2"
	local src
	src="$(ci_artifact_path "$name")"
	if [ ! -d "$src" ]; then
		echo "artifact not found: ${name} (${src})" >&2
		return 1
	fi
	mkdir -p "$dest"
	cp -a "$src"/. "$dest"/
}

# ci_artifact_exists NAME
ci_artifact_exists() {
	[ -d "$(ci_artifact_path "$1")" ]
}

# ci_download_artifact NAME DEST [RUN_ID]
#   Prefer the per-run copy on the shared /ci volume (fast when the producing
#   and consuming jobs land on the same runner). Otherwise fetch the artifact
#   zip through the Forgejo API, with curl's byte progress instead of the
#   download-artifact action's file-count progress.
ci_download_artifact() {
	local name="$1"
	local dest="$2"
	local run_id="${3:-${GITHUB_RUN_ID:-0}}"
	mkdir -p "$dest"

	local local_root="/ci/runs/${run_id}/${name}"
	if [ -d "$local_root" ]; then
		cp -a "$local_root"/. "$dest"/
		echo "artifact ${name} copied from ${local_root}"
		return 0
	fi

	# Runner-to-runner transfer over the LAN. Each runner serves /ci/runs on
	# port 18080 (scripts/ci/artifact-server.sh).
	local peers="${CI_ARTIFACT_PEERS:-192.168.11.2 192.168.11.3}"
	local host manifest files file ok
	manifest="$(mktemp)"
	for host in $peers; do
		if ! curl -fsS --max-time 3 -o "$manifest" \
			"http://${host}:18080/${run_id}/${name}/manifest.json"; then
			continue
		fi
		files="$(jq -r '.files[]' "$manifest")"
		[ -n "$files" ] || continue
		ok=1
		for file in $files; do
			case "$file" in
			'' | */* | ..*)
				echo "artifact ${name}: refusing unsafe file name ${file}" >&2
				ok=0
				break
				;;
			esac
			mkdir -p "$(dirname "${dest}/${file}")"
			if ! curl -fL --retry 3 --progress-bar \
				"http://${host}:18080/${run_id}/${name}/${file}" \
				-o "${dest}/${file}"; then
				ok=0
				break
			fi
		done
		if [ "$ok" = 1 ]; then
			rm -f "$manifest"
			echo "artifact ${name} copied from EasyTier peer ${host}"
			return 0
		fi
	done
	rm -f "$manifest"

	local token="${TOKEN:-${GITHUB_TOKEN:-}}"
	[ -n "$token" ] || {
		echo "artifact ${name}: missing GITHUB_TOKEN for API download" >&2
		return 1
	}
	# Artifact traffic goes over EasyTier when the runner can reach the mesh;
	# fall back to the public endpoint for hosts outside it.
	local site="${CI_ARTIFACT_BASE:-http://100.0.0.11:3000}"
	local api="${site}/api/v1/repos/${GITHUB_REPOSITORY}"
	local json
	if ! curl -fsS --max-time 4 "${site}/api/v1/version" >/dev/null 2>&1; then
		site="${FORGEJO_PUBLIC_URL:-https://git.zako.shirkneko.top:20004}"
		api="${site}/api/v1/repos/${GITHUB_REPOSITORY}"
	fi
	json="$(curl -fsS --max-time 30 -H "Authorization: token ${token}" \
		"${api}/actions/artifacts?name=${name}&limit=100")"
	local id
	id="$(printf '%s' "$json" | jq -r --argjson rid "${run_id:-0}" \
		'[.[] | select(.expired == false) | select($rid == 0 or .run_id == $rid)] | sort_by(.id) | last | .id // empty')"
	[ -n "$id" ] || {
		echo "artifact ${name} not found for run ${run_id}" >&2
		return 1
	}
	# Build the zip URL on the same base: archive_download_url points at the
	# public host and would bypass EasyTier.
	local url="${api}/actions/artifacts/${id}/zip"
	local zip
	zip="$(mktemp)"
	curl -fL --retry 5 --retry-all-errors --progress-bar \
		-H "Authorization: token ${token}" -o "$zip" "$url"
	unzip -q -o "$zip" -d "$dest"
	rm -f "$zip"
	echo "artifact ${name} downloaded"
}

# ci_download_all_artifacts DEST [RUN_ID]
#   Mirrors download-artifact without a name: one directory per artifact.
ci_download_all_artifacts() {
	local dest="$1"
	local run_id="${2:-${GITHUB_RUN_ID:-0}}"
	local token="${TOKEN:-${GITHUB_TOKEN:-}}"
	[ -n "$token" ] || {
		echo "missing GITHUB_TOKEN for artifact list" >&2
		return 1
	}
	local site="${CI_ARTIFACT_BASE:-http://100.0.0.11:3000}"
	local api="${site}/api/v1/repos/${GITHUB_REPOSITORY}"
	if ! curl -fsS --max-time 4 "${site}/api/v1/version" >/dev/null 2>&1; then
		site="${FORGEJO_PUBLIC_URL:-https://git.zako.shirkneko.top:20004}"
		api="${site}/api/v1/repos/${GITHUB_REPOSITORY}"
	fi
	local json names name
	json="$(curl -fsS --max-time 30 -H "Authorization: token ${token}" \
		"${api}/actions/artifacts?limit=100")"
	names="$(printf '%s' "$json" | jq -r --argjson rid "${run_id:-0}" \
		'.[] | select(.expired == false) | select($rid == 0 or .run_id == $rid) | .name' | sort -u)"
	[ -n "$names" ] || {
		echo "no artifacts found for run ${run_id}" >&2
		return 1
	}
	mkdir -p "$dest"
	for name in $names; do
		ci_download_artifact "$name" "$dest/$name" "$run_id"
	done
}

# ci_summary_artifacts NAME...
#   Job Summary: rendered above the job log by Forgejo. One row per artifact with
#   the download link (Forgejo serves artifacts at /actions/runs/<run_number>/artifacts/<name>).
ci_summary_artifacts() {
	local summary="${FORGEJO_STEP_SUMMARY:-${GITHUB_STEP_SUMMARY:-}}"
	[ -n "$summary" ] || return 0
	local site="${FORGEJO_PUBLIC_URL:-https://git.zako.shirkneko.top:20004}"
	local run="${site}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_NUMBER:-${GITHUB_RUN_ID}}"
	{
		echo "## 构建产物"
		echo
		echo "| Artifact | 下载 |"
		echo "| --- | --- |"
		local name
		for name in "$@"; do
			echo "| \`${name}\` | [下载](${run}/artifacts/${name}) |"
		done
		echo
		echo "[运行详情](${run})"
	} >> "$summary"
}
