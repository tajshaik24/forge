# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

FORGE is an iOS 27 + watchOS 27 SwiftUI strength-training app with an on-device AI coach (Apple Foundation Models). It's pre-alpha: the repo is public, but the app is not ready to publish.

The deployment target is iOS/watchOS 27.0 (built with Xcode 27 and the 27.x SDKs), so iOS 27 APIs can be used without `#available` checks. Point releases still need them, as in `Fold.swift`'s `#available(iOS 27.1, *)`. Prefer the iOS 27 API over one deprecated in 27; for example, catch `LanguageModelError`, not `LanguageModelSession.GenerationError`.

## Release rules

- **Never submit to App Store review.** TestFlight uploads are fine, but only when the user asks for one.
- The build number is `CURRENT_PROJECT_VERSION` in `project.yml`. Bump it, run `xcodegen`, then archive and export with the `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` flags. The App Store Connect API key config lives in `~/.appstoreconnect/config.json`; don't ask the user for it.

## Commands

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen -q          # regenerate FORGE.xcodeproj; required after adding, removing or renaming any file

# All tests (Swift Testing)
xcodebuild test -project FORGE.xcodeproj -scheme FORGE -destination 'platform=iOS Simulator,name=iPhone 17'
# One suite, or one test (note the trailing parentheses)
xcodebuild test ... -only-testing:FORGETests/ChatDecisionTests
xcodebuild test ... '-only-testing:FORGETests/ChatDecisionTests/questionsChangeNothing()'

# The Watch app builds separately; check it after changing Shared/
xcodebuild build -project FORGE.xcodeproj -scheme FORGEWatch -destination 'generic/platform=watchOS Simulator'

# Open the app on one demo screen in the simulator (DEBUG only; screen names in FORGE/Debug/*Screens.swift)
xcrun simctl launch <sim> com.taj.forge -demo -screen today
```

The test summary line is `Test run with N tests …`. Grep for it, and for `✘`, to find failures.

### Testing the AI coach: `tools/coach-eval`

**The iOS Simulator can't run Foundation Models:** every request fails the safety filter. `tools/coach-eval/run.sh` compiles the real coach sources for macOS and runs them against the Mac's on-device model:

```sh
tools/coach-eval/run.sh                  # chat replies for every line of messages.txt
tools/coach-eval/run.sh my-messages.txt  # your own messages, one per line
PLAN=1 tools/coach-eval/run.sh           # the planner on five sample setups
SETS=1 tools/coach-eval/run.sh           # between-set rewording and recaps
```

- Run it after any change to a prompt, the instructions, a `@Generable` type or `CoachKnowledge`.
- The model's wording varies between runs, so read the output by eye. The deterministic decisions are unit-tested.
- `run.sh` lists the source files it compiles. A new file the coach depends on must be added there, and a new `CoachContext` field may need a value in `context.swift`.
- If compilation fails, the script can run the old binary without telling you. Check for compiler errors in the output.

## Gotchas

- **The Xcode project is generated** and git-ignored. Change targets, Info.plist keys and build settings in `project.yml`; entitlements are the checked-in `*.entitlements` files.
- **The project uses Swift 5 language mode**, so bare `/regex/` literals don't compile. Use `#/…/#`.
- **`Personal` config / `FORGE Personal` scheme** is for free Apple teams. It defines `PERSONAL_TEAM` and drops iCloud and push: SwiftData stays local, `SyncedSettings` uses `LocalSettingsStore`, and Crews are off. Keep both paths compiling.
- **The data model syncs through CloudKit.** `@Model` types are in `Shared/Persistence.swift`, with container `iCloud.com.taj.forge`. Avoid schema changes where possible. New Codable fields on stored structs must be optional so old data still decodes, as with `PlannedExercise.goal`. Small synced state can go in `SyncedSettings` as JSON instead; skill goals do this.
- **HealthKit workouts, Watch mirroring and the Live Activity** need real hardware. See `docs/scope-device-watch-live.md`.
- **Visual style is "Chalk":** chalk white, ink text and a cobalt accent, with a slate dark mode. Use the `Shared/Theme.swift` tokens, make UI work in light and dark, and never bring back orange.

## Architecture

### Targets

| Target | What it is |
|---|---|
| `FORGE/` | iPhone app: views, coach, Crews, Live Activity controller, intents |
| `FORGEWatch/` | Watch app |
| `FORGEWidgets/`, `FORGEWatchWidgets/` | Widget extensions |
| `Shared/` | Compiled into both apps: models, exercise catalog, progression, strength math, skill goals, `WorkoutTracker` (HealthKit session + mirroring), phone↔watch link, theme |

Anything the Watch uses must live in `Shared/`.

