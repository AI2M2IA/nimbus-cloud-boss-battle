# AWS Boss Battle Roadmap

This roadmap captures the parts of the reference archive that make sense for this repository, adapted to the current AWS Boss Battle architecture, license policy, identity policy, and American English artifact policy. It is intentionally incremental: keep the existing boss-battle flow, pure rules modules, and lightweight Godot setup.

## Already Adapted

- Project-local Godot shortcut: `godot.sh` runs the project or passes raw arguments through to Godot.
- Test runner isolation: `run-tests.sh` now sets `HOME` under `user-data/home` and writes the Godot log to `user-data/godot.log`, so headless tests do not depend on global Godot user data.
- Generated/local test artifacts are ignored through `.gitignore` entries for `user-data/` and `*.log`.
- Save the Pet visuals are modularized in `scripts/pet_avatar.gd` and integrated into the menu and mode battle screen.
- Release hygiene is documented in `docs/release-checklist.md`, including identity checks, license verification, package exclusions, and final release commands.

## Phase 1: Release Hygiene (Complete)

Goal: make releases safer without changing game behavior.

- Add `docs/release-checklist.md` in American English.
- Include required checks for pseudonymous Git identity before and after commits.
- Include AGPL-3.0 additional-terms license verification.
- Include export-package exclusions for `.git`, `.godot`, `user-data`, logs, local exports, temporary files, and OS metadata.
- Include the final commands:
  - `./run-tests.sh`
  - `./godot.sh --headless --path . --quit`

Acceptance criteria:
- The checklist has no local machine paths, personal identity data, or conflicting license language.
- The checklist references this project's actual scripts and file layout.

## Phase 2: Static Audit

Goal: catch risky artifacts before a commit or release.

- Add a small `scripts/dev/static_audit.py` adapted to this project.
- Audit for personal emails, local user paths, private keys, AWS access key patterns, private URLs, logs, `.godot/`, `user-data/`, and export artifacts.
- Audit that required license and attribution files still exist and mention AGPL-3.0 additional terms and AI(2)M(2)IA attribution.
- Audit that docs and comments stay in American English, excluding localized strings in `data/i18n/*.json`.

Acceptance criteria:
- The audit runs locally without network access.
- The audit avoids false positives in legitimate localized string files.
- `./run-tests.sh` can optionally call the audit once it is stable.

## Phase 3: Progress And Badges

Goal: make the study loop more motivating without changing question rules.

- Add a small progress summary screen or section that shows total XP, rank, best streak, defeated bosses, mode attempts, and pet saves.
- Add badges for meaningful milestones:
  - First boss defeated.
  - Each domain boss defeated.
  - Final Gauntlet cleared.
  - Three-answer streak.
  - Ten-answer streak.
  - Pet saved.
- Keep badge computation in a pure `RefCounted` module so it is unit-testable.

Acceptance criteria:
- Existing save data migrates safely when badge state is absent.
- Badges are deterministic and not duplicated.
- Tests cover badge award rules and save migration.

## Phase 4: Review Queue

Goal: turn missed questions into a lightweight study loop.

- Add a pure review scheduler inspired by Leitner boxes.
- Track question IDs missed in boss battles and game modes.
- Add a menu entry for review practice using due or missed questions.
- Keep the initial version local-only and offline-only.

Acceptance criteria:
- Review scheduling logic is pure and unit-tested.
- Missed-question tracking does not change current battle scoring.
- Review mode works with built-in questions and active custom sets where possible.

## Phase 5: Content And Privacy Guardrails

Goal: strengthen custom question workflows without expanding scope too much.

- Document the current custom question JSON shape in `docs/question-bank-schema.md`.
- Add privacy guidance: no personal data, private URLs, local paths, credentials, prompt dumps, or proprietary answer dumps in custom sets.
- Extend existing import validation only where it matches the current schema.

Acceptance criteria:
- Docs match `scripts/quiz_import.gd` and current `data/questions.json`.
- Tests cover any new validation behavior.

## Phase 6: Optional Coverage Probes

Goal: measure behavior coverage only if the test suite grows enough to justify it.

- Consider a tiny `CoverageProbe` helper for pure modules.
- Start with a small manifest for rules, import validation, leaderboard, custom sets, i18n, and pet avatar behavior.
- Avoid instrumenting UI-heavy code until it provides clear value.

Acceptance criteria:
- Coverage probes do not make production logic harder to read.
- Missing probes fail tests only after the manifest is stable.

## Visual Inspiration

The reference archive includes a badge-style icon and a cloud map illustration. Treat them as inspiration, not direct drop-in assets.

Potential future direction:
- Refresh the app icon while preserving the AWS Boss Battle identity.
- Add a simple domain map or boss progression view covering D0, D1, D2, D3, D4, and the Final Gauntlet.
- Keep visuals lightweight, readable, and consistent with the current dark arcade-study interface.

## Non-Goals

- Do not replace the current app with the archive's `scripts/core` and `scripts/ui/screens` architecture.
- Do not copy the archive README or NOTICE text; it uses different language, naming, and license framing.
- Do not adopt the archive question-bank schema wholesale.
- Do not commit `.godot/`, `user-data/`, logs, `__MACOSX/`, local exports, or generated caches.
- Do not introduce network-dependent gameplay.
