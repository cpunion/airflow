#!/usr/bin/env bash
set -euo pipefail

# AirFlow macOS Application Bundle & Packaging Script
# Assembles a standalone AirFlow.app menubar application bundle and generates release DMG.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/AirFlow.app"

echo "==> [1/5] Building Rust core dynamic library..."
cd "${ROOT_DIR}"
cargo build --release -p airflow-core

echo "==> [2/5] Building Swift release executable..."
swift build -c release

echo "==> [3/5] Assembling AirFlow.app bundle structure..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Frameworks"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy binary
SWIFT_BIN="${ROOT_DIR}/.build/release/AirFlow"
if [[ ! -f "${SWIFT_BIN}" ]]; then
    # Fallback search path in .build
    SWIFT_BIN=$(find "${ROOT_DIR}/.build" -type f -perm +111 -name "AirFlow" | grep "release" | head -n 1)
fi

cp "${SWIFT_BIN}" "${APP_DIR}/Contents/MacOS/AirFlow"
chmod +x "${APP_DIR}/Contents/MacOS/AirFlow"

# Copy Rust dylib
RUST_DYLIB="${ROOT_DIR}/target/release/libairflow_core.dylib"
if [[ -f "${RUST_DYLIB}" ]]; then
    cp "${RUST_DYLIB}" "${APP_DIR}/Contents/Frameworks/"
fi

# Copy Info.plist
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

echo "==> [4/5] Codesigning AirFlow.app (Ad-hoc signature)..."
codesign --force --deep -s - "${APP_DIR}"

echo "==> [5/5] Packaging release DMG / ZIP artifact..."
ZIP_PATH="${DIST_DIR}/AirFlow-macOS-universal.zip"
rm -f "${ZIP_PATH}"
cd "${DIST_DIR}"
zip -r -q "${ZIP_PATH}" "AirFlow.app"

if command -v hdiutil &> /dev/null; then
    DMG_PATH="${DIST_DIR}/AirFlow-macOS.dmg"
    rm -f "${DMG_PATH}"
    hdiutil create -volname "AirFlow" -srcfolder "${APP_DIR}" -ov -format UDZO "${DMG_PATH}" > /dev/null
    echo "✓ Generated DMG: ${DMG_PATH}"
fi

echo "✓ Generated ZIP: ${ZIP_PATH}"
echo "✓ Successfully assembled AirFlow.app bundle at: ${APP_DIR}"
