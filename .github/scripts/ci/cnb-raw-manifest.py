#!/usr/bin/env python3
"""Build the release-shaped manifest consumed by the manager's update checker.

The manifest deliberately mirrors the subset of the GitHub release JSON that
the app already understands: ``tag_name``, ``name``, ``body``, ``prerelease``
and an ``assets`` array with ``name``/``browser_download_url``. That keeps the
Android side on one parser while the transport is an ordinary CNB raw file.

Usage:
    cnb-raw-manifest.py --assets-dir DIR --repo OWNER/REPO --asset-branch REF
        --base-url https://cnb.cool --tag manager-ci --name "Manager CI"
        --body-file notes.md --prerelease --output manifest.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import mimetypes
import os
from pathlib import Path
from urllib.parse import quote


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets-dir", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--asset-branch", required=True)
    parser.add_argument("--asset-prefix", default="apks")
    parser.add_argument("--base-url", default="https://cnb.cool")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--name", default="")
    parser.add_argument("--body-file", default="")
    parser.add_argument("--prerelease", action="store_true")
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def iter_assets(root: Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        if path.name == "manifest.json":
            continue
        yield path


def raw_url(base_url: str, repo: str, branch: str, rel_path: str) -> str:
    base = base_url.rstrip("/")
    repo_path = "/".join(quote(part, safe="") for part in repo.split("/") if part)
    branch_path = quote(branch, safe="")
    file_path = "/".join(quote(part, safe="") for part in rel_path.split("/") if part)
    return f"{base}/{repo_path}/-/git/raw/{branch_path}/{file_path}"


def main() -> None:
    args = parse_args()
    root = Path(args.assets_dir)
    if not root.is_dir():
        raise SystemExit(f"assets directory missing: {root}")

    body = ""
    if args.body_file:
        body_path = Path(args.body_file)
        if body_path.is_file():
            body = body_path.read_text(encoding="utf-8").strip()

    assets = []
    for path in iter_assets(root):
        rel = path.relative_to(root).as_posix()
        prefix = args.asset_prefix.strip("/")
        url_path = f"{prefix}/{rel}" if prefix else rel
        content_type, _ = mimetypes.guess_type(path.name)
        assets.append(
            {
                "name": path.name,
                "browser_download_url": raw_url(
                    args.base_url, args.repo, args.asset_branch, url_path
                ),
                "size": path.stat().st_size,
                "content_type": content_type or "application/octet-stream",
            }
        )

    if not assets:
        raise SystemExit(f"no files to publish under {root}")

    manifest = {
        "tag_name": args.tag,
        "name": args.name or args.tag,
        "body": body,
        "draft": False,
        "prerelease": bool(args.prerelease),
        "published_at": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "assets": assets,
    }
    output = Path(args.output)
    output.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"manifest: {output} ({len(assets)} assets)")


if __name__ == "__main__":
    main()
