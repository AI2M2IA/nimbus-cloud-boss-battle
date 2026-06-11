# Release Checklist

Use this checklist before creating a release commit, tag, source archive, or Godot export for AWS Boss Battle.

## Identity

- Confirm the repository is not carrying unintended changes:

```sh
git status --short
```

- Before any commit or tag, confirm the required pseudonymous Git identity:

```sh
git config user.name && git config user.email
```

- The only valid author and committer identity is:

```text
AI(2)M(2)IA <AI2M2IA@users.noreply.github.com>
```

- After committing, verify the last commit metadata:

```sh
git log -1 --format='%an <%ae> | %cn <%ce>'
```

- Stop immediately if any real name, personal email address, local username, or private machine path appears in commit metadata, tag metadata, commit messages, documentation, game text, code comments, or packaged files.

## License And Attribution

- Keep `LICENSE` unchanged and present in the release.
- Verify that `LICENSE` still contains the GNU AGPL-3.0 text plus the Section 7 additional terms.
- Verify that the Section 7 additional terms still credit `AI(2)M(2)IA` and preserve the origin-integrity terms and original source repository reference.
- Do not add conflicting license text, closed-source terms, paid-access requirements, or language that weakens the AGPL-3.0 source availability requirements.
- Confirm any About, credits, release notes, or package metadata preserve the same attribution and source availability expectations.

## Source Package Contents

Release source packages should include the project source needed to study, run, test, modify, and rebuild the game. Do not include local state, generated caches, private files, or machine-specific output.

Exclude these paths and file types from source packages and exported archives:

- `.git/`
- `.godot/`
- `user-data/`
- `user://` save data
- `*.log`
- `*.save`
- `/build/`
- `/exports/`
- `export_presets.cfg`
- `*.zip`
- `*.tmp`
- `.DS_Store`
- `.DS_Store?`
- `._*`
- `Thumbs.db`

Before publishing a package, inspect its file list and confirm it contains no personal identity data, local machine paths, private URLs, private keys, AWS credentials, generated logs, or temporary files.

## Project Layout Checks

- Confirm `project.godot`, `data/questions.json`, `data/i18n/`, `scenes/`, `scripts/`, `tests/`, `README.md`, and `LICENSE` are present.
- Confirm `./godot.sh` launches Godot or forwards Godot arguments.
- Confirm `./run-tests.sh` runs the headless test suite with project-local Godot user data under `user-data/`.
- Keep all repository artifacts in American English, except player-facing localized strings under `data/i18n/<code>.json`.

## Final Verification

Run these commands from the repository root:

```sh
./run-tests.sh
```

```sh
./godot.sh --headless --path . --quit
```

Only publish after both commands finish successfully and `git status --short` shows only the release changes you intend to ship.
