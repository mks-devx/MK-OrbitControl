#!/usr/bin/env python3.8
"""
MK-AntelopeControl Bridge
Connects to Antelope Audio server using their own RemoteDevice API.
Requires Python 3.8 (for PyInstaller bytecode compatibility).

Single command mode:
    python3.8 bridge.py set_volume 0 44

Daemon mode (stays connected, reads JSON commands from stdin):
    python3.8 bridge.py --daemon
    Then write: {"cmd":"set_volume","ch":0,"val":44}
    Responds:   {"ok":true}

Channel IDs: 0=MON A, 1=MON B, 2=HP1, 3=HP2, 4=Line
"""
import sys
import os
import json
import types
import marshal
import struct
import socket
import time

MODULES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "antelope_modules")
REPORT_FORMAT_PATH = "/Users/Shared/.AntelopeAudio/orionstudioiii/panels/report_format_2.3.1"
SERVER_HOST = "127.0.0.1"


def setup_environment():
    sys.path.insert(0, MODULES_DIR)
    os.environ["SETTINGSPY_MODULE"] = ""
    os.environ["SETTINGSPY_CATALOG"] = ""
    from settingspy import spy
    spy["DEVICE_SLUG"] = "orionstudioiii"
    spy["USE_DEVICE"] = True
    spy["FORMATTER_FULL"] = False


def fix_circular_imports():
    import antelope.dev.device_info

    reports_mod = types.ModuleType("antelope.dev.reports")
    reports_mod.__file__ = os.path.join(MODULES_DIR, "antelope/dev/reports.pyc")
    reports_mod.__path__ = []
    reports_mod.__package__ = "antelope.dev"
    reports_mod.ReportFactory = type("DummyRF", (), {})
    reports_mod.Request = type("DummyReq", (), {})
    sys.modules["antelope.dev.reports"] = reports_mod

    beacon_mod = types.ModuleType("antelope.networking.beacon")
    beacon_mod.__file__ = os.path.join(MODULES_DIR, "antelope/networking/beacon.pyc")
    beacon_mod.__path__ = []
    beacon_mod.__package__ = "antelope.networking"
    beacon_mod.ServiceInfo = type("SI", (), {})
    beacon_mod.BeaconBrowser = type("BB", (), {})
    beacon_mod.BeaconServer = type("BS", (), {})
    sys.modules["antelope.networking.beacon"] = beacon_mod

    import antelope.dev.base

    for mod, path in [(reports_mod, "antelope/dev/reports.pyc"),
                      (beacon_mod, "antelope/networking/beacon.pyc")]:
        pyc = os.path.join(MODULES_DIR, path)
        with open(pyc, "rb") as f:
            f.read(16)
            code = marshal.loads(f.read())
        mod.__dict__["__name__"] = mod.__name__
        exec(code, mod.__dict__)


class FakeServiceInfo:
    def __init__(self, host=SERVER_HOST, port=2021, serial="2913921000101"):
        self.port = port
        self.name = "OrionStudio_III._antelope_control._tcp.local."
        self.type = "_antelope_control._tcp.local."
        self.ip = host
        self.server = host
        self.address = socket.inet_aton(host)
        self.properties = {
            "device_name": "OrionStudio_III",
            "serial_number": serial,
            "hardware_version": "1.0",
            "firmware_version": "1.0",
            "connection_type": "usb",
            "vendor_id": "0x2982",
            "product_id": "0x1969",
            "server_version": "1.8.20",
            "mode": "app",
        }
        self.text = self.properties
        self._addresses = [socket.inet_aton(host)]

    def parsed_addresses(self):
        return [self.ip]

    def __getattr__(self, name):
        if name in self.__dict__.get("properties", {}):
            return self.properties[name]
        raise AttributeError(name)


