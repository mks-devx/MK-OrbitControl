import Foundation

final class AntelopeCommander {
    private struct CommandRequest: Encodable {
        let cmd: String
        let ch: Int
        let val: Int
        let token: String
    }

    private struct CommandResponse: Decodable {
        let ok: Bool
    }

    private struct PendingVolume {
        var value: Int
        var completions: [(Bool) -> Void]
    }

    private let pythonPath: String
    private let bridgePath: String
    private let pythonEnvironment: [String: String]
    private let modulesPath: String
    private let authToken: String
    private let daemonPort: UInt16 = 17580
    private let commandQueue = DispatchQueue(label: "com.mkdevices.orbitcontrol.commands", qos: .userInteractive)
    private let processLock = NSLock()
    private let setupLock = NSLock()
    private let volumeLock = NSLock()
    private var daemonProcess: Process?
    private var setupProcess: Process?
    private var pendingVolumes: [OutputChannel: PendingVolume] = [:]
    private var volumeDrainScheduled = false
    var onStatusChange: ((ControlAvailability) -> Void)?

    init(pythonPath: String? = nil, bridgePath: String? = nil, authToken: String? = nil) {
        let runtime = Self.resolveRuntime()
        self.pythonPath = pythonPath ?? runtime.pythonPath
        self.bridgePath = bridgePath ?? runtime.bridgePath
        self.modulesPath = runtime.modulesPath
        self.authToken = authToken ?? Self.loadOrCreateAuthToken(in: runtime.applicationSupport)
        var environment = runtime.environment
        environment["MK_ORBIT_AUTH_TOKEN"] = self.authToken
        self.pythonEnvironment = environment
    }

