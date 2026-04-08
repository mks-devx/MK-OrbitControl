# MK-AntelopeControl Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS menu bar app to control Antelope Orion Studio III monitor volume, mute, dim, and output selection — without the laggy Antelope Control Panel.

**Architecture:** Swift Package menu bar app. Reads device state via TCP port 2021 (JSON cyclic reports). Sends commands by spawning bridge.py via Python 3.8 (using Antelope's own RemoteDevice API). No external dependencies.

**Tech Stack:** Swift 6 / SwiftUI, Python 3.8 (bridge), TCP sockets, Antelope RemoteDevice API

---

## File Structure

```
MK-AntelopeControl/
├── Package.swift
├── Sources/
│   └── MKAntelopeControl/
│       ├── App.swift               # @main, NSStatusBar menu bar icon + popover
│       ├── MenuBarView.swift       # SwiftUI popover: volume slider, mute, output tabs
│       ├── AntelopeState.swift     # TCP client: reads cyclic JSON from port 2021
│       ├── AntelopeCommander.swift # Sends commands via bridge.py (Process)
│       └── Models.swift            # Channel enum, VolumeState, DeviceState
├── bridge.py                       # Python 3.8 command bridge (DONE)
└── antelope_modules/               # Extracted Antelope Python 3.8 modules (DONE)
```

## Prerequisites

- Python 3.8.20 installed at `~/.pyenv/versions/3.8.20/bin/python3.8`
- Antelope modules extracted at `antelope_modules/`
- bridge.py working (tested: set_volume confirmed)
- Antelope Launcher + Control Panel running
- Report format at `/Users/Shared/.AntelopeAudio/orionstudioiii/panels/report_format_2.3.1`

## Key Protocol Details

- **State reading:** TCP connect to `127.0.0.1:2021`, receive 4-byte big-endian length prefix + JSON with `type: "cyclic"`, parse `contents.volumes_and_mutes` array (7 entries)
- **Command sending:** Spawn `python3.8 bridge.py <command> <channel_id> <value>`
- **Channel mapping:** 0=MON A, 1=MON B, 2=HP1, 3=HP2, 4=Line
- **Volume range:** 0-255 (ubyte), current MON A typically ~40-50
- **Server port:** Usually 2021 but can vary (2020-2052 range). The admin port (2020) welcome message tells you the device port.

---

### Task 1: Swift Package + Menu Bar Shell

**Files:**
- Create: `Package.swift`
- Create: `Sources/MKAntelopeControl/App.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MKAntelopeControl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MKAntelopeControl", path: "Sources/MKAntelopeControl")
    ]
)
```

- [ ] **Step 2: Create App.swift with menu bar icon**

Minimal NSStatusBar app with a speaker icon. Click shows a popover with "MK-AntelopeControl" text. Uses AppDelegate pattern (not SwiftUI App lifecycle) for proper menu bar behavior.

- [ ] **Step 3: Build and run**

Run: `swift build && .build/debug/MKAntelopeControl`
Expected: Speaker icon appears in menu bar, click shows popover

- [ ] **Step 4: Commit**

---

### Task 2: Models

**Files:**
- Create: `Sources/MKAntelopeControl/Models.swift`

- [ ] **Step 1: Define data models**

```swift
enum OutputChannel: Int, CaseIterable, Identifiable {
    case monA = 0, monB = 1, hp1 = 2, hp2 = 3
    var id: Int { rawValue }
    var label: String { ... }
}

struct ChannelState {
    var volume: Int  // 0-255
    var mute: Bool
    var dim: Bool
    var mono: Bool
}

class DeviceState: ObservableObject {
    @Published var channels: [OutputChannel: ChannelState]
    @Published var connected: Bool
    @Published var selectedOutput: OutputChannel
}
```

- [ ] **Step 2: Commit**

---

### Task 3: AntelopeState — Read Device State

**Files:**
- Create: `Sources/MKAntelopeControl/AntelopeState.swift`

- [ ] **Step 1: TCP client that connects to port 2021**

Connect, read 4-byte length prefix, read JSON payload, parse `volumes_and_mutes` array. Reconnect on disconnect. Poll every ~500ms via cyclic reports (server sends them automatically).

- [ ] **Step 2: Update DeviceState from cyclic reports**

Parse the JSON `contents.volumes_and_mutes` array. Each entry has: volume (int), mute (int 0/1), dim (int 0/1), mono (int 0/1).

- [ ] **Step 3: Test** — Run app, verify DeviceState updates match Antelope Control Panel values

- [ ] **Step 4: Commit**

---

### Task 4: AntelopeCommander — Send Commands

**Files:**
- Create: `Sources/MKAntelopeControl/AntelopeCommander.swift`

- [ ] **Step 1: Process wrapper for bridge.py**

```swift
class AntelopeCommander {
    let pythonPath = "~/.pyenv/versions/3.8.20/bin/python3.8"
    let bridgePath: String  // resolved from Bundle

    func send(_ command: String, channel: Int, value: Int) async throws -> Bool
}
```

Spawns: `python3.8 bridge.py set_volume 0 44`
Parses stdout for `=> True` or `=> False`

- [ ] **Step 2: Convenience methods**

```swift
func setVolume(channel: OutputChannel, value: Int)
func setMute(channel: OutputChannel, muted: Bool)
func setDim(channel: OutputChannel, dimmed: Bool)
func setMono(channel: OutputChannel, mono: Bool)
```

- [ ] **Step 3: Test** — Call setVolume, verify in Antelope Control Panel

- [ ] **Step 4: Commit**

---

### Task 5: MenuBarView — UI

**Files:**
- Create: `Sources/MKAntelopeControl/MenuBarView.swift`

- [ ] **Step 1: Basic popover layout**

- Output selector tabs: MON A | MON B | HP1 | HP2
- Volume slider (0-255 mapped to visual range)
- Mute toggle button
- Connection status indicator (green dot / red dot)

- [ ] **Step 2: Wire to DeviceState and AntelopeCommander**

Slider onChange -> commander.setVolume()
Mute button -> commander.setMute()
DeviceState updates -> UI reflects current values

- [ ] **Step 3: Test** — Move slider, verify volume changes on hardware

- [ ] **Step 4: Commit**

---

### Task 6: Bridge Daemon Mode

**Files:**
- Modify: `bridge.py`

- [ ] **Step 1: Add `--daemon` mode**

Instead of connect-send-disconnect per command, the bridge stays connected and reads commands from stdin (JSON lines). This eliminates the 2-second connect overhead per command.

Protocol: write `{"cmd": "set_volume", "ch": 0, "val": 44}\n` to stdin, read `{"ok": true}\n` from stdout.

- [ ] **Step 2: Update AntelopeCommander to use daemon mode**

Launch bridge.py --daemon once at app start. Send commands via stdin pipe.

- [ ] **Step 3: Test** — Rapid volume changes should be instant

- [ ] **Step 4: Commit**

---

### Task 7: Polish

- [ ] Scroll wheel on menu bar icon adjusts volume
- [ ] Keyboard shortcut for mute toggle
- [ ] Launch at login (LSSharedFileList or LoginItems)
- [ ] Graceful handling when Antelope server not running
- [ ] App icon

---

## Future: Stream Deck Plugin (Phase 2)

Separate project using Elgato Stream Deck SDK. Communicates with bridge.py daemon.

## Future: Multi-Device Support

- Auto-detect device slug from `/Users/Shared/.AntelopeAudio/*/panels/report_format_*`
- Device selector in UI
- Per-device channel mapping
