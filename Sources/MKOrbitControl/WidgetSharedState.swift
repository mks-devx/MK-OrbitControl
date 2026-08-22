import Foundation
import WidgetKit
import Darwin

enum OrbitWidgetConfiguration {
    static let kind = "MKOrbitControlWidget"
    static let appGroup = "group.com.mkdevices.orbitcontrol"
    static let stateKey = "widget.control-state"
    static let authTokenKey = "widget.bridge-token"
    static let requestedOutputKey = "widget.requested-output"
    static let bridgePort: UInt16 = 17_580
}

extension Notification.Name {
    static let orbitWidgetSelectOutput = Notification.Name("com.mkdevices.orbitcontrol.widget.select-output")
}

struct OrbitWidgetSnapshot: Codable, Equatable, Sendable {
    var outputRawValue: Int
    var volume: Int
    var muted: Bool
    var dimmed: Bool
    var connected: Bool
    var updatedAt: Date
    var lastCommandFailed: Bool

    static let offline = OrbitWidgetSnapshot(
        outputRawValue: 0,
        volume: 96,
        muted: false,
        dimmed: false,
        connected: false,
        updatedAt: .distantPast,
        lastCommandFailed: false
    )

    var displayVolume: String {
        let clamped = min(96, max(0, volume))
        if clamped == 96 { return "−∞" }
        if clamped == 0 { return "0" }
        return "−\(clamped)"
    }

    var outputLabel: String {
        switch outputRawValue {
        case 0: return "MON A"
        case 1: return "HP 1"
        case 2: return "HP 2"
        case 5: return "MON B"
        default: return "OUTPUT"
        }
    }

    func visuallyMatches(_ other: OrbitWidgetSnapshot) -> Bool {
        outputRawValue == other.outputRawValue
            && volume == other.volume
            && muted == other.muted
            && dimmed == other.dimmed
            && connected == other.connected
            && lastCommandFailed == other.lastCommandFailed
    }
}

enum OrbitWidgetStateStore {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: OrbitWidgetConfiguration.appGroup) ?? .standard
    }

    static func load() -> OrbitWidgetSnapshot {
        guard let data = defaults.data(forKey: OrbitWidgetConfiguration.stateKey),
              let snapshot = try? JSONDecoder().decode(OrbitWidgetSnapshot.self, from: data) else {
            return .offline
        }
        return snapshot
    }

    static func save(_ snapshot: OrbitWidgetSnapshot, reload: Bool = true) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: OrbitWidgetConfiguration.stateKey)
        if reload {
            WidgetCenter.shared.reloadTimelines(ofKind: OrbitWidgetConfiguration.kind)
        }
    }

    static func saveAuthToken(_ token: String) {
        guard token.count >= 32 else { return }
        defaults.set(token, forKey: OrbitWidgetConfiguration.authTokenKey)
    }

    static var authToken: String? {
        guard let token = defaults.string(forKey: OrbitWidgetConfiguration.authTokenKey),
              token.count >= 32 else { return nil }
        return token
    }

    static func requestOutput(_ rawValue: Int) {
        defaults.set(rawValue, forKey: OrbitWidgetConfiguration.requestedOutputKey)
    }

    static func consumeRequestedOutput() -> Int? {
        guard defaults.object(forKey: OrbitWidgetConfiguration.requestedOutputKey) != nil else {
            return nil
        }
        let rawValue = defaults.integer(forKey: OrbitWidgetConfiguration.requestedOutputKey)
        defaults.removeObject(forKey: OrbitWidgetConfiguration.requestedOutputKey)
        return rawValue
    }
}

enum OrbitWidgetCommandError: LocalizedError {
    case missingAuthentication
    case bridgeUnavailable
    case invalidResponse
    case commandRejected

    var errorDescription: String? {
        switch self {
        case .missingAuthentication: return "Open MK-OrbitControl once to enable widget control."
        case .bridgeUnavailable: return "MK-OrbitControl is not connected to its local bridge."
        case .invalidResponse: return "The local bridge returned an invalid response."
        case .commandRejected: return "The Antelope device did not confirm the command."
        }
    }
}

struct OrbitWidgetCommandClient: Sendable {
    private struct Request: Encodable {
        let cmd: String
        let ch: Int
        let val: Int
        let token: String
    }

    private struct Response: Decodable {
        let ok: Bool
    }

    func send(command: String, channel: Int, value: Int) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try sendSynchronously(command: command, channel: channel, value: value)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendSynchronously(command: String, channel: Int, value: Int) throws {
        guard let token = OrbitWidgetStateStore.authToken else {
            throw OrbitWidgetCommandError.missingAuthentication
        }
        guard let fd = connectToBridge(retryFor: 6) else {
            throw OrbitWidgetCommandError.bridgeUnavailable
        }
        defer { close(fd) }

        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 6, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var payload = try JSONEncoder().encode(Request(cmd: command, ch: channel, val: value, token: token))
        payload.append(0x0A)
        guard payload.withUnsafeBytes({ sendAll(fd: fd, bytes: $0) }) else {
            throw OrbitWidgetCommandError.bridgeUnavailable
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 256)
        while response.count < 4_096 {
            let received = recv(fd, &buffer, buffer.count, 0)
            if received < 0, errno == EINTR { continue }
            guard received > 0 else { throw OrbitWidgetCommandError.bridgeUnavailable }
            response.append(contentsOf: buffer[0..<received])
            if response.contains(0x0A) { break }
        }

        guard let newline = response.firstIndex(of: 0x0A),
              let decoded = try? JSONDecoder().decode(Response.self, from: response[..<newline]) else {
            throw OrbitWidgetCommandError.invalidResponse
        }
        guard decoded.ok else { throw OrbitWidgetCommandError.commandRejected }
    }

    private func connectToBridge(retryFor seconds: TimeInterval) -> Int32? {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { return nil }

            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = OrbitWidgetConfiguration.bridgePort.bigEndian
            inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)

            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result == 0 { return fd }
            close(fd)
            if Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        } while Date() < deadline
        return nil
    }

    private func sendAll(fd: Int32, bytes: UnsafeRawBufferPointer) -> Bool {
        guard let baseAddress = bytes.baseAddress else { return bytes.isEmpty }
        var sent = 0
        while sent < bytes.count {
            let count = Darwin.send(fd, baseAddress.advanced(by: sent), bytes.count - sent, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return false }
            sent += count
        }
        return true
    }
}
