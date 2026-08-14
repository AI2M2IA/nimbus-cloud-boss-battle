#!/usr/bin/env python3
"""Accept only an exact, GitHub-verified official Dependabot commit record."""

from __future__ import annotations

import json
import re
import sys


SHA_RE = re.compile(r"[0-9a-fA-F]{40}")


def is_verified_dependabot_commit(data: object, expected_sha: str) -> bool:
    if not isinstance(data, dict):
        return False

    author = data.get("author")
    committer = data.get("committer")
    commit = data.get("commit")
    if not isinstance(author, dict) or not isinstance(committer, dict) or not isinstance(commit, dict):
        return False

    git_author = commit.get("author")
    git_committer = commit.get("committer")
    verification = commit.get("verification")
    if not all(isinstance(item, dict) for item in (git_author, git_committer, verification)):
        return False

    return (
        data.get("sha") == expected_sha.lower()
        and author.get("login") == "dependabot[bot]"
        and author.get("id") == 49699333
        and committer.get("login") == "web-flow"
        and committer.get("id") == 19864447
        and git_author.get("name") == "dependabot[bot]"
        and git_author.get("email") == "49699333+dependabot[bot]@users.noreply.github.com"
        and git_committer.get("name") == "GitHub"
        and git_committer.get("email") == "noreply@github.com"
        and verification.get("verified") is True
        and verification.get("reason") == "valid"
    )


def main() -> int:
    if len(sys.argv) != 2 or SHA_RE.fullmatch(sys.argv[1]) is None:
        return 2
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return 1
    return 0 if is_verified_dependabot_commit(data, sys.argv[1]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
