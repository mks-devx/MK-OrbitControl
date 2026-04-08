import Foundation

class AntelopeCommander {
    private let pythonPath: String
    private let bridgePath: String
    private let daemonPort: UInt16 = 17580
    private var daemonProcess: Process?

    init() {
        self.pythonPath = NSHomeDirectory() + "/.pyenv/versions/3.8.20/bin/python3.8"
        self.bridgePath = NSHomeDirectory() + "/Developer/MK-AntelopeControl/bridge.py"
    }

    func startDaemon() {
        DispatchQueue.global(qos: .utility).async { [self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: pythonPath)
            proc.arguments = [bridgePath, "--daemon"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                daemonProcess = proc
            } catch { }
        }
    }

    func stopDaemon() {
        daemonProcess?.terminate()
        daemonProcess = nil
    }

    private func sendViaDaemon(_ cmd: String, ch: Int, val: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        // Prevent TIME_WAIT buildup — close socket immediately
        var lin = linger(l_onoff: 1, l_linger: 0)
        setsockopt(fd, SOL_SOCKET, SO_LINGER, &lin, socklen_t(MemoryLayout<linger>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = daemonPort.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let cr = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard cr == 0 else { close(fd); return false }

        let msg = Array("{\"cmd\":\"\(cmd)\",\"ch\":\(ch),\"val\":\(val)}\n".utf8)
        _ = msg.withUnsafeBytes { ptr in
            send(fd, ptr.baseAddress!, msg.count, 0)
        }

        var buf = [UInt8](repeating: 0, count: 256)
        var tv = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let n = recv(fd, &buf, 256, 0)
        close(fd)

        if n > 0 {
            let resp = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
            return resp.contains("true")
        }
        return false
    }

    // MARK: - Public API

    func setVolume(channel: OutputChannel, value: Int, completion: @escaping (Bool) -> Void = { _ in }) {
        let v = max(0, min(96, value))
        DispatchQueue.global(qos: .userInteractive).async {
            let ok = self.sendViaDaemon("set_volume", ch: channel.rawValue, val: v)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func setMute(channel: OutputChannel, muted: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        DispatchQueue.global(qos: .userInteractive).async {
            let ok = self.sendViaDaemon("set_mute", ch: channel.rawValue, val: muted ? 1 : 0)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func setDim(channel: OutputChannel, dimmed: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        DispatchQueue.global(qos: .userInteractive).async {
            let ok = self.sendViaDaemon("set_dim", ch: channel.rawValue, val: dimmed ? 1 : 0)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func setMono(channel: OutputChannel, mono: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        DispatchQueue.global(qos: .userInteractive).async {
            let ok = self.sendViaDaemon("set_mono", ch: channel.rawValue, val: mono ? 1 : 0)
            DispatchQueue.main.async { completion(ok) }
        }
    }
}
