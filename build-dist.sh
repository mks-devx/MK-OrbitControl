#!/bin/bash
# Build the Apple Silicon MK-OrbitControl distribution with bundled Python 3.8.
# Python 3.8 is required because Antelope's extracted bytecode targets that ABI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR"
DIST="${DIST_ROOT:-$PROJECT/dist-bundled}"
APP="$DIST/MK-OrbitControl.app"
PY38="${PY38_ROOT:-$HOME/.pyenv/versions/3.8.20}"
GETTEXT_LIB="${GETTEXT_LIB:-/opt/homebrew/opt/gettext/lib/libintl.8.dylib}"
DERIVED_DATA="${DERIVED_DATA_ROOT:-/tmp/MKOrbitControl-Release-DerivedData}"
SOURCE_PACKAGES="${SOURCE_PACKAGES_ROOT:-/tmp/MKOrbitControl-Packages}"
DEPENDENCY_MANIFEST="$PROJECT/Config/release-dependencies.json"
PACKAGE_RESOLVED="$PROJECT/Package.resolved"
RELEASE_TOOLS="$PROJECT/scripts/release_tools.py"

# Use a certificate SHA-1 fingerprint when multiple identities share a name.
# Public artifacts require both Developer ID signing and notarization. The
# default remains ad-hoc so local package verification does not need secrets.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ALLOW_UNTAGGED_BUILD="${ALLOW_UNTAGGED_BUILD:-0}"
ALLOW_DIRTY_BUILD="${ALLOW_DIRTY_BUILD:-0}"

# A public package must be built from the exact annotated release tag. Local
# audit builds are visibly labelled UNRELEASED and require an explicit opt-in.
EXACT_TAG=$(cd "$PROJECT" && git describe --tags --exact-match HEAD 2>/dev/null || true)
SHORT_SHA=$(cd "$PROJECT" && git rev-parse --short=12 HEAD)
if [ -n "$EXACT_TAG" ]; then
  if ! printf '%s\n' "$EXACT_TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "ERROR: Release tag must use the form vX.Y.Z."
    exit 1
  fi
  VERSION="${EXACT_TAG#v}"
  ARTIFACT_LABEL="$EXACT_TAG"
else
  if [ "$ALLOW_UNTAGGED_BUILD" != "1" ]; then
    echo "ERROR: HEAD is not an exact release tag."
    echo "Use ALLOW_UNTAGGED_BUILD=1 only for a local audit package."
    exit 1
  fi
  NEAREST_TAG=$(cd "$PROJECT" && git describe --tags --abbrev=0 2>/dev/null || true)
  VERSION="${NEAREST_TAG#v}"
  if [ -z "$VERSION" ]; then VERSION="0.0"; fi
  ARTIFACT_LABEL="UNRELEASED-${SHORT_SHA}"
fi

if [ -n "$(git -C "$PROJECT" status --porcelain)" ]; then
  if [ "$ALLOW_DIRTY_BUILD" != "1" ]; then
    echo "ERROR: Refusing to package a dirty working tree."
    echo "Use ALLOW_DIRTY_BUILD=1 only for a local audit package."
    exit 1
  fi
  ARTIFACT_LABEL="${ARTIFACT_LABEL}-dirty"
fi

if [ "$SIGN_IDENTITY" != "-" ]; then
  if ! printf '%s\n' "$EXACT_TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "ERROR: Developer ID release tags must use the form vX.Y.Z."
    exit 1
  fi
  if [ -z "$EXACT_TAG" ] || [ "$(git -C "$PROJECT" cat-file -t "refs/tags/$EXACT_TAG")" != "tag" ]; then
    echo "ERROR: Developer ID releases require an exact annotated git tag."
    exit 1
  fi
  if [ -z "$NOTARY_PROFILE" ]; then
    echo "ERROR: Developer ID release builds also require NOTARY_PROFILE."
    exit 1
  fi
elif [ -n "$NOTARY_PROFILE" ]; then
  echo "ERROR: NOTARY_PROFILE requires a Developer ID SIGN_IDENTITY."
  exit 1
fi

BUILD_NUMBER="${BUILD_NUMBER:-$(cd "$PROJECT" && git rev-list --count HEAD 2>/dev/null || echo "1")}"
if [ -z "$BUILD_NUMBER" ]; then BUILD_NUMBER="1"; fi
DMG_FILE="${DMG_OUTPUT:-$HOME/Desktop/MK-OrbitControl-${ARTIFACT_LABEL}.dmg}"

