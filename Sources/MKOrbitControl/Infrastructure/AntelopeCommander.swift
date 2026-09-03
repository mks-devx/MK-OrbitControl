import Darwin
import Foundation

/// Sends a deliberately small monitor-control command set directly to the
/// device service on localhost. No Antelope executable code is copied or loaded.
final class AntelopeCommander {
    enum MonitorCommand: String, CaseIterable {
        case setVolume = "set_volume"
        case setMute = "set_mute"
        case setDim = "set_dim"
        case setMono = "set_mono"
    }

    private enum AttemptResult {
        case noService
        case commandUnconfirmed
        case confirmed
    }

    private struct PendingVolume {
        var value: Int
        var completions: [(Bool) -> Void]
    }

    private let commandQueue = DispatchQueue(
        label: "com.mkdevices.orbitcontrol.commands",
        qos: .userInteractive
    )
    private let volumeLock = NSLock()
    private let portLock = NSLock()
    private let candidatePorts: [UInt16]
    private var preferredPort: UInt16?
    private var pendingVolumes: [OutputChannel: PendingVolume] = [:]
    private var volumeDrainScheduled = false

    var onStatusChange: ((ControlAvailability) -> Void)?

    init(candidatePorts: [UInt16] = AntelopeProtocol.candidatePorts) {
        self.candidatePorts = candidatePorts
    }

    /// Forget the last endpoint after wake, logout/login, or a server restart.
    func resetConnection() {
        portLock.withCriticalSection { preferredPort = nil }
        publishStatus(.starting)
    }

    // MARK: - Public API

    func setVolume(
        channel: OutputChannel,
        value: Int,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        let value = VolumeScale.clamp(raw: value)
        let shouldSchedule = volumeLock.withCriticalSection { () -> Bool in
            if var pending = pendingVolumes[channel] {
                pending.value = value
                pending.completions.append(completion)
                pendingVolumes[channel] = pending
            } else {
                pendingVolumes[channel] = PendingVolume(
                    value: value,
                    completions: [completion]
                )
            }
            if volumeDrainScheduled { return false }
            volumeDrainScheduled = true
            return true
        }
        if shouldSchedule {
            commandQueue.async { [weak self] in self?.drainOneVolume() }
        }
    }

    func setMute(
        channel: OutputChannel,
        muted: Bool,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        enqueue(.setMute, channel: channel, value: muted ? 1 : 0, completion: completion)
    }

    func setDim(
        channel: OutputChannel,
        dimmed: Bool,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        enqueue(.setDim, channel: channel, value: dimmed ? 1 : 0, completion: completion)
    }

    func setMono(
        channel: OutputChannel,
        mono: Bool,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        enqueue(.setMono, channel: channel, value: mono ? 1 : 0, completion: completion)
    }

