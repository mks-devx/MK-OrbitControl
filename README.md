# MK-OrbitControl

> Experimental macOS menu bar monitor controller for selected Antelope Synergy Core audio interfaces.

Control volume, mute, dim, mono, and output selection directly from your macOS menu bar — without opening the Antelope Control Panel.

<p align="center">
  <img src="screenshots/main.png" alt="MK-OrbitControl" width="240">
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/mini.png" alt="Mini Mode" width="200">
</p>
<p align="center"><sub>Crimson theme · Full controller · Mini mode</sub></p>

---

## Table of Contents

- [Features](#features)
- [Compatibility](#compatibility)
- [Installation](#installation)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
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
- **Step buttons** for immediate quieter/louder changes without dragging
- **Configurable 1, 2, 3, or 6 dB step** shared by buttons, arrow keys, VoiceOver, and global hotkeys
- **DIM** — reduce volume by a fixed amount for quick conversations
- **MUTE** — instant silence with visual feedback
- **MONO** — collapse stereo to mono for mix checking

### Output Management
- **A/B monitor switching** — toggle between two monitor outputs
- **4 preset slots** — right-click to save, click to recall the selected output's saved state
- **Night mode** — configurable, persistent volume cap for late-night sessions

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
- **Font choices** — built-in macOS fonts plus compatible optional fonts already installed on the Mac
- **9 menu bar icons** — choose the icon that fits your menu bar style
- **Settings panel** — native tabbed sidebar that follows the selected light or dark theme

### Integration
- **Global hotkeys** — configurable per output, works from any app (Carbon-based via HotKey library)
- **MIDI learn** — map any MIDI CC to volume or mute (CoreMIDI)
- **Volume HUD** — on-screen overlay when adjusting volume via hotkeys
- **Auto update checker** — notifies when a downloadable GitHub Release is available

### Reliability
- **Auto-reconnect** — if the connection to the Antelope server drops after extended uptime, the bridge automatically recovers without manual restart
- **Reconnect button** — force an immediate device re-scan after cable disconnect
- **Restart Server** — one-click server restart when offline (relaunches Antelope Launcher, auto-reconnects)

---

## Compatibility

### Requirements

- **macOS 13+**
- **Apple Silicon Mac**; Intel packaging is not currently supported or validated
- **Antelope Launcher** installed and running ([download](https://www.antelopeaudio.com/downloads/))
- **A supported Synergy Core device** connected via Thunderbolt; verify the mapping table below before testing

### Tested Devices

| Device | Status | Notes |
|--------|--------|-------|
| Orion Studio III (Synergy Core) | Regression test required | Previously tested; the hardened command path still needs a controlled hardware pass |
| Discrete 4 / 8 | Community testing | Shows offline — debug data needed |
| Galaxy 32 / 64 | Unverified | Channel mapping and report format must be validated |
| Orion 32+ Gen4 | Unverified | Channel mapping and report format must be validated |
| Zen Tour Synergy Core | Unverified | Channel mapping and report format must be validated |
| Goliath | Unverified | Channel mapping and report format must be validated |

Have a Synergy Core device not listed here? [Test and report your results](../../issues) — community testing welcome.

---

## Installation

### Current availability

MK-OrbitControl is currently a source-only beta. A public DMG will be published on the [Releases page](../../releases) only after Developer ID signing, notarisation, and clean-Mac validation are complete.

For now, use the [Build from Source](#build-from-source) instructions below. Do not download application bundles or DMGs offered through issues, forks, or third-party links.

### Signed release installation

The following steps apply after a notarised DMG is published.

### Step 1: Download

Download the notarised DMG from the [Releases page](../../releases).

### Step 2: Install the App

1. Double-click the downloaded `.dmg` file to mount it
2. Drag **MK-OrbitControl.app** into your **Applications** folder
3. Eject the DMG when done (right-click → Eject in Finder)

### Step 3: Complete First-Run Setup

Open MK-OrbitControl and click **Run Setup** if the setup notice appears. It extracts the required modules from the Antelope software already installed on your Mac. No proprietary code is downloaded or included in the app.

If in-app setup cannot run after copying the app to Applications, use this Terminal fallback:

```bash
bash "/Applications/MK-OrbitControl.app/Contents/Resources/setup.sh"
```

You should see `Extracted X modules` followed by `Done!`.

> **Note:** If Terminal says the volume is not found, re-mount the DMG by double-clicking it again.

### Step 4: Control Your Outputs

Open **MK-OrbitControl** from your Applications folder. A speaker icon will appear in your menu bar (top right of the screen). Click it to open the controller.

> Ad-hoc local builds may require right-click → Open. No current public build has been presented as signed, notarised, or distribution-ready.

---

## Usage

### Basic Controls
- **Click** the menu bar icon to open the popover
- **Drag** the rotary knob or slider to adjust volume
- **Click − / +** beside the knob for repeatable stepped adjustments
- **Click** DIM / MUTE / MONO buttons to toggle
- **Click** MON A, MON B, HP 1, or HP 2 to switch outputs

### Presets
- **Click** a preset slot (A–D) to recall
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

## Troubleshooting

### "Application is not supported on this Mac"

This message can indicate an incompatible CPU architecture, an unsupported macOS version, a damaged bundle, or a signing problem. Confirm that the Mac is Apple Silicon and runs macOS 13 or later before trying the signing workarounds below.

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
┌─────────────────┐  TCP :17580  ┌─────────────┐  RemoteDevice API  ┌──────────────────────┐
│ MK-OrbitControl │ ───────────► │  bridge.py  │ ─────────────────► │ AntelopeAudioServer  │
│    (SwiftUI)    │              └─────────────┘                    │ dynamic :2020–2100   │
└─────────────────┘                                                  └──────────┬───────────┘
                                                                               │ Thunderbolt
                                                                               ▼
                                                                          ┌──────────┐
                                                                          │ Hardware │
                                                                          └──────────┘
```

## Repository Structure

```text
Config/                         App metadata and the canonical app icon
Sources/MKOrbitControl/
  Application/                  App lifecycle and window coordination
  Domain/                       Volume, channel, preset, and device state
  Infrastructure/               Antelope state and command transports
  Input/                        Global hotkey and MIDI control
  Services/                     Update checking
  UI/                           Menu, settings, floating window, HUD, themes
Tests/                          Swift and Python regression tests
docs/                           Installation and archived design history
bridge.py                       Authenticated local Python command bridge
setup.sh                        Local Antelope module extraction
build-dist.sh                   Reproducible app and DMG packaging
```

Generated builds belong in `dist-bundled/`, which is intentionally ignored and must not be committed.

### Tech Stack

| Component | Technology |
|-----------|------------|
| App | Swift 6 / SwiftUI — menu bar popover, floating window, settings |
| Bridge | Python 3.8 compatibility daemon on localhost port 17580; commands require a per-install authentication token |
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

- Restricts commands to volume (0–96), mute, dim, and mono on known output channels
- Keeps the command bridge bound to localhost and requires a per-install 64-character authentication token stored with owner-only permissions
- Starts from silence until the first valid device state is received
- No proprietary code is distributed — modules are extracted from the user's own installation

> Python 3.8.20 is currently required because the Antelope modules are Python 3.8 bytecode. Python 3.8 is end-of-life, so replacing this compatibility layer is a release-hardening priority.

---

## Build from Source

```bash
# Clone the repository
git clone https://github.com/mks-devx/MK-OrbitControl.git
cd MK-OrbitControl

# Install the project generator
brew install xcodegen

# Generate the Xcode project and build the app
xcodegen generate --spec project.yml
xcodebuild -project MKOrbitControl.xcodeproj -scheme MKOrbitControl \
  -configuration Release -derivedDataPath /tmp/MKOrbitControl-Release \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build

# Install Python 3.8 for the bridge daemon (one time)
brew install pyenv
pyenv install 3.8.20
~/.pyenv/versions/3.8.20/bin/python3.8 -m pip install zeroconf netifaces

# Run setup to extract Antelope modules
bash setup.sh

# Run the unsigned development build
open /tmp/MKOrbitControl-Release/Build/Products/Release/MK-OrbitControl.app
```

### Build a Local Audit DMG

```bash
ALLOW_UNTAGGED_BUILD=1 ALLOW_DIRTY_BUILD=1 bash build-dist.sh
# Output: ~/Desktop/MK-OrbitControl-UNRELEASED-{commit}.dmg
```

The script verifies the pinned dependency manifest, generates the Xcode project, builds an arm64 app, creates a relocatable Python 3.8 runtime, neutralises private build-machine paths, bundles third-party licences, tests the runtime, audits the artifact, signs nested code, and creates a DMG plus SHA-256 checksum.

Public packages must be built from a clean checkout at an exact annotated `vX.Y.Z` tag. Set `SIGN_IDENTITY` to a Developer ID Application identity and `NOTARY_PROFILE` to a `notarytool` keychain profile. The script refuses a Developer ID build without notarisation. Untagged or dirty builds require the explicit local-audit flags shown above and are visibly labelled `UNRELEASED`.

---

## Uninstall

```bash
# Remove the app
rm -rf /Applications/MK-OrbitControl.app

# (Optional) Remove extracted compatibility modules and bridge
rm -rf "$HOME/Library/Application Support/MK-OrbitControl"

# (Optional) Remove saved preferences after disabling Launch at Login in the app
defaults delete com.mkdevices.orbitcontrol 2>/dev/null || true
```

Disable **Launch at Login** in Settings before deleting the app. MK-OrbitControl installs no privileged helper, launch daemon, or system service; Antelope Launcher manages its own separate services.

---

## Contributing

Contributions welcome:

- **Device testing** — try it on your Synergy Core device and [open an issue](../../issues) with your results
- **Channel mapping** — help identify correct output indices for untested devices
- **Bug reports** — include your device model, macOS version, and any console output
- **Interface work** — follow the repository's [design direction](docs/DESIGN.md)

---

## Changelog

### v1.4 — Server Restart
- **Restart Server button** — when offline, an orange indicator appears in the header to relaunch the Antelope server with one click (no admin password needed)
- **Restart in Settings** — also available under Settings → General → Restart Antelope Server
- Opens Antelope Launcher to re-initialize the server, then auto-reconnects

### v1.3 — Auto-reconnect
- Bridge daemon now auto-reconnects after connection drops during extended uptime
- No more manual bridge restarts after sleep/wake or long sessions

### v1.2 — Interface and Local Packaging Update
- Fixed "application not supported" error on macOS 15.7+
- Added ad-hoc signing for local development packages; this is not Developer ID distribution signing
- Added local DMG packaging
- Added `docs/INSTALL.md` with step-by-step troubleshooting
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

This software uses the same command protocol as the official Control Panel and limits its bridge to monitor-control commands. Use conservative levels when testing an unverified device mapping.

---

## License

[MIT](LICENSE)

Distribution packages also include [third-party notices](THIRD_PARTY_NOTICES.md) and the complete applicable licence texts.
