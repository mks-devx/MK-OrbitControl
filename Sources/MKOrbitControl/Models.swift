import Foundation
import SwiftUI

enum OutputChannel: Int, CaseIterable, Identifiable {
    case monA = 0
    case hp1 = 1
    case hp2 = 2
    case monB = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .monA: return "MON A"
        case .monB: return "MON B"
        case .hp1: return "HP 1"
        case .hp2: return "HP 2"
        }
    }

    var icon: String {
        switch self {
        case .monA, .monB: return "speaker.wave.2.fill"
        case .hp1, .hp2: return "headphones"
        }
    }

    /// Display order: MON A, MON B, HP 1, HP 2
    static var displayOrder: [OutputChannel] {
        [.monA, .monB, .hp1, .hp2]
    }
}

struct ChannelState {
    var volume: Int = 0      // 0-255
    var mute: Bool = false
    var dim: Bool = false
    var mono: Bool = false
}

// MARK: - Presets

struct Preset: Codable, Identifiable {
    var id: Int
    var name: String
    var channels: [Int: PresetChannel] // OutputChannel.rawValue -> state

    struct PresetChannel: Codable {
        var volume: Int
        var mute: Bool
    }
}

class PresetManager: ObservableObject {
    @Published var presets: [Preset] = []

    private static let key = "MKPresets"

    init() { load() }

    func save(slot: Int, name: String, from state: DeviceState) {
        var channels = [Int: Preset.PresetChannel]()
        for ch in OutputChannel.displayOrder {
            let s = state.channels[ch] ?? ChannelState()
            channels[ch.rawValue] = Preset.PresetChannel(volume: s.volume, mute: s.mute)
        }
        let preset = Preset(id: slot, name: name, channels: channels)
        presets.removeAll { $0.id == slot }
        presets.append(preset)
        presets.sort { $0.id < $1.id }
        persist()
    }

    func recall(slot: Int, to commander: AntelopeCommander, state: DeviceState) {
        guard let preset = presets.first(where: { $0.id == slot }) else { return }
        // Only recall the SELECTED channel (fast — 2 commands instead of 8)
        let ch = state.selectedOutput
        guard let saved = preset.channels[ch.rawValue] else { return }
        commander.setVolume(channel: ch, value: saved.volume)
        commander.setMute(channel: ch, muted: saved.mute)
    }

    func get(slot: Int) -> Preset? {
        presets.first { $0.id == slot }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let p = try? JSONDecoder().decode([Preset].self, from: data) else { return }
        presets = p
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Peak Meters

struct PeakData {
    var levels: [Int] = Array(repeating: 96, count: 32) // 96 = silence
    var smoothL: Double = 0
    var smoothR: Double = 0
    var peakHoldL: Double = 0
    var peakHoldR: Double = 0

    func level(at index: Int) -> Double {
        guard index < levels.count else { return 0 }
        let raw = levels[index]
        if raw >= 96 { return 0 }
        return Double(96 - raw) / 96.0
    }

    mutating func updateSmooth() {
        let rawL = level(at: 0)
        let rawR = level(at: 1)
        // Fast attack, fast decay (responsive to beats)
        if rawL > smoothL { smoothL = rawL } else { smoothL = rawL * 0.8 + smoothL * 0.2 }
        if rawR > smoothR { smoothR = rawR } else { smoothR = rawR * 0.8 + smoothR * 0.2 }
        // Peak hold — jumps up, drops steadily
        if rawL > peakHoldL { peakHoldL = rawL } else { peakHoldL = max(0, peakHoldL - 0.05) }
        if rawR > peakHoldR { peakHoldR = rawR } else { peakHoldR = max(0, peakHoldR - 0.05) }
    }
}

// MARK: - Device State

class DeviceState: ObservableObject {
    @Published var channels: [OutputChannel: ChannelState] = {
        var dict = [OutputChannel: ChannelState]()
        for ch in OutputChannel.allCases {
            dict[ch] = ChannelState()
        }
        return dict
    }()
    @Published var lastDataReceived: Date = .distantPast
    @Published var peaks = PeakData()

    var connected: Bool {
        Date().timeIntervalSince(lastDataReceived) < 30.0
    }
    @Published var selectedOutput: OutputChannel = .monA
    @Published var nightMode: Bool = false
    @Published var nightModeMax: Int = 40  // raw 40 = -40 dB max
    @Published var miniMode: Bool = false

    /// Reference to state reader for manual reconnect
    weak var stateReader: AntelopeStateReader?

    func reconnect() {
        stateReader?.reconnect()
        // Reset connection state immediately for UI feedback
        lastDataReceived = .distantPast
    }

    var currentChannel: ChannelState {
        get { channels[selectedOutput] ?? ChannelState() }
    }
}
