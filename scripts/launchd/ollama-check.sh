#!/usr/bin/env bash
# ollama-check.sh — Daily probe of Ollama: ensure daemon is reachable and the
# expected Nexus models are pulled. Re-pulls anything missing.
#
# Run by launchd via com.nexus.ollama-check.plist on a daily schedule.
# Logs to ~/Library/Logs/Nexus/ollama-check.log.
#
# Exits 0 when everything is healthy or all gaps were filled. Exits 1 when
# Ollama daemon is unreachable (cannot fix that automatically — the macOS
# Ollama app needs to be running). Exits 2 on a model pull failure.

set -uo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
EXPECTED_MODELS=(
  "llama3.2:3b"
  "qwen2.5:3b"
  "llava:7b"
)

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf '[%s] %s\n' "$(ts)" "$*"; }

log "ollama-check starting (host: $OLLAMA_HOST)"

# 1. Reachability
if ! curl -fsS --max-time 5 "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
  log "ERROR: Ollama daemon unreachable at $OLLAMA_HOST"
  log "Hint: open the Ollama macOS app, or run 'ollama serve' manually."
  exit 1
fi
log "Ollama daemon reachable."

# 2. Inventory
INSTALLED="$(curl -fsS "$OLLAMA_HOST/api/tags" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' || true)"

# 3. Check & pull
PULL_FAILURES=0
for model in "${EXPECTED_MODELS[@]}"; do
  if echo "$INSTALLED" | grep -Fxq "$model"; then
    log "  ok: $model"
  else
    log "  pulling: $model"
    if ollama pull "$model" >>"$HOME/Library/Logs/Nexus/ollama-check.log" 2>&1; then
      log "  pulled: $model"
    else
      log "  FAILED to pull: $model"
      PULL_FAILURES=$((PULL_FAILURES + 1))
    fi
  fi
done

if [ "$PULL_FAILURES" -gt 0 ]; then
  log "ollama-check finished with $PULL_FAILURES failure(s)"
  exit 2
fi

log "ollama-check finished clean"
exit 0
