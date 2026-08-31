#!/bin/bash
set -eu

echo "MK-OrbitControl Setup"
echo "====================="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="${RUNTIME_ROOT:-$HOME/Library/Application Support/MK-OrbitControl}"
MODULES="$RUNTIME/antelope_modules"
READY_MARKER="$RUNTIME/setup-complete"
if [ -x "$SCRIPT_DIR/python/python3.8" ]; then
    BUNDLED_ROOT="$SCRIPT_DIR/python"
else
    BUNDLED_ROOT="$SCRIPT_DIR/MK-OrbitControl.app/Contents/Resources/python"
fi
BUNDLED_PYTHON="$BUNDLED_ROOT/python3.8"
DEVELOPER_PYTHON="${PYTHON38_PATH:-$HOME/.pyenv/versions/3.8.20/bin/python3.8}"

if [ -d "$MODULES" ] && [ -f "$READY_MARKER" ]; then
    echo "Antelope modules already extracted. Ready to go!"
    exit 0
fi

PANEL="${ANTELOPE_PANEL:-}"
if [ ! -d /Users/Shared/.AntelopeAudio ] && [ -z "$PANEL" ]; then
    echo "ERROR: Antelope software not found. Install and open Antelope Launcher first."
    exit 1
fi

if [ -x "$BUNDLED_PYTHON" ]; then
    PYTHON="$BUNDLED_PYTHON"
    PYTHONHOME_VALUE="$BUNDLED_ROOT"
    PYTHONPATH_VALUE="$BUNDLED_ROOT/lib/python3.8:$BUNDLED_ROOT/lib/python3.8/lib-dynload:$BUNDLED_ROOT/lib/python3.8/site-packages"
elif [ -x "$DEVELOPER_PYTHON" ]; then
    PYTHON="$DEVELOPER_PYTHON"
    PYTHONHOME_VALUE=""
    PYTHONPATH_VALUE=""
else
    echo "ERROR: Python 3.8 runtime not found."
    echo "Install Python 3.8.20 with pyenv or set PYTHON38_PATH."
    exit 1
fi

mkdir -p "$RUNTIME"
chmod 700 "$RUNTIME"
STAGING=$(mktemp -d "$RUNTIME/.setup-staging.XXXXXX")
cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT

echo "Extracting modules from your Antelope installation..."
PYTHONHOME="$PYTHONHOME_VALUE" PYTHONPATH="$PYTHONPATH_VALUE" PYTHONDONTWRITEBYTECODE=1 \
"$PYTHON" - "$PANEL" "$STAGING/antelope_modules" << 'PYTHON_SCRIPT'
import importlib.util
import marshal
import os
import struct
import sys
import zlib

path = sys.argv[1]
out = sys.argv[2]
if not path:
    candidates = []
    for root, _, files in os.walk("/Users/Shared/.AntelopeAudio"):
        if "/panels/" not in root or ".app/Contents/MacOS" not in root:
            continue
        for filename in files:
            candidate = os.path.join(root, filename)
            if not os.path.isfile(candidate):
                continue
            try:
                with open(candidate, "rb") as source:
                    if source.read().find(b"PYZ\x00") >= 0:
                        candidates.append(candidate)
            except OSError:
                continue
    if not candidates:
        raise SystemExit("ERROR: no Antelope panel module archive was found")
    path = max(candidates, key=os.path.getmtime)

with open(path, "rb") as source:
    data = source.read()

pyz = data.find(b"PYZ\x00")
if pyz < 0:
    raise SystemExit("ERROR: Antelope module archive not found")

toc_position = struct.unpack(">I", data[pyz + 8:pyz + 12])[0]
toc = marshal.loads(data[pyz + toc_position:])
os.makedirs(out, exist_ok=True)
magic = importlib.util.MAGIC_NUMBER
count = 0

for entry in toc:
    name, (is_package, offset, length) = entry
    parts = name.split(".")
    if not parts or any(not part or part in (".", "..") or "/" in part or "\\" in part for part in parts):
        continue
    # These networking dependencies are supplied by MK-OrbitControl's native
    # arm64 Python runtime. The currently installed Antelope panel may itself
    # be x86_64 and its compiled extensions cannot load in the arm64 bridge.
    if parts[0] in ("zeroconf", "ifaddr", "async_timeout", "netifaces"):
        continue
    if length == 0:
        # PyInstaller namespace package: it has no payload or __init__.pyc.
        os.makedirs(os.path.join(out, *parts), exist_ok=True)
        continue
    raw = zlib.decompress(data[pyz + offset:pyz + offset + length])
    if is_package:
        destination_dir = os.path.join(out, *parts)
        destination = os.path.join(destination_dir, "__init__.pyc")
    else:
        destination_dir = os.path.join(out, *parts[:-1]) if len(parts) > 1 else out
        destination = os.path.join(destination_dir, parts[-1] + ".pyc")
    os.makedirs(destination_dir, exist_ok=True)
    with open(destination, "wb") as target:
        target.write(magic + b"\x00" * 12 + raw)
    count += 1

print(f"Extracted {count} modules")
if count < 10:
    raise SystemExit("ERROR: extracted module archive is unexpectedly small")
PYTHON_SCRIPT

rm -rf "$MODULES"
mv "$STAGING/antelope_modules" "$MODULES"
chmod -R u+rwX,go-rwx "$MODULES"
touch "$READY_MARKER"
chmod 600 "$READY_MARKER"
echo "Done! Open MK-OrbitControl.app"
