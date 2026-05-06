# Operation Letsgo — Boot System

**Created:** 2026-05-04
**Goal:** Nexus runs as a permanent fixture on the Director's Mac. Lumen is a standalone `.app`. Services auto-start on login and auto-restart on crash. A single CLI (`vera`) brings everything up, takes it down, or pauses it for travel. No VS Code dependency anywhere.

---

## Naming convention (from `memory/project_vera_eve_personas.md`)

| Layer                  | Branding                                                     | Why                                                                                                        |
| ---------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| **CLI orchestrator**   | `vera`                                                       | Admin/operational maps to Vera's persona. Sets her up as the admin agent surface even before she has a UI. |
| **launchd job labels** | `com.nexus.web`, `com.nexus.arena`, `com.nexus.ollama-check` | Infrastructure stays neutral. Don't tattoo a persona onto schemas or service ids.                          |
| **Log paths**          | `~/Library/Logs/Nexus/{web,arena,vera,ollama-check}.log`     | Service logs are nexus-named; CLI's own log uses its tool name.                                            |
| **Lumen**              | unchanged                                                    | Eve lives in Lumen. No rename.                                                                             |
| **Future Vera UIs**    | menu-bar app, status dashboard, admin chat                   | When built later, they're Vera-branded. The CLI is the toehold.                                            |

---

## Dependencies (already installed)

- macOS 15+ (Darwin 25.4.0 confirmed)
- Xcode (Lumen builds)
- Node 20+ (nexus-web, arena)
- Ollama 0.23.0 on `:11434`
- iTerm2 (or Terminal.app — `Claude-Vera.command` works with either)

No new tools required.

---

## Tracks

### Track L — Lumen as a real `.app`

#### L1 — Release build configuration
**File:** `lumen/lumen-desktop/lumen-desktop.xcodeproj`

**Approach:**
- Verify Release scheme builds clean (`xcodebuild -scheme lumen-desktop -configuration Release`).
- Self-signed; no Apple Developer Program needed for personal use.
- Bump version/build numbers (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) so future builds are identifiable.
- Confirm no debug-only env vars or `localhost` overrides leak into Release config.

**Acceptance:** `xcodebuild` BUILD SUCCEEDED on Release config; built `.app` launches independently of Xcode.

**Estimate:** 30 min.

#### L2 — Archive + export to `/Applications`
**File:** `scripts/build-lumen.sh` (new)

**Approach:**
- Wrap the archive + export commands in a script:
  ```bash
  xcodebuild -scheme lumen-desktop -configuration Release \
    -archivePath build/Lumen.xcarchive archive
  xcodebuild -exportArchive -archivePath build/Lumen.xcarchive \
    -exportPath build/ -exportOptionsPlist scripts/export-options.plist
  cp -R build/Lumen.app /Applications/
  ```
- `scripts/export-options.plist` configured for `mac-application` / `developer-id` (or `mac-application` if unsigned for personal).
- First-launch macOS will warn ("unidentified developer"); user right-clicks → Open once → trusted thereafter.

**Acceptance:** `./scripts/build-lumen.sh` produces a working `/Applications/Lumen.app`. Quitting and relaunching from Spotlight works without Xcode.

**Estimate:** 30 min.

