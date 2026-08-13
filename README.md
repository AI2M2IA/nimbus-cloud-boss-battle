# Nimbus Cloud Boss Battle

A gamified version of the SAA-C03 practice exam from *Let's Learn AWS Together*, built with Godot 4. Each exam domain is a boss fight.

## Play it

Play in your browser at https://ai2m2ia.github.io/nimbus-cloud-boss-battle/, or download a desktop build (Linux, macOS, Windows) from the [Releases](https://github.com/AI2M2IA/nimbus-cloud-boss-battle/releases) page.

The desktop builds are **free and open source**. The macOS build is **ad-hoc signed but not notarized** (notarization needs a paid Apple Developer ID, which would tie the release to a legal name). On first launch, right-click the app and choose **Open**, or go to **System Settings → Privacy & Security → Open Anyway**.

If macOS still says the app is *"damaged and can't be opened"* — common on Apple Silicon for non-notarized apps — clear the download quarantine in Terminal:

```
xattr -dr com.apple.quarantine "Nimbus Cloud Boss Battle.app"
```

The app is safe; macOS simply can't verify a paid developer identity. This is expected for ad-hoc, open-source builds.

On **Windows**, the unsigned `.exe` may trigger SmartScreen (*"Windows protected your PC"*) — click **More info → Run anyway**. It is the same unsigned-app notice; the build is safe.

A signed, auto-updating build for **Steam and itch.io** is planned and will be announced on the project site when it lands. Those versions are a convenience; the game is and always will be free and open source here.

## How it plays

Pick a boss on the menu — one per exam domain, plus a cross-domain warm-up and the Final Gauntlet (all 65 exam questions):

| Boss | Domain |
|---|---|
| The Cloud Gatekeeper | Cross-domain warm-up |
| The Breach Baron | D1 · Design Secure Architectures |
| The Chaos Monkey King | D2 · Design Resilient Architectures |
| The Latency Demon | D3 · High-Performing Architectures |
| Bill Shock, Budget Devourer | D4 · Cost-Optimized Architectures |
| The Examiner | Final Gauntlet (full exam set) |

Mechanics, designed for learning:

- **Correct answer** → damage the boss. Streaks build a combo multiplier (up to 2x XP). Every 4-streak restores a heart.
- **Wrong answer** → lose a heart, and the question is re-queued a few rounds later — you must beat every question to defeat the boss (active recall).
- **Every answer shows the explanation**, right or wrong.
- **Long bosses are resumable**: progress is checkpointed after every question, and leaving mid-battle offers to save the run for later.
- XP, ranks (Cloud Novice → Solutions Architect Hero), best accuracy and best streak persist between sessions (`user://save.json`; on web exports this lives in browser storage).

## Game modes

Besides the boss battles, the main menu offers three modes that draw from the full question pool (all domains, shuffled; each question is asked at most once per run — no requeue):

- **Survival** — three wrong answers end the run. No heart regen, no second chances. Score is how many questions you answered correctly.
- **Points Decay** — start with **1000 points**; a wrong answer costs **100**, a correct one earns **50**. The pool is clamped at 0, and hitting 0 ends the run. Reaching the **100-question cap** ends the run as a win with whatever points are left.
- **Save the Pet** — pick a pet (cat, dog, parrot, fish, or hamster) on the menu card. **20 correct answers save it** (the goal scales down to the pool size for smaller custom sets); **3 wrong answers** and the pet is lost. A loss takes precedence if both thresholds are hit. The chosen pet appears on screen as a small animated cartoon avatar and reacts to correct and wrong answers.

All modes keep the combo/XP rules from the boss battles, show every explanation, and record a per-mode best score and attempt count in the save file. Runs that draw from a player-authored custom set are practice only: they award no XP and no leaderboard entry. The thresholds live in `scripts/mode_rules.gd` as pure, unit-tested functions.

## Flashcards (Leitner)

A spaced-repetition study mode over the book's **186 flashcards** (`data/flashcards.json`). Each card shows a term; click it to flip to the definition (with a flip animation), then grade yourself **Got it** or **Again**. "Got it" promotes the card through Leitner boxes (review intervals of 0 / 2 / 5 / 10 days); "Again" sends it back to box 1. Box state persists in the save. The scheduling logic lives in `scripts/review_scheduler.gd` (pure, unit-tested).

## Languages

