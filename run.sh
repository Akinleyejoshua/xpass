#!/bin/bash
# Build xpass and launch it the way macOS privacy permissions require.
#
# `flutter run` execs the binary as a child of your terminal, and macOS then
# treats the terminal as the "responsible process" for privacy: it checks the
# terminal's Screen Recording grant instead of xpass's, and reads the
# terminal's Info.plist for usage descriptions — so asking for Speech
# Recognition terminates the app. Launching the bundle with `open` makes
# launchd responsible, and xpass is judged on its own permissions.
#
# Usage:  ./run.sh [--release] [--attach]
set -euo pipefail
cd "$(dirname "$0")"

MODE=debug
ATTACH=false
for arg in "$@"; do
  case "$arg" in
    --release) MODE=release ;;
    --attach)  ATTACH=true ;;
    *) echo "unknown option: $arg"; exit 1 ;;
  esac
done

echo "==> Building ($MODE)"
flutter build macos --"$MODE"

APP="build/macos/Build/Products/$( [ "$MODE" = release ] && echo Release || echo Debug )/xpass.app"

# Re-sign with the local certificate if one exists. Without it the build is
# ad-hoc signed, whose designated requirement is the binary hash — so every
# rebuild invalidates the Screen Recording grant. See ./sign-setup.sh.
IDENTITY="xpass Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  echo "==> Signing with '$IDENTITY'"
  codesign --force --deep --options runtime \
    --entitlements macos/Runner/DebugProfile.entitlements \
    --sign "$IDENTITY" "$APP" 2>&1 | grep -v "replacing existing signature" || true
else
  echo "==> No local signing certificate — this build is ad-hoc signed."
  echo "    Screen Recording will need re-granting after every rebuild."
  echo "    Run ./sign-setup.sh once to fix that permanently."
fi

echo "==> Stopping any running instance"
pkill -x xpass 2>/dev/null || true
sleep 0.5

echo "==> Launching $APP"
open "$APP"

if [ "$ATTACH" = true ]; then
  echo "==> Attaching for hot reload (Ctrl-C to detach; the app keeps running)"
  flutter attach -d macos
else
  echo
  echo "xpass is running as a menu-less agent — no Dock icon by design."
  echo "Press Cmd+Option+H if the HUD is not visible."
fi
