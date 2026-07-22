#!/bin/bash
# Removes the redundant, empty onnxruntime.framework stub from the most recent
# Xcode archive so the App Store accepts the build (fixes ITMS-90208).
#
# onnxruntime is STATICALLY linked into the app binary; Xcode embeds a binary-less
# framework stub that Apple rejects. The app does not need it at runtime.
#
# Usage:
#   1. In Xcode: Product > Archive  (build 5+)
#   2. Run this script:  ./strip-archive-stub.sh
#   3. If it prints ALL ✅, go back to Organizer and Distribute App > App Store Connect.
#      (Xcode re-signs the bundle during distribution, so removing the stub is fine.)
set -euo pipefail

ARCH=$(ls -dt ~/Library/Developer/Xcode/Archives/*/*.xcarchive 2>/dev/null | head -1)
if [ -z "${ARCH:-}" ]; then echo "❌ No archive found. Archive in Xcode first."; exit 1; fi
APP=$(ls -d "$ARCH/Products/Applications/"*.app | head -1)
EXE="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>/dev/null)"

echo "Archive : $ARCH"
echo "Build   : $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null) (version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null))"
echo

for f in onnxruntime onnxruntime_extensions; do
  if [ -d "$APP/Frameworks/$f.framework" ]; then
    echo "Removing redundant $f.framework stub…"
    rm -rf "$APP/Frameworks/$f.framework"
  fi
done
# drop an empty Frameworks dir if nothing else is in it
rmdir "$APP/Frameworks" 2>/dev/null || true

echo
echo "=== verification ==="
ok=1
if ls -d "$APP/Frameworks/onnxruntime.framework" >/dev/null 2>&1; then
  echo "❌ stub STILL present"; ok=0
else
  echo "✅ stub removed"
fi
if otool -L "$EXE" 2>/dev/null | grep -qi onnx; then
  echo "❌ app dynamically depends on onnxruntime (would crash) — DO NOT upload"; ok=0
else
  echo "✅ no dynamic dependency on onnxruntime"
fi
TEXT=$(size -m "$EXE" 2>/dev/null | awk -F': ' '/Segment __TEXT:/{print $2+0}')
if [ "${TEXT:-0}" -gt 10000000 ]; then
  echo "✅ ONNX code is statically linked in the app ( __TEXT = ${TEXT} bytes )"
else
  echo "❌ app binary too small ( __TEXT = ${TEXT:-0} ) — ONNX may not be linked, DO NOT upload"; ok=0
fi
echo
[ "$ok" = 1 ] && echo "ALL GOOD ✅  → Distribute App now." || echo "PROBLEM ❌  → stop and report this output."
