#!/usr/bin/env bash
# build-lumen.sh — Build Lumen as a standalone .app and install to /Applications.
#
# Part of Operation Letsgo, Track L2. See mission/operation-letsgo.md.
#
# Usage:
#   ./scripts/build-lumen.sh
#
# What it does:
#   1. Archives the lumen-desktop scheme in Release configuration with ad-hoc
#      signing (no Apple Developer Program required).
#   2. Pulls the .app out of the archive and installs to /Applications/Lumen.app,
#      replacing any previous copy.
#   3. Strips the quarantine attribute so macOS Gatekeeper doesn't double-warn.
#
# First-launch behavior: on an ad-hoc signed build, macOS may warn
# "Lumen.app cannot be opened because the developer cannot be verified."
# Right-click the app in Finder → Open → Open. After that, trusted.

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/lumen/lumen-desktop"
SCHEME="lumen-desktop"
PRODUCT_NAME="lumen-desktop"   # what xcodebuild produces
INSTALL_NAME="Lumen"           # what /Applications calls it
DEST="/Applications/$INSTALL_NAME.app"

# ── Pre-flight ────────────────────────────────────────────────────────────────
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "❌ xcodebuild not found. Install Xcode and run 'xcode-select -s /Applications/Xcode.app/Contents/Developer'." >&2
  exit 1
fi

if [ ! -d "$PROJECT_DIR/$SCHEME.xcodeproj" ]; then
  echo "❌ Lumen project not found at $PROJECT_DIR/$SCHEME.xcodeproj" >&2
  exit 1
fi

# Detect if Lumen is currently running and warn (we'll still install, but
# /Applications copy may not take effect until next launch).
if pgrep -x "$INSTALL_NAME" >/dev/null 2>&1 || pgrep -x "$PRODUCT_NAME" >/dev/null 2>&1; then
  echo "⚠️  Lumen is currently running. The new build will install but won't"
  echo "   take effect until you quit and relaunch."
  echo ""
fi

# ── Build ─────────────────────────────────────────────────────────────────────
BUILD_DIR="$(mktemp -d -t lumen-build)"
ARCHIVE_PATH="$BUILD_DIR/Lumen.xcarchive"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "🔨 Archiving $SCHEME (Release, ad-hoc signed)…"
echo "   Build dir: $BUILD_DIR"
echo ""

xcodebuild \
  -project "$PROJECT_DIR/$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  archive

ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/$PRODUCT_NAME.app"
if [ ! -d "$ARCHIVED_APP" ]; then
  echo "" >&2
  echo "❌ Archive completed but $PRODUCT_NAME.app was not produced." >&2
  echo "   Expected at: $ARCHIVED_APP" >&2
  echo "   Inspect: $ARCHIVE_PATH" >&2
  exit 1
fi

# ── Install ───────────────────────────────────────────────────────────────────
if [ -d "$DEST" ]; then
  echo ""
  echo "🗑  Removing previous $DEST"
  rm -rf "$DEST"
fi

echo "📦 Installing to $DEST"
cp -R "$ARCHIVED_APP" "$DEST"

# Strip quarantine so Gatekeeper doesn't show the extra "downloaded from
# internet" warning on top of the unverified-developer one.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✅ Lumen.app built and installed."
echo "   Location: $DEST"
echo "   Launch:   open '$DEST'   (or Cmd-Space → 'Lumen')"
echo ""
echo "ℹ️  First launch may warn: \"Lumen.app cannot be opened because the"
echo "   developer cannot be verified.\" Right-click the app in Finder → Open"
echo "   → Open. macOS will trust it after that."
