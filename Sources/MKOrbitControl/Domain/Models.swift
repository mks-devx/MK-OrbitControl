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
        case .monA: return "hifispeaker.fill"
        case .monB: return "hifispeaker.2.fill"
        case .hp1: return "headphones"
        case .hp2: return "earbuds"
        }
    }

    /// Display order: MON A, MON B, HP 1, HP 2
    static var displayOrder: [OutputChannel] {
        [.monA, .monB, .hp1, .hp2]
    }
}

struct ChannelState: Equatable {
    var volume: Int = 96     // 0 dB at 0; silence at 96
    var mute: Bool = false
    var dim: Bool = false
    var mono: Bool = false
}

// MARK: - Control Runtime Status

enum ControlAvailability: Equatable {
    case starting
    case ready
    case serverUnavailable
    case commandFailed

    var isBlocking: Bool {
        switch self {
        case .serverUnavailable, .commandFailed:
            return true
        case .starting, .ready:
            return false
        }
    }

    var title: String {
        switch self {
        case .starting: return "Connecting to device"
        case .ready: return "Device control ready"
        case .serverUnavailable: return "Device service is unavailable"
        case .commandFailed: return "The last command failed"
        }
    }

    var recovery: String {
        switch self {
        case .serverUnavailable:
            return "Open Antelope Launcher, then use Reconnect."
        case .commandFailed:
            return "The device did not confirm the change. Check the connection before increasing volume."
        case .starting, .ready:
            return ""
        }
    }
}

// MARK: - Volume Scale

enum VolumeScale {
    static let minimumRaw = 0
    static let maximumRaw = 96
    static let allowedSteps = [1, 2, 3, 6]
    static let allowedNightModeCaps = [20, 30, 40, 50, 60]

    static func clamp(raw: Int) -> Int {
        min(maximumRaw, max(minimumRaw, raw))
    }

    static func rawToSlider(_ raw: Int) -> Double {
        Double(maximumRaw - clamp(raw: raw))
    }

    static func sliderToRaw(_ slider: Double) -> Int {
        clamp(raw: maximumRaw - Int(slider.rounded()))
    }

    static func rawToDisplay(_ raw: Int) -> String {
        let clamped = clamp(raw: raw)
        if clamped == maximumRaw { return "-∞" }
        if clamped == minimumRaw { return "0" }
        return "-\(clamped)"
    }

    static func midiToRaw(_ value: Int) -> Int {
        let clamped = min(127, max(0, value))
        return clamp(raw: maximumRaw - Int((Double(clamped) / 127.0 * Double(maximumRaw)).rounded()))
    }

    /// Missing device state must fail quiet. Raw 96 is silence; raw 0 is 0 dB.
    static func adjustedRaw(_ raw: Int?, by delta: Int) -> Int {
        clamp(raw: (raw ?? maximumRaw) + delta)
    }
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
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

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

    func clear(slot: Int) {
        presets.removeAll { $0.id == slot }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let p = try? JSONDecoder().decode([Preset].self, from: data) else { return }
        presets = p
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Peak Meters

struct PeakData: Equatable {
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
    private(set) var lastDataReceived: Date = .distantPast
    @Published var peaks = PeakData()
    @Published private(set) var connected: Bool = false
    @Published private(set) var controlAvailability: ControlAvailability = .starting
    @Published var selectedOutput: OutputChannel {
        didSet { defaults.set(selectedOutput.rawValue, forKey: Self.selectedOutputKey) }
    }
    @Published var nightMode: Bool = false
    @Published var nightModeMax: Int {
        didSet {
            let validated = Self.validatedNightModeCap(nightModeMax)
            if validated != nightModeMax {
                nightModeMax = validated
            }
            defaults.set(validated, forKey: Self.nightModeMaxKey)
        }
    }
    @Published var volumeStep: Int {
        didSet {
            let validated = Self.validatedVolumeStep(volumeStep)
            if validated != volumeStep {
                volumeStep = validated
            }
            defaults.set(validated, forKey: Self.volumeStepKey)
        }
    }
    @Published var miniMode: Bool {
        didSet { defaults.set(miniMode, forKey: Self.miniModeKey) }
    }

    private static let selectedOutputKey = "MKSelectedOutput"
    private static let nightModeMaxKey = "MKNightModeMaximum"
    private static let volumeStepKey = "MKVolumeStep"
    private static let miniModeKey = "MKMiniMode"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let savedOutput = defaults.object(forKey: Self.selectedOutputKey) as? Int,
           let output = OutputChannel(rawValue: savedOutput) {
            selectedOutput = output
        } else {
            selectedOutput = .monA
        }

        nightModeMax = Self.validatedNightModeCap(
            defaults.object(forKey: Self.nightModeMaxKey) as? Int ?? 40
        )
        volumeStep = Self.validatedVolumeStep(
            defaults.object(forKey: Self.volumeStepKey) as? Int ?? 3
        )
        miniMode = defaults.object(forKey: Self.miniModeKey) as? Bool ?? false
    }

    private static func validatedNightModeCap(_ value: Int) -> Int {
        VolumeScale.allowedNightModeCaps.contains(value) ? value : 40
    }

    private static func validatedVolumeStep(_ value: Int) -> Int {
        VolumeScale.allowedSteps.contains(value) ? value : 3
    }

    /// Reference to state reader for manual reconnect
    weak var stateReader: AntelopeStateReader?

    func reconnect() {
        stateReader?.reconnect()
        // Reset connection state immediately for UI feedback
        lastDataReceived = .distantPast
        connected = false
    }

    func markDataReceived(at date: Date = Date()) {
        lastDataReceived = date
        if !connected { connected = true }
    }

    func markDisconnected() {
        guard connected else { return }
        connected = false
    }

    func applySnapshot(
        channelUpdates: [OutputChannel: ChannelState],
        peakLevels: [Int],
        at date: Date = Date()
    ) {
        var nextChannels = channels
        var channelsChanged = false
        for (channel, state) in channelUpdates where nextChannels[channel] != state {
            nextChannels[channel] = state
            channelsChanged = true
        }
        if channelsChanged {
            channels = nextChannels
        }

        if !peakLevels.isEmpty {
            var nextPeaks = peaks
            nextPeaks.levels = peakLevels
            nextPeaks.updateSmooth()
            if nextPeaks != peaks {
                peaks = nextPeaks
            }
        }

        markDataReceived(at: date)
    }

    func updateControlAvailability(_ availability: ControlAvailability) {
        controlAvailability = availability
    }

    @Published var isRestartingServer: Bool = false

    /// Restart connection by launching Antelope Launcher (re-initializes the server)
    func restartServer() {
        guard !isRestartingServer else { return }
        isRestartingServer = true

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.antelopeaudio.launcher") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else {
            // Fallback: open by path
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Antelope Launcher.app"))
        }

        // Give the launcher time to re-initialize the server, then reconnect
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Thread.sleep(forTimeInterval: 5)
            DispatchQueue.main.async {
                self?.isRestartingServer = false
                self?.reconnect()
            }
        }
    }

    var currentChannel: ChannelState {
        get { channels[selectedOutput] ?? ChannelState() }
    }

}
