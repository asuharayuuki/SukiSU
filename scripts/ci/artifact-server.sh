#!/bin/sh
# Run this on each CI runner host (not inside a job).
# Serves the shared /ci/runs volume over the host's EasyTier address so the
# other runner can copy build artifacts directly:
#
#   ./artifact-server.sh 100.0.0.20   # windows-docker runner
#   ./artifact-server.sh 100.0.0.21   # laptop-docker runner
#
# The server is read-only and bound to the EasyTier interface, so it is not
# exposed on the public/LAN address.
set -eu

ip="${1:?usage: $0 <easytier-ip>}"

docker rm -f ci-artifacts >/dev/null 2>&1 || true
# Git Bash rewrites /ci/runs into a Windows path; keep container paths intact.
MSYS_NO_PATHCONV=1 docker run -d \
	--name ci-artifacts \
	--restart unless-stopped \
	--network host \
	-u 0:0 \
	-v forgejo-ci:/ci:ro \
	--entrypoint python3 \
	forgejo-ci/full:1 \
	-m http.server 18080 --bind "$ip" --directory /ci/runs

echo "serving /ci/runs on http://${ip}:18080"
