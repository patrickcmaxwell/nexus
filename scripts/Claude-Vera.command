#!/usr/bin/env bash
# Claude-Vera.command — double-clickable launcher for Claude Code at the
# Nexus repo root. No VS Code required.
#
# Usage:
#   - Double-click from Finder → opens your default Terminal at
#     /Users/shadow/code/nexus with Claude running.
#   - Drag this file to the Dock or Desktop for one-click access.
#
# Why source NVM: Finder/Terminal opens a fresh shell that doesn't load
# ~/.zshrc, so `claude` (installed via npm under NVM) wouldn't be on PATH.
# Same trick as scripts/launchd/with-node.sh.

cd "/Users/shadow/code/nexus" || exit 1

# Load NVM so `claude` resolves
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
fi

# Make sure ~/bin is on PATH so `vera` works too
export PATH="$HOME/bin:/usr/local/bin:$PATH"

clear
cat <<'BANNER'

  Nexus / Vera — Claude Code launcher
  ───────────────────────────────────
  cwd: /Users/shadow/code/nexus

  Quick check:
    vera status     # service health (web / arena / ollama)
    vera up         # bring services up if down
    vera logs       # tail all service logs

BANNER

exec claude
