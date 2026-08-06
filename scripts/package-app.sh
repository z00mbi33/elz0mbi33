#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/elz0mbi33.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
BIN_ARM64="$ROOT/.build/release-arm64/elz0mbi33"
BIN_X86_64="$ROOT/.build/release-x86_64/elz0mbi33"
TMP_ARM64="$ROOT/.build/release-arm64"
TMP_X86_64="$ROOT/.build/release-x86_64"

rm -rf "$TMP_ARM64" "$TMP_X86_64"
swift build -c release --arch arm64 --build-path "$TMP_ARM64"
swift build -c release --arch x86_64 --build-path "$TMP_X86_64"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
ditto "$BIN_ARM64" "$MACOS_DIR/elz0mbi33-arm64"
ditto "$BIN_X86_64" "$MACOS_DIR/elz0mbi33-x86_64"
lipo -create "$MACOS_DIR/elz0mbi33-arm64" "$MACOS_DIR/elz0mbi33-x86_64" -output "$MACOS_DIR/elz0mbi33"
rm "$MACOS_DIR/elz0mbi33-arm64" "$MACOS_DIR/elz0mbi33-x86_64"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$MACOS_DIR/elz0mbi33"

printf '%s\n' "$APP_DIR"
