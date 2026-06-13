#!/usr/bin/env bash
# Enforce the repository Identity Policy in CI: every commit in RANGE must be
# authored AND committed exclusively by the project pseudonym. Fails the build
# on any other identity, so a personal name or e-mail can never pass the gate.
set -euo pipefail

EXPECTED="AI(2)M(2)IA <AI2M2IA@users.noreply.github.com>"
RANGE="${1:-}"
if [ -z "$RANGE" ]; then
  echo "usage: check_commit_identity.sh <git-range>" >&2
  exit 2
fi

status=0
while IFS=$'\t' read -r sha an ae cn ce; do
  author="$an <$ae>"
  committer="$cn <$ce>"
  if [ "$author" != "$EXPECTED" ] || [ "$committer" != "$EXPECTED" ]; then
    echo "::error::$sha is not pseudonymous (author='$author' committer='$committer')"
    status=1
  fi
done < <(git log --format=$'%H\t%an\t%ae\t%cn\t%ce' "$RANGE")

if [ "$status" -ne 0 ]; then
  echo "Identity Policy violation: every commit must be '$EXPECTED'." >&2
  exit 1
fi
echo "Commit identity OK for $RANGE"
