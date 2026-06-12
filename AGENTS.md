# AGENTS.md

Instructions for any AI agent (and any human contributor) working in this repository. **Nimbus Cloud Boss Battle** is a free, open-source, pseudonymous study game. Three policies below are MANDATORY for every contribution.

## Identity Policy (MANDATORY)

- Every commit and tag uses **exclusively** `AI(2)M(2)IA <AI2M2IA@users.noreply.github.com>` as both author AND committer.
- It is **forbidden** for the author's real name or any personal email address to appear anywhere — in commit metadata, tags, commit messages, file contents, code comments, or game text. Never.
- **Double check, always:** before any commit run `git config user.name && git config user.email` and confirm the pseudonymous identity; after committing, verify with `git log -1 --format='%an <%ae> | %cn <%ce>'`. If the identity is wrong, stop and fix it before doing anything else.

## Language Policy (MANDATORY)

- All repository artifacts are written in **American English**: commit messages, documentation, README, code comments, identifiers, and design notes.
- The exception is **player-facing localized strings** (the `data/i18n/<code>.json` files), which carry their target language by design. AWS service names stay in English in every language.
- Do not commit internal working documents written in other languages.

## License Policy (MANDATORY)

- This game is licensed under **AGPL-3.0 with the Section 7 additional terms** in `LICENSE` (author attribution to AI(2)M(2)IA + origin integrity). **Do not change or remove the license**, the per-file notices, or the attribution.
- Anyone who copies, forks, or builds on this project must keep it open under the **same** license and credit AI(2)M(2)IA and the original repository. Commercial use is allowed, but the complete corresponding source must stay public (including for network/SaaS use). This mirrors the VLC philosophy: free forever, sellable but never closed.
- The game and all its content are free. Voluntary financial support is welcome; access is never conditioned on payment.

## Engine & language

Godot 4.6, GDScript. Keep pure game logic in RefCounted modules with static functions (see `scripts/battle_rules.gd`, `scripts/mode_rules.gd`) so it stays unit-testable independently of UI. Run the headless test suite before committing logic changes:

```
godot --headless --path . -s tests/run_tests.gd
```

(Exits 0 on success, 1 on failure — CI-friendly.)

## Localization

The reference locale set is the AWS book's language set: English plus zh, hi, es, fr, ar, bn, pt, ru, ur, id, de, ja, sw, tr, vi, ko, th, he. Align `LANGS` and `data/i18n/` to this set; add translation files progressively and show only languages whose file exists.
