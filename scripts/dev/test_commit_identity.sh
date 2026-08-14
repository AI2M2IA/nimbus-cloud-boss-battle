#!/usr/bin/env bash
## Regression tests for check_commit_identity.sh. The official automation
## identity remains rejected by default and is accepted only with the explicit
## PR flag or an allowlisted exact SHA; a lookalike using a different no-reply
## address remains rejected.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
checker="$repo_root/scripts/dev/check_commit_identity.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/nimbus-identity.XXXXXX")"
trap 'rm -rf -- "$fixture_root"' EXIT

git -C "$fixture_root" init -q

commit_as() {  # author-name author-email committer-name committer-email
	GIT_AUTHOR_NAME="$1" \
	GIT_AUTHOR_EMAIL="$2" \
	GIT_COMMITTER_NAME="$3" \
	GIT_COMMITTER_EMAIL="$4" \
		git -C "$fixture_root" commit --allow-empty -q -m "identity fixture"
	git -C "$fixture_root" rev-parse HEAD
}

expect_pass() {
	if ! "$@" >/dev/null 2>&1; then
		echo "identity regression: expected success" >&2
		exit 1
	fi
}

expect_fail() {
	if "$@" >/dev/null 2>&1; then
		echo "identity regression: expected rejection" >&2
		exit 1
	fi
}

check_fixture() {
	(
		cd "$fixture_root"
		"$checker" "$@"
	)
}

project_name='AI(2)M(2)IA'
project_email='286691643+AI2M2IA@users.noreply.github.com'
bot_name='dependabot[bot]'
bot_email='49699333+dependabot[bot]@users.noreply.github.com'

base_sha="$(commit_as "$project_name" "$project_email" "$project_name" "$project_email")"
bot_sha="$(commit_as "$bot_name" "$bot_email" "$bot_name" "$bot_email")"
expect_fail check_fixture "$base_sha..$bot_sha"
expect_pass check_fixture "$base_sha..$bot_sha" --allow-dependabot
expect_pass check_fixture "$base_sha..$bot_sha" --allow-dependabot-sha "$bot_sha"
expect_fail check_fixture "$base_sha..$bot_sha" --allow-dependabot-sha "$base_sha"
expect_fail check_fixture "$base_sha..$bot_sha" --allow-dependabot-sha not-a-sha

lookalike_sha="$(commit_as "$bot_name" "$project_email" "$bot_name" "$project_email")"
expect_fail check_fixture "$bot_sha..$lookalike_sha" --allow-dependabot
expect_fail check_fixture "$bot_sha..$lookalike_sha" --allow-dependabot-sha "$lookalike_sha"

second_bot_sha="$(commit_as "$bot_name" "$bot_email" "$bot_name" "$bot_email")"
expect_fail check_fixture "$lookalike_sha..$second_bot_sha" --allow-dependabot-sha "$bot_sha"
expect_pass check_fixture "$lookalike_sha..$second_bot_sha" --allow-dependabot-sha "$second_bot_sha"

project_sha="$(commit_as "$project_name" "$project_email" "$project_name" "$project_email")"
expect_pass check_fixture "$second_bot_sha..$project_sha"
expect_fail check_fixture "missing-base..missing-head"

echo "Commit identity regression tests passed."
