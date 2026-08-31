#!/bin/bash
# Build the Apple Silicon MK-OrbitControl distribution with bundled Python 3.8.
# Python 3.8 is required because Antelope's extracted bytecode targets that ABI.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR"
DIST="${DIST_ROOT:-$PROJECT/dist-bundled}"
APP="$DIST/MK-OrbitControl.app"
PY38="${PY38_ROOT:-$HOME/.pyenv/versions/3.8.20}"
GETTEXT_LIB="${GETTEXT_LIB:-/opt/homebrew/opt/gettext/lib/libintl.8.dylib}"
DERIVED_DATA="${DERIVED_DATA_ROOT:-/tmp/MKOrbitControl-Release-DerivedData}"
SOURCE_PACKAGES="${SOURCE_PACKAGES_ROOT:-/tmp/MKOrbitControl-Packages}"

# Get version from the latest git tag (e.g., v1.4 -> 1.4).
VERSION=$(cd "$PROJECT" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.4")
if [ -z "$VERSION" ] || [ "$VERSION" = "v" ]; then VERSION="1.4"; fi
BUILD_NUMBER="${BUILD_NUMBER:-$(cd "$PROJECT" && git rev-list --count HEAD 2>/dev/null || echo "1")}"
if [ -z "$BUILD_NUMBER" ]; then BUILD_NUMBER="1"; fi
DMG_FILE="${DMG_OUTPUT:-$HOME/Desktop/MK-OrbitControl-v${VERSION}.dmg}"

# Use a certificate SHA-1 fingerprint when multiple identities share a name.
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
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: XcodeGen is required to build the app."
  echo "Install it with: brew install xcodegen"
  exit 1
fi
case "$DIST" in
  "$PROJECT"/dist-*|/tmp/*) ;;
  *) echo "ERROR: Refusing unsafe distribution path: $DIST"; exit 1 ;;
esac

# Build the app for Apple Silicon. The bundled Python runtime is arm64-only.
cd "$PROJECT"
echo "Building arm64..."
xcodegen generate --spec "$PROJECT/project.yml"
if ! xcodebuild \
  -project "$PROJECT/MKOrbitControl.xcodeproj" \
  -scheme MKOrbitControl \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
  -destination 'platform=macOS,arch=arm64' \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  build; then
  echo "ERROR: Xcode app build failed."
  exit 1
fi

BUILT_APP="$DERIVED_DATA/Build/Products/Release/MK-OrbitControl.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "ERROR: Xcode build failed. App not found at $BUILT_APP"
  exit 1
fi

# Create fresh .app
rm -rf "$DIST"
ditto "$BUILT_APP" "$APP"
PYTHON_ROOT="$APP/Contents/Resources/python"
PYTHON_STDLIB="$PYTHON_ROOT/lib/python3.8"
mkdir -p "$PYTHON_STDLIB/site-packages"

# Copy bridge + icon
cp "$PROJECT/bridge.py" "$APP/Contents/Resources/"
cp "$PROJECT/setup.sh" "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/setup.sh"

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
while IFS= read -r -d '' binary; do
  if ! codesign "${SIGN_OPTIONS[@]}" "$binary"; then
    echo "ERROR: Failed to sign nested runtime code: $binary"
    exit 1
  fi
done < <(find "$PYTHON_ROOT" -type f \( -name '*.dylib' -o -name '*.so' \) -print0)
if ! codesign "${SIGN_OPTIONS[@]}" "$PYTHON_ROOT/python3.8"; then
  echo "ERROR: Failed to sign the embedded Python runtime."
  exit 1
fi
if ! codesign "${SIGN_OPTIONS[@]}" "$APP/Contents/MacOS/MK-OrbitControl"; then
  echo "ERROR: Failed to sign the app executable."
  exit 1
fi
if ! codesign "${SIGN_OPTIONS[@]}" "$APP"; then
  echo "ERROR: Failed to sign the app bundle."
  exit 1
fi

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
if ! hdiutil create -volname "MK-OrbitControl v${VERSION}" -srcfolder "$DIST" -ov -format UDZO "$DMG_FILE"; then
  echo "ERROR: DMG creation failed."
  exit 1
fi

# Code sign the DMG
echo "Signing DMG..."
if ! codesign "${SIGN_OPTIONS[@]}" "$DMG_FILE"; then
  echo "ERROR: DMG signing failed."
  exit 1
fi

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