def find_device_port():
    for port in [2021, 2023, 2022, 2024, 2025, 2020]:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2)
            s.connect((SERVER_HOST, port))
            h = s.recv(4)
            if len(h) < 4:
                s.close()
                continue
            length = struct.unpack(">I", h)[0]
            data = b""
            while len(data) < length:
                chunk = s.recv(min(8192, length - len(data)))
                if not chunk:
                    break
                data += chunk
            s.close()
            if b"cyclic" in data and length > 500:
                return port
        except Exception:
            try:
                s.close()
            except Exception:
                pass
    return None


def connect():
    from antelope.dev.remote_device import RemoteDevice

    port = find_device_port()
    if port is None:
        raise RuntimeError("Cannot find Antelope device server")

    with open(REPORT_FORMAT_PATH) as f:
        report_format = json.load(f)

    si = FakeServiceInfo(port=port)
    device = RemoteDevice(si)
    device.try_connect(report_format=report_format)
    device.start()
    time.sleep(2)

    if not device.is_running():
        raise RuntimeError("RemoteDevice failed to start")

    return device


def run_daemon():
    """Stay connected. Listen on TCP port 17580 for JSON commands."""
    setup_environment()
    fix_circular_imports()
    device = connect()

    valid = {"set_volume", "set_mute", "set_dim", "set_mono", "set_talk"}

    # Start TCP server on localhost
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 17580))
    srv.listen(5)
    srv.settimeout(1)

    sys.stderr.write("Bridge daemon listening on 127.0.0.1:17580\n")
    sys.stderr.flush()

    while True:
        try:
            client, addr = srv.accept()
        except socket.timeout:
            continue
        except Exception:
            break

        try:
            client.settimeout(5)
            data = b""
            while True:
                chunk = client.recv(4096)
                if not chunk:
                    break
                data += chunk
                if b"\n" in data:
                    break

            line = data.decode("utf-8", errors="replace").strip()
            if not line:
                client.close()
                continue

            msg = json.loads(line)
            cmd = msg.get("cmd", "")
            ch = int(msg.get("ch", 0))
            val = int(msg.get("val", 0))

            if cmd in valid:
                result = device.request(cmd, ch, val, timeout=5)
                resp = '{"ok":true}\n' if result else '{"ok":false}\n'
            else:
                resp = '{"ok":false,"error":"unknown"}\n'

            client.sendall(resp.encode())
            client.close()
        except Exception as e:
            try:
                client.sendall(('{"ok":false,"error":' + json.dumps(str(e)) + '}\n').encode())
                client.close()
            except Exception:
                pass

    srv.close()
    device.stop()


def run_single():
    """Single command mode — connect, send, disconnect."""
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]
    channel_id = int(sys.argv[2])
    value = int(sys.argv[3])

    valid = ["set_volume", "set_mute", "set_dim", "set_mono", "set_talk"]
    if command not in valid:
        print("Unknown command: " + command)
        sys.exit(1)

    setup_environment()
    fix_circular_imports()

    device = connect()
    try:
        result = device.request(command, channel_id, value, timeout=5)
        print(command + "(" + str(channel_id) + ", " + str(value) + ") => " + str(result))
    finally:
        device.stop()


def run_stdin():
    """Stdin/stdout mode — stays connected, reads JSON lines from stdin."""
    setup_environment()
    fix_circular_imports()
    device = connect()

    valid = {"set_volume", "set_mute", "set_dim", "set_mono", "set_talk"}

    sys.stdout.write('{"ready":true}\n')
    sys.stdout.flush()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
            cmd = msg.get("cmd", "")
            ch = int(msg.get("ch", 0))
            val = int(msg.get("val", 0))
            if cmd in valid:
                result = device.request(cmd, ch, val, timeout=5)
                sys.stdout.write('{"ok":true}\n' if result else '{"ok":false}\n')
            else:
                sys.stdout.write('{"ok":false}\n')
        except Exception:
            sys.stdout.write('{"ok":false}\n')
        sys.stdout.flush()

    device.stop()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--daemon":
        run_daemon()
    elif len(sys.argv) > 1 and sys.argv[1] == "--stdin":
        run_stdin()
    else:
        run_single()
