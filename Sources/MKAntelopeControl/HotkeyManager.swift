import Foundation
import AppKit
import HotKey
import Carbon

// MARK: - Data Types

struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt  // NSEvent.ModifierFlags rawValue
    var action: HotkeyAction
}

enum HotkeyAction: String, Codable, CaseIterable {
    case volumeUpMonA, volumeDownMonA, muteMonA
    case volumeUpMonB, volumeDownMonB, muteMonB
    case volumeUpHP1, volumeDownHP1, muteHP1
    case volumeUpHP2, volumeDownHP2, muteHP2

    var channel: OutputChannel {
        switch self {
        case .volumeUpMonA, .volumeDownMonA, .muteMonA: return .monA
        case .volumeUpMonB, .volumeDownMonB, .muteMonB: return .monB
        case .volumeUpHP1,  .volumeDownHP1,  .muteHP1:  return .hp1
        case .volumeUpHP2,  .volumeDownHP2,  .muteHP2:  return .hp2
        }
    }

    var isMute: Bool {
        switch self {
        case .muteMonA, .muteMonB, .muteHP1, .muteHP2: return true
        default: return false
        }
    }

    var isVolumeUp: Bool {
        switch self {
        case .volumeUpMonA, .volumeUpMonB, .volumeUpHP1, .volumeUpHP2: return true
        default: return false
        }
    }
}

// MARK: - HotkeyManager

final class HotkeyManager {

    private let commander: AntelopeCommander
    private let deviceState: DeviceState
    private var registeredHotKeys: [HotkeyAction: HotKey] = [:]

    private static let defaultsKey = "MKHotkeyBindings"

    init(commander: AntelopeCommander, deviceState: DeviceState) {
        self.commander = commander
        self.deviceState = deviceState
    }

    // MARK: - Persistence

    func save(_ binding: HotkeyBinding) {
        var all = loadAll()
        all.removeAll { $0.action == binding.action }
        all.append(binding)
        persist(all)
        registerAll()
    }

    func remove(action: HotkeyAction) {
        var all = loadAll()
        all.removeAll { $0.action == action }
        persist(all)
        registerAll()
    }

    func getBinding(for action: HotkeyAction) -> HotkeyBinding? {
        loadAll().first { $0.action == action }
    }

    private func loadAll() -> [HotkeyBinding] {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let bindings = try? JSONDecoder().decode([HotkeyBinding].self, from: data) else {
            return []
        }
        return bindings
    }

    private func persist(_ bindings: [HotkeyBinding]) {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: - Registration using HotKey library (Carbon-based, reliable)

    func registerAll() {
        unregisterAll()

        for binding in loadAll() {
            guard let key = Key(carbonKeyCode: binding.keyCode) else { continue }
            let mods = carbonToNSModifiers(binding.modifiers)

            let hotkey = HotKey(key: key, modifiers: mods)
            hotkey.keyDownHandler = { [weak self] in
                self?.executeAction(binding.action)
            }
            registeredHotKeys[binding.action] = hotkey
        }
    }

    func unregisterAll() {
        registeredHotKeys.removeAll()
    }

    // No accessibility needed for Carbon hotkeys!
    func hasAccessibilityPermission() -> Bool { true }

    // MARK: - Convert modifiers

    private func carbonToNSModifiers(_ raw: UInt) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if raw & UInt(NSEvent.ModifierFlags.command.rawValue) != 0 { flags.insert(.command) }
        if raw & UInt(NSEvent.ModifierFlags.shift.rawValue) != 0 { flags.insert(.shift) }
        if raw & UInt(NSEvent.ModifierFlags.option.rawValue) != 0 { flags.insert(.option) }
        if raw & UInt(NSEvent.ModifierFlags.control.rawValue) != 0 { flags.insert(.control) }
        return flags
    }

    // MARK: - Action Execution

    private func executeAction(_ action: HotkeyAction) {
        let channel = action.channel
        if action.isMute {
            let current = deviceState.channels[channel]?.mute ?? false
            let newMute = !current
            commander.setMute(channel: channel, muted: newMute)
            let vol = deviceState.channels[channel]?.volume ?? 0
            VolumeHUD.shared.show(volume: vol, muted: newMute, channel: channel.label)
        } else if action.isVolumeUp {
            let current = deviceState.channels[channel]?.volume ?? 0
            let newVol = max(0, current - 1)
            commander.setVolume(channel: channel, value: newVol)
            DispatchQueue.main.async {
                self.deviceState.channels[channel]?.volume = newVol
            }
            let muted = deviceState.channels[channel]?.mute ?? false
            VolumeHUD.shared.show(volume: newVol, muted: muted, channel: channel.label)
        } else {
            let current = deviceState.channels[channel]?.volume ?? 0
            let newVol = min(96, current + 1)
            commander.setVolume(channel: channel, value: newVol)
            DispatchQueue.main.async {
                self.deviceState.channels[channel]?.volume = newVol
            }
            let muted = deviceState.channels[channel]?.mute ?? false
            VolumeHUD.shared.show(volume: newVol, muted: muted, channel: channel.label)
        }
    }
}
