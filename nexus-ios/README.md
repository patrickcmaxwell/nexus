# Nexus iOS

Native iPhone app for Nexus — talk to Eve from anywhere.

## Setup in Xcode

1. Create a new Xcode project: iOS App, SwiftUI, Swift
2. File → Add Package Dependency → `https://github.com/supabase/supabase-swift`
3. Copy these files into your Xcode project:
   - `SupabaseManager.swift` — Supabase connection
   - `EveVoiceManager.swift` — voice recording + Hey Sync
   - `EveMemoryManager.swift` — loads correct memory per user
   - `ContentView.swift` — main UI
4. Add `eve-base.md`, `eve-private.md`, `eve-shared.md` to the Xcode target bundle
5. Replace `YOUR_PROJECT_URL` and `YOUR_ANON_KEY_HERE` in `SupabaseManager.swift`
6. Add permissions to `Info.plist`:
   - `NSMicrophoneUsageDescription` — "Eve needs your microphone to listen"
   - `NSSpeechRecognitionUsageDescription` — "Eve uses speech recognition to understand you"

## How it works

- Tap "Talk to Eve" → records your voice
- Tap "Done" → transcribes and routes:
  - "Hey Sync" → pulls latest memory from home via Supabase
  - "Use grok" / "Use internet" → switches to cloud mode
  - Everything else → routes to home brain (LM Studio relay)
  - If home brain unreachable → Apple Intelligence fallback

## Key Rules

- Offline-first — never calls cloud unless explicitly asked
- Patrick gets full private memory; other users get shared memory only
- Must always be fast and native (no browser feel)
- Apple Intelligence is the required fallback — never feels dumb
