# Running FORGE on iPhone and Apple Watch

This guide takes you from a fresh clone to FORGE running on your own iPhone and Apple Watch.

## Build status (verified 2026-10-08)

| Check | Result |
|---|---|
| iOS app, Simulator build (`generic/platform=iOS Simulator`) | ✅ builds, 0 warnings |
| iOS app, device build (`generic/platform=iOS`), Watch app embedded | ✅ builds, 0 warnings |
| watchOS app, Simulator + device (`FORGEWatch` scheme) | ✅ builds, 0 warnings |
| Unit tests (`FORGETests`, iPhone 17 Simulator, iOS 26.5) | ✅ 43 tests in 8 suites pass |

Toolchain: Xcode 27.0 (27A266a), iOS/watchOS 27.0 SDKs, deployment target iOS/watchOS 26.0.

Fixes made to get here:

- `FORGE/Health/HealthService.swift`: the `HealthService.snapshot()` default argument read the main-actor `WorkoutTracker.shared` from a nonisolated context. It now resolves the store inside the function. This was a Swift 6 error-in-waiting.
- `FORGE/App/FORGEApp.swift`: the remote-notification handler switched from the `async` overload to the `fetchCompletionHandler` overload. The `async` overload sends a non-Sendable `userInfo` across actors, which is another Swift 6 error-in-waiting.
- `Shared/Persistence.swift`: under XCTest, `DataStore.shared` uses an in-memory, non-CloudKit store. Unsigned test hosts have no iCloud entitlement, so SwiftData's CloudKit mirroring trapped (`SIGTRAP` in `PFCloudKitContainerProvider`) before any test ran. The in-memory store also keeps tests away from real data.
- `project.yml`: added a `FORGEWatch` scheme so you can run and debug directly on the Watch.
- Added a free-team `Personal` configuration with its own schemes. See [Without a paid account](#without-a-paid-account).

Reproduce the checks without signing:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # or run xcode-select once, see below
xcodegen
xcodebuild -scheme FORGE      -destination 'generic/platform=iOS'     CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme FORGEWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme FORGE      -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
```

> [!NOTE]
> On this Mac, `xcode-select` points at the Command Line Tools, so a bare `xcodebuild` fails with *"requires Xcode"*. Fix it once with
> `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
> Also, no simulator devices exist yet. Create one in Xcode › Settings › Components, or run
> `xcrun simctl create "iPhone 17" com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-26-5`.

---

## 1. What you need

- **Mac with Xcode 26 or later.** Xcode 27 is installed here.
- **iPhone on iOS 26+.** The AI Coach needs Apple Intelligence (iPhone 15 Pro or newer) with Apple Intelligence turned on. Without it, the rule-based coach takes over automatically.
- **Apple Watch on watchOS 26+,** paired to that iPhone (optional).
- **Apple Developer Program membership ($99/yr).** FORGE uses iCloud/CloudKit, iCloud key-value storage, push notifications (`aps-environment`) and time-sensitive notifications. A free Personal Team can't provision iCloud or push. See [Without a paid account](#without-a-paid-account) for a workaround.

## 2. Make the project yours

The bundle IDs (`com.taj.forge…`) and the iCloud container (`iCloud.com.taj.forge`) have to be registered under *your* team. If you are Taj and own those IDs, skip to step 3.

1. Find your Team ID: [developer.apple.com/account](https://developer.apple.com/account) › Membership details. It's a 10-character string.
2. In `project.yml`, set it once so it survives regeneration:
   ```yaml
   settings:
     base:
       DEVELOPMENT_TEAM: "ABCDE12345"
   ```
3. If someone else already owns `com.taj.forge`, choose your own prefix and change it everywhere:
   - `bundleIdPrefix`, and the three `PRODUCT_BUNDLE_IDENTIFIER`s (`…forge`, `…forge.tests`, `…forge.watchkitapp`). The Watch ID **must** be the iPhone ID + a suffix.
   - `WKCompanionAppBundleIdentifier` in the Watch `info` block, which must equal the iPhone bundle ID.
   - `iCloud.com.taj.forge` and the `ubiquity-kvstore-identifier` values in `FORGE/FORGE.entitlements` and `FORGEWatch/FORGEWatch.entitlements`.
   - `DataStore.cloudContainerID` in `Shared/Persistence.swift`.
4. Run `xcodegen` again, then `open FORGE.xcodeproj`.

## 3. Signing and capabilities in Xcode

For each of the **FORGE** and **FORGEWatch** targets, open *Signing & Capabilities*:

1. Tick **Automatically manage signing** and pick your Team. Xcode registers the App IDs for you.
2. Under **iCloud**, make sure *CloudKit* is checked and the container `iCloud.com.taj.forge` (or yours) is listed and ticked. If it shows red, press **+** to create the container under your team, then hit the refresh button.
3. Confirm **HealthKit**, **Push Notifications** and **Background Modes** (iPhone: *Remote notifications*, *Workout processing*; Watch: *Workout processing*) are present. They come from the checked-in `.entitlements` files and `project.yml`, so you shouldn't need to add them by hand.
4. If signing errors appear after you change IDs, try *Product › Clean Build Folder*, then let Xcode retry provisioning.

> Edit Info.plist keys in `project.yml` and entitlements in the `.entitlements` files, not in Xcode's target editor. The next `xcodegen` overwrites changes made in the generated project.

## 4. Prepare your devices

**iPhone**

1. Connect it by USB the first time, unlock it and tap **Trust This Computer**.
2. Turn on *Settings › Privacy & Security › Developer Mode*. The toggle appears only after Xcode has seen the phone once. The phone restarts; confirm when it comes back.
3. Sign in to iCloud on the phone. CloudKit sync and Crews need it, and the app falls back to local storage without it.
4. Optional: in Xcode › Window › Devices and Simulators, tick **Connect via network** to deploy over Wi-Fi from then on.

**Apple Watch**

1. Keep it paired to that iPhone, unlocked, on the charger or on your wrist, and on the same Wi-Fi as the Mac. Bluetooth on the Mac helps.
2. In *Devices and Simulators*, the Watch appears under the iPhone. The first time, Xcode spends a few minutes *preparing* the Watch and copying debug symbols. Leave it alone until that finishes.
3. On the Watch, turn on *Settings › Privacy & Security › Developer Mode* and confirm after the restart.

## 5. Run it

**iPhone (installs the Watch app too)**

1. Choose the **FORGE** scheme and your iPhone as the destination. Press **⌘R**.
2. On the first launch of a dev-signed app you may need *Settings › General › VPN & Device Management* › your developer profile › **Trust**.
3. Allow Health access when asked. That covers heart rate, sleep and HRV, plus permission to write workouts.

The Watch app is embedded in the iPhone app (`FORGE.app/Watch/FORGEWatch.app`). If *Watch app › General › Automatic App Install* is on, it installs on the Watch automatically. Otherwise, open the **Watch** app on the iPhone and tap **Install** next to FORGE under *Available Apps*.

**Debugging on the Watch**

Choose the **FORGEWatch** scheme and your Watch as the destination (*iPhone name › Watch name*), then press **⌘R**. Watch deploys are slower than iPhone deploys and drop more often. If one stalls, unlock the Watch, keep it near the Mac and retry.

## 6. First-run checklist

- [ ] Onboarding finishes and **Today** shows a coach pick.
- [ ] The AI Coach answers in chat. If you only get rule-based plans, check *Settings › Apple Intelligence & Siri* on the phone. The model may still be downloading.
- [ ] Start a workout, log a set, and finish it. The workout shows up in the **Fitness** app and in *Health › Workouts*.
- [ ] Open the Watch app and see today's plan. Log a set with the Digital Crown and check heart rate.
- [ ] Data syncs to a second device on the same Apple Account (allow a minute or two).
- [ ] Crews: turn on *Settings › Crews (beta)* and create a crew. This writes the CloudKit development schema. Test invites with a second Apple Account on another device.

## 7. What doesn't work in the Simulator

| Feature | Simulator | Device |
|---|---|---|
| UI, plans, history, tests | ✅ | ✅ |
| `HKWorkoutSession`, live heart rate, calories | ❌ no sensors | ✅ |
| Foundation Models AI Coach | Only when the Mac itself has Apple Intelligence on | ✅ (eligible iPhone) |
| CloudKit sync / Crews | Partial (sign in to iCloud in the Simulator) | ✅ |
| Push notifications for crew nudges | ❌ unreliable | ✅ |

## Without a paid account

A free Personal Team can't sign iCloud, CloudKit, push or time-sensitive notifications. Instead of the `FORGE` scheme, run the **`FORGE Personal`** scheme (use `FORGEWatch Personal` to debug on the Watch). It builds the `Personal` configuration, which:

- signs with `FORGE/FORGE-Personal.entitlements` and `FORGEWatch/FORGEWatch-Personal.entitlements`, which contain HealthKit only
- compiles with `PERSONAL_TEAM`, so SwiftData uses a local store (SwiftData traps at launch if it's asked for CloudKit without the entitlement), settings live in `UserDefaults`, and Crews is hidden
- still sends today's plan straight to the Watch over WatchConnectivity, and runs one shared workout across iPhone and Watch, because neither needs iCloud

```sh
xcodebuild -scheme "FORGE Personal" -configuration Personal \
  -destination 'platform=iOS,name=<your iPhone>' -allowProvisioningUpdates build
```

Free-team builds expire after 7 days. Re-run from Xcode to refresh them.

## Sharing with others: TestFlight

1. In the [CloudKit Console](https://icloud.developer.apple.com/), **deploy the development schema to production**. Otherwise Crews and sync fail in TestFlight and App Store builds.
2. Change `aps-environment` to `production` for release builds, or let Xcode's archive/export step set it.
3. Bump `CURRENT_PROJECT_VERSION` in `project.yml`, then choose *Product › Archive* with the **Any iOS Device** destination, and in the Organizer choose *Distribute App › TestFlight*.
4. Create the app record in App Store Connect with the same bundle ID. Fill in the Health data usage and privacy answers. HealthKit apps get extra review scrutiny.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `xcodebuild` says "requires Xcode, but active developer directory … is a command line tools instance" | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| Crash at launch in `PFCloudKitContainerProvider` / `CKContainer` | The build has no iCloud entitlement. Fix signing (step 3), or use the `FORGE Personal` scheme. |
| "Personal development teams … do not support the iCloud and Push Notifications capabilities" | You're on a free team. Use the `FORGE Personal` scheme. |
| "Your team has no devices from which to generate a provisioning profile" | Build once with your iPhone selected as the destination (with Developer Mode on), so Xcode registers it. |
| "No profiles for 'com.taj.forge' were found" | The bundle ID isn't registered to your team. Set your Team, or change the IDs (step 2). |
| iCloud container shows red in Signing & Capabilities | The container doesn't exist under your team. Press **+**, create it, then refresh. |
| Watch app doesn't appear on the Watch | Watch app on iPhone › FORGE › Install. Check that `WKCompanionAppBundleIdentifier` matches the iPhone bundle ID. |
| Xcode stuck at "Preparing Apple Watch…" | Keep the Watch unlocked and near the Mac. Restart the Watch and Xcode. Toggle Developer Mode off and on. |
| Workouts don't appear in Fitness | Check *Settings › Health › Data Access & Devices › FORGE*. Workout write must be allowed. |
| Signing settings disappear after `xcodegen` | Put `DEVELOPMENT_TEAM` in `project.yml`, not in Xcode. |
