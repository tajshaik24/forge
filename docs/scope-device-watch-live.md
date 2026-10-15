# Scope: device build, Watch ↔ iPhone mirroring, Live Activity, widgets, complication

Status as of 2026-10-14. This doc covers what each roadmap item means, how it's built, and what "done" looks like.

| Item | Code | On device |
|---|---|---|
| 1. Device build + free-team config | ✅ builds, 0 warnings | ✅ installed and running on iPhone |
| 2a. Plan → Watch (WatchConnectivity) | ✅ `Shared/PhoneWatchLink.swift` | ⏳ |
| 2b. Shared workout (mirroring) | ✅ `Shared/WorkoutTracker.swift`, `Shared/MirrorMessage.swift`, both workout screens, Today "Live on Apple Watch" card; message coding unit-tested | ⏳ hardware only |
| 3a. Live Activity / Dynamic Island | ✅ `FORGEWidgets/` extension, `FORGE/Activity/` (Skip / +30 s buttons) | ⏳ |
| 3b/3c. Widgets + complication | ⏸ waiting on the App Group check (§0) | — |

As built, the Live Activity runs while the workout screen is open on the iPhone. That covers workouts started on the phone, and Watch-started workouts once you open them from the Today card. Showing it for a Watch-started workout without ever opening the phone is a follow-up.

## 0. Constraints that shape everything

- **The team is a free Personal Team.** It can't sign iCloud, push or time-sensitive notifications. The free-team **Personal** build configuration (`FORGE Personal` / `FORGEWatch Personal` schemes, `PERSONAL_TEAM` flag) drops those capabilities and uses local storage. Everything below has to work **without iCloud and without push**. When the paid program is active, the `FORGE` scheme brings sync and Crews back with no other changes.
- **Without iCloud, the Watch had no way to get today's plan.** Today the Watch reads `DailyPlan` from SwiftData, which arrives only through CloudKit. On the free team, the Watch always shows "Open FORGE on your iPhone". The mirroring work fixes this with a direct phone → Watch channel (WatchConnectivity), which needs no entitlement.
- **Free-team builds expire after 7 days.** Re-run from Xcode to refresh them.
- **App Groups:** widgets and the complication read data from a shared App Group container. Whether a Personal Team can provision App Groups is checked on the first signed build. If it can't, widgets and the complication wait for the paid program (see §3). The Live Activity doesn't need an App Group.

## 1. First device build ✅ compile / ⏳ device

| Step | State |
|---|---|
| Compiles: iOS + watchOS, Simulator + device, 0 warnings | ✅ |
| 43 unit tests pass | ✅ |
| Free-team `Personal` configuration (entitlements, local store, local settings, Crews hidden) | ✅ builds, capabilities accepted by Apple |
| Device registered + provisioning profile | ✅ |
| Installed + launched on iPhone, Watch app installed | ✅ iPhone · ⏳ Watch |
| First-run checklist (`docs/running-on-device.md` §6) | ⏳ you, on the phone |

**Done when:** FORGE launches on the iPhone, you can complete a workout, and it appears in Fitness. The Watch app installs and shows today's plan, which also depends on §2a.

## 2. Watch ↔ iPhone workout mirroring

**Goal:** one live workout, whichever device you start on. Heart rate comes from the Watch, you can log sets on either screen and both stay in step, and Health gets **one** workout instead of two.

### 2a. Plan + settings to the Watch (WatchConnectivity)
- New `Shared/PhoneWatchLink.swift`: a `WCSession` wrapper on both sides.
- The iPhone pushes `updateApplicationContext` with today's `PlannedWorkout` (already `Codable`), the unit, and recent weights per exercise for prefill. It sends whenever the plan changes and on launch.
- The Watch caches the latest context and `WatchPlanView` reads it when there's no synced `DailyPlan`. With iCloud, SwiftData still wins. Without it, this is the only source.

### 2b. One shared HealthKit session (HealthKit mirroring API)
- **The Watch always owns the workout.** It has the heart-rate sensor, and only one session should write to Health.
  - **Started on the Watch:** `WorkoutTracker.start` calls `session.startMirroringToCompanionDevice()`.
  - **Started on the iPhone with a reachable, paired Watch that has the app:** the iPhone calls `HKHealthStore.startWatchApp(toHandle:)`. The Watch app launches in the background (`handle(_ workoutConfiguration:)` in a `WKApplicationDelegate`), starts the primary session and mirrors back to the phone.
  - **No Watch:** the iPhone runs its own session, which is today's behavior.
