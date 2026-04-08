import Foundation
import CoreMIDI
import AppKit

// MARK: - MIDI Mapping

struct MIDIMapping: Codable, Equatable, Identifiable {
    var id: String { "\(channel)_\(cc)_\(action)" }
    var channel: Int      // MIDI channel 0-15
    var cc: Int           // CC number 0-127
    var action: MIDIAction
}

enum MIDIAction: String, Codable, CaseIterable {
    case volumeMonA, volumeMonB, volumeHP1, volumeHP2
    case muteMonA, muteMonB, muteHP1, muteHP2

    var outputChannel: OutputChannel {
        switch self {
        case .volumeMonA, .muteMonA: return .monA
        case .volumeMonB, .muteMonB: return .monB
        case .volumeHP1, .muteHP1: return .hp1
        case .volumeHP2, .muteHP2: return .hp2
        }
    }

    var isVolume: Bool {
        switch self {
        case .volumeMonA, .volumeMonB, .volumeHP1, .volumeHP2: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .volumeMonA: return "MON A Volume"
        case .volumeMonB: return "MON B Volume"
        case .volumeHP1: return "HP 1 Volume"
        case .volumeHP2: return "HP 2 Volume"
        case .muteMonA: return "MON A Mute"
        case .muteMonB: return "MON B Mute"
        case .muteHP1: return "HP 1 Mute"
        case .muteHP2: return "HP 2 Mute"
        }
    }
}

// MARK: - MIDI Manager

class MIDIManager: ObservableObject {
    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private let commander: AntelopeCommander
    private let deviceState: DeviceState

    @Published var mappings: [MIDIMapping] = []
    @Published var isLearning = false
    @Published var learningAction: MIDIAction?
    @Published var lastReceivedCC: String = ""

    private var onLearnComplete: ((Int, Int) -> Void)?
    private static let defaultsKey = "MKMIDIMappings"

    init(commander: AntelopeCommander, deviceState: DeviceState) {
        self.commander = commander
        self.deviceState = deviceState
        loadMappings()
        setupMIDI()
    }

    // MARK: - CoreMIDI Setup

    private func setupMIDI() {
        var status = MIDIClientCreateWithBlock("MK-OrbitControl" as CFString, &midiClient) { [weak self] notification in
            // MIDI setup changed — reconnect
            DispatchQueue.main.async { self?.connectAllSources() }
        }
        guard status == noErr else { return }

        status = MIDIInputPortCreateWithProtocol(
            midiClient,
            "Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, srcConnRefCon in
            self?.handleMIDI(eventList)
        }
        guard status == noErr else { return }

        connectAllSources()
    }

    private func connectAllSources() {
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, src, nil)
        }
    }

    // MARK: - MIDI Processing

    private func handleMIDI(_ eventListPtr: UnsafePointer<MIDIEventList>) {
        let eventList = eventListPtr.pointee
        var packet = eventList.packet

        for _ in 0..<eventList.numPackets {
            let words = Mirror(reflecting: packet.words).children.map { $0.value as! UInt32 }
            if let word = words.first, word != 0 {
                let status = (word >> 16) & 0xF0
                let channel = Int((word >> 16) & 0x0F)
                let data1 = Int((word >> 8) & 0x7F)
                let data2 = Int(word & 0x7F)

                // CC message (status 0xB0)
                if status == 0xB0 {
                    DispatchQueue.main.async {
                        self.processMIDICC(channel: channel, cc: data1, value: data2)
                    }
                }
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func processMIDICC(channel: Int, cc: Int, value: Int) {
        lastReceivedCC = "Ch\(channel + 1) CC\(cc) Val\(value)"

        // Learning mode — capture the CC
        if isLearning, let action = learningAction {
            let mapping = MIDIMapping(channel: channel, cc: cc, action: action)
            saveMappingAndStopLearn(mapping)
            return
        }

        // Normal mode — execute mapping
        for mapping in mappings {
            if mapping.channel == channel && mapping.cc == cc {
                executeMapping(mapping, value: value)
            }
        }
    }

    private func executeMapping(_ mapping: MIDIMapping, value: Int) {
        let ch = mapping.action.outputChannel
        if mapping.action.isVolume {
            // Map MIDI 0-127 to volume 96-0 (0=loudest, 96=silence)
            let vol = 96 - Int(Double(value) / 127.0 * 96.0)
            commander.setVolume(channel: ch, value: vol)
            DispatchQueue.main.async {
                self.deviceState.channels[ch]?.volume = vol
            }
        } else {
            // Mute: value > 63 = mute on, <= 63 = mute off
            let muted = value > 63
            commander.setMute(channel: ch, muted: muted)
        }
    }

    // MARK: - Learn Mode

    func startLearn(for action: MIDIAction) {
        isLearning = true
        learningAction = action
    }

    func cancelLearn() {
        isLearning = false
        learningAction = nil
    }

    private func saveMappingAndStopLearn(_ mapping: MIDIMapping) {
        mappings.removeAll { $0.action == mapping.action }
        mappings.append(mapping)
        isLearning = false
        learningAction = nil
        persistMappings()
    }

    func removeMapping(for action: MIDIAction) {
        mappings.removeAll { $0.action == action }
        persistMappings()
    }

    func getMapping(for action: MIDIAction) -> MIDIMapping? {
        mappings.first { $0.action == action }
    }

    // MARK: - Persistence

    private func loadMappings() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let m = try? JSONDecoder().decode([MIDIMapping].self, from: data) else { return }
        mappings = m
    }

    private func persistMappings() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
