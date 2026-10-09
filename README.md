# FORGE

A strength-training app in the spirit of PUSH. An on-device Apple Intelligence coach picks today's session from muscle readiness, your training days, your gym's equipment and what you've told it ("squats make me lightheaded").

## Run it

```sh
brew install xcodegen      # once
cd ~/Developer/FORGE
xcodegen                   # writes FORGE.xcodeproj from project.yml
open FORGE.xcodeproj
```

Requirements: Xcode 26 or later, iOS 26 / watchOS 26. In **Signing & Capabilities**, set your team on both targets. Xcode will register the iCloud container `iCloud.com.taj.forge`; change it in `project.yml` and `Shared/Persistence.swift` (`DataStore.cloudContainerID`) if you want a different ID. The AI coach needs a device with Apple Intelligence turned on. Without it, FORGE falls back to a built-in rule-based coach.

## How it's put together

| Folder | What's inside |
|---|---|
| `Shared/` | Used by both iPhone and Watch. SwiftData models (CloudKit-ready), exercise catalog, form guides, HealthKit `WorkoutTracker`, theme. |
| `FORGE/Coach/` | `CoachEngine` protocol, `AppleIntelligenceCoach` (Foundation Models), `RuleBasedCoach` fallback, `CoachStore`. |
| `FORGE/Views/` | Today, Plan, Exercise (form guide), Active workout, Summary, Coach chat, Notes, Week, Gyms. |
| `FORGE/Intents/` | Siri / Shortcuts: "What's today's workout in FORGE", "Log a set in FORGE". |
| `FORGEWatch/` | Watch app: today's plan, Digital Crown set logging, rest timer, live heart rate. |

### The AI coach
- `AppleIntelligenceCoach` uses `LanguageModelSession` with **guided generation** (`@Generable GeneratedDayPlan`). The model returns a typed plan, not free text.
- **Tool calling:** the model calls `findExercises(muscle:)`. That tool only returns exercises that (a) the active gym's equipment supports and (b) no coach note rules out. This means the model can't suggest a leg press at your home gym, or a back squat after you said squats make you lightheaded.
- **Chat → notes:** `GeneratedReply` decides whether a message is lasting feedback, turns it into a rule plus `MovementFlag`s to avoid, and triggers a replan.
- `PlanFinisher` runs on every engine's output. It validates names against the catalog, tops up thin plans, trims volume when sleep or HRV are under your baseline, adds "replaces back squat" labels, and lengthens rest when a note calls for caution.

### Sync
- SwiftData syncs through your **private iCloud database (CloudKit)** to iPhone, Watch and iPad. There's no server to run, and the data stays in your iCloud account.
- Training days, split, goal and session length live in iCloud key-value storage (`SyncedSettings`).
- Today's plan is stored as a `DailyPlan` record, so the Watch shows exactly what the iPhone coach built.

### Apple Health + Fitness
- Starting a workout runs an `HKWorkoutSession` with `HKLiveWorkoutBuilder` (Traditional Strength Training). This works on the Watch, and on iPhone with iOS 26.
- Live heart rate and active calories are shown during the workout.
- Every logged set is added to the workout as a segment event, with exercise, weight and reps in its metadata.
- Finishing saves the workout to Health, so it shows up in Fitness. FORGE keeps the workout ID plus average/max heart rate, calories and a heart-rate timeline for its summary screen.

### Coaching features
- **Weight targets** (`Shared/Progression.swift`): double progression. Each move gets a target (e.g. "+10 lb, you hit 12 on every set"). It holds the weight and adds a rep inside the range, and backs off if you fell short of the range.
- **Feedback loop:** per-set RPE and the "how did it feel" answer after a workout feed a session signal (`CoachContext.signal`). That signal eases or pushes load and volume, and is passed to the AI Coach prompt.
- **Week ahead:** `CoachStore.planWeek` plans each upcoming training day, accounting for the days already planned before it. Chat can target a day ("make Saturday shorter").
- **Mid-workout edits:** swap to an allowed alternative, add an exercise, skip, or fix/delete logged sets. Today's plan is updated, so the Watch sees the change too.
- **History:** weekly volume, week streak, past workouts, and per-lift estimated 1-rep max charts.
- **Custom exercises:** synced via iCloud and used by the coach like built-in ones.
- **First-run setup + Settings:** goal, experience (sets per exercise), training days, session length, lb/kg (weights are stored in lb), gym, Health and notification permissions.
- **Coach chat is saved** (`ChatEntry`) and syncs.
- **Rest alert:** a local notification when rest ends with the app in the background.
- **Tests:** `FORGETests/CoachLogicTests.swift` (Swift Testing), run with ⌘U.

## Not built yet (best done in Claude Code on the Mac)
- **Compile + first run:** nothing has been built yet; expect a round of compiler fixes.
- **Workout mirroring** between Watch and iPhone (`startMirroringToCompanionDevice`). For now, start the workout on one device; starting on both records two workouts in Health.
- **Live Activity / Dynamic Island** rest timer, a home-screen widget, and a Watch complication. These need extension targets.
- **"Scan this gym" from photos** (iOS 27 multimodal Foundation Models) and form demo videos.
- Two devices logging at the same moment, before iCloud syncs, can create two sessions for that day.
