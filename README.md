# MK-OrbitControl

> macOS menu bar monitor controller for Antelope Synergy Core audio interfaces.

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

## Table of Contents

- [Features](#features)
- [Compatibility](#compatibility)
- [Installation](#installation)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)
- [Build from Source](#build-from-source)
- [Uninstall](#uninstall)
- [Contributing](#contributing)
- [Changelog](#changelog)
- [License](#license)

---

## Features

### Volume Control
- **Rotary knob** with precise dB display (-∞ to 0 dB)
- **Slider** for quick adjustments
- **DIM** — reduce volume by a fixed amount for quick conversations
- **MUTE** — instant silence with visual feedback
- **MONO** — collapse stereo to mono for mix checking

### Output Management
- **A/B monitor switching** — toggle between two monitor outputs
- **4 preset slots** — right-click to save, click to recall complete output states
- **Night mode** — configurable volume cap for late-night sessions

### Metering
- **Peak meters** with peak hold indicators (L/R channels)
- Color-coded levels: green → yellow → red
- ~3 fps update rate (limited by Antelope server's cyclic report interval)

### Display Modes
| Mode | Description |
|------|-------------|
| **Menu bar popover** | Default — full controls in a popover from the menu bar icon |
| **Mini mode** | Compact view with slider, mute, and output selector |
| **Floating window** | Always-on-top, draggable — position anywhere on screen |

### Customization
- **12 themes** — Crimson, Midnight, Cyber, Diablo, Nova, Aether, Flux, and more
- **8 fonts** — System, Hack, Fira Code, JetBrains Mono, Dot Matrix, and more
- **9 menu bar icons** — choose the icon that fits your menu bar style
- **Settings panel** — tabbed sidebar with dark theme

### Integration
- **Global hotkeys** — configurable per output, works from any app (Carbon-based via HotKey library)
- **MIDI learn** — map any MIDI CC to volume or mute (CoreMIDI)
- **Volume HUD** — on-screen overlay when adjusting volume via hotkeys
- **Auto update checker** — notifies when new versions are available on GitHub

### Reliability
- **Auto-reconnect** — if the connection to the Antelope server drops after extended uptime, the bridge automatically recovers without manual restart
- **Reconnect button** — force an immediate device re-scan after cable disconnect
- **Restart Server** — one-click server restart when offline (relaunches Antelope Launcher, auto-reconnects)

---

## Compatibility

### Requirements

- **macOS 13+** (Ventura, Sonoma, Sequoia)
- **Antelope Launcher** installed and running ([download](https://www.antelopeaudio.com/downloads/))
- **Synergy Core device** connected via Thunderbolt

### Tested Devices

| Device | Status | Notes |
|--------|--------|-------|
| Orion Studio III (Synergy Core) | Tested | Full functionality verified |
| Discrete 4 / 8 | Community testing | Shows offline — debug data needed |
| Galaxy 32 / 64 | Untested | Should work — [report results](../../issues) |
| Orion 32+ Gen4 | Untested | Should work — [report results](../../issues) |
| Zen Tour Synergy Core | Untested | Should work — [report results](../../issues) |
| Goliath | Untested | Should work — [report results](../../issues) |

Have a Synergy Core device not listed here? [Test and report your results](../../issues) — community testing welcome.

---

## Installation

### Step 1: Download

Download the latest DMG from the [Releases page](../../releases/latest).

### Step 2: Install the App

1. Double-click the downloaded `.dmg` file to mount it
2. Drag **MK-OrbitControl.app** into your **Applications** folder
3. Eject the DMG when done (right-click → Eject in Finder)

### Step 3: Run the Setup Script

The setup script extracts necessary modules from your local Antelope installation. No proprietary code is downloaded — everything comes from software already on your Mac.

Open **Terminal** (Applications → Utilities → Terminal) and run:

```bash
bash "/Volumes/MK-OrbitControl v1.3/setup.sh"
```

You should see `Extracted X modules` followed by `Done!`.

> **Note:** If Terminal says the volume is not found, re-mount the DMG by double-clicking it again.

### Step 4: Launch

Open **MK-OrbitControl** from your Applications folder. A speaker icon will appear in your menu bar (top right of the screen). Click it to open the controller.

> **First launch on macOS 13+:** You may need to right-click the app → Open → Open to bypass Gatekeeper. See [Troubleshooting](#troubleshooting) for details.

---

## Usage

### Basic Controls
- **Click** the menu bar icon to open the popover
- **Drag** the rotary knob or slider to adjust volume
- **Click** DIM / MUTE / MONO buttons to toggle
- **Click** A or B to switch monitor outputs

### Presets
- **Click** a preset slot (1–4) to recall
- **Right-click** a preset slot to save the current state

### Hotkeys
1. Open **Settings** (gear icon)
2. Go to the **Hotkeys** tab
3. Click the record button next to an action
4. Press your desired key combination
5. Hotkeys work globally from any application

### MIDI Learn
1. Open **Settings** → **MIDI** tab
2. Click **Learn** next to the control you want to map
3. Move a knob/fader on your MIDI controller
4. The CC is captured and saved automatically

### Display Modes
- **Mini mode** — click the minimize icon in the popover header
- **Floating window** — click the window icon in the popover header; drag to position anywhere
- **Return to popover** — close the floating window or click the menu bar icon

---

## Troubleshooting

### "Application is not supported on this Mac"

macOS blocks unsigned or improperly signed applications. Three fixes, in order of preference:

**Fix 1 — Right-click to open (recommended):**
1. Open Finder → Applications
2. Right-click **MK-OrbitControl.app**
3. Select **"Open"** from the context menu
4. Click **"Open"** in the dialog
5. After this, the app opens normally with a double-click

**Fix 2 — Remove quarantine attribute:**
```bash
xattr -d com.apple.quarantine /Applications/MK-OrbitControl.app
```

**Fix 3 — Allow in System Settings:**
1. Go to **System Settings → Privacy & Security**
2. Scroll down — you'll see a message about MK-OrbitControl being blocked
3. Click **"Open Anyway"**

### App Shows "Offline"

The app can't find your Antelope device. Check in order:

1. **Antelope Launcher running?** — Look for the Antelope icon in your menu bar. If missing, open it from Applications. Enable auto-start in System Settings → General → Login Items.

2. **Device connected and powered on?** — Ensure the Thunderbolt cable is firmly plugged in. The device should show as connected in the Antelope Control Panel.

3. **Click the reconnect button** — the circular arrow icon in the app header forces an immediate device re-scan.

4. **Restart the server** — when offline, an orange warning icon appears next to the reconnect button. Click it to relaunch Antelope Launcher and re-initialize the server automatically. Also available in Settings → General.

### Setup Script: "Antelope software not found"

The setup script needs Antelope Launcher installed to extract modules.

1. Download and install [Antelope Launcher](https://www.antelopeaudio.com/downloads/)
2. Open it at least once (this installs the AntelopeAudioServer daemon)
3. Run the setup script again

### Setup Script: "already extracted"

Normal — the modules are already set up. Just launch the app.

### No Icon in Menu Bar

- The app runs as a menu bar app (no Dock icon). Look for the speaker icon in the top-right area of your screen.
- If no icon appears after 5 seconds, quit and relaunch.
- On macOS 15: check System Settings → Control Center → Menu Bar Only to ensure it's not hidden behind the notch.

### Peak Meters Not Moving

Peak meters update at ~3 fps — this is limited by the Antelope server's cyclic report rate (~300ms). This is normal and expected.

---

## Architecture

MK-OrbitControl communicates with the Antelope Audio server running locally on your Mac via TCP. The protocol was reverse-engineered for interoperability under EU Directive 2009/24/EC.

```
┌─────────────────┐    TCP/JSON     ┌──────────────────────┐  Thunderbolt  ┌──────────┐
│  MK-OrbitControl │ ◄────────────► │  AntelopeAudioServer  │ ◄──────────► │ Hardware  │
│    (SwiftUI)     │   :2020-2025   │   (Antelope daemon)   │              │          │
└────────┬────────┘                 └──────────────────────┘              └──────────┘
         │ TCP :17580
         ▼
┌─────────────────┐
│    bridge.py     │  Python 3.8 — uses Antelope's own RemoteDevice API
└─────────────────┘
```

### Tech Stack

| Component | Technology |
|-----------|------------|
| App | Swift 6 / SwiftUI — menu bar popover, floating window, settings |
| Bridge | Python 3.8 — TCP daemon on port 17580, translates JSON commands |
| Hotkeys | HotKey (Swift package) — Carbon-based global keyboard shortcuts |
| MIDI | CoreMIDI — native macOS MIDI framework |
| Protocol | TCP with 4-byte big-endian length prefix + JSON payload |

### Command Protocol

| Command | Description | Parameters |
|---------|-------------|------------|
| `set_volume` | Set output volume | channel (0–6), value (0–96) |
| `set_mute` | Toggle mute | channel, 0/1 |
| `set_dim` | Toggle dim | channel, 0/1 |
| `set_mono` | Toggle mono | channel, 0/1 |

Volume mapping: 0 = 0 dB (loudest), 95 = -95 dB, 96 = -∞ (auto-mutes).

### Channel Mapping (Orion Studio III)

| Index | Output |
|-------|--------|
| 0 | MON A |
| 1 | HP 1 |
| 2 | HP 2 |
| 5 | MON B |
| 3, 4, 6 | Unknown / unmapped |

### Safety

- Uses Antelope's own RemoteDevice API — **cannot brick or damage hardware**
- Only sends volume, mute, dim, and mono commands
- The Antelope server validates all commands before forwarding to hardware
- No proprietary code is distributed — modules are extracted from the user's own installation

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
.build/release/MKAntelopeControl
```

### Build DMG for Distribution

```bash
bash build-dist.sh
# Output: ~/Desktop/MK-OrbitControl-v{version}.dmg
```

The build script automatically detects the version from the latest git tag, builds a universal binary (arm64 + x86_64), code signs the app, bundles Python 3.8, and creates a DMG.

---

## Uninstall

```bash
# Remove the app
rm -rf /Applications/MK-OrbitControl.app

# (Optional) Remove extracted modules
rm -rf ~/Developer/MK-AntelopeControl
```

No other files are created. No launch agents, no system modifications.

---

## Contributing

Contributions welcome:

- **Device testing** — try it on your Synergy Core device and [open an issue](../../issues) with your results
- **Channel mapping** — help identify correct output indices for untested devices
- **Bug reports** — include your device model, macOS version, and any console output

---

## Changelog

### v1.4 — Server Restart
- **Restart Server button** — when offline, an orange indicator appears in the header to relaunch the Antelope server with one click (no admin password needed)
- **Restart in Settings** — also available under Settings → General → Restart Antelope Server
- Opens Antelope Launcher to re-initialize the server, then auto-reconnects

### v1.3 — Auto-reconnect
- Bridge daemon now auto-reconnects after connection drops during extended uptime
- No more manual bridge restarts after sleep/wake or long sessions

### v1.2 — Code Signing Fix
- Fixed "application not supported" error on macOS 15.7+
- App now properly code signed (ad-hoc)
- DMG packaging for better install experience
- Added INSTALL.md with step-by-step troubleshooting

### v1.2 — Major Update
- Mini mode, floating window, MIDI learn
- Peak hold meters, 12 themes, 8 fonts, 9 menu bar icons
- Global hotkeys, volume HUD, night mode
- Settings panel with tabbed sidebar
- Auto update checker, multi-device detection

### v1.1
- Mini mode, check for updates

### v1.0
- Initial release — volume, mute, dim, mono, A/B switching, presets

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
