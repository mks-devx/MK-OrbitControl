# MK-OrbitControl

> Menu bar monitor controller for Antelope Synergy Core audio interfaces.

Control volume, mute, dim, mono, and output selection directly from your macOS menu bar — without opening the Antelope Control Panel.

<p align="center">
  <img src="screenshots/main.png" alt="MK-OrbitControl" width="240">
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/floating.png" alt="Floating Window" width="240">
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/mini.png" alt="Mini Mode" width="200">
</p>
<p align="center"><sub>Diablo theme · Floating window · Mini mode</sub></p>

---

## Features

**Control**
- Rotary volume knob with dB display (-inf to 0 dB)
- DIM / MUTE / MONO buttons
- A/B monitor switching
- 4 preset slots (right-click to save, click to recall)
- Night mode — configurable volume cap for late sessions
- Reconnect button — instantly re-scan device after cable disconnect

**Monitor**
- Peak meters with peak hold (L/R, green -> yellow -> red)
- Volume HUD overlay when using hotkeys

**Modes**
- Menu bar popover (default)
- Mini mode — compact slider + mute + output selector
- Floating window — always on top, drag anywhere

**Customization**
- 12 themes (Crimson, Midnight, Cyber, Diablo, Nova, Aether, Flux, and more)
- 8 fonts (System, Hack, Fira Code, JetBrains Mono, Dot Matrix, and more)
- 9 menu bar icons

**Integration**
- Global hotkeys — configurable per output, works from any app
- MIDI learn — map any MIDI CC to volume or mute
- Auto update checker

---

## Compatibility

| Device | Status |
|--------|--------|
| Orion Studio III (Synergy Core) | Tested |
| Discrete 4 / 8 | Untested |
| Galaxy 32 / 64 | Untested |
| Orion 32+ Gen4 | Untested |
| Zen Tour Synergy Core | Untested |
| Goliath | Untested |

Have a Synergy Core device? [Test and report your results](../../issues) — community testing welcome!

---

## Install

### Requirements

Before installing, make sure you have:

