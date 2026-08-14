#!/usr/bin/env bash
# Enforce the repository Identity Policy in CI. Every commit in RANGE must keep
# the project pseudonym in its authored metadata and must never carry a real
# name or a personal e-mail. GitHub's own PR-merge identity is tolerated as a
# committer. The official Dependabot identity is accepted only when CI passes
# --allow-dependabot after independently validating the event actor, branch,
# and source repository.
set -euo pipefail

EXPECTED_NAME="AI(2)M(2)IA"
EMAIL_RE='^([0-9]+[+])?AI2M2IA@users[.]noreply[.]github[.]com$'
DEPENDABOT_NAME='dependabot[bot]'
DEPENDABOT_EMAIL_RE='^49699333[+]dependabot\[bot\]@users[.]noreply[.]github[.]com$'

RANGE="${1:-}"
OPTION="${2:-}"
if [ -z "$RANGE" ] || [ "$#" -gt 2 ]; then
	echo "usage: check_commit_identity.sh <git-range> [--allow-dependabot]" >&2
	exit 2
fi

allow_dependabot=0
case "$OPTION" in
	"") ;;
	--allow-dependabot) allow_dependabot=1 ;;
	*)
		echo "usage: check_commit_identity.sh <git-range> [--allow-dependabot]" >&2
		exit 2
		;;
esac

ok_pseudonym() {  # name email
	[ "$1" = "$EXPECTED_NAME" ] && [[ "$2" =~ $EMAIL_RE ]]
}

ok_dependabot() {  # name email
	[ "$allow_dependabot" -eq 1 ] \
		&& [ "$1" = "$DEPENDABOT_NAME" ] \
		&& [[ "$2" =~ $DEPENDABOT_EMAIL_RE ]]
}

ok_authored_identity() {  # name email
	ok_pseudonym "$1" "$2" || ok_dependabot "$1" "$2"
}

status=0
if ! log_rows="$(git log --format=$'%H\t%an\t%ae\t%cn\t%ce' "$RANGE")"; then
	echo "Identity Policy check failed: invalid or unreadable commit range." >&2
	exit 2
fi
if [ -n "$log_rows" ]; then
	while IFS=$'\t' read -r sha an ae cn ce; do
		if ! ok_authored_identity "$an" "$ae"; then
			# Never echo rejected metadata: the check itself must not publish a
			# personal name or e-mail that it was created to block.
			echo "::error::$sha author identity is not allowed"
			status=1
		fi
		if ! ok_authored_identity "$cn" "$ce" \
				&& ! { [ "$cn" = "GitHub" ] && [ "$ce" = "noreply@github.com" ]; }; then
			echo "::error::$sha committer identity is not allowed"
			status=1
		fi
	done <<< "$log_rows"
fi

if [ "$status" -ne 0 ]; then
	echo "Identity Policy violation: unapproved author or committer metadata." >&2
	echo "Personal names and e-mails are forbidden; rejected metadata is intentionally redacted." >&2
	exit 1
fi
echo "Commit identity OK for $RANGE"
