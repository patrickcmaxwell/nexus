#!/usr/bin/env bash
# with-node.sh — Wrap a Node command for launchd, ensuring the right node is on PATH.
#
# launchd doesn't source ~/.zshrc, so NVM's PATH manipulation never happens
# in the spawned shell. This wrapper sources nvm.sh, switches to the default
# alias (or pinned version), then execs the requested command.
#
# Usage: with-node.sh <working-dir> <command> [args...]
# Example: with-node.sh /Users/shadow/code/nexus/nexus-web npm run dev

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <working-dir> <command> [args...]" >&2
  exit 64
fi

WORKDIR="$1"
shift

export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
  nvm use default >/dev/null 2>&1 || true
else
  echo "warning: NVM not found at $NVM_DIR — falling back to system PATH" >&2
fi

# Ensure /usr/local/bin is on PATH so things like ollama, codesign, etc. resolve.
export PATH="/usr/local/bin:$PATH"

cd "$WORKDIR"
exec "$@"