    private func enqueue(
        _ command: MonitorCommand,
        channel: OutputChannel,
        value: Int,
        completion: @escaping (Bool) -> Void
    ) {
        commandQueue.async { [weak self] in
            guard let self else { return }
            let ok = self.send(command, channel: channel.rawValue, value: value)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    private func drainOneVolume() {
        let item = volumeLock.withCriticalSection { () -> (OutputChannel, PendingVolume)? in
            guard let channel = pendingVolumes.keys.first,
                  let pending = pendingVolumes.removeValue(forKey: channel) else {
                volumeDrainScheduled = false
                return nil
            }
            return (channel, pending)
        }

        guard let (channel, pending) = item else { return }
        let ok = send(.setVolume, channel: channel.rawValue, value: pending.value)
        DispatchQueue.main.async {
            pending.completions.forEach { $0(ok) }
        }

        let hasMore = volumeLock.withCriticalSection { () -> Bool in
            if pendingVolumes.isEmpty {
                volumeDrainScheduled = false
                return false
            }
            return true
        }
        if hasMore {
            commandQueue.async { [weak self] in self?.drainOneVolume() }
        }
    }

    // MARK: - Native device transport

    private func send(_ command: MonitorCommand, channel: Int, value: Int) -> Bool {
        guard OutputChannel(rawValue: channel) != nil,
              Self.isValid(value: value, for: command) else {
            publishStatus(.commandFailed)
            return false
        }

        let cached = portLock.withCriticalSection { preferredPort }
        var ports = candidatePorts
        if let cached {
            ports.removeAll { $0 == cached }
            ports.insert(cached, at: 0)
        }

        for port in ports {
            switch attempt(command, channel: channel, value: value, port: port) {
            case .noService:
                continue
            case .commandUnconfirmed:
                // Set operations are idempotent. One fresh connection handles a
                // short server state race without masking persistent failures.
                if case .confirmed = attempt(
                    command,
                    channel: channel,
                    value: value,
                    port: port
                ) {
                    portLock.withCriticalSection { preferredPort = port }
                    publishStatus(.ready)
                    return true
                }
                portLock.withCriticalSection { preferredPort = nil }
                publishStatus(.commandFailed)
                return false
            case .confirmed:
                portLock.withCriticalSection { preferredPort = port }
                publishStatus(.ready)
                return true
            }
        }

        portLock.withCriticalSection { preferredPort = nil }
        publishStatus(.serverUnavailable)
        return false
    }

    private func attempt(
        _ command: MonitorCommand,
        channel: Int,
        value: Int,
        port: UInt16
    ) -> AttemptResult {
        let fd = connectWithTimeout(port: port, timeoutMilliseconds: 350)
        guard fd >= 0 else { return .noService }
        defer { close(fd) }

        var noSigPipe: Int32 = 1
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        // Never send a command until this endpoint proves that it is the local
        // device service. This avoids writing to an unrelated process that may
        // happen to use a port in the discovery range.
        guard let greeting = readOneMessage(fd: fd),
              AntelopeProtocol.isCyclicPayload(greeting) else {
            return .noService
        }

        guard let frame = Self.commandFrame(command, channel: channel, value: value),
              frame.withUnsafeBytes({ sendAll(fd: fd, bytes: $0) }) else {
            return .commandUnconfirmed
        }

        let deadline = Date().addingTimeInterval(3)
        repeat {
            guard let payload = readOneMessage(fd: fd) else {
                return .commandUnconfirmed
            }
            if AntelopeProtocol.confirmsMonitorCommand(
                payload,
                command: command.rawValue,
                channel: channel,
                value: value
            ) {
                return .confirmed
            }
        } while Date() < deadline

        return .commandUnconfirmed
    }

    static func isValid(value: Int, for command: MonitorCommand) -> Bool {
        switch command {
        case .setVolume:
            return VolumeScale.minimumRaw...VolumeScale.maximumRaw ~= value
        case .setMute, .setDim, .setMono:
            return value == 0 || value == 1
        }
    }

    static func commandPayload(
        _ command: MonitorCommand,
        channel: Int,
        value: Int
    ) -> Data? {
        guard OutputChannel(rawValue: channel) != nil,
              isValid(value: value, for: command) else {
            return nil
        }
        return "[\"\(command.rawValue)\",[\(channel),\(value)],{}]"
            .data(using: .utf8)
    }

    static func commandFrame(
        _ command: MonitorCommand,
        channel: Int,
        value: Int
    ) -> Data? {
        guard let payload = commandPayload(command, channel: channel, value: value),
              var length = AntelopeProtocol.totalFrameLength(payloadLength: payload.count)?
                .bigEndian else {
            return nil
        }
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        return frame
    }

    private func connectWithTimeout(
        port: UInt16,
        timeoutMilliseconds: Int32
    ) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        let oldFlags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, oldFlags | O_NONBLOCK)

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1 else {
            close(fd)
            return -1
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 {
            _ = fcntl(fd, F_SETFL, oldFlags)
            return fd
        }

        guard errno == EINPROGRESS else {
            close(fd)
            return -1
        }

        var pollDescriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pollDescriptor, 1, timeoutMilliseconds)
        guard pollResult > 0 else {
            close(fd)
            return -1
        }

        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &errorLength)
        guard socketError == 0 else {
            close(fd)
            return -1
        }

        _ = fcntl(fd, F_SETFL, oldFlags)
        return fd
    }

    private func readOneMessage(fd: Int32) -> [UInt8]? {
        var header = [UInt8](repeating: 0, count: AntelopeProtocol.headerSize)
        guard recvAll(fd: fd, buffer: &header, count: header.count) else {
            return nil
        }

        let totalLength = Int(
            UInt32(header[0]) << 24
                | UInt32(header[1]) << 16
                | UInt32(header[2]) << 8
                | UInt32(header[3])
        )
        guard let payloadLength = AntelopeProtocol.payloadLength(
            totalFrameLength: totalLength
        ) else {
            return nil
        }

        var payload = [UInt8](repeating: 0, count: payloadLength)
        guard recvAll(fd: fd, buffer: &payload, count: payloadLength) else {
            return nil
        }
        return payload
    }

    private func recvAll(fd: Int32, buffer: inout [UInt8], count: Int) -> Bool {
        var received = 0
        while received < count {
            let result = buffer.withUnsafeMutableBytes { pointer in
                recv(fd, pointer.baseAddress!.advanced(by: received), count - received, 0)
            }
            if result < 0, errno == EINTR { continue }
            if result <= 0 { return false }
            received += result
        }
        return true
    }

    private func sendAll(fd: Int32, bytes: UnsafeRawBufferPointer) -> Bool {
        guard let baseAddress = bytes.baseAddress else { return bytes.isEmpty }
        var sent = 0
        while sent < bytes.count {
            let result = Darwin.send(
                fd,
                baseAddress.advanced(by: sent),
                bytes.count - sent,
                0
            )
            if result < 0, errno == EINTR { continue }
            if result <= 0 { return false }
            sent += result
        }
        return true
    }

    private func publishStatus(_ status: ControlAvailability) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChange?(status)
        }
    }
}
