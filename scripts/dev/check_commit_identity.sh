#!/usr/bin/env bash
# Enforce the repository Identity Policy in CI. Every commit in RANGE must keep
# the project pseudonym in its authored metadata and must never carry a real
# name or a personal e-mail. GitHub's own PR-merge identity is tolerated as a
# committer. The official Dependabot identity is accepted only when CI passes
# --allow-dependabot after independently validating the event actor, branch,
# and source repository, or --allow-dependabot-sha after cryptographically
# verifying that exact commit through GitHub's API.
set -euo pipefail

EXPECTED_NAME="AI(2)M(2)IA"
EMAIL_RE='^([0-9]+[+])?AI2M2IA@users[.]noreply[.]github[.]com$'
DEPENDABOT_NAME='dependabot[bot]'
DEPENDABOT_EMAIL_RE='^49699333[+]dependabot\[bot\]@users[.]noreply[.]github[.]com$'

usage() {
	echo "usage: check_commit_identity.sh <git-range> [--allow-dependabot] [--allow-dependabot-sha <sha>]..." >&2
}

RANGE="${1:-}"
if [ -z "$RANGE" ]; then
	usage
	exit 2
fi
shift

allow_dependabot=0
allowed_dependabot_shas=()
while [ "$#" -gt 0 ]; do
	case "$1" in
		--allow-dependabot)
			allow_dependabot=1
			shift
			;;
		--allow-dependabot-sha)
			if [ "$#" -lt 2 ] || [[ ! "$2" =~ ^[0-9a-f]{40}$ ]]; then
				usage
				exit 2
			fi
			allowed_dependabot_shas+=("$2")
			shift 2
			;;
		*)
			usage
			exit 2
			;;
	esac
done

ok_pseudonym() {  # name email
	[ "$1" = "$EXPECTED_NAME" ] && [[ "$2" =~ $EMAIL_RE ]]
}

dependabot_sha_allowed() {  # sha
	local candidate="$1"
	local allowed_sha
	[ "$allow_dependabot" -eq 1 ] && return 0
	for allowed_sha in "${allowed_dependabot_shas[@]}"; do
		[ "$candidate" = "$allowed_sha" ] && return 0
	done
	return 1
}

ok_dependabot() {  # sha name email
	dependabot_sha_allowed "$1" \
		&& [ "$2" = "$DEPENDABOT_NAME" ] \
		&& [[ "$3" =~ $DEPENDABOT_EMAIL_RE ]]
}

ok_authored_identity() {  # sha name email
	ok_pseudonym "$2" "$3" || ok_dependabot "$1" "$2" "$3"
}

status=0
if ! log_rows="$(git log --format=$'%H\t%an\t%ae\t%cn\t%ce' "$RANGE")"; then
	echo "Identity Policy check failed: invalid or unreadable commit range." >&2
	exit 2
fi
if [ -n "$log_rows" ]; then
	while IFS=$'\t' read -r sha an ae cn ce; do
		if ! ok_authored_identity "$sha" "$an" "$ae"; then
			# Never echo rejected metadata: the check itself must not publish a
			# personal name or e-mail that it was created to block.
			echo "::error::$sha author identity is not allowed"
			status=1
		fi
		if ! ok_authored_identity "$sha" "$cn" "$ce" \
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