- **macOS 13 or later** (Ventura, Sonoma, or Sequoia)
- **Antelope Launcher** installed and running (free download from [antelopeaudio.com/downloads](https://www.antelopeaudio.com/downloads/))
- **Synergy Core device** connected via Thunderbolt (Orion Studio III, Discrete 4, etc.)

### Step 1: Download

Download the latest DMG from the [Releases page](../../releases/latest).

### Step 2: Install the app

1. Double-click the downloaded `.dmg` file to mount it
2. Drag **MK-OrbitControl.app** into your **Applications** folder
3. Eject the DMG when done (right-click -> Eject in Finder)

### Step 3: Run the setup script

The setup script extracts necessary modules from your Antelope installation. Open **Terminal** (Applications -> Utilities -> Terminal) and run:

```bash
bash /Volumes/MK-OrbitControl\ v1.2/setup.sh
```

You should see `Extracted X modules` followed by `Done!`.

> **Note:** If Terminal says the volume is not found, re-mount the DMG by double-clicking it again.

### Step 4: Launch

Open **MK-OrbitControl** from your Applications folder. A speaker icon will appear in your menu bar (top right of the screen). Click it to open the controller.

---

## Troubleshooting

### "Application is not supported on this Mac"

This happens when macOS blocks an unsigned or improperly signed application.

**Fix 1 — Right-click to open (recommended):**
1. Open Finder -> Applications
2. Right-click **MK-OrbitControl.app**
3. Select **"Open"** from the context menu
4. Click **"Open"** in the dialog that appears
5. The app will launch. From now on, you can open it normally by double-clicking.

**Fix 2 — Remove quarantine attribute:**
```bash
xattr -d com.apple.quarantine /Applications/MK-OrbitControl.app
```
Then double-click to open normally.

**Fix 3 — Allow in System Settings:**
1. Go to **System Settings -> Privacy & Security**
2. Scroll down — you should see a message about MK-OrbitControl being blocked
3. Click **"Open Anyway"**

### "App can't be opened because it's from an unidentified developer"

Same solutions as above — use right-click -> Open, or the `xattr` command.

### App launches but shows "Offline"

The app can't find your Antelope device. Check:

1. **Is Antelope Launcher running?**
   - Look for the Antelope icon in your menu bar
   - If not there, open it from Applications
   - Check System Settings -> General -> Login Items to enable auto-start

2. **Is your device connected and powered on?**
   - Make sure the Thunderbolt cable is firmly plugged in
   - The device should show as connected in Antelope Control Panel

3. **Try restarting the Antelope server:**
   ```bash
   sudo killall AntelopeAudioServer
   ```
   Wait 5 seconds, then click the reconnect button in the app.

4. **Click the reconnect button (circular arrow icon)**
   - In the app header, click the refresh icon next to the connection status
   - This forces an immediate re-scan for your device

### Setup script says "ERROR: Antelope software not found"

The setup script needs Antelope Launcher installed to extract the required modules.

1. Download and install [Antelope Launcher](https://www.antelopeaudio.com/downloads/)
2. Open it at least once (this installs the AntelopeAudioServer daemon)
3. Run the setup script again

### Setup script says "already extracted"

This is normal — the modules are already set up. Just launch the app from Applications.

### Device disconnects when unplugging Thunderbolt cable

This is expected. When you reconnect the cable:
1. Wait a few seconds for the device to be detected
2. Click the **reconnect button** (circular arrow) in the app header
3. The app will immediately re-scan and reconnect

### No icon in menu bar after launching

- The app runs as a menu bar app (no Dock icon). Look for the speaker icon in the top-right area of your screen.
- If no icon appears after 5 seconds, try quitting and relaunching.
- On macOS 15: check System Settings -> Control Center -> Menu Bar Only to make sure it's not hidden.

### Peak meters not moving

Peak meters update at ~3 fps (limited by the Antelope server's cyclic report rate of ~300ms). This is normal — they won't be as smooth as the official Control Panel.

---

## Build from Source

```bash
# Clone the repository
git clone https://github.com/mks-devx/MK-OrbitControl.git
cd MK-OrbitControl

# Build the Swift app
swift build -c release

# Install Python 3.8 for the bridge daemon (one time)
brew install pyenv
pyenv install 3.8.20
~/.pyenv/versions/3.8.20/bin/python3.8 -m pip install zeroconf netifaces

# Run setup to extract Antelope modules
bash dist-bundled/setup.sh

# Run the app
.build/release/MKOrbitControl
```

### Build DMG for distribution

```bash
bash build-dist.sh
# Output: ~/Desktop/MK-OrbitControl-v1.2.dmg
```

---

## How It Works

MK-OrbitControl talks to the Antelope Audio server on your Mac via TCP (localhost). The protocol was reverse-engineered for interoperability under EU Directive 2009/24/EC.

```
+----------------+    TCP/JSON     +---------------------+   Thunderbolt   +----------+
| MK-OrbitControl | <------------> | AntelopeAudioServer  | <------------> | Hardware  |
|   (SwiftUI)     |   :2020-2025   |  (Antelope daemon)   |                |          |
+-------+--------+                 +---------------------+                +----------+
        | TCP :17580
        v
+----------------+
|   bridge.py     |  Python 3.8 — uses Antelope's own RemoteDevice API
+----------------+
```

No proprietary code is distributed. The setup script extracts modules from **your own** Antelope installation.

---

## Uninstall

```bash
# Remove the app
rm -rf /Applications/MK-OrbitControl.app

# (Optional) Remove extracted modules
rm -rf ~/Developer/MK-AntelopeControl
```

---

## Contributing

Contributions welcome:
- **Device testing** — try it on your Synergy Core device and [open an issue](../../issues)
- **Channel mapping** — help identify correct output indices for untested devices
- **Bug reports** — include your device model and macOS version

---

## Disclaimer

Not affiliated with, endorsed by, or associated with Antelope Audio. All trademarks belong to their respective owners.

This software uses the same command protocol as the official Control Panel. It cannot modify firmware or cause hardware damage.

---

## License

[MIT](LICENSE)

---

<p align="center">
  If this saved you a few clicks, consider buying me a coffee
  <br>
  <a href="https://buymeacoffee.com/mk_tools">buymeacoffee.com/mk_tools</a>
</p>
