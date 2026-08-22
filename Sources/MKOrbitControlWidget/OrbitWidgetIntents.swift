import AppIntents
import WidgetKit

enum OrbitWidgetVolumeDirection: String, AppEnum {
    case louder
    case quieter

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Volume direction")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .louder: DisplayRepresentation(title: "Louder"),
        .quieter: DisplayRepresentation(title: "Quieter"),
    ]
}

enum OrbitWidgetOutput: Int, AppEnum {
    case monA = 0
    case hp1 = 1
    case hp2 = 2
    case monB = 5

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Monitor output")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .monA: DisplayRepresentation(title: "MON A"),
        .monB: DisplayRepresentation(title: "MON B"),
        .hp1: DisplayRepresentation(title: "HP 1"),
        .hp2: DisplayRepresentation(title: "HP 2"),
    ]
}

private enum OrbitWidgetAction {
    static func run(command: String, value: Int, update: (inout OrbitWidgetSnapshot) -> Void) async {
        var snapshot = OrbitWidgetStateStore.load()
        do {
            try await OrbitWidgetCommandClient().send(
                command: command,
                channel: snapshot.outputRawValue,
                value: value
            )
            update(&snapshot)
            snapshot.connected = true
            snapshot.lastCommandFailed = false
        } catch {
            snapshot.lastCommandFailed = true
        }
        snapshot.updatedAt = Date()
        OrbitWidgetStateStore.save(snapshot)
    }
}

struct AdjustOrbitVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Adjust monitor volume"
    static let description = IntentDescription("Raises or lowers the selected Antelope output by 3 dB.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Direction")
    var direction: OrbitWidgetVolumeDirection

    init() {
        direction = .louder
    }

    init(direction: OrbitWidgetVolumeDirection) {
        self.direction = direction
    }

    func perform() async throws -> some IntentResult {
        let snapshot = OrbitWidgetStateStore.load()
        let delta = direction == .louder ? -3 : 3
        let nextVolume = min(96, max(0, snapshot.volume + delta))
        await OrbitWidgetAction.run(command: "set_volume", value: nextVolume) {
            $0.volume = nextVolume
        }
        return .result()
    }
}

struct ToggleOrbitMuteIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle monitor mute"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        let nextValue = !OrbitWidgetStateStore.load().muted
        await OrbitWidgetAction.run(command: "set_mute", value: nextValue ? 1 : 0) {
            $0.muted = nextValue
        }
        return .result()
    }
}

struct ToggleOrbitDimIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle monitor dim"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        let nextValue = !OrbitWidgetStateStore.load().dimmed
        await OrbitWidgetAction.run(command: "set_dim", value: nextValue ? 1 : 0) {
            $0.dimmed = nextValue
        }
        return .result()
    }
}

struct SelectOrbitOutputIntent: AppIntent {
    static let title: LocalizedStringResource = "Select monitor output"
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Output")
    var output: OrbitWidgetOutput

    init() {
        output = .monA
    }

    init(output: OrbitWidgetOutput) {
        self.output = output
    }

    func perform() async throws -> some IntentResult {
        var snapshot = OrbitWidgetStateStore.load()
        snapshot.outputRawValue = output.rawValue
        snapshot.updatedAt = Date()
        snapshot.lastCommandFailed = false
        OrbitWidgetStateStore.save(snapshot)
        OrbitWidgetStateStore.requestOutput(output.rawValue)
        NotificationCenter.default.post(
            name: .orbitWidgetSelectOutput,
            object: nil,
            userInfo: ["rawValue": output.rawValue]
        )
        return .result()
    }
}
