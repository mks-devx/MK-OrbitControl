# Installation Guide — MK-OrbitControl

## Quick Install (Recommended)

### Step 1: Download the DMG
- Visit [Releases](https://github.com/mks-devx/MK-OrbitControl/releases/latest)
- Download `MK-OrbitControl-v1.2.dmg` (or newer)
- Double-click to mount

### Step 2: Install the App
1. Open Finder → go to **Applications** folder
2. Drag **MK-OrbitControl.app** from the mounted DMG into Applications
3. Wait for copy to complete
4. Eject the DMG when done

### Step 3: Run Setup
1. Open Terminal (Applications → Utilities → Terminal)
2. Copy and paste this command:
   ```bash
   bash /Volumes/MK-OrbitControl/setup.sh
   ```
3. Press Enter and wait for "Extracted X modules"

### Step 4: Launch
- Open Finder → Applications
- Double-click **MK-OrbitControl**
- A speaker icon should appear in your menu bar (top right)

---

## Troubleshooting

### ❌ "Application not supported on this Mac"

**This is a code signing issue on macOS 13+**

**Solution:**
1. Right-click the MK-OrbitControl.app in Applications
2. Select **"Open"** from the menu
3. Click **"Open"** in the dialog that appears
4. App should launch normally now
5. From then on, you can click it normally

**Alternative (if right-click doesn't work):**
```bash
xattr -d com.apple.quarantine /Applications/MK-OrbitControl.app
```
Then double-click normally.

### ❌ "App can't be opened because it's from an unidentified developer"

Same as above — use the right-click "Open" workaround.

### ❌ Icon doesn't show in menu bar

**Try:**
1. Quit the app (menu bar icon → Quit)
2. Relaunch it
3. Check System Settings → General → Login Items (should auto-start)

**If still missing:**
- The app runs in menu bar only (LSUIElement). If no menu bar icon appears within 5 seconds, restart your Mac.

### ❌ "ERROR: Antelope software not found"

**The setup script needs Antelope Launcher installed.**

**Solution:**
1. Install [Antelope Launcher](https://www.antelopeaudio.com/downloads/) from Antelope's website
2. Launch it once (it installs the AntelopeAudioServer)
3. Then run the setup script again:
   ```bash
   bash /Volumes/MK-OrbitControl/setup.sh
   ```

### ❌ Setup script says "already extracted"

This is normal if you've run it before. Just launch the app from Applications.

### ❌ App launches but shows "Offline" or no device

1. Make sure Antelope Launcher is running (look in System Settings → General → Login Items)
2. Check that your Synergy Core device is powered on and connected via Thunderbolt
3. Restart the AntelopeAudioServer:
   ```bash
   sudo killall AntelopeAudioServer
   ```
   Then wait 5 seconds and reconnect.

### ❌ Can't find /Volumes/MK-OrbitControl in Terminal

The DMG might have ejected. Double-click the DMG file again to re-mount it, then run the setup command again.

---

## Advanced Setup (For Developers)

### Build from Source

```bash
# Clone repo
git clone https://github.com/mks-devx/MK-OrbitControl.git
cd MK-OrbitControl

# Install Python 3.8
brew install pyenv
pyenv install 3.8.20

# Install Python deps
~/.pyenv/versions/3.8.20/bin/python3.8 -m pip install zeroconf netifaces

# Build Swift app
swift build -c release

# Run setup to extract Antelope modules
bash dist-bundled/setup.sh

# Run the app
.build/release/MKAntelopeControl
```

### Build DMG for Distribution

```bash
bash build-dist.sh
# Creates: ~/Desktop/MK-OrbitControl-vX.Y.Z.dmg
```

---

## What Gets Installed?

| File | Location | Purpose |
|------|----------|---------|
| **MK-OrbitControl.app** | `/Applications/` | The menu bar app |
| **bridge.py** | `~/Developer/MK-AntelopeControl/` | Python bridge to Antelope API |
| **antelope_modules/** | `~/Developer/MK-AntelopeControl/` | Extracted from your Antelope installation |

Nothing else is installed. The app talks to the official Antelope Audio server on your Mac (AntelopeAudioServer), which is part of Antelope Launcher.

---

## Uninstall

```bash
# Remove app
rm -rf /Applications/MK-OrbitControl.app

# (Optional) Clean up developer files
rm -rf ~/Developer/MK-AntelopeControl
```

---

## System Requirements

- **macOS 13 or later** (13, 14, 15)
- **Antelope Launcher** installed (free from antelopeaudio.com)
- **Synergy Core device** (Orion Studio III, Discrete 4, etc.)
- **Thunderbolt connection** to device

---

## Support

Having issues? [Open an issue on GitHub](https://github.com/mks-devx/MK-OrbitControl/issues) with:
- Your **device model** (Orion Studio III, Discrete 4, etc.)
- Your **macOS version** (Settings → About → macOS)
- The **exact error message** you see

Or [buy me a coffee](https://buymeacoffee.com/mk_tools) to show support!