- **iPhone side:** `store.workoutSessionMirroringStartHandler` is set at launch. It adopts the mirrored session and reads live heart rate and calories from the mirrored builder. `ActiveWorkoutView` behaves the same whether the session is local or mirrored.
- **Messages over `sendToRemoteWorkoutSession(data:)`** (small JSON `MirrorMessage` enum):
  - `setLogged(exercise, weight, reps, rpe, start, end)`: either side, to the other
  - `restStarted(until, next)` / `restEnded`: keeps both rest timers in step
  - `position(exerciseIndex, setNumber)`
  - `finish`: the iPhone asks the Watch to end and save
- **Persistence rule:** the **iPhone stores** sets, since it's the history and plan source of truth, and on the free team the only store. The Watch writes the HealthKit segment events, since it owns the builder. The Watch also stores sets locally only when it isn't mirrored, so they reach the phone over iCloud on the paid build.
- **Finish:** whichever side taps Finish, the Watch ends the session and saves the workout to Health, then sends the summary stats (`healthWorkoutID`, calories, average and max heart rate, timeline). The iPhone fills in `WorkoutSession` and shows `SummaryView`.

**Done when:** you start on the phone and the Watch picks it up, log a set on the Watch and it appears on the phone within about 1 s (and the other way round), the phone shows the Watch's heart rate, and exactly one workout appears in Fitness.

**Risks:** mirroring only works in a live session on real hardware, so the Simulator can't test it. The background launch through `startWatchApp` can take 2–5 s and fails if the Watch is locked; the UI shows "Starting on Watch…" and falls back to a phone-only session after a timeout.

## 3. Live Activity, widgets, Watch complication

### 3a. Live Activity / Dynamic Island rest timer (iPhone, also on the Watch Smart Stack)
- New **`FORGEWidgets`** iOS widget-extension target. `NSSupportsLiveActivities = YES` on the app.
- `WorkoutActivityAttributes` (Shared): static focus. `ContentState` holds exercise, set *n/m*, rest end date (optional), next-up text, heart rate and workout start.
- Lock Screen + Dynamic Island (compact/minimal/expanded): rest countdown with `Text(timerInterval:)` and `ProgressView(timerInterval:)`, so no per-second updates are needed. When not resting, it shows elapsed workout time and the current set.
- Buttons (`LiveActivityIntent`): **Skip rest** and **+30 s**. They run in the app process and update the activity, the rest notification and, through §2, the Watch.
- Started and updated by a `LiveActivityController` the app calls on start, set logged, rest start/end and finish. Updates are local only, since there's no push on the free team. That's enough because the app stays alive in the background during an active workout session.
- On watchOS 26 the iPhone Live Activity appears in the Watch Smart Stack automatically.

**Done when:** you lock the phone during rest, the countdown runs on the Lock Screen and in the Dynamic Island, Skip and +30 s work, and the activity ends on Finish.

### 3b. Home/Lock Screen widgets (iPhone)
- Same extension. **Today** widget (small/medium + accessoryRectangular) shows the focus, number of moves, minutes and gym, or "Rest day". **Streak** (accessoryCircular / small) shows week streak and this week's sessions.
- Data: a small `WidgetSnapshot` JSON written by the app to the App Group (`group.com.taj.forge`) whenever the plan or history changes, then `WidgetCenter.reloadAllTimelines()`.

### 3c. Watch complication
- New **`FORGEWatchWidgets`** watchOS widget-extension target (WidgetKit complications): accessoryCircular (week streak ring), accessoryRectangular (today's focus + moves), accessoryCorner, and accessoryInline. Tapping a complication opens the Watch app.
- Data: the Watch app writes the same `WidgetSnapshot` to its App Group from the WatchConnectivity context (§2a).

**Gate:** 3b and 3c need the App Group capability. If the Personal Team can't provision it, these are built and kept compiling but signed only on the paid team's `FORGE` scheme.

## Build order

1. Device build: finish when Developer Mode is on.
2. 2a, plan to the Watch: small, and makes the free-team Watch useful straight away.
3. 2b, mirroring.
4. 3a, Live Activity: builds on the shared workout state from step 3.
5. 3b + 3c, widgets and complication: after the App Group check.

Every step keeps both configurations building with 0 warnings and the unit tests passing. Pure logic (message coding, snapshot building, which device owns the workout) gets unit tests. Hardware behavior is checked on your devices with the checklist in each "Done when".
