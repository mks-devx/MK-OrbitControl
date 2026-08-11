import Foundation

// MARK: - JSON decoding types

private struct CyclicMessage: Decodable {
    let type: String
    let contents: CyclicContents?
}

private struct CyclicContents: Decodable {
    let volumes_and_mutes: [ChannelEntry]
    let peaks_meters: [Int]?
}

private struct ChannelEntry: Decodable {
    let volume: Int
    let mute: Int
    let dim: Int
    let mono: Int
}

enum AntelopeProtocol {
    static let headerSize = 4
    private static let preferredPorts: [UInt16] = [2024, 2021, 2023, 2022, 2025, 2020]

    /// Antelope assigns the device endpoint dynamically. It has moved beyond
    /// the original 2020...2025 window after server restarts in real use.
    static let candidatePorts: [UInt16] = {
        preferredPorts + Array(UInt16(2020)...UInt16(2100)).filter { !preferredPorts.contains($0) }
    }()

    static func payloadLength(totalFrameLength: Int) -> Int? {
        guard totalFrameLength > headerSize, totalFrameLength <= 2_000_000 else { return nil }
        return totalFrameLength - headerSize
    }

    static func totalFrameLength(payloadLength: Int) -> UInt32? {
        guard payloadLength > 0, payloadLength <= 2_000_000 - headerSize else { return nil }
        return UInt32(payloadLength + headerSize)
    }

    static func isCyclicPayload(_ payload: [UInt8]) -> Bool {
        guard let text = String(bytes: payload, encoding: .utf8) else { return false }
        return text.contains("\"type\": \"cyclic\"") || text.contains("\"type\":\"cyclic\"")
    }
}

// MARK: - AntelopeStateReader

final class AntelopeStateReader {

    private let deviceState: DeviceState
    private var thread: Thread?
    private let stateLock = NSLock()
    private var currentFd: Int32 = -1
    private var forceReconnect = false
    private var lastUIUpdate: Date = .distantPast
    private let minimumUIUpdateInterval: TimeInterval = 1.0 / 30.0

    init(deviceState: DeviceState) {
        self.deviceState = deviceState
    }

    /// Force drop current connection and reconnect immediately
    func reconnect() {
        let fd = stateLock.withCriticalSection { () -> Int32 in
            forceReconnect = true
            return currentFd
        }
        // The reader thread owns close(); shutdown only interrupts a blocking recv.
        if fd >= 0 { shutdown(fd, SHUT_RDWR) }
    }

    deinit {
        stop()
    }

    func start() {
        let t = Thread { [weak self] in
            self?.run()
        }
        t.qualityOfService = .utility
        t.name = "AntelopeStateReader"
        thread = t
        t.start()
    }

    func stop() {
        thread?.cancel()
        thread = nil
        let fd = stateLock.withCriticalSection { currentFd }
        if fd >= 0 { shutdown(fd, SHUT_RDWR) }
    }

    // MARK: - Main loop

