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
