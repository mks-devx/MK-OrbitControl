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

// MARK: - AntelopeStateReader

final class AntelopeStateReader {

    private let deviceState: DeviceState
    private var thread: Thread?
    private var currentFd: Int32 = -1

    init(deviceState: DeviceState) {
        self.deviceState = deviceState
    }

    deinit {
        if currentFd >= 0 { close(currentFd); currentFd = -1 }
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
        if currentFd >= 0 { close(currentFd); currentFd = -1 }
    }

    // MARK: - Main loop

    private func run() {
        while !Thread.current.isCancelled {
            let fd = findAndConnect()
            if fd < 0 {
                Thread.sleep(forTimeInterval: 2)
                continue
            }

            currentFd = fd

            var tv = timeval(tv_sec: 15, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            // Enable SO_LINGER for clean socket shutdown
            var linger = linger(l_onoff: 1, l_linger: 0)
            setsockopt(fd, SOL_SOCKET, SO_LINGER, &linger, socklen_t(MemoryLayout<linger>.size))

            var consecutiveFailures = 0

            while !Thread.current.isCancelled {
                guard let payload = readOneMessage(fd: fd) else {
                    consecutiveFailures += 1
                    // Only give up after many failures (timeout = 15s each, so 10 = 2.5 min)
                    // This keeps the connection alive through idle periods
                    if consecutiveFailures >= 10 { break }
                    // Check if socket is still alive by peeking
                    var buf = [UInt8](repeating: 0, count: 1)
                    let peek = recv(fd, &buf, 1, MSG_PEEK | MSG_DONTWAIT)
                    if peek == 0 { break } // connection closed by server
                    // peek < 0 with EAGAIN/EWOULDBLOCK = still connected, just no data
                    continue
                }
                consecutiveFailures = 0
                parseAndApply(payload: payload)
            }

            close(fd)
            currentFd = -1

            if !Thread.current.isCancelled {
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }

    // MARK: - Find device server port and connect

    // Load report format once for init handshake
    private static let reportFormatJSON: String? = {
        let path = "/Users/Shared/.AntelopeAudio/orionstudioiii/panels/report_format_2.3.1"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }()

    private func findAndConnect() -> Int32 {
        let hosts = ["127.0.0.1", "192.168.0.235", "192.168.1.20"]
        let ports: [UInt16] = [2024, 2021, 2023, 2022, 2025, 2020]

        for host in hosts {
            for port in ports {
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

                if payload.count > 500 {
                    let str = String(bytes: payload, encoding: .utf8) ?? ""
                    if str.contains("cyclic") {
                        parseAndApply(payload: payload)
                        return fd
                    }
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
        var len = UInt32(data.count).bigEndian
        _ = withUnsafeBytes(of: &len) { ptr in
            send(fd, ptr.baseAddress!, 4, 0)
        }
        _ = data.withUnsafeBytes { ptr in
            send(fd, ptr.baseAddress!, data.count, 0)
        }
    }

    // MARK: - Read one length-prefixed message

    private func readOneMessage(fd: Int32) -> [UInt8]? {
        var lenBuf = [UInt8](repeating: 0, count: 4)
        guard recvAll(fd: fd, buf: &lenBuf, count: 4) else { return nil }

        let msgLen = Int(UInt32(lenBuf[0]) << 24 | UInt32(lenBuf[1]) << 16 |
                        UInt32(lenBuf[2]) << 8  | UInt32(lenBuf[3]))
        guard msgLen > 0, msgLen < 2_000_000 else { return nil }

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

        let ds = self.deviceState
        DispatchQueue.main.async {
            for (ch, state) in updates {
                ds.channels[ch] = state
            }
            if !peakLevels.isEmpty {
                ds.peaks.levels = peakLevels
                ds.peaks.updateSmooth()
            }
            ds.lastDataReceived = Date()
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
        inet_pton(AF_INET, host, &addr.sin_addr)

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
            if n <= 0 { return false }
            got += n
        }
        return true
    }
}
