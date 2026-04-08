#!/bin/bash
# Build MK-OrbitControl distribution with bundled Python 3.8
# Continue on errors for optional copies

PROJECT="$HOME/Developer/MK-AntelopeControl"
DIST="$PROJECT/dist-bundled"
APP="$DIST/MK-OrbitControl.app"
PY38="$HOME/.pyenv/versions/3.8.20"

echo "Building MK-OrbitControl..."

# Build Swift
cd "$PROJECT"
swift build -c release 2>&1 | tail -3

# Create fresh .app
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/python/lib"
mkdir -p "$APP/Contents/Resources/python/lib-dynload"
mkdir -p "$APP/Contents/Resources/python/site-packages"

# Copy binary
cp "$PROJECT/.build/release/MKAntelopeControl" "$APP/Contents/MacOS/MK-OrbitControl"

# Copy bridge + icon
cp "$PROJECT/bridge.py" "$APP/Contents/Resources/"
cp "$PROJECT/Sources/MKAntelopeControl/AppIcon.icns" "$APP/Contents/Resources/"

# Info.plist
cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MK-OrbitControl</string>
    <key>CFBundleDisplayName</key><string>MK-OrbitControl</string>
    <key>CFBundleIdentifier</key><string>com.mkdevices.orbitcontrol</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>MK-OrbitControl</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
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
cp "$PROJECT/dist/README.txt" "$DIST/"

# Create zip
cd "$DIST"
zip -r "$HOME/Desktop/MK-OrbitControl-v1.0.zip" MK-OrbitControl.app setup.sh README.txt

echo ""
echo "Done! Zip at: ~/Desktop/MK-OrbitControl-v1.0.zip"
ls -lh "$HOME/Desktop/MK-OrbitControl-v1.0.zip"
