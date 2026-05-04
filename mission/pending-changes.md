# Pending Changes

Proposed code changes waiting on a condition. Each entry has a **trigger** that determines when it can be applied.

---

## 1. Lumen API key — read from environment, not hardcoded

**Trigger:** Xcode is closed (or stopped debugging `lumen-desktop`).
**File:** `lumen/lumen-desktop/lumen-desktop/LumenAPIManager.swift:72`
**Current:** `private let anthropicApiKey = "PASTE_YOUR_KEY_HERE"`
**Risk if left:** First time a real `sk-ant-…` key is pasted in, it will be one `git add` away from being committed to a public repo.

### Proposed replacement

Replace the line:
```swift
private let anthropicApiKey = "PASTE_YOUR_KEY_HERE"
```

With:
```swift
private var anthropicApiKey: String {
    // 1. Environment variable (Xcode scheme → Run → Environment Variables)
    if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
        return env
    }
    // 2. Keychain (recommended for production builds)
    if let kc = KeychainHelper.read(service: "com.nexus.lumen", account: "anthropic") {
        return kc
    }
    // 3. Fallback for legacy bundles
    return ""
}
```

You'll also need a tiny `KeychainHelper.swift` (Security framework wrapper) — happy to write it when Xcode is free.

### How to set the env var in Xcode

`Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables → +`
- Name: `ANTHROPIC_API_KEY`
- Value: your key
- ✅ Check "Encrypted in scheme" if available, otherwise add the scheme to `.gitignore`.

### Verification

After applying:
```bash
grep -r "PASTE_YOUR_KEY_HERE\|sk-ant-" lumen/lumen-desktop/
# should return nothing
```