#### L3 — Login Item
**Approach:**
- Add `Lumen.app` to System Settings → General → Login Items → Open at Login.
- Documented in `vera install` output, but no programmatic install (Apple's APIs for this are fiddly and require user consent anyway).

**Acceptance:** Reboot → Lumen launches automatically.

**Estimate:** 5 min (manual).

---

### Track V — `vera` CLI

#### V1 — `scripts/vera` skeleton
**File:** `nexus/scripts/vera` (new, zsh, no deps)

**Subcommands:**
| Command | Behavior |
|---|---|
| `vera up` | Bootstrap all `com.nexus.*` launchd jobs. Idempotent. |
| `vera down` | Bootout all jobs. Services stop, do not auto-restart, do not survive reboot. |
| `vera pause` | Bootout all jobs but mark state as "paused" in `~/.vera/state`. Survives reboot (jobs stay paused). |
| `vera resume` | Bootstrap all jobs and clear paused state. |
| `vera status` | Show launchd state per job + one-line health probe per service. |
| `vera logs [service]` | `tail -f ~/Library/Logs/Nexus/<service>.log`. No arg = tail all interleaved. |
| `vera install` | One-time setup: copy plists into `~/Library/LaunchAgents/`, create log dir, symlink `~/bin/vera`, print Login Items reminder. |
| `vera uninstall` | Reverse of install. |

**Acceptance:** Each subcommand runnable from any directory; `--help` prints usage; exit codes meaningful.

**Estimate:** 1.5h.

#### V2 — Health probes for `vera status`
**Approach:**
- nexus-web: `curl -fsS http://localhost:3000/api/dashboard/overview -H "Authorization: Bearer $NEXUS_HEALTH_TOKEN"` (or the unauthenticated health endpoint if/when one exists).
- arena: `curl -fsS http://localhost:3001/health`.
- Ollama: `curl -fsS http://localhost:11434/api/tags`.
- Each probe has a 2s timeout; status output shows ✅/⚠️/❌ per service with last-restart time from `launchctl print`.

**Acceptance:** `vera status` returns in <3s with accurate state of all four services.

**Estimate:** 30 min (rolled into V1).

#### V3 — `~/bin/vera` symlink
**Approach:** `vera install` creates `~/bin/vera → /Users/shadow/code/nexus/scripts/vera`. Director adds `~/bin` to PATH if not present (most macOS shells already include it under `~/.zshrc`).

**Acceptance:** `which vera` returns `/Users/shadow/bin/vera` from a fresh shell.

**Estimate:** 5 min (rolled into V1).

#### V4 — `vera doctor` diagnostic
**Approach:** Single command that runs every health probe and prints a triage report:
- node/npm absolute paths resolved (`which npm`, `which node`)
- Port `:3000` and `:3001` not occupied by stray processes
- All `com.nexus.*` plists present in `~/Library/LaunchAgents/` and bootstrapped
- Ollama reachable + expected models present (`llama3.2:3b`, `qwen2.5:3b`, `llava:7b`)
- macOS clock drift check (`sntp -sS time.apple.com`) — JWT/Supabase tokens silently fail if drifted
- `~/.ollama/models/` free space >5GB (model eviction guard)
- `~/Library/Application Support/Lumen/` exists and writable

Each row prints ✅/⚠️/❌ + actionable next step.

**Acceptance:** `vera doctor` covers the top failure modes; new users can self-debug 80% of issues without asking.

**Estimate:** 1h.

#### V5 — `vera reload [service]`
**Approach:** Restart one or all services without doing `down → up`. For when `git pull` lands new code and a soft restart is enough.
- `vera reload` → reload all services
- `vera reload web` / `vera reload arena` → single service
- Internally: `launchctl kickstart -k gui/$(id -u)/com.nexus.<service>`

**Acceptance:** Code changes pick up without losing other services' state.

**Estimate:** 15 min.

#### V6 — Crash notifications
**Approach:** When launchd restarts a service 3+ times in 60s, post a macOS notification ("Nexus arena restarting repeatedly — check `vera logs arena`"). Implementation: each plist's stdout/stderr piped through a tiny tee that counts restarts and shells out to `osascript -e 'display notification …'` past threshold.

Alternative: skip the tee, run a small `vera watchdog` daemon as its own launchd job that polls `launchctl print` for restart counts. Cleaner.

**Acceptance:** A wedged service surfaces visually; you don't have to know to check logs.

**Estimate:** 1h. Defer to end of Session 2 if time-pressed.

#### V7 — First-run wizard inside `vera install`
**Approach:** `vera install` becomes interactive on first run:
1. Confirms log dir location (default `~/Library/Logs/Nexus/`).
2. Asks pause-on-battery preference (defaults to manual / no auto-pause; v2 add).
3. Asks Lumen-on-pause behavior (defaults to "quit Lumen on pause" per P2 decision).
4. Writes choices to `~/.vera/config` (TOML or simple key=value).
5. Prints final manual step: open System Settings → General → Login Items → add Lumen.app.
6. Runs `vera doctor` automatically and reports.

**Acceptance:** Director runs `vera install` once and is fully bootstrapped without external docs.

**Estimate:** 30 min.

---

### Track D — launchd plists

#### D1 — `com.nexus.web.plist`
**File:** `nexus/scripts/launchd/com.nexus.web.plist`

**Key bits:**
```xml
<key>Label</key>             <string>com.nexus.web</string>
<key>ProgramArguments</key>  <array><string>/usr/local/bin/npm</string><string>run</string><string>dev</string></array>
<key>WorkingDirectory</key>  <string>/Users/shadow/code/nexus/nexus-web</string>
<key>RunAtLoad</key>         <true/>
<key>KeepAlive</key>         <true/>
<key>StandardOutPath</key>   <string>/Users/shadow/Library/Logs/Nexus/web.log</string>
<key>StandardErrorPath</key> <string>/Users/shadow/Library/Logs/Nexus/web.log</string>
<key>EnvironmentVariables</key>
<dict>
  <key>PATH</key><string>/usr/local/bin:/usr/bin:/bin</string>
</dict>
```

**Acceptance:** `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nexus.web.plist` brings nexus-web up on `:3000`.

**Estimate:** 30 min including verification.

#### D2 — `com.nexus.arena.plist`
**File:** `nexus/scripts/launchd/com.nexus.arena.plist`

Same shape, working dir `arena/`, command `npm run dev`. Logs to `arena.log`.

**Acceptance:** Arena up on `:3001`, `/health` returns 200.

**Estimate:** 15 min.

#### D3 — `com.nexus.ollama-check.plist`
**File:** `nexus/scripts/launchd/com.nexus.ollama-check.plist`

A daily probe that ensures Ollama is reachable and the expected models (`llama3.2:3b`, `qwen2.5:3b`, `llava:7b`) are pulled. Re-pulls anything missing. Logs to `ollama-check.log`.

**Type:** `StartCalendarInterval` (daily 9am).

**Acceptance:** Logs show daily success or actionable failure.

**Estimate:** 30 min.

---

### Track P — Pause / resume

#### P1 — Pause state file
**File:** `~/.vera/state`

**Contents:** Single key=value file with `mode={running|paused}` + last transition timestamp.

**Behavior:**
- `vera pause` → bootout all jobs, write `mode=paused`.
- `vera resume` → read state, bootstrap all jobs, write `mode=running`.
- `vera install` → read state on install. If `mode=paused`, do not auto-bootstrap (respects prior intent).

**Acceptance:** Pause persists across reboot. Resume restores all services. `vera status` shows paused mode prominently.

**Estimate:** 30 min (rolled into V1).

#### P2 — Lumen behavior when paused — OPEN QUESTION
**Decision needed from Director.**

Options:
- **A — Lumen runs regardless.** Pause only affects services. Lumen falls through its existing 3-tier brain (nexus-web → Ollama → Claude). When paused, nexus-web is dead, Ollama is dead → Lumen routes everything through Claude API. Functional but cloud-dependent and chatty on Anthropic spend.
- **B — `vera pause` also quits Lumen.** Cleanest "battery saver" mode. Director relaunches Lumen manually after `vera resume`.
- **C — `vera pause --keep-lumen`** flag exposes both. Default = quit Lumen on pause.

**Default recommendation if no decision:** B (quit Lumen on pause). Travel = quiet machine = no Eve hovering.

**Estimate:** 15 min once decided.

#### P3 — Auto-pause on battery — DEFERRED TO V2
A small watcher polling `pmset -g batt` could auto-pause when on battery and auto-resume on AC. **Not building this now** — manual pause is fine until the Director has actually traveled with the system once and knows what they want.

---

### Track O — Offline mode (separate op — `mission/offline-mode.md`)

The questions about offline brain, offline auth, and write-when-offline-sync-when-online are **real architecture work**, not boot-system plumbing. They're tracked in their own mission doc:

- **Layer 1** — Local credential cache (encrypted, in `~/Library/Application Support/Lumen/credentials/`). Unblocks "Lumen opens offline."
- **Layer 2** — nexus-web outbox + read-through cache (local SQLite). Unblocks "Eve writes offline, syncs on reconnect."
- **Layer 3** — Network-aware brain routing (`NWPathMonitor` in Lumen + iOS, OFFLINE pill in TopHUD, tool-call refusal when no internet). Unblocks "Eve answers offline via Ollama gracefully."

**Sequencing:** Operation Letsgo lands first. Offline mode is the next op after Letsgo and before Arena launch (Arena writes through nexus-web, so the outbox needs to exist first). See `offline-mode.md`.

---

### Track C — Claude Code without VS Code

#### C1 — `Claude-Vera.command` launcher
**File:** `nexus/scripts/Claude-Vera.command` (new, executable)

**Contents:** Tiny shell script that opens iTerm (or Terminal.app fallback) in `/Users/shadow/code/nexus`, runs `claude`. Double-clickable from Finder/Dock.

**Acceptance:** Double-click → terminal opens at repo root with Claude running. No VS Code involved.

**Estimate:** 15 min.

#### C2 — Drop VS Code requirement from `PROJECT-STATUS.md`
**File:** `nexus/PROJECT-STATUS.md` lines 295-305

**Change:** Replace "Required: VS Code with Claude Code running in the integrated terminal" with the `vera` flow + `Claude-Vera.command` launcher. Quick Reference table updated to use `vera up` / `vera status` instead of the per-service `npm run dev` lines.

**Acceptance:** A fresh reader of `PROJECT-STATUS.md` knows how to start Nexus without ever opening VS Code.

**Estimate:** 10 min.

---

## Suggested execution order

```
Session 1 (~1.5h):
  ├─ L1: Release build config verification
  ├─ L2: build-lumen.sh + first /Applications/Lumen.app
  ├─ L3: Add to Login Items (manual)
        → Lumen now runs without Xcode.

Session 2 (~3h):
  ├─ V1: vera CLI skeleton (up/down/pause/resume/status/logs/install/uninstall)
  ├─ V2: Health probes
  ├─ V3: ~/bin/vera symlink via vera install
  ├─ V4: vera doctor diagnostic
  ├─ V5: vera reload [service]
  ├─ D1: com.nexus.web plist
  ├─ D2: com.nexus.arena plist
  ├─ P1: ~/.vera/state pause file
  ├─ P2: Lumen-on-pause behavior (default: quit Lumen)
  └─ V7: first-run wizard inside vera install
        → Single-command boot/pause working with self-diagnosis.

Session 3 (~1.5h):
  ├─ D3: com.nexus.ollama-check plist
  ├─ V6: crash notifications (watchdog daemon)
  ├─ C1: Claude-Vera.command
  ├─ C2: PROJECT-STATUS.md rewrite
  ├─ Log rotation (newsyslog.d entry — see Cross-cutting risks)
  └─ Verification: reboot, confirm everything comes up clean.
        → Operation Letsgo complete.

Deferred (post-launch):
  ├─ P3: Auto-pause on battery
  ├─ Vera menu-bar status app (separate project)
  └─ Offline mode — see mission/offline-mode.md (next op)
```

---

## Cross-cutting risks

- **launchd permissions on macOS Sonoma+:** First load of each plist may prompt for "Allow in background" approval. Documented in `vera install` output.
- **Node path inside launchd:** `npm`/`node` need explicit absolute paths or PATH set in `EnvironmentVariables`. Use `which npm` to find it; bake the result into the plist generator.
- **Working-directory `node_modules` permissions:** launchd runs as user, not root, so existing `node_modules` should work. Confirm with first plist load.
- **Port collisions:** If a stray `npm run dev` is already running on `:3000` or `:3001`, launchd will silently keep restarting and failing. `vera install` should detect existing listeners and warn.
- **Log rotation:** launchd doesn't rotate log files. Without rotation, `web.log` grows to multiple GB in a month. Mitigation: `vera install` drops a `/etc/newsyslog.d/nexus.conf` (or user-level alternative) that rotates `~/Library/Logs/Nexus/*.log` weekly, keeping 4 weeks. Sudo prompt during install — accept once.
- **Time drift:** If the Mac's clock is off by >5 minutes, Supabase JWT tokens silently 401. `vera doctor` includes an `sntp -sS time.apple.com` check. Cheap to add; saves a confusing debug session.
- **`caffeinate` while running:** Default behavior — let the Mac sleep. launchd resumes services on wake; sleep saves battery. Don't `caffeinate` unless an explicit reason emerges.
- **Disk pressure on Ollama models:** `~/.ollama/models/` is ~10GB+. If laptop disk gets tight, models can be evicted silently and inference fails. `vera doctor` checks free space.
- **Update path after `git pull`:** Hot-reload works for nexus-web (Next.js), but if a `package.json` change requires `npm install`, services won't pick it up automatically. Convention: after any `package.json` change, run `vera reload <service>`. Document in `PROJECT-STATUS.md`.
- **First-boot online-only constraint:** Ollama models must be pulled (online once), Supabase auth must be seeded (online once), and the local credential cache (offline-mode Layer 1) must be populated. Operation Letsgo doesn't address offline auth — it assumes you've been online at least once. The offline-mode op handles the broader case.
- **Eve's `currentDate` awareness:** Already a problem; Eve sometimes confidently states wrong dates. Server-side fix: inject `currentDate` into every Eve system prompt at request time. Out of Letsgo scope but worth flagging — handle in offline-mode op or as a one-line nexus-web tweak.

---

## Won't-do for this op

- **Apple Developer Program signing** — $99/yr, only matters if distributing. Self-signed is fine for one machine.
- **Notarization** — same reason.
- **Docker** — overkill for a single-Mac local dev rig. Saved for Arena prod deploy (`arena-launch.md` Track C).
- **Auto-pause on battery** — defer to v2 (P3 above).
- **A Vera menu-bar UI** — natural next surface but separate project. Operation Letsgo is plumbing, not UI.

---

## Decisions (resolved before kickoff)

| Question | Decision | Why |
|---|---|---|
| **P2:** Should `vera pause` quit Lumen too? | **Yes — quit Lumen on pause.** | Travel = quiet machine. Avoids Eve falling through to Claude API and burning Anthropic spend on cloud-dependent answers. `vera pause --keep-lumen` flag available for the rare case. |
| Login Items approach | **Manual System Settings click**, documented in `vera install` output. | Apple's `SMAppService` is fiddly and requires LoginItems plist signing. Manual is one click and survives macOS upgrades. |
| Log directory location | **`~/Library/Logs/Nexus/`** (services) + `~/Library/Logs/Nexus/vera.log` (CLI). | Convention-matching — Console.app and other macOS tooling discover it automatically. |
| Streamlining (Q2) | **V4 doctor + V5 reload + V6 notifications + V7 wizard added to Track V.** | All folded into Sessions 2-3. |
| Offline brain (Q1) | **Acknowledge gap, defer to `offline-mode.md`.** | Real architecture work. Track O above documents the layered approach. |
| Offline sync (Q3) | **Outbox pattern in offline-mode Layer 2.** | Local SQLite write-through cache; sync worker drains to Supabase on reconnect. |
| Offline auth (Q4) | **Local encrypted credential cache (offline-mode Layer 1).** | `~/Library/Application Support/Lumen/credentials/` — Director's intuited "storage area I can manage." Encrypted via macOS Keychain. First-boot must be online to seed. |
| What am I missing (Q5) | **Captured in Cross-cutting risks** above + offline-mode op. | Log rotation, time drift, Ollama disk pressure, first-boot constraint, currentDate awareness. |

No remaining open questions block kickoff. If new ones surface mid-build, log them in `journal.md`.

---

## Status

- [x] **L1** — Release build config verified (ad-hoc signing, archive succeeds)
- [x] **L2** — `build-lumen.sh` + `/Applications/Lumen.app` + AppIcon (placeholder: core_gold)
- [ ] **L3** — Added to Login Items
- [x] **V1** — `vera` CLI skeleton (8 subcommands)
- [x] **V2** — Health probes (web/arena/ollama, 2s timeout)
- [x] **V3** — `~/bin/vera` symlink (wired into `vera install`)
- [x] **V4** — `vera doctor` diagnostic (toolchain / ports / launchd / Ollama / disk / clock / filesystem)
- [x] **V5** — `vera reload [service]` (kickstart -k, idempotent, single or all)
- [ ] **V6** — Crash notifications watchdog (deferred — KeepAlive on `Crashed` covers 95%; revisit if a real crash slips through silently)
- [ ] **V7** — First-run wizard inside `vera install` (deferred — `vera install` already worked without interactive prompts; revisit if onboarding becomes painful for a 2nd machine)
- [x] **D1** — `com.nexus.web.plist` (NVM-aware via `with-node.sh`, KeepAlive on crash)
- [x] **D2** — `com.nexus.arena.plist` (same shape, different working dir)
- [x] **D3** — `com.nexus.ollama-check.plist` + `ollama-check.sh` (daily 09:00 probe + auto-pull missing models)
- [x] **P1** — Pause state file (`~/.vera/state`, wired into pause/resume)
- [x] **CUTOVER** — Manual `npm run dev` killed; `vera install` + `vera up` running clean end-to-end
- [ ] **P2** — Lumen-on-pause implemented (quit on pause)
- [x] **C1** — `Claude-Vera.command` (NVM-aware, double-clickable, Dock-draggable)
- [x] **C2** — `PROJECT-STATUS.md` rewrite (vera flow + manual fallbacks documented)
- [x] Log rotation entry (`scripts/launchd/newsyslog-nexus.conf`, install with `sudo cp`)

Update this file as items land. Cross-link incidents to `journal.md`.
