#!/bin/bash
# Build the native Apple Silicon MK-OrbitControl distribution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR"
DIST="${DIST_ROOT:-$PROJECT/dist-bundled}"
APP="$DIST/MK-OrbitControl.app"
DERIVED_DATA="${DERIVED_DATA_ROOT:-/tmp/MKOrbitControl-Release-DerivedData}"
SOURCE_PACKAGES="${SOURCE_PACKAGES_ROOT:-/tmp/MKOrbitControl-Packages}"
DEPENDENCY_MANIFEST="$PROJECT/Config/release-dependencies.json"
PACKAGE_RESOLVED="$PROJECT/Package.resolved"
RELEASE_TOOLS="$PROJECT/scripts/release_tools.py"

# Use a certificate SHA-1 fingerprint when multiple identities share a name.
# Public artifacts require both Developer ID signing and notarisation. The
# default remains ad-hoc so local package verification does not need secrets.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ALLOW_UNTAGGED_BUILD="${ALLOW_UNTAGGED_BUILD:-0}"
ALLOW_DIRTY_BUILD="${ALLOW_DIRTY_BUILD:-0}"
UNRELEASED_VERSION="${UNRELEASED_VERSION:-}"

EXACT_TAG=$(git -C "$PROJECT" describe --tags --exact-match HEAD 2>/dev/null || true)
SHORT_SHA=$(git -C "$PROJECT" rev-parse --short=12 HEAD)
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
  NEAREST_TAG=$(git -C "$PROJECT" describe --tags --abbrev=0 2>/dev/null || true)
  VERSION="${UNRELEASED_VERSION:-${NEAREST_TAG#v}}"
  if [ -z "$VERSION" ]; then VERSION="0.0"; fi
  if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "ERROR: UNRELEASED_VERSION must use the form X.Y.Z."
    exit 1
  fi
  ARTIFACT_LABEL="UNRELEASED-$SHORT_SHA"
fi

if [ -n "$(git -C "$PROJECT" status --porcelain)" ]; then
  if [ "$ALLOW_DIRTY_BUILD" != "1" ]; then
    echo "ERROR: Refusing to package a dirty working tree."
    echo "Use ALLOW_DIRTY_BUILD=1 only for a local audit package."
    exit 1
  fi
  ARTIFACT_LABEL="$ARTIFACT_LABEL-dirty"
fi

if [ "$SIGN_IDENTITY" != "-" ]; then
  if [ -z "$EXACT_TAG" ] \
    || [ "$(git -C "$PROJECT" cat-file -t "refs/tags/$EXACT_TAG")" != "tag" ]; then
    echo "ERROR: Developer ID releases require an exact annotated vX.Y.Z tag."
    exit 1
  fi
  if [ -z "$NOTARY_PROFILE" ]; then
    echo "ERROR: Developer ID releases also require NOTARY_PROFILE."
    exit 1
  fi
elif [ -n "$NOTARY_PROFILE" ]; then
  echo "ERROR: NOTARY_PROFILE requires a Developer ID SIGN_IDENTITY."
  exit 1
fi

BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$PROJECT" rev-list --count HEAD 2>/dev/null || echo "1")}"
if [ -z "$BUILD_NUMBER" ]; then BUILD_NUMBER="1"; fi
DMG_FILE="${DMG_OUTPUT:-$HOME/Desktop/MK-OrbitControl-$ARTIFACT_LABEL.dmg}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: XcodeGen is required. Install it with: brew install xcodegen"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: Python 3 is required only for release validation."
  exit 1
fi
case "$DIST" in
  "$PROJECT"/dist-*|/tmp/*|/private/tmp/*) ;;
  *) echo "ERROR: Refusing unsafe distribution path: $DIST"; exit 1 ;;
esac
if [ ! -f "$DEPENDENCY_MANIFEST" ] \
  || [ ! -f "$PACKAGE_RESOLVED" ] \
  || [ ! -f "$RELEASE_TOOLS" ]; then
  echo "ERROR: Release manifest or verification tools are missing."
  exit 1
fi

python3 "$RELEASE_TOOLS" verify-dependencies \
  --manifest "$DEPENDENCY_MANIFEST" \
  --package-resolved "$PACKAGE_RESOLVED"

echo "Building MK-OrbitControl $ARTIFACT_LABEL..."
xcodegen generate --spec "$PROJECT/project.yml"
xcodebuild \
  -project "$PROJECT/MKOrbitControl.xcodeproj" \
  -scheme MKOrbitControl \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
  -destination 'platform=macOS,arch=arm64' \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/MK-OrbitControl.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "ERROR: Xcode build did not produce MK-OrbitControl.app."
  exit 1
fi

rm -rf "$DIST"
ditto "$BUILT_APP" "$APP"

LICENSE_DIR="$APP/Contents/Resources/ThirdPartyLicenses"
mkdir -p "$LICENSE_DIR"
cp "$PROJECT/LICENSE" "$LICENSE_DIR/MK-OrbitControl-MIT.txt"
if [ ! -s "$SOURCE_PACKAGES/checkouts/HotKey/LICENSE" ]; then
  echo "ERROR: HotKey licence is missing from the resolved source package."
  exit 1
fi
cp "$SOURCE_PACKAGES/checkouts/HotKey/LICENSE" "$LICENSE_DIR/HotKey-0.2.1-MIT.txt"
cp "$PROJECT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

# Release builds can embed build-machine paths in binaries. Neutralise them
# before signing, then reject private data and incomplete licence bundles.
python3 "$RELEASE_TOOLS" sanitise "$APP"
python3 "$RELEASE_TOOLS" audit "$APP" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/MK-OrbitControl-MIT.txt" \
  --require-licence "Contents/Resources/ThirdPartyLicenses/HotKey-0.2.1-MIT.txt"

SIGN_OPTIONS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then
  SIGN_OPTIONS+=(--timestamp --options runtime)
fi
codesign "${SIGN_OPTIONS[@]}" "$APP/Contents/MacOS/MK-OrbitControl"
codesign "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

cp "$PROJECT/README.md" "$DIST/README.md"
cp "$PROJECT/THIRD_PARTY_NOTICES.md" "$DIST/THIRD_PARTY_NOTICES.md"
ditto "$LICENSE_DIR" "$DIST/ThirdPartyLicenses"
python3 "$RELEASE_TOOLS" audit "$DIST" \
  --require-licence "ThirdPartyLicenses/MK-OrbitControl-MIT.txt" \
  --require-licence "ThirdPartyLicenses/HotKey-0.2.1-MIT.txt"

rm -f "$DMG_FILE"
hdiutil create \
  -volname "MK-OrbitControl $ARTIFACT_LABEL" \
  -srcfolder "$DIST" \
  -ov \
  -format UDZO \
  "$DMG_FILE"

codesign "${SIGN_OPTIONS[@]}" "$DMG_FILE"
if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit "$DMG_FILE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_FILE"
  xcrun stapler validate "$DMG_FILE"
  spctl --assess --type install --verbose=2 "$DMG_FILE"
fi

DMG_DIRECTORY=$(dirname "$DMG_FILE")
DMG_BASENAME=$(basename "$DMG_FILE")
(cd "$DMG_DIRECTORY" && shasum -a 256 "$DMG_BASENAME" > "$DMG_BASENAME.sha256")

echo "✓ Build complete"
echo "  DMG: $DMG_FILE"
echo "  SHA-256: $DMG_FILE.sha256"
if [ -z "$NOTARY_PROFILE" ]; then
  echo "  Local package only: set SIGN_IDENTITY and NOTARY_PROFILE for a notarised release."
fi
