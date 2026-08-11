#!/bin/bash
# Build the Apple Silicon MK-OrbitControl distribution with bundled Python 3.8.
# Python 3.8 is required because Antelope's extracted bytecode targets that ABI.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR"
DIST="${DIST_ROOT:-$PROJECT/dist-bundled}"
APP="$DIST/MK-OrbitControl.app"
PY38="${PY38_ROOT:-$HOME/.pyenv/versions/3.8.20}"
GETTEXT_LIB="${GETTEXT_LIB:-/opt/homebrew/opt/gettext/lib/libintl.8.dylib}"

# Get version from git tag (e.g., v1.2 → 1.2), fallback to 1.2
VERSION=$(cd "$PROJECT" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.4")
if [ -z "$VERSION" ] || [ "$VERSION" = "v" ]; then VERSION="1.4"; fi
DMG_FILE="${DMG_OUTPUT:-$HOME/Desktop/MK-OrbitControl-v${VERSION}.dmg}"

# Use SIGN_IDENTITY="Developer ID Application: ..." for distributable builds.
# The default remains ad-hoc so local verification does not require credentials.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

echo "Building MK-OrbitControl v${VERSION}..."

# Validate the local release toolchain before deleting the previous output.
if [ ! -x "$PY38/bin/python3.8" ] || [ ! -f "$PY38/lib/libpython3.8.dylib" ]; then
  echo "ERROR: Python 3.8.20 runtime not found at $PY38"
  echo "Set PY38_ROOT to a complete arm64 Python 3.8 installation."
  exit 1
fi
if [ ! -f "$GETTEXT_LIB" ]; then
  echo "ERROR: gettext runtime not found at $GETTEXT_LIB"
  echo "Set GETTEXT_LIB to libintl.8.dylib."
  exit 1
fi
case "$DIST" in
  "$PROJECT"/dist-*|/tmp/*) ;;
  *) echo "ERROR: Refusing unsafe distribution path: $DIST"; exit 1 ;;
esac

# Build Swift for Apple Silicon. The bundled Python runtime is arm64-only.
cd "$PROJECT"
echo "Building arm64..."
swift build -c release --arch arm64

# Create fresh .app
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS"
PYTHON_ROOT="$APP/Contents/Resources/python"
PYTHON_STDLIB="$PYTHON_ROOT/lib/python3.8"
mkdir -p "$PYTHON_STDLIB/site-packages"

# Copy binary (prefer arm64, fallback to existing)
BINARY="$(swift build -c release --arch arm64 --show-bin-path)/MKOrbitControl"
if [ ! -f "$BINARY" ]; then
  echo "ERROR: Swift build failed. Binary not found at $BINARY"
  exit 1
fi
cp "$BINARY" "$APP/Contents/MacOS/MK-OrbitControl"

# Copy bridge + icon
cp "$PROJECT/bridge.py" "$APP/Contents/Resources/"
cp "$PROJECT/setup.sh" "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/setup.sh"
cp "$PROJECT/Sources/MKOrbitControl/AppIcon.icns" "$APP/Contents/Resources/"

# Info.plist with dynamic version
cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MK-OrbitControl</string>
    <key>CFBundleDisplayName</key><string>MK-OrbitControl</string>
    <key>CFBundleIdentifier</key><string>com.mkdevices.orbitcontrol</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>MK-OrbitControl</string>
    <key>CFBundleIconFile</key><string>AppIcon.icns</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Bundle a relocatable Python 3.8 runtime. Copying a random subset of the
# standard library produced installations that failed before bridge.py ran.
cp "$PY38/bin/python3.8" "$PYTHON_ROOT/"
cp "$PY38/lib/libpython3.8.dylib" "$PYTHON_ROOT/lib/"
cp "$GETTEXT_LIB" "$PYTHON_ROOT/lib/"
RUNTIME_LIBRARIES="
/opt/homebrew/opt/xz/lib/liblzma.5.dylib
/opt/homebrew/opt/readline/lib/libreadline.8.dylib
/opt/homebrew/opt/ncurses/lib/libncursesw.6.dylib
/opt/homebrew/opt/ncurses/lib/libpanelw.6.dylib
/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib
/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib
"
for library in $RUNTIME_LIBRARIES; do
  if [ ! -f "$library" ]; then
    echo "ERROR: Python runtime dependency not found: $library"
    exit 1
  fi
  cp "$library" "$PYTHON_ROOT/lib/"
done
rsync -a \
  --exclude '__pycache__' \
  --exclude 'site-packages' \
  --exclude 'test' \
  --exclude 'tests' \
  --exclude 'idlelib' \
  --exclude 'tkinter' \
  --exclude 'turtledemo' \
  --exclude 'ensurepip' \
  "$PY38/lib/python3.8/" "$PYTHON_STDLIB/"

# Remove build-machine absolute library paths from the embedded interpreter.
install_name_tool -change \
  "$PY38/lib/libpython3.8.dylib" \
  "@executable_path/lib/libpython3.8.dylib" \
  "$PYTHON_ROOT/python3.8"
install_name_tool -change \
  "$GETTEXT_LIB" \
  "@executable_path/lib/libintl.8.dylib" \
  "$PYTHON_ROOT/python3.8"
install_name_tool -id "@rpath/libpython3.8.dylib" "$PYTHON_ROOT/lib/libpython3.8.dylib"
install_name_tool -change \
  "$GETTEXT_LIB" \
  "@loader_path/libintl.8.dylib" \
  "$PYTHON_ROOT/lib/libpython3.8.dylib"
install_name_tool -id "@rpath/libintl.8.dylib" "$PYTHON_ROOT/lib/libintl.8.dylib"
install_name_tool -add_rpath "@executable_path/lib" "$PYTHON_ROOT/python3.8"

# Relocate optional native-module dependencies so importing them does not
# require Homebrew on the destination Mac.
for library in "$PYTHON_ROOT"/lib/*.dylib; do
  install_name_tool -id "@rpath/$(basename "$library")" "$library"
done
find "$PYTHON_ROOT" -type f \( -name 'python3.8' -o -name '*.dylib' -o -name '*.so' \) -print0 |
while IFS= read -r -d '' binary; do
  otool -L "$binary" | awk 'NR > 1 { print $1 }' | grep '^/opt/homebrew/' |
  while IFS= read -r old_path; do
    bundled="$PYTHON_ROOT/lib/$(basename "$old_path")"
    if [ -f "$bundled" ]; then
      install_name_tool -change "$old_path" "@rpath/$(basename "$old_path")" "$binary"
    fi
  done
done

# Copy site-packages
cd "$PY38/lib/python3.8/site-packages"
for pkg in zeroconf ifaddr async_timeout; do
    cp -R "$pkg" "$PYTHON_STDLIB/site-packages/" 2>/dev/null
done
cp netifaces*.so "$PYTHON_STDLIB/site-packages/" 2>/dev/null

echo ""
echo "App size:"
du -sh "$APP"

# Sign nested executable code before signing the outer app bundle.
echo ""
echo "Code signing app..."
SIGN_OPTIONS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then
  SIGN_OPTIONS+=(--timestamp --options runtime)
fi
find "$PYTHON_ROOT" -type f \( -name '*.dylib' -o -name '*.so' \) -exec \
  codesign "${SIGN_OPTIONS[@]}" {} \;
codesign "${SIGN_OPTIONS[@]}" "$PYTHON_ROOT/python3.8"
codesign "${SIGN_OPTIONS[@]}" "$APP/Contents/MacOS/MK-OrbitControl"
codesign "${SIGN_OPTIONS[@]}" "$APP"

# Verify signature
if ! codesign --verify --deep --strict --verbose=2 "$APP"; then
  echo "ERROR: Signature verification failed."
  exit 1
fi

# Copy the canonical setup script.
cp "$PROJECT/setup.sh" "$DIST/setup.sh"
chmod +x "$DIST/setup.sh"

# Copy README
cp "$PROJECT/README.md" "$DIST/README.md" 2>/dev/null || echo "# MK-OrbitControl v${VERSION}" > "$DIST/README.md"

# Create DMG
echo ""
echo "Creating DMG..."
rm -f "$DMG_FILE"
hdiutil create -volname "MK-OrbitControl v${VERSION}" -srcfolder "$DIST" -ov -format UDZO "$DMG_FILE" 2>&1 | tail -2

# Code sign the DMG
echo "Signing DMG..."
codesign "${SIGN_OPTIONS[@]}" "$DMG_FILE" 2>&1 | head -2

if [ -n "$NOTARY_PROFILE" ]; then
  if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "ERROR: NOTARY_PROFILE requires a Developer ID SIGN_IDENTITY."
    exit 1
  fi
  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "$DMG_FILE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_FILE"
  xcrun stapler validate "$DMG_FILE"
fi

echo ""
echo "✓ Build complete!"
echo "  DMG: $DMG_FILE"
ls -lh "$DMG_FILE"
echo ""
if [ -z "$NOTARY_PROFILE" ]; then
  echo "Local package only: set SIGN_IDENTITY and NOTARY_PROFILE for a notarized release."
fi
