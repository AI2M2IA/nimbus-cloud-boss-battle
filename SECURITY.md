# Security Policy

## Supported Version

Security fixes are applied to the latest code on develop and promoted to main
through a pull request. Published releases are rebuilt after a relevant fix
reaches main.

## Reporting A Vulnerability

Do not open a public issue for a suspected vulnerability or include exploit
details in a public pull request.

Use GitHub's private vulnerability reporting flow:

1. Open the repository's **Security** tab.
2. Choose **Advisories** and then **Report a vulnerability**.
3. Include the affected version, reproduction steps, impact, and a minimal
   proof of concept when it is safe to share.

If private reporting is unavailable, open a public issue that asks the
maintainer to enable a private advisory. Do not include technical details in
that issue.

The project does not request credentials, cloud keys, personal information, or
production AWS data. Remove all such data from reports and test fixtures.

## Scope

Useful reports include unsafe import handling, persistence corruption,
workflow or release-chain weaknesses, dependency compromise, and ways a
crafted local question set could execute code or escape its intended storage.

The expected behavior of an unsigned or ad-hoc-signed desktop build is not a
security vulnerability by itself. See the platform warnings in README.md.
