#!/bin/bash
# MK-OrbitControl Setup Script
# Run this before using the app for the first time

echo "=============================="
echo "  MK-OrbitControl Setup"
echo "=============================="
echo ""

# Check for Antelope
if [ ! -d "/Users/Shared/.AntelopeAudio" ]; then
    echo "ERROR: Antelope Audio software not found."
    echo "Please install Antelope Launcher first."
    exit 1
fi

echo "[1/4] Checking Antelope installation... OK"

# Check for report format
RF=$(find /Users/Shared/.AntelopeAudio -name "report_format_*" -type f 2>/dev/null | head -1)
if [ -z "$RF" ]; then
    echo "ERROR: No Antelope device report format found."
    echo "Please open the Antelope Control Panel at least once."
    exit 1
fi
echo "[2/4] Found report format: $RF"

# Install pyenv + Python 3.8
if ! command -v pyenv &> /dev/null; then
    echo "[3/4] Installing pyenv..."
    brew install pyenv
else
    echo "[3/4] pyenv already installed"
fi

PY38="$HOME/.pyenv/versions/3.8.20/bin/python3.8"
if [ ! -f "$PY38" ]; then
    echo "       Installing Python 3.8.20 (this takes a few minutes)..."
    eval "$(pyenv init -)" && pyenv install 3.8.20
fi

if [ -f "$PY38" ]; then
    echo "       Python 3.8.20 ready"
    $PY38 -m pip install zeroconf netifaces 2>/dev/null | tail -1
else
    echo "ERROR: Python 3.8 installation failed"
    exit 1
fi

# Extract Antelope modules
MODULES_DIR="$HOME/Developer/MK-AntelopeControl/antelope_modules"
if [ ! -d "$MODULES_DIR" ]; then
    echo "[4/4] Extracting Antelope modules from your installation..."
    mkdir -p "$HOME/Developer/MK-AntelopeControl"

    # Find the panel binary
    PANEL=$(find /Users/Shared/.AntelopeAudio -name "orionstudioiii" -type f 2>/dev/null | grep MacOS | head -1)
    if [ -z "$PANEL" ]; then
        # Try other devices
        PANEL=$(find /Users/Shared/.AntelopeAudio -path "*/MacOS/*" -type f ! -name ".*" 2>/dev/null | head -1)
    fi

    if [ -z "$PANEL" ]; then
        echo "ERROR: Cannot find Antelope panel binary"
        exit 1
    fi

    $PY38 -c "
import struct, zlib, marshal, os, sys, importlib.util

path = '$PANEL'
with open(path, 'rb') as f:
    data = f.read()

pyz_offset = data.find(b'PYZ\x00')
if pyz_offset < 0:
    print('ERROR: Not a PyInstaller binary')
    sys.exit(1)

toc_pos = struct.unpack('>I', data[pyz_offset+8:pyz_offset+12])[0]
toc_data = data[pyz_offset + toc_pos:]
toc = marshal.loads(toc_data)

output_dir = '$MODULES_DIR'
os.makedirs(output_dir, exist_ok=True)
magic = importlib.util.MAGIC_NUMBER
extracted = 0

for entry in toc:
    name, (ispkg, offset, length) = entry
    compressed = data[pyz_offset + offset: pyz_offset + offset + length]
    raw = zlib.decompress(compressed)
    parts = name.split('.')
    if ispkg:
        dir_path = os.path.join(output_dir, *parts)
    else:
        dir_path = os.path.join(output_dir, *parts[:-1]) if len(parts) > 1 else output_dir
    os.makedirs(dir_path, exist_ok=True)
    if ispkg:
        pyc_path = os.path.join(dir_path, '__init__.pyc')
    else:
        pyc_path = os.path.join(dir_path, parts[-1] + '.pyc') if len(parts) > 1 else os.path.join(output_dir, parts[0] + '.pyc')
    header = magic + b'\x00' * 12
    with open(pyc_path, 'wb') as f:
        f.write(header + raw)
    extracted += 1

print(f'Extracted {extracted} modules')
"
else
    echo "[4/4] Antelope modules already extracted"
fi

# Copy bridge.py
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/MK-OrbitControl.app/Contents/Resources/bridge.py" "$HOME/Developer/MK-AntelopeControl/bridge.py" 2>/dev/null

echo ""
echo "=============================="
echo "  Setup complete!"
echo "=============================="
echo ""
echo "To run: open MK-OrbitControl.app"
echo "Make sure Antelope Launcher is running first."
