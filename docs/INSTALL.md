# Installation Guide — MK-OrbitControl

## Official release

The Apple Silicon build is distributed only through [GitHub Releases](https://github.com/mks-devx/MK-OrbitControl/releases). Official DMGs are Developer ID signed, Apple notarised, and accompanied by a SHA-256 checksum. Do not install app bundles or DMGs received through issues, forks, email, or third-party links.

1. Download the latest DMG and matching `.sha256` file from GitHub Releases.
2. Verify the download in Terminal:

   ```bash
   shasum -a 256 MK-OrbitControl-vX.Y.Z.dmg
   ```

3. Open the DMG and drag **MK-OrbitControl.app** to **Applications**.
4. Launch the app. A speaker icon should appear in the menu bar.

No setup utility, Python runtime, administrator access, or module extraction is required. Antelope Launcher remains responsible for installing and running Antelope's own local device service.

## Requirements

- macOS 13 or later
- Apple Silicon Mac for the downloadable build
- Antelope Launcher installed and opened at least once
- A connected Antelope Synergy Core interface

The current mapping has been hardware-tested on Orion Studio III. Other Synergy Core models may expose different output mappings; test at a conservative monitor level.

## Troubleshooting

### The app shows Offline

1. Confirm the interface is powered on, connected, and visible in the official Antelope Control Panel.
2. Confirm Antelope Launcher is running.
3. Click **Reconnect** in MK-OrbitControl.
4. If it remains offline, use **Restart Server** once and allow several seconds for reconnection.
5. If the device is still unavailable, report the model, macOS version, connection type, and exact message. Do not post serial numbers, usernames, local file paths, account details, or complete logs.

### The menu-bar icon does not appear

Quit and relaunch the app. If **Launch at Login** is enabled, confirm it remains allowed in System Settings → General → Login Items. MK-OrbitControl is menu-bar-only and does not create a Dock icon.

### macOS rejects the app

The official release should pass Gatekeeper. Delete the rejected copy, download it again from the official Releases page, and compare its SHA-256 checksum. Do not disable Gatekeeper. Report a persistent validation error through GitHub Issues.

### The device reconnects after unplugging Thunderbolt

Wait for the interface and Antelope service to finish starting, then click **Reconnect**. No app reinstall or setup step is required.

## Build from source

```bash
git clone https://github.com/mks-devx/MK-OrbitControl.git
cd MK-OrbitControl
brew install xcodegen
xcodegen generate --spec project.yml
swift test
```

Create an ad-hoc local audit package with:

```bash
ALLOW_UNTAGGED_BUILD=1 ALLOW_DIRTY_BUILD=1 UNRELEASED_VERSION=1.6.0 bash build-dist.sh
```

Python 3 is used only by repository release-validation tests and is not included in, or required by, the app. Public packages require a clean checkout at an annotated `vX.Y.Z` tag, a Developer ID Application identity, and an Apple notarisation profile.

## Installed data

| Item | Location | Purpose |
|---|---|---|
| MK-OrbitControl.app | `/Applications/` | Menu-bar application |
| Preferences | `~/Library/Preferences/com.mkdevices.orbitcontrol.plist` | App settings and mappings |
| Login Item | macOS background-items database | Present only when Launch at Login is enabled |

MK-OrbitControl installs no privileged helper, launch daemon, system service, Python environment, or extracted compatibility modules.

## Uninstall

1. Disable **Launch at Login** in MK-OrbitControl Settings.
2. Move **MK-OrbitControl.app** from Applications to the Bin.
3. Optionally remove its saved preferences.

Antelope Launcher's software and services are separate and are not removed.

## Support

[Open an issue](https://github.com/mks-devx/MK-OrbitControl/issues) with the device model, macOS version, connection type, and exact error message. Keep all personal and device-identifying information out of public reports.
