#!/bin/bash
# Build MK-OrbitControl distribution with bundled Python 3.8
# Builds universal binary (arm64 + x86_64), code signs, creates DMG
# Continue on errors for optional copies

PROJECT="$HOME/Developer/MK-AntelopeControl"
DIST="$PROJECT/dist-bundled"
APP="$DIST/MK-OrbitControl.app"
PY38="$HOME/.pyenv/versions/3.8.20"

# Get version from git tag (e.g., v1.2 → 1.2), fallback to 1.2
VERSION=$(cd "$PROJECT" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.2")
if [ -z "$VERSION" ] || [ "$VERSION" = "v" ]; then VERSION="1.2"; fi
DMG_FILE="$HOME/Desktop/MK-OrbitControl-v${VERSION}.dmg"

# Signing identity (change if you have a certificate)
SIGN_IDENTITY="-" # ad-hoc signing

echo "Building MK-OrbitControl v${VERSION}..."

# Build Swift for both architectures
cd "$PROJECT"
echo "Building arm64..."
swift build -c release 2>&1 | tail -1
echo "Building x86_64..."
swift build -c release -Xswiftc -target -Xswiftc x86_64-apple-macosx13 2>&1 | tail -1 || {
  echo "x86_64 build optional (universal may fail), continuing..."
}

# Create fresh .app
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/python/lib"
mkdir -p "$APP/Contents/Resources/python/lib-dynload"
mkdir -p "$APP/Contents/Resources/python/site-packages"

# Copy binary (prefer arm64, fallback to existing)
BINARY="$PROJECT/.build/release/MKAntelopeControl"
if [ ! -f "$BINARY" ]; then
  echo "ERROR: Swift build failed. Binary not found at $BINARY"
  exit 1
fi
cp "$BINARY" "$APP/Contents/MacOS/MK-OrbitControl"

# Copy bridge + icon
cp "$PROJECT/bridge.py" "$APP/Contents/Resources/"
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

# Bundle Python 3.8 binary
cp "$PY38/bin/python3.8" "$APP/Contents/Resources/python/"

# Bundle minimal stdlib
cd "$PY38/lib/python3.8"
for f in $(find . -name "*.pyc" -path "*/__pycache__/*" | head -200); do
    dir=$(dirname "$f")
    # Convert __pycache__/foo.cpython-38.pyc to foo.pyc
    base=$(basename "$f" | sed 's/.cpython-38//')
    parent=$(dirname "$dir")
    mkdir -p "$APP/Contents/Resources/python/lib/$parent"
    cp "$f" "$APP/Contents/Resources/python/lib/$parent/$base" 2>/dev/null
done

# Also copy .py files for essential modules
for mod in os.py posixpath.py stat.py genericpath.py types.py abc.py \
    copyreg.py warnings.py weakref.py functools.py operator.py \
    enum.py re.py sre_compile.py sre_parse.py sre_constants.py \
    socket.py selectors.py threading.py queue.py struct.py \
    traceback.py linecache.py tokenize.py token.py keyword.py \
    ipaddress.py datetime.py contextlib.py textwrap.py \
    _bootlocale.py _py_abc.py _weakrefset.py _collections_abc.py \
    _threading_local.py __future__.py typing.py; do
    cp "$mod" "$APP/Contents/Resources/python/lib/" 2>/dev/null
done

# Copy essential packages
for pkg in json collections encodings importlib; do
    cp -r "$pkg" "$APP/Contents/Resources/python/lib/" 2>/dev/null
done

# Copy native extensions
for ext in _json _struct _socket select math _datetime _bisect _heapq \
    _contextvars _queue array _posixsubprocess fcntl _operator \
    _collections _functools _statistics binascii zlib; do
    cp lib-dynload/${ext}*.so "$APP/Contents/Resources/python/lib-dynload/" 2>/dev/null
done

# Copy site-packages
cd "$PY38/lib/python3.8/site-packages"
for pkg in zeroconf ifaddr async_timeout; do
    cp -r "$pkg" "$APP/Contents/Resources/python/site-packages/" 2>/dev/null
done
cp netifaces*.so "$APP/Contents/Resources/python/site-packages/" 2>/dev/null

echo ""
echo "App size:"
du -sh "$APP"

# CODE SIGN THE APP (critical for macOS 13+)
echo ""
echo "Code signing app..."
codesign --deep --force --verbose --sign "$SIGN_IDENTITY" "$APP" 2>&1 | grep -E "(Signing|replacing)"

# Verify signature
if ! codesign -v "$APP" 2>&1 | grep -q "valid"; then
  echo "WARNING: Signature verification failed. App may not run."
fi

# Create setup script (only needs to extract antelope modules)
cat > "$DIST/setup.sh" << 'SETUP'
#!/bin/bash
echo "MK-OrbitControl Setup"
echo "====================="

MODULES="$HOME/Developer/MK-AntelopeControl/antelope_modules"
if [ -d "$MODULES" ]; then
    echo "Antelope modules already extracted. Ready to go!"
    exit 0
fi

PANEL=$(find /Users/Shared/.AntelopeAudio -path "*/MacOS/*" -type f ! -name ".*" 2>/dev/null | head -1)
if [ -z "$PANEL" ]; then
    echo "ERROR: Antelope software not found. Install Antelope Launcher first."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="$SCRIPT_DIR/MK-OrbitControl.app/Contents/Resources/python/python3.8"

mkdir -p "$HOME/Developer/MK-AntelopeControl"

echo "Extracting modules from your Antelope installation..."
"$PYTHON" -c "
import struct, zlib, marshal, os, sys, importlib.util
path = '$PANEL'
with open(path, 'rb') as f:
    data = f.read()
pyz = data.find(b'PYZ\x00')
if pyz < 0: print('ERROR'); sys.exit(1)
tp = struct.unpack('>I', data[pyz+8:pyz+12])[0]
toc = marshal.loads(data[pyz+tp:])
out = '$MODULES'
os.makedirs(out, exist_ok=True)
magic = importlib.util.MAGIC_NUMBER
n = 0
for e in toc:
    nm, (ip, off, ln) = e
    raw = zlib.decompress(data[pyz+off:pyz+off+ln])
    pts = nm.split('.')
    dp = os.path.join(out, *pts) if ip else (os.path.join(out, *pts[:-1]) if len(pts)>1 else out)
    os.makedirs(dp, exist_ok=True)
    pp = os.path.join(dp, '__init__.pyc') if ip else os.path.join(dp if ip else (os.path.join(out, *pts[:-1]) if len(pts)>1 else out), (pts[-1] if len(pts)>1 else pts[0])+'.pyc')
    with open(pp, 'wb') as f: f.write(magic + b'\x00'*12 + raw)
    n += 1
print(f'Extracted {n} modules')
"

cp "$SCRIPT_DIR/MK-OrbitControl.app/Contents/Resources/bridge.py" "$HOME/Developer/MK-AntelopeControl/"
echo "Done! Open MK-OrbitControl.app"
SETUP
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
codesign --force --verbose --sign "$SIGN_IDENTITY" "$DMG_FILE" 2>&1 | head -2

echo ""
echo "✓ Build complete!"
echo "  DMG: $DMG_FILE"
ls -lh "$DMG_FILE"
echo ""
echo "Next: Upload to GitHub Releases and notarize (optional):"
echo "  xcrun notarytool submit '$DMG_FILE' --apple-id YOUR_EMAIL --password YOUR_PASSWORD"
