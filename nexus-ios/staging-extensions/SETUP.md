# Nexus iOS — extension setup

Three pieces of native iOS surface are staged here as ready-to-add source. Each requires Xcode UI to add the target (5 minutes per target). Once the target exists, drop in the staged Swift files and synchronized folders pick them up automatically.

## 1. Widget Extension (briefing + activity widgets, Live Activity)

**Why:** Lock Screen + Home Screen briefing glance, Dynamic Island when Eve is thinking or firing Arena tools.

**Steps:**

1. Xcode → File → New → Target → **Widget Extension**
2. Name: `NexusWidgets`. Bundle ID: `nexus.nexus-ios.widgets`
3. Uncheck "Include Configuration Intent" (we use static configuration)
4. **Check** "Include Live Activity"
5. Drag the four files from `staging-extensions/NexusWidgets/` into the new target's source folder:
   - `NexusWidgetsBundle.swift`
   - `BriefingWidget.swift`
   - `LatestActivityWidget.swift`
   - `EveLiveActivity.swift`
6. Delete the auto-generated `NexusWidgets.swift` and `NexusWidgetsLiveActivity.swift` (the bundle file already declares both).
7. **App Group setup** (both the main app target AND this widget target need the same group):
   - Main `nexus-ios` target → Signing & Capabilities → **+ Capability → App Groups** → add `group.io.talkcircles.nexus`
   - `NexusWidgets` target → same
8. Main app `Info.plist` → add key **`NSSupportsLiveActivities`** = `YES` (required for ActivityKit to start activities)
9. Build & run main app — widget shows up in Add Widgets gallery.

Snapshots are written by the main app (already wired in `EveLiveActivityController.swift` etc.) into the App Group's UserDefaults, so the widget always reflects current state.

## 2. Share Sheet Extension (Share-to-Eve from any app)

**Why:** Long-press a tweet → "Share to Eve" → Eve has it. Email thread → Eve summarizes.

**Steps:**

1. Xcode → File → New → Target → **Share Extension**
2. Name: `NexusShare`. Bundle ID: `nexus.nexus-ios.share`
3. Drop `staging-extensions/NexusShare/ShareViewController.swift` into the target, replacing the auto-generated one.
4. **App Group**: same group as widget (`group.io.talkcircles.nexus`) on this target too.
5. The main app needs to consume the queue on launch — see `EveShareQueueConsumer.swift` (TODO: wire into `ContentView.task`).

## 3. Watch Complication

**Why:** Tap-to-launch Eve from the watch face. No extension needed; embeds in the existing Watch App target on watchOS 10+.

**Steps:**

1. Drop `staging-extensions/NexusWatchComplication/EveComplication.swift` into the existing `nexus-watch Watch App` target's source folder.
2. The Watch app's `nexus_watchApp.swift` needs a tweak — the complication is a separate Widget that needs its own `@main` declaration. Two routes:
   - **Easier**: add a new `NexusWatchComplication` Widget Extension target inside the Watch App, drop `EveComplication.swift` there, and let Xcode wire up the `@main`. Same bundle-ID-prefix rule applies (so: `nexus.nexus-ios.watchkitapp.complication`).
   - **Manual**: replace `nexus_watchApp.swift`'s `@main struct nexus_watch_Watch_AppApp: App` with a `WidgetBundle` that includes both the App scene and the complication widget. (Less standard; avoid unless you know what you're doing.)
3. After install → on the watch, long-press the watch face → Edit → tap a complication slot → pick "Eve" from the list.

---

## Entitlement-gated features (next sessions)

These need Apple Developer-portal entitlement requests AND/OR explicit user permission flows that should be designed deliberately. Source code patterns are already understood; they're parked for now.

### Push to Talk framework (`com.apple.developer.push-to-talk`)

Apple-blessed walkie-talkie API. Hold lock-screen channel button → Eve answers without unlocking. On-watch supported.

- Request entitlement: developer.apple.com → Identifiers → your App ID → enable "Push to Talk". Requires explanation to Apple of use case.
- Implementation: subclass `PTChannelManager`, register channel, handle `channelManager(_:incomingPushResultFor:)`.
- ~half a day of work once the entitlement is granted.

### CallKit (`com.apple.developer.user-management.calls`)

Eve places a real "incoming call" interface for genuinely urgent things.

- Entitlement is auto-included in iOS apps; no Apple approval needed.
- Implementation: `CXProvider`, `CXCallController`, VoIP push or local notification as trigger.
- Use sparingly — mis-use will get the app rejected.

### HealthKit (`com.apple.developer.healthkit`)

Sleep, workouts, HRV as briefing context.

- Entitlement is request-only (no Apple gating), but app will trigger explicit user permission per data type.
- `Info.plist` keys: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`.
- Implementation: `HKHealthStore`, `HKQueryDescriptor`, query sleep + workout last 24h, fold into briefing.
- Privacy: never send raw health data to nexus-web — only Eve-side derived summary ("you slept 4h").

### NFC (`com.apple.developer.nfc.readersession.formats`)

Tap NFC tags around your space to trigger Eve workflows.

- Entitlement is request-only.
- `Info.plist` key: `NFCReaderUsageDescription`, `com.apple.developer.nfc.readersession.iso7816.select-identifiers`.
- Implementation: `NFCNDEFReaderSession` for read; `NFCNDEFReaderSessionDelegate` to handle scans.
- App also needs to register URL schemes the tags will encode.

### Apple Intelligence Foundation Models (`com.apple.developer.foundation-models`)

On-device Eve via `import FoundationModels`. Already stubbed in `EveOnDeviceBrain.swift` with availability checks.

- Capability gate: requires Apple Intelligence to be enabled (iPhone 15 Pro+ or later, plus user opt-in).
- Implementation: stub already in place (`EveOnDeviceBrain.ask`). Wire as third brain tier in `EveVoiceManager` after cloud + local fallbacks.
- Entitlement is automatic when the framework is imported on a supported target.

### Always Allow Location (`com.apple.developer.location.always`)

Geofence triggers ("when I get home, brief me on incoming"). Currently we use significant-change with When-In-Use, which is enough for "where am I roughly" but not for "do something the moment I cross my driveway."

- User-prompted. App requests once, user grants in Settings.
- Apple reviews: needs a clear written justification in App Store Connect.
- Implementation: `CLLocationManager.startMonitoring(for: CLCircularRegion(...))`.