echo "Building MK-OrbitControl ${ARTIFACT_LABEL}..."

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
  "$PROJECT"/dist-*|/tmp/*|/private/tmp/*) ;;
  *) echo "ERROR: Refusing unsafe distribution path: $DIST"; exit 1 ;;
esac
if [ ! -f "$DEPENDENCY_MANIFEST" ] || [ ! -f "$PACKAGE_RESOLVED" ] || [ ! -f "$RELEASE_TOOLS" ]; then
  echo "ERROR: Release manifest or verification tools are missing."
  exit 1
fi
"$PY38/bin/python3.8" "$RELEASE_TOOLS" verify-dependencies \
  --manifest "$DEPENDENCY_MANIFEST" \
  --python "$PY38/bin/python3.8" \
  --package-resolved "$PACKAGE_RESOLVED"

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
while IFS= read -r -d '' binary; do
  while IFS= read -r old_path; do
    bundled="$PYTHON_ROOT/lib/$(basename "$old_path")"
    if [ -f "$bundled" ]; then
      install_name_tool -change "$old_path" "@rpath/$(basename "$old_path")" "$binary"
    fi
  done < <(otool -L "$binary" | awk 'NR > 1 { print $1 }' | grep '^/opt/homebrew/' || true)
done < <(find "$PYTHON_ROOT" -type f \( -name 'python3.8' -o -name '*.dylib' -o -name '*.so' \) -print0)

# Copy only the pinned runtime packages. Do not carry local bytecode caches or
# installed-package metadata containing build-machine paths into the app.
cd "$PY38/lib/python3.8/site-packages"
for pkg in zeroconf ifaddr async_timeout; do
  if [ ! -d "$pkg" ]; then
    echo "ERROR: Required Python package directory is missing: $pkg"
    exit 1
  fi
  rsync -a --exclude '__pycache__' --exclude '*.pyc' \
    "$pkg" "$PYTHON_STDLIB/site-packages/"
done
shopt -s nullglob
NETIFACES_BINARIES=(netifaces*.so)
shopt -u nullglob
if [ "${#NETIFACES_BINARIES[@]}" -ne 1 ]; then
  echo "ERROR: Expected exactly one pinned netifaces extension."
  exit 1
fi
cp "${NETIFACES_BINARIES[0]}" "$PYTHON_STDLIB/site-packages/"

# Remove development-only runtime content and every local bytecode cache.
rm -rf "$PYTHON_STDLIB/config-3.8-darwin"
rm -f "$PYTHON_STDLIB"/lib-dynload/readline.*.so
rm -f "$PYTHON_STDLIB"/lib-dynload/_curses.*.so
rm -f "$PYTHON_STDLIB"/lib-dynload/_curses_panel.*.so
find "$PYTHON_ROOT" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$PYTHON_ROOT" -type f -name '*.pyc' -delete

# Bundle complete licence texts inside the signed app so they remain available
# after the user copies the app out of the DMG.
LICENSE_DIR="$APP/Contents/Resources/ThirdPartyLicenses"
mkdir -p "$LICENSE_DIR"
copy_required_licence() {
  source_path="$1"
  destination_name="$2"
  if [ ! -s "$source_path" ]; then
    echo "ERROR: Required licence file is missing: $destination_name"
    exit 1
  fi
  cp "$source_path" "$LICENSE_DIR/$destination_name"
}
copy_required_licence "$PROJECT/LICENSE" "MK-OrbitControl-MIT.txt"
copy_required_licence "$PROJECT/licenses/netifaces-0.11.0-MIT.txt" "netifaces-0.11.0-MIT.txt"
copy_required_licence "$PY38/lib/python3.8/LICENSE.txt" "Python-3.8.20.txt"
copy_required_licence "$PY38/lib/python3.8/site-packages/async_timeout-5.0.1.dist-info/LICENSE" "async-timeout-5.0.1-Apache-2.0.txt"
copy_required_licence "$PY38/lib/python3.8/site-packages/ifaddr-0.2.0.dist-info/LICENSE.txt" "ifaddr-0.2.0-MIT.txt"
copy_required_licence "$PY38/lib/python3.8/site-packages/zeroconf-0.136.2.dist-info/COPYING" "zeroconf-0.136.2-LGPL-2.1-or-later.txt"
copy_required_licence "$SOURCE_PACKAGES/checkouts/HotKey/LICENSE" "HotKey-0.2.1-MIT.txt"
copy_required_licence "/opt/homebrew/opt/gettext/COPYING" "gettext-1.0-COPYING.txt"
copy_required_licence "/opt/homebrew/opt/openssl@3/LICENSE.txt" "OpenSSL-3.6.3-Apache-2.0.txt"
copy_required_licence "/opt/homebrew/opt/xz/COPYING" "xz-5.8.3-COPYING.txt"
copy_required_licence "/opt/homebrew/opt/xz/COPYING.0BSD" "xz-5.8.3-0BSD.txt"
copy_required_licence "/opt/homebrew/opt/xz/COPYING.LGPLv2.1" "xz-5.8.3-LGPL-2.1.txt"
cp "$PROJECT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

# Neutralise build-home strings without changing binary sizes, then prove the
# relocated runtime can import every required bridge dependency.
"$PY38/bin/python3.8" "$RELEASE_TOOLS" sanitise "$APP"

# Binary sanitisation invalidates signatures inherited from Homebrew and the
# local Python installation. Apply temporary ad-hoc signatures so macOS can
# execute the relocated runtime smoke test; the final identity is applied below.
while IFS= read -r -d '' binary; do
  codesign --force --sign - "$binary"
done < <(find "$PYTHON_ROOT" -type f \( -name '*.dylib' -o -name '*.so' \) -print0)
codesign --force --sign - "$PYTHON_ROOT/python3.8"

PYTHONHOME="$PYTHON_ROOT" \
PYTHONPATH="$PYTHON_STDLIB:$PYTHON_STDLIB/lib-dynload:$PYTHON_STDLIB/site-packages" \
PYTHONDONTWRITEBYTECODE=1 \
"$PYTHON_ROOT/python3.8" -c \
  'import async_timeout, ifaddr, netifaces, zeroconf; print("Bundled Python runtime smoke test passed.")'

"$PY38/bin/python3.8" "$RELEASE_TOOLS" audit "$APP" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/MK-OrbitControl-MIT.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/Python-3.8.20.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/HotKey-0.2.1-MIT.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/async-timeout-5.0.1-Apache-2.0.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/ifaddr-0.2.0-MIT.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/netifaces-0.11.0-MIT.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/zeroconf-0.136.2-LGPL-2.1-or-later.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/gettext-1.0-COPYING.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/OpenSSL-3.6.3-Apache-2.0.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/xz-5.8.3-COPYING.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/xz-5.8.3-0BSD.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/xz-5.8.3-LGPL-2.1.txt"

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
cp "$PROJECT/THIRD_PARTY_NOTICES.md" "$DIST/THIRD_PARTY_NOTICES.md"
ditto "$LICENSE_DIR" "$DIST/ThirdPartyLicenses"
"$PY38/bin/python3.8" "$RELEASE_TOOLS" audit "$DIST" \
  --require-licence "ThirdPartyLicenses/MK-OrbitControl-MIT.txt" \
  --require-licence "ThirdPartyLicenses/Python-3.8.20.txt" \
  --require-licence "ThirdPartyLicenses/HotKey-0.2.1-MIT.txt" \
  --require-licence "ThirdPartyLicenses/zeroconf-0.136.2-LGPL-2.1-or-later.txt"

# Create DMG
echo ""
echo "Creating DMG..."
rm -f "$DMG_FILE"
if ! hdiutil create -volname "MK-OrbitControl ${ARTIFACT_LABEL}" -srcfolder "$DIST" -ov -format UDZO "$DMG_FILE"; then
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
  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "$DMG_FILE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_FILE"
  xcrun stapler validate "$DMG_FILE"
  spctl --assess --type install --verbose=2 "$DMG_FILE"
fi

DMG_DIRECTORY=$(dirname "$DMG_FILE")
DMG_BASENAME=$(basename "$DMG_FILE")
(cd "$DMG_DIRECTORY" && shasum -a 256 "$DMG_BASENAME" > "${DMG_BASENAME}.sha256")

echo ""
echo "✓ Build complete!"
echo "  DMG: $DMG_FILE"
ls -lh "$DMG_FILE"
echo "  SHA-256: ${DMG_FILE}.sha256"
echo ""
if [ -z "$NOTARY_PROFILE" ]; then
  echo "Local package only: set SIGN_IDENTITY and NOTARY_PROFILE for a notarized release."
fi