    @discardableResult
    func startDaemon() -> Bool {
        processLock.lock()
        defer { processLock.unlock() }

        if daemonProcess?.isRunning == true { return true }
        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            NSLog("MK-OrbitControl: Python runtime is missing at %@", pythonPath)
            publishStatus(.missingRuntime)
            return false
        }
        guard FileManager.default.fileExists(atPath: bridgePath) else {
            NSLog("MK-OrbitControl: bridge is missing at %@", bridgePath)
            publishStatus(.missingBridge)
            return false
        }
        guard FileManager.default.fileExists(atPath: modulesPath) else {
            NSLog("MK-OrbitControl: extracted Antelope modules are missing at %@", modulesPath)
            publishStatus(.missingModules)
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [bridgePath, "--daemon"]
        process.environment = pythonEnvironment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self, weak process] _ in
            guard let self, let process else { return }
            self.processLock.lock()
            if self.daemonProcess === process { self.daemonProcess = nil }
            self.processLock.unlock()
        }

        do {
            try process.run()
            daemonProcess = process
            publishStatus(.starting)
            return true
        } catch {
            NSLog("MK-OrbitControl: failed to start bridge: %@", error.localizedDescription)
            publishStatus(.bridgeUnavailable)
            return false
        }
    }

    func installModules(completion: @escaping (Bool) -> Void) {
        let setupPath = Self.resolveSetupPath()
        guard let setupPath else {
            publishStatus(.missingBridge)
            DispatchQueue.main.async { completion(false) }
            return
        }

        let shouldStart = setupLock.withCriticalSection { () -> Bool in
            if setupProcess?.isRunning == true { return false }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [setupPath]
            process.environment = ProcessInfo.processInfo.environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self, weak process] processResult in
                guard let self, let process else { return }
                self.setupLock.withCriticalSection {
                    if self.setupProcess === process { self.setupProcess = nil }
                }
                let succeeded = processResult.terminationStatus == 0
                if succeeded {
                    _ = self.startDaemon()
                } else {
                    self.publishStatus(.missingModules)
                }
                DispatchQueue.main.async { completion(succeeded) }
            }
            do {
                try process.run()
                setupProcess = process
                publishStatus(.starting)
                return true
            } catch {
                NSLog("MK-OrbitControl: failed to run setup: %@", error.localizedDescription)
                return false
            }
        }

        if !shouldStart {
            DispatchQueue.main.async { completion(false) }
        }
    }

    func stopDaemon() {
        processLock.lock()
        let process = daemonProcess
        daemonProcess = nil
        processLock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    /// Replace a bridge session after wake/unlock, when Antelope may have
    /// reassigned its local device port while the old process stayed alive.
    func restartDaemon() {
        commandQueue.async { [weak self] in
            guard let self else { return }
            let process = self.processLock.withCriticalSection { () -> Process? in
                let current = self.daemonProcess
                self.daemonProcess = nil
                return current
            }
            if process?.isRunning == true {
                process?.terminate()
                process?.waitUntilExit()
            }
            _ = self.startDaemon()
        }
    }

    // MARK: - Public API

    func setVolume(channel: OutputChannel, value: Int, completion: @escaping (Bool) -> Void = { _ in }) {
        let value = VolumeScale.clamp(raw: value)
        let shouldSchedule = volumeLock.withCriticalSection { () -> Bool in
            if var pending = pendingVolumes[channel] {
                pending.value = value
                pending.completions.append(completion)
                pendingVolumes[channel] = pending
            } else {
                pendingVolumes[channel] = PendingVolume(value: value, completions: [completion])
            }
            if volumeDrainScheduled { return false }
            volumeDrainScheduled = true
            return true
        }
        if shouldSchedule { commandQueue.async { [weak self] in self?.drainOneVolume() } }
    }

    func setMute(channel: OutputChannel, muted: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        enqueue("set_mute", channel: channel, value: muted ? 1 : 0, completion: completion)
    }

    func setDim(channel: OutputChannel, dimmed: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        enqueue("set_dim", channel: channel, value: dimmed ? 1 : 0, completion: completion)
    }

    func setMono(channel: OutputChannel, mono: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        enqueue("set_mono", channel: channel, value: mono ? 1 : 0, completion: completion)
    }

    private func enqueue(
        _ command: String,
        channel: OutputChannel,
        value: Int,
        completion: @escaping (Bool) -> Void
    ) {
        commandQueue.async { [weak self] in
            guard let self else { return }
            let ok = self.sendViaDaemon(command, channel: channel.rawValue, value: value)
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
        let ok = sendViaDaemon("set_volume", channel: channel.rawValue, value: pending.value)
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
        if hasMore { commandQueue.async { [weak self] in self?.drainOneVolume() } }
    }

    // MARK: - Bridge transport

    private func sendViaDaemon(_ command: String, channel: Int, value: Int) -> Bool {
        guard startDaemon() else { return false }

        guard let fd = connectToDaemon(retryFor: 6) else {
            publishStatus(.bridgeUnavailable)
            return false
        }
        defer { close(fd) }

        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 6, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard var data = try? JSONEncoder().encode(CommandRequest(
            cmd: command,
            ch: channel,
            val: value,
            token: authToken
        )) else {
            return false
        }
        data.append(0x0A)
        guard data.withUnsafeBytes({ sendAll(fd: fd, bytes: $0) }) else { return false }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 256)
        while response.count < 4096 {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count < 0, errno == EINTR { continue }
            if count <= 0 { return false }
            response.append(contentsOf: buffer[0..<count])
            if response.contains(0x0A) { break }
        }

        guard let newline = response.firstIndex(of: 0x0A) else { return false }
        let ok = (try? JSONDecoder().decode(CommandResponse.self, from: response[..<newline]))?.ok == true
        publishStatus(ok ? .ready : .commandFailed)
        return ok
    }

    private func connectToDaemon(retryFor seconds: TimeInterval) -> Int32? {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { return nil }

            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = daemonPort.bigEndian
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
            let count = send(fd, baseAddress.advanced(by: sent), bytes.count - sent, 0)
            if count < 0, errno == EINTR { continue }
            if count <= 0 { return false }
            sent += count
        }
        return true
    }

    // MARK: - Runtime discovery

    private func publishStatus(_ status: ControlAvailability) {
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?(status) }
    }

    private static func loadOrCreateAuthToken(in directory: URL) -> String {
        let fileManager = FileManager.default
        let tokenURL = directory.appendingPathComponent("bridge-token", isDirectory: false)
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if let token = try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           token.count >= 32 {
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
            return token
        }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        do {
            try Data(token.utf8).write(to: tokenURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
        } catch {
            NSLog("MK-OrbitControl: could not persist bridge authentication token: %@", error.localizedDescription)
        }
        return token
    }

    private static func resolveSetupPath() -> String? {
        let fileManager = FileManager.default
        let resources = Bundle.main.resourceURL
        let candidates = [
            resources?.appendingPathComponent("setup.sh").path,
            resources?.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("setup.sh").path,
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("setup.sh").path,
        ].compactMap { $0 }
        return candidates.first(where: fileManager.fileExists(atPath:))
    }

    private static func resolveRuntime() -> (
        pythonPath: String,
        bridgePath: String,
        modulesPath: String,
        applicationSupport: URL,
        environment: [String: String]
    ) {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let resources = Bundle.main.resourceURL
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MK-OrbitControl", isDirectory: true)
        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        let pythonCandidates = [
            resources?.appendingPathComponent("python/python3.8").path,
            home.appendingPathComponent(".pyenv/versions/3.8.20/bin/python3.8").path,
        ].compactMap { $0 }

        var bridgeCandidates: [String] = []
        if let resources { bridgeCandidates.append(resources.appendingPathComponent("bridge.py").path) }
        bridgeCandidates.append(appSupport.appendingPathComponent("bridge.py").path)
        bridgeCandidates.append(workingDirectory.appendingPathComponent("bridge.py").path)
        bridgeCandidates.append(home.appendingPathComponent("Developer/MK-AntelopeControl/bridge.py").path)

        let selectedPython = pythonCandidates.first(where: fileManager.isExecutableFile(atPath:))
            ?? pythonCandidates[0]
        let selectedBridge = bridgeCandidates.first(where: fileManager.fileExists(atPath:))
            ?? bridgeCandidates[0]

        var environment = ProcessInfo.processInfo.environment
        let modulesPath = appSupport.appendingPathComponent("antelope_modules", isDirectory: true).path
        if let resources, selectedPython.hasPrefix(resources.path) {
            let pythonRoot = resources.appendingPathComponent("python", isDirectory: true)
            let standardLibrary = pythonRoot.appendingPathComponent("lib/python3.8", isDirectory: true)
            environment["PYTHONHOME"] = pythonRoot.path
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            environment["PYTHONPATH"] = [
                standardLibrary.path,
                standardLibrary.appendingPathComponent("lib-dynload").path,
                standardLibrary.appendingPathComponent("site-packages").path,
            ].joined(separator: ":")
        }
        return (selectedPython, selectedBridge, modulesPath, appSupport, environment)
    }
}
