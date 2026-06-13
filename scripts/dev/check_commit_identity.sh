#!/usr/bin/env bash
# Enforce the repository Identity Policy in CI. Every commit in RANGE must keep
# the project pseudonym in its authored metadata and must never carry a real
# name or a personal e-mail. GitHub's own PR-merge identities are tolerated:
# the account no-reply e-mail (bare or numeric-id form) as the author, and
# "GitHub <noreply@github.com>" as the committer of merge/squash commits.
set -euo pipefail

EXPECTED_NAME="AI(2)M(2)IA"
EMAIL_RE='^([0-9]+[+])?AI2M2IA@users[.]noreply[.]github[.]com$'

RANGE="${1:-}"
if [ -z "$RANGE" ]; then
  echo "usage: check_commit_identity.sh <git-range>" >&2
  exit 2
fi

ok_pseudonym() {  # name email
  [ "$1" = "$EXPECTED_NAME" ] && [[ "$2" =~ $EMAIL_RE ]]
}

status=0
while IFS=$'\t' read -r sha an ae cn ce; do
  if ! ok_pseudonym "$an" "$ae"; then
    echo "::error::$sha author is not the pseudonym: $an <$ae>"
    status=1
  fi
  if ! ok_pseudonym "$cn" "$ce" && ! { [ "$cn" = "GitHub" ] && [ "$ce" = "noreply@github.com" ]; }; then
    echo "::error::$sha committer is not allowed: $cn <$ce>"
    status=1
  fi
done < <(git log --format=$'%H\t%an\t%ae\t%cn\t%ce' "$RANGE")

if [ "$status" -ne 0 ]; then
  echo "Identity Policy violation: real names and personal e-mails are forbidden." >&2
  echo "Author must be '$EXPECTED_NAME' on a GitHub no-reply address; committer may also be GitHub's merge bot." >&2
  exit 1
fi
echo "Commit identity OK for $RANGE"
