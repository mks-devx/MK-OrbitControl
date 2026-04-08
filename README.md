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
- Rotary volume knob with dB display (-∞ to 0 dB)
- DIM / MUTE / MONO buttons
- A/B monitor switching
- 4 preset slots (right-click to save, click to recall)
- Night mode — configurable volume cap for late sessions

**Monitor**
- Peak meters with peak hold (L/R, green → yellow → red)
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
| Orion Studio III (Synergy Core) | ✅ Tested |
| Discrete 4 / 8 | ⚠️ Untested |
| Galaxy 32 / 64 | ⚠️ Untested |
| Orion 32+ Gen4 | ⚠️ Untested |
| Zen Tour Synergy Core | ⚠️ Untested |
| Goliath | ⚠️ Untested |

Have a Synergy Core device? [Test and report your results](../../issues) — community testing welcome!

---

## Install

### Download (recommended)
1. Grab the latest DMG from [**Releases**](../../releases/latest)
2. Drag **MK-OrbitControl.app** to Applications
3. Open Terminal: `bash /Volumes/MK-OrbitControl/setup.sh`
4. If macOS blocks it: **Right-click → Open → Open**

### Build from source
```bash
git clone https://github.com/mks-devx/MK-OrbitControl.git
cd MK-OrbitControl
swift build

# Python 3.8 bridge setup (one time):
brew install pyenv && pyenv install 3.8.20
~/.pyenv/versions/3.8.20/bin/python3.8 -m pip install zeroconf netifaces
bash dist-bundled/setup.sh

.build/debug/MKOrbitControl
```

### Requirements
- macOS 13+
- Antelope Launcher running
- Antelope Synergy Core device

---

## How It Works

MK-OrbitControl talks to the Antelope Audio server on your Mac via TCP (localhost). The protocol was reverse-engineered for interoperability under EU Directive 2009/24/EC.

```
┌────────────────┐    TCP/JSON     ┌─────────────────────┐   Thunderbolt   ┌──────────┐
│ MK-OrbitControl │ ◄────────────► │ AntelopeAudioServer  │ ◄────────────► │ Hardware  │
│   (SwiftUI)     │   :2020-2025   │  (Antelope daemon)   │                │          │
└───────┬────────┘                 └─────────────────────┘                └──────────┘
        │ TCP :17580
        ▼
┌────────────────┐
│   bridge.py     │  Python 3.8 — uses Antelope's own RemoteDevice API
└────────────────┘
```

No proprietary code is distributed. The setup script extracts modules from **your own** Antelope installation.

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
  If this saved you a few clicks, consider buying me a coffee ☕
  <br>
  <a href="https://buymeacoffee.com/mk_tools">buymeacoffee.com/mk_tools</a>
</p>
