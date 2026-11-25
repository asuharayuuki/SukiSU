#!/usr/bin/env bash
# Git helpers for storing files as ordinary files in a CNB repository.
#
# The artifact transport used to keep a rolling release and rotate its assets.
# That needs release write permission on every build and CNB throttles the
# repository that does it, so everything now lives on branches instead:
#
#   branches, not releases   a branch is one snapshot, deleting it deletes the
#                            files, and no release API is involved
#   blobs are never read     trees are fetched with `--filter=blob:none`, so a
#                            publisher downloads a few kilobytes of tree
#                            objects instead of every file already stored
#
# Environment:
#   CNB_ARTIFACT_TOKEN  preferred token (artifact repository)
#   CNB_RAW_TOKEN       fallback token (publication repository)
#   CNB_TOKEN           last fallback
#   CNB_WEB             default https://cnb.cool
#
# The token never reaches a command line, a URL or a log: git asks for it
# through GIT_ASKPASS, whose script reads it from the environment.

# cnb_raw_token -> the token that can write to the repository
cnb_raw_token() {
	printf '%s\n' "${CNB_ARTIFACT_TOKEN:-${CNB_RAW_TOKEN:-${CNB_TOKEN:-}}}"
}

# cnb_raw_web -> the public CNB host, without a trailing slash
cnb_raw_web() {
	local web="${CNB_WEB:-https://cnb.cool}"
	printf '%s\n' "${web%/}"
}

# cnb_raw_url REPO BRANCH PATH -> the raw download URL of one file
cnb_raw_url() {
	printf '%s/%s/-/git/raw/%s/%s\n' "$(cnb_raw_web)" "$1" "$2" "$3"
}

# cnb_raw_git_init WORK [REPO]
#   Prepares WORK as an empty repository that can fetch and push REPO. The
#   askpass helper lives next to WORK (not inside it) so it can never be staged.
cnb_raw_git_init() {
	local work="$1" repo="${2:-${CNB_ARTIFACT_REPO:-sukisu-nova/artifacts}}"
	local token askpass
	token="$(cnb_raw_token)"
	[ -n "$token" ] || return 1
	repo="${repo%.git}"
	mkdir -p "$work"
	askpass="${work}-askpass"
	cat >"$askpass" <<'EOF'
#!/bin/sh
case "$1" in
*Username*) printf '%s\n' cnb ;;
*) printf '%s\n' "$CNB_RAW_GIT_TOKEN" ;;
esac
EOF
	chmod 700 "$askpass"
	CNB_RAW_GIT_TOKEN="$token"
	export CNB_RAW_GIT_TOKEN
	GIT_ASKPASS="$askpass"
	export GIT_ASKPASS
	GIT_TERMINAL_PROMPT=0
	export GIT_TERMINAL_PROMPT
	GIT_LFS_SKIP_SMUDGE=1
	export GIT_LFS_SKIP_SMUDGE
	git -C "$work" init -q || return 1
	git -C "$work" config user.name "SukiSU CI"
	git -C "$work" config user.email "ci@sukisu.local"
	git -C "$work" remote add origin "$(cnb_raw_web)/${repo}.git"
}

# cnb_raw_git_commit WORK BRANCH PATHSPEC MESSAGE -> commit id
#   Builds one commit on top of BRANCH that adds/updates PATHSPEC. Plumbing on
#   purpose: the index is filled from the branch tree, so the commit carries the
#   files that stay untouched even though their blobs are not in this checkout.
cnb_raw_git_commit() {
	local work="$1" branch="$2" pathspec="$3" message="$4"
	local parent="" tree commit
	# No --depth here: a shallow client cannot push (the server rejects an update
	# whose history it cannot see), and the blob filter already keeps the fetch to
	# commits and trees.
	if git -C "$work" fetch -q --filter=blob:none origin "refs/heads/$branch" 2>/dev/null; then
		parent="$(git -C "$work" rev-parse FETCH_HEAD)" || return 1
		git -C "$work" read-tree "$parent" || return 1
	else
		git -C "$work" read-tree --empty || return 1
	fi
	git -C "$work" add -A -- "$pathspec" || return 1
	tree="$(git -C "$work" write-tree)" || return 1
	if [ -n "$parent" ]; then
		commit="$(git -C "$work" commit-tree "$tree" -p "$parent" -m "$message")" || return 1
	else
		commit="$(git -C "$work" commit-tree "$tree" -m "$message")" || return 1
	fi
	printf '%s\n' "$commit"
}

# cnb_raw_git_publish WORK BRANCH PATHSPEC MESSAGE
#   Commits and pushes, rebuilding the commit when another job moved the branch
#   meanwhile (the tree fetch is cheap, the files are already on disk).
cnb_raw_git_publish() {
	local work="$1" branch="$2" pathspec="$3" message="$4"
	local attempt=1 commit
	while [ "$attempt" -le 4 ]; do
		if commit="$(cnb_raw_git_commit "$work" "$branch" "$pathspec" "$message")" &&
			git -C "$work" push -q origin "$commit:refs/heads/$branch"; then
			return 0
		fi
		attempt=$((attempt + 1))
		sleep 2
	done
	echo "cnb: cannot update ${branch} after retries" >&2
	return 1
}

# cnb_raw_branch_list [REPO] -> one branch name per line
cnb_raw_branch_list() {
	local repo="${1:-${CNB_ARTIFACT_REPO:-sukisu-nova/artifacts}}"
	git ls-remote --heads "$(cnb_raw_web)/${repo%.git}.git" 2>/dev/null |
		sed 's#.*refs/heads/##'
}

# cnb_raw_branch_delete BRANCH [REPO]
#   Deletes the branch and, with it, every file it pointed at. Deleting a branch
#   is how a run is pruned: the objects become unreachable instead of piling up
#   in history for the next run to download.
cnb_raw_branch_delete() {
	local branch="$1" repo="${2:-${CNB_ARTIFACT_REPO:-sukisu-nova/artifacts}}"
	local work status
	work="$(mktemp -d)"
	git -C "$work" init -q || {
		rm -rf "$work" 2>/dev/null || true
		return 1
	}
	git -C "$work" push -q "$(cnb_raw_web)/${repo%.git}.git" --delete "refs/heads/$branch"
	status=$?
	rm -rf "$work" 2>/dev/null || true
	return "$status"
}

# cnb_raw_list_dirs REPO BRANCH
#   One top-level entry per line. Only tree objects are fetched, so listing a
#   run with hundreds of megabytes of artifacts stays a few kilobytes.
cnb_raw_list_dirs() {
	local repo="$1" branch="$2" work
	work="$(mktemp -d)"
	if ! cnb_raw_git_init "$work" "$repo"; then
		rm -rf "$work" 2>/dev/null || true
		return 0
	fi
	# Read-only: one commit is enough, and the blob filter keeps even that to a
	# handful of tree objects.
	if git -C "$work" fetch -q --depth 1 --filter=blob:none origin "refs/heads/$branch" 2>/dev/null; then
		git -C "$work" ls-tree --name-only FETCH_HEAD || true
	fi
	rm -rf "$work" "${work}-askpass" 2>/dev/null || true
	return 0
}