UI strings are translated through flat JSON files in `data/i18n/`, with `en.json` as the fallback. The shipped set mirrors the book's `chapters/` reference list — 19 languages: en, ar, bn, de, es, fr, he, hi, id, ja, ko, pt, ru, sw, th, tr, ur, vi, zh. Languages listed in `LANGS` (`scripts/game_state.gd`) that have a file appear in the in-game language picker. AWS service names (and the bosses' proper names) stay in English in every language. Question content itself is currently English only. Right-to-left locales (ar, he, ur) switch the scene layout direction accordingly.

The test suite enforces translation health: every language file must load, match `en.json`'s key set exactly, and keep format placeholders (`%d`, `%s`, `%.1f`) in the same order as English. To add a language: create `data/i18n/<code>.json` with all keys and add the entry to `LANGS`.

Script-coverage note: subsetted Noto fonts for the CJK, Arabic, Hebrew, Indic, and Thai locales ship in `assets/fonts/` and are chained as the theme's fallback font (`scripts/ui_fonts.gd`), so those scripts render on every platform — including Web exports, which have no system fonts.

## Accessibility

A text-size control (**A− / A / A+**) sits next to the language picker: shrink, reset to default, or enlarge all in-game text. The scale (0.85×–1.5×) persists in the save and applies on startup across every screen.

## Run it

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot → Import → select this folder's `project.godot`.
3. Press F5 (Run Project).

From a terminal, `./godot.sh` launches the project and `./run-game.sh` is kept as a readable alias. The shortcut locates Godot from `$GODOT`, `PATH`, or the standard macOS app path.

## Export to HTML (play in the browser)

1. In Godot: Editor → Manage Export Templates → Download and Install.
2. Project → Export… → Add… → **Web**.
3. Set the export path (e.g. `build/web/index.html`) → Export Project.
4. Serve the folder over HTTP (browsers block `file://` for wasm):
   `python3 -m http.server -d build/web 8000` → open http://localhost:8000
5. For GitHub Pages: commit the exported files. If the page hangs on load, add a `coi-serviceworker` shim or set the export's "Head Include" per Godot's [Web export docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html) (Pages can't send the COOP/COEP headers Godot's threads need; in Export → Web you can also disable "Thread Support" to avoid this entirely).

## Unit tests

Game rules live in `scripts/battle_rules.gd` and `scripts/mode_rules.gd` (pure functions) and are covered by `tests/run_tests.gd`, along with question-bank integrity, save/record logic, checkpoint validation, mode win/lose boundaries (Survival, Points Decay, Save the Pet), and i18n consistency (key parity and matching format placeholders between `en.json` and every shipped locale). Run headless from the project folder:

```
./run-tests.sh
```

You can also pass raw Godot arguments through the shortcut, for example `./godot.sh --headless --path . -s tests/run_tests.gd`. Exits 0 on success, 1 on failure — CI-friendly. Your save file is snapshotted and restored by the tests.

## Updating the questions

`data/questions.json` is a copy of `docs/api/questions.json` from the book site, plus supplemental batches appended over time. To sync after editing the book's exam-prep questions, just copy the file over again — the game reads it at startup, nothing else to change.

The file also carries a summary block (`generatedAt` / `contentHash` / `counts`) at the top. After any manual edit to the `questions` array, regenerate that block with:

```
python3 data/build_question_stats.py
```

The test suite fails if the block drifts out of sync with the actual array.

## Project layout

```
project.godot           # Godot 4 config (GL Compatibility renderer — web-friendly)
godot.sh                # local Godot shortcut; no args runs this project
data/questions.json     # question bank (662 questions, SAA-C03 domains)
data/flashcards.json    # 186 Leitner flashcards (from the book)
data/i18n/              # UI translations (en.json fallback + 18 locales)
assets/fonts/           # subsetted Noto fallback fonts for non-Latin scripts
scenes/                 # minimal scenes; UI is built in code
scripts/game_state.gd   # autoload: question bank, battles, modes, i18n, save data
scripts/main_menu.gd    # boss select, game modes, language picker
scripts/battle.gd       # boss battle loop, combo, requeue, checkpoints, results
scripts/battle_rules.gd # pure boss-battle rules (unit-tested)
scripts/mode_rules.gd   # pure mode rules: Survival, Points Decay, Save the Pet
scripts/mode_battle.gd  # run loop for the extra game modes
scripts/flashcards.gd   # Leitner flashcard review screen
scripts/review_scheduler.gd # pure Leitner spaced-repetition rules (unit-tested)
scripts/pet_avatar.gd   # animated cartoon pet renderer for Save the Pet
scripts/ui_theme.gd     # shared styles (no art assets needed)
scripts/ui_fonts.gd     # fallback font chain for the Web export
scripts/ui/dialog_view.gd # shared modal dialog (resume/leave/abandon)
```
