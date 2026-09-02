# Installation Guide — MK-OrbitControl

## Current Availability

The official Apple Silicon public beta is distributed only through [GitHub Releases](https://github.com/mks-devx/MK-OrbitControl/releases). Release DMGs are Developer ID signed, notarised by Apple, and published with a SHA-256 checksum. Do not install application bundles or DMGs from issues, forks, or third-party links.

## Signed Release Installation

These steps apply to the official notarised DMG.

### Step 1: Download the DMG
- Visit [Releases](https://github.com/mks-devx/MK-OrbitControl/releases)
- Download the current notarised `MK-OrbitControl` DMG
- Double-click to mount

### Step 2: Install the App
1. Open Finder → go to **Applications** folder
2. Drag **MK-OrbitControl.app** from the mounted DMG into Applications
3. Wait for copy to complete
4. Eject the DMG when done

### Step 3: Complete Setup
1. Launch MK-OrbitControl.
2. If the setup notice appears, click **Run Setup**.
3. If in-app setup fails, keep the DMG mounted and run this Terminal fallback:
   ```bash
   bash "/Applications/MK-OrbitControl.app/Contents/Resources/setup.sh"
   ```
4. Wait for "Extracted X modules" and reopen the app.

### Step 4: Launch
- Open Finder → Applications
- Double-click **MK-OrbitControl**
- A speaker icon should appear in your menu bar (top right)

---

## Troubleshooting

### ❌ "Application not supported on this Mac"

This can indicate an incompatible CPU architecture, an unsupported macOS version, a damaged bundle, or a signing problem. Confirm that the Mac is Apple Silicon and runs macOS 13 or later first.

**Official release:**
1. Confirm the Mac is Apple Silicon and runs macOS 13 or later.
2. Delete the rejected copy and download the DMG again from GitHub Releases.
3. Verify the published SHA-256 checksum.
4. If macOS still rejects it, open an issue rather than disabling Gatekeeper.

### ❌ "App can't be opened because it's from an unidentified developer"

The official release should not show this warning because it is Developer ID signed and notarised. Delete the copy, download it again from the official Releases page, verify the checksum, and report the problem if it persists. Right-click → Open is appropriate only for your own ad-hoc source build.

### ❌ Icon doesn't show in menu bar

**Try:**
1. Quit the app (menu bar icon → Quit)
2. Relaunch it
3. If you enabled **Launch at Login**, check System Settings → General → Login Items

**If still missing:**
- The app runs in menu bar only (LSUIElement). If no menu bar icon appears within 5 seconds, restart your Mac.

### ❌ "ERROR: Antelope software not found"

**The setup script needs Antelope Launcher installed.**

**Solution:**
1. Install [Antelope Launcher](https://www.antelopeaudio.com/downloads/) from Antelope's website
2. Launch it once (it installs the AntelopeAudioServer)
3. Then run the setup script again:
   ```bash
   bash "/Applications/MK-OrbitControl.app/Contents/Resources/setup.sh"
   ```

### ❌ Setup script says "already extracted"

This is normal if you've run it before. Just launch the app from Applications.

### ❌ App launches but shows "Offline" or no device

1. Make sure Antelope Launcher is running (look in System Settings → General → Login Items)
2. Check that your Synergy Core device is powered on and connected via Thunderbolt
3. Click the **reconnect button** (circular arrow icon next to the connection status) to force an immediate re-scan
4. If still offline, use **Restart Antelope Server** in MK-OrbitControl. This reopens Antelope Launcher without terminating system processes.

### ❌ Device disconnects when unplugging Thunderbolt cable

This is expected. When you reconnect the cable:
1. Wait a few seconds for the device to power up
2. Click the **reconnect button** (circular arrow) in the app header
3. The app will immediately re-scan and reconnect — no need to restart

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
bash setup.sh

# Run the app
.build/release/MKOrbitControl
```

### Build a Local Audit DMG

```bash
ALLOW_UNTAGGED_BUILD=1 ALLOW_DIRTY_BUILD=1 bash build-dist.sh
# Creates: ~/Desktop/MK-OrbitControl-UNRELEASED-{commit}.dmg
```

Public packages require a clean checkout at an exact annotated `vX.Y.Z` tag, a Developer ID Application identity, and a `notarytool` keychain profile. The build stops if dependencies differ from `Config/release-dependencies.json`, private build paths remain, licence texts are missing, or runtime smoke tests fail.

---

## What Gets Installed?

| File | Location | Purpose |
|------|----------|---------|
| **MK-OrbitControl.app** | `/Applications/` | The menu bar app |
| **bridge-token** | `~/Library/Application Support/MK-OrbitControl/` | Owner-only authentication token for the local bridge |
| **setup-complete** | `~/Library/Application Support/MK-OrbitControl/` | Setup completion marker |
| **antelope_modules/** | `~/Library/Application Support/MK-OrbitControl/` | Extracted from your Antelope installation |
| **Preferences** | `~/Library/Preferences/com.mkdevices.orbitcontrol.plist` | App settings, mappings, and appearance choices |
| **Login Item** | macOS background-items database | Present only when Launch at Login is enabled |

MK-OrbitControl installs no privileged helper, launch daemon, or system service. The app talks to the official Antelope Audio server on your Mac, which is installed and managed separately by Antelope Launcher.

---

## Uninstall

```bash
# Remove app
rm -rf /Applications/MK-OrbitControl.app

# (Optional) Remove extracted compatibility modules and bridge
rm -rf "$HOME/Library/Application Support/MK-OrbitControl"

# (Optional) Remove saved preferences
defaults delete com.mkdevices.orbitcontrol 2>/dev/null || true
```

Disable **Launch at Login** in MK-OrbitControl Settings before deleting the app so macOS removes its login-item registration cleanly.

---

## System Requirements

- **macOS 13 or later**
- **Apple Silicon Mac** for the downloadable build
- **Antelope Launcher** installed (free from antelopeaudio.com)
- **Synergy Core device** (Orion Studio III, Discrete 4, etc.)
- **Thunderbolt connection** to device

---

## Support

Having issues? [Open an issue on GitHub](https://github.com/mks-devx/MK-OrbitControl/issues) with:
- Your **device model** (Orion Studio III, Discrete 4, etc.)
- Your **macOS version** (Settings → About → macOS)
- The **exact error message** you see