    private func run() {
        while !Thread.current.isCancelled {
            let fd = findAndConnect()
            if fd < 0 {
                markDisconnected()
                Thread.sleep(forTimeInterval: 2)
                continue
            }

            stateLock.withCriticalSection { currentFd = fd }

            var tv = timeval(tv_sec: 15, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            // Enable SO_LINGER for clean socket shutdown
            var linger = linger(l_onoff: 1, l_linger: 0)
            setsockopt(fd, SOL_SOCKET, SO_LINGER, &linger, socklen_t(MemoryLayout<linger>.size))

            while !Thread.current.isCancelled && !shouldForceReconnect() {
                guard let payload = readOneMessage(fd: fd) else {
                    // A timeout or partial frame makes the stream boundary unknown.
                    // Reconnect instead of interpreting remaining bytes as a new header.
                    break
                }
                parseAndApply(payload: payload)
            }

            stateLock.withCriticalSection {
                if currentFd == fd { currentFd = -1 }
                forceReconnect = false
            }
            close(fd)
            markDisconnected()

            if !Thread.current.isCancelled {
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }

    // MARK: - Find device server port and connect

    // Load the newest installed report format once for the init handshake.
    private static let reportFormatJSON: String? = {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: "/Users/Shared/.AntelopeAudio", isDirectory: true)
        guard let deviceDirectories = try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let candidates = deviceDirectories.flatMap { deviceURL -> [URL] in
            let panelsURL = deviceURL.appendingPathComponent("panels", isDirectory: true)
            return (try? fileManager.contentsOfDirectory(
                at: panelsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.filter { $0.lastPathComponent.hasPrefix("report_format_") } ?? []
        }.sorted {
            $0.lastPathComponent.compare(
                $1.lastPathComponent,
                options: [.numeric, .caseInsensitive]
            ) == .orderedDescending
        }

        guard let path = candidates.first,
              let data = try? Data(contentsOf: path),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }()

    private func findAndConnect() -> Int32 {
        let hosts = ["127.0.0.1"]
        for host in hosts {
            for port in AntelopeProtocol.candidatePorts {
                let fd = connectWithTimeout(host: host, port: port, timeoutSec: 2)
                if fd < 0 { continue }

                var tv = timeval(tv_sec: 5, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                // Send initialize_format to trigger cyclic data
                sendInitFormat(fd: fd)

                // Read first message
                guard let payload = readOneMessage(fd: fd) else {
                    close(fd)
                    continue
                }

                if AntelopeProtocol.isCyclicPayload(payload) {
                    parseAndApply(payload: payload)
                    return fd
                }

                close(fd)
            }
        }
        return -1
    }

    /// Send initialize_format command so the server starts sending cyclic reports
    private func sendInitFormat(fd: Int32) {
        guard let rfJSON = Self.reportFormatJSON else { return }
        let cmd = "[\"initialize_format\",[\(rfJSON)],{}]"
        guard let data = cmd.data(using: .utf8) else { return }
        guard var len = AntelopeProtocol.totalFrameLength(payloadLength: data.count)?.bigEndian else {
            return
        }
        guard withUnsafeBytes(of: &len, { sendAll(fd: fd, bytes: $0) }) else { return }
        _ = data.withUnsafeBytes { sendAll(fd: fd, bytes: $0) }
    }

    // MARK: - Read one length-prefixed message

    private func readOneMessage(fd: Int32) -> [UInt8]? {
        var lenBuf = [UInt8](repeating: 0, count: 4)
        guard recvAll(fd: fd, buf: &lenBuf, count: 4) else { return nil }

        let totalFrameLength = Int(UInt32(lenBuf[0]) << 24 | UInt32(lenBuf[1]) << 16 |
                                   UInt32(lenBuf[2]) << 8  | UInt32(lenBuf[3]))
        guard let msgLen = AntelopeProtocol.payloadLength(totalFrameLength: totalFrameLength) else {
            return nil
        }

        var payload = [UInt8](repeating: 0, count: msgLen)
        guard recvAll(fd: fd, buf: &payload, count: msgLen) else { return nil }

        return payload
    }

    // MARK: - JSON parsing

    private func parseAndApply(payload: [UInt8]) {
        // Find JSON boundary
        var depth = 0
        var jsonEnd = 0
        for (i, byte) in payload.enumerated() {
            if byte == UInt8(ascii: "{") { depth += 1 }
            else if byte == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 { jsonEnd = i + 1; break }
            }
        }
        guard jsonEnd > 0 else { return }

        let jsonData = Data(payload[0..<jsonEnd])
        guard let msg = try? JSONDecoder().decode(CyclicMessage.self, from: jsonData),
              msg.type == "cyclic",
              let contents = msg.contents else { return }

        let entries = contents.volumes_and_mutes
        var updates = [OutputChannel: ChannelState]()

        for channel in OutputChannel.allCases {
            let idx = channel.rawValue
            guard idx < entries.count else { continue }
            let e = entries[idx]
            updates[channel] = ChannelState(
                volume: e.volume,
                mute:   e.mute != 0,
                dim:    e.dim  != 0,
                mono:   e.mono != 0
            )
        }

        let peakLevels = contents.peaks_meters ?? []

        let updateDate = Date()
        guard updateDate.timeIntervalSince(lastUIUpdate) >= minimumUIUpdateInterval else {
            return
        }
        lastUIUpdate = updateDate

        let ds = self.deviceState
        DispatchQueue.main.async {
            ds.applySnapshot(
                channelUpdates: updates,
                peakLevels: peakLevels,
                at: updateDate
            )
        }
    }

    // MARK: - Connection state

    // Connected state is now derived from lastDataReceived in DeviceState

    // MARK: - Socket helpers

    private func connectWithTimeout(host: String, port: UInt16, timeoutSec: Int) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        let oldFlags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, oldFlags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            close(fd)
            return -1
        }

        let cr = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if cr == 0 {
            _ = fcntl(fd, F_SETFL, oldFlags)
            return fd
        }

        guard errno == EINPROGRESS else {
            close(fd)
            return -1
        }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pr = poll(&pfd, 1, Int32(timeoutSec * 1000))
        guard pr > 0 else { close(fd); return -1 }

        var err: Int32 = 0
        var errLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &errLen)
        guard err == 0 else { close(fd); return -1 }

        _ = fcntl(fd, F_SETFL, oldFlags)
        return fd
    }

    private func recvAll(fd: Int32, buf: inout [UInt8], count: Int) -> Bool {
        var got = 0
        while got < count {
            let n = buf.withUnsafeMutableBytes { ptr in
                recv(fd, ptr.baseAddress!.advanced(by: got), count - got, 0)
            }
            if n < 0, errno == EINTR { continue }
            if n <= 0 { return false }
            got += n
        }
        return true
    }

    private func sendAll(fd: Int32, bytes: UnsafeRawBufferPointer) -> Bool {
        guard let baseAddress = bytes.baseAddress else { return bytes.isEmpty }
        var sent = 0
        while sent < bytes.count {
            let count = send(fd, baseAddress.advanced(by: sent), bytes.count - sent, 0)
            if count < 0, errno == EINTR { continue }
            if count <= 0 { return false }
            sent += count
        }
        return true
    }

    private func shouldForceReconnect() -> Bool {
        stateLock.withCriticalSection { forceReconnect }
    }

    private func markDisconnected() {
        DispatchQueue.main.async { [weak deviceState] in
            deviceState?.markDisconnected()
        }
    }
}

extension NSLock {
    func withCriticalSection<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
