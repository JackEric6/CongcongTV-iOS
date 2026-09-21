#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Build/Products/Release-iphoneos/CongcongTV.app"
OUT="$ROOT/CongcongTV-unsigned.ipa"

test -d "$APP"
rm -rf "$ROOT/Payload" "$OUT"
mkdir -p "$ROOT/Payload"
cp -R "$APP" "$ROOT/Payload/CongcongTV.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ROOT/Payload" "$OUT"
printf 'Created %s\n' "$OUT"