### Coach pipeline (`FORGE/Coach/`)

The guiding rule: **the rules decide, the model words.** Anything that has to be predictable is done in code, and the model's structured output is checked against the athlete's own words before anything is acted on. That includes which lifts are allowed, weights, goal steps, notes, and changes to time, rest days or gyms.

**Shared machinery:**
- `CoachStore` (`@Observable`) owns the coach. It builds a `CoachContext`: readiness, notes, goals, gyms, health, recent sessions and the current plan. It then calls the active `CoachEngine` and applies the reply: saving notes, replanning, rest days, switching gyms, goal offers and progress.
- The two `CoachEngine` implementations:
  - `AppleIntelligenceCoach` uses Foundation Models.
  - `RuleBasedCoach` is the fallback when Apple Intelligence is off or a request fails.

**Planning:**
1. The rules pick the day's focus (`rankedTemplates`).
2. The model picks lifts from a short candidate list (`PlanFinisher.candidates`).
3. **Every plan, AI or rule-based, goes through `PlanFinisher.finish`.** It validates catalog names, checks equipment and notes, applies pattern caps, covers every muscle, sets rep schemes, adds `Progression` weight targets and inserts skill-goal steps.

**Chat:**
1. `CoachPrompts.chat` builds a compact prompt. It includes only the facts relevant to the message, plus `App:` lines saying what the app itself is doing.
2. The model returns a `@Generable GeneratedReply`.
3. `ChatDecision.make` turns it into a `CoachReply`. This is where off-topic filtering, question/request detection, note rules, goal offers, minutes, rest days, gym switches and reply cleanup happen.
4. `CoachKnowledge` holds short, fixed coaching answers that are inserted into the prompt by topic.

**Between sets:** `SetCoach` asks the model to reword the rules' next-set note. A reword is kept only if every number in it came from the rule (`keepsNumbers`).

**Skill goals:** `Shared/SkillGoals.swift` has two kinds:
- Ladders of easier versions that lead to a bodyweight lift (pull-up, chin-up, push-up, dip).
- "Priority lifts" for weighted lifts.

Progress through a ladder is rule-based: two qualifying sessions per step.

**Constraints of the on-device model.** Each one caused a real failure:
- **No tools in sessions.** Tool calls trip the safety filter on harmless chat, and their round trips overflow the 8,192-token context. Put facts in the prompt instead.
- **No concrete examples in `@Guide` text or instructions.** The model copies them into its output.
- **The safety filter is nondeterministic.** Chat retries once with `minimal: true` before falling back to the built-in coach.
- **Never trust a model field on its own.** Check it in `ChatDecision` against the message, and add a test there that uses deliberately wrong model fields.
- The README's "How the AI Coach works" section still describes a `findExercises` tool. That tool was removed; the code is the source of truth.

### Exercises and progression

- `Shared/ExerciseCatalog.swift`:
  - Exercise names are identifiers, used in plans, sets, notes and goals.
  - It also holds aliases, `easierVersions`/`harderVersion` and the movement flags (`MovementFlag`) that notes can rule out.
  - Every exercise needs a form guide (`FORGE/Views/FormGuides*.swift`); `LibraryTests` enforces that.
- `Exercise.isBodyweight` (equipment is only pull-up bar, dip station, bench, foam roller or bands) controls calibration, rep schemes and weight display. Weight progression in `Progression`/`NextSet` deliberately keeps the `equipment.isEmpty` check, so a weighted pull-up keeps its added weight.
- `Shared/Strength.swift` covers the estimated 1RM, the "First Heat" test sets and goal-based working weights. `Shared/Progression.swift` does double progression from RPE (the Easy/Good/Hard taps).

### Devices and sync

- **Data:** SwiftData syncs through the CloudKit private database. Settings use `SyncedSettings` over `NSUbiquitousKeyValueStore`.
- **Plans to the Watch:** today's plan goes over WatchConnectivity (`PhoneWatchLink`).
- **Live workouts:** the Watch runs the HealthKit workout and the iPhone mirrors it (`WorkoutTracker`, with `MirrorMessage` coding). Health gets exactly one workout.
- **Live Activity:** the rest timer, in `FORGE/Activity/` plus `FORGEWidgets`.
- **Crews (beta):** CloudKit zone-wide sharing, in `FORGE/Crew/`.

## Docs

- `docs/gameplan.md`: the roadmap and the order to build things in.
- `docs/running-on-device.md`: signing and device setup.
- `docs/scope-device-watch-live.md`: hardware test checklists.
- `docs/mockups/`: the HTML mockups behind the README screenshots, rendered with `tools/render_mockups.py`. The icon comes from `tools/make_icon.py`.
