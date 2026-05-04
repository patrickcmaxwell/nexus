# Nexus iOS

Native iPhone app for Nexus — talk to Eve from anywhere.

## Setup in Xcode

1. Create a new Xcode project: iOS App, SwiftUI, Swift, **iOS 17+**.
2. Copy these files into your Xcode project:
   - `NexusAPIClient.swift` — talks to nexus-web Eve (PIN auth + brain calls)
   - `EveVoiceManager.swift` — voice recording + transcription + speaking replies
   - `EveMemoryManager.swift` — loads memory files (optional, for local context)
   - `SupabaseManager.swift` — direct Supabase access (optional, only needed for `Hey Sync`)
   - `ContentView.swift` — main UI with PIN gate + settings
3. Optional (only if using `Hey Sync`):
   - File → Add Package Dependency → `https://github.com/supabase/supabase-swift`
   - Replace `YOUR_PROJECT_URL` and `YOUR_ANON_KEY_HERE` in `SupabaseManager.swift`
4. Optional: add `eve-base.md`, `eve-private.md`, `eve-shared.md` to the bundle if you want local memory loading.
5. `Info.plist` permissions:
   - `NSMicrophoneUsageDescription` — "Eve needs your microphone to listen"
   - `NSSpeechRecognitionUsageDescription` — "Eve uses speech recognition to understand you"

## How it works

- App opens → if not authenticated, shows a 4-digit PIN gate that POSTs to nexus-web `/api/security/pin` and caches the session id in `UserDefaults`.
- Tap "Talk to Eve" → records via `SFSpeechRecognizer` and displays the transcript live.
- Tap "Done" → routes the transcript:
  - "Hey Sync" / "sync with home" → pulls latest memory updates from Supabase
  - "Use grok" / "use cloud" / "use internet" → sets cloud brain (default)
  - "Use local" / "use ollama" / "go offline" → sets local brain (Ollama via `/api/eve/local`)
  - Anything else → POSTs to nexus-web Eve with the Bearer session and the active conversation id, then speaks the reply via `AVSpeechSynthesizer`.
- Settings (gear icon): change the Nexus base URL (cloud `https://nexus.talkcircles.io` or home LAN like `http://192.168.x.x:3000`) and sign out.
- "NEW" button starts a fresh conversation thread.

## Architecture

| File | Responsibility |
|---|---|
| `NexusAPIClient` | PIN auth → sessionId; `askEve` (Grok + tools) and `askEveLocal` (Ollama) |
| `EveVoiceManager` | Voice in (SFSpeech), voice out (AVSpeechSynthesizer), brain routing, conversation threading |
| `ContentView` | PIN gate, talk button, transcription + reply display, settings sheet |
| `SupabaseManager` | Optional direct Supabase access — only used by `Hey Sync` |
| `EveMemoryManager` | Optional local memory file loader (memory primarily lives server-side now) |

## Key Rules

- Offline-first when on home wifi: point base URL at the LAN Mac to keep traffic local.
- Voice is fully native — no browser feel.
- Bearer auth via `X-Lumen-Client: 1` header (same flow Lumen Desktop uses).
- The phone never holds API keys — all model calls go through nexus-web.
