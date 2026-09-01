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

Channel IDs used by the app: 0=MON A, 1=HP1, 2=HP2, 5=MON B
"""
import sys
import os
import json
import types
import importlib.machinery
import importlib.util
import pwd
import stat
import struct
import socket
import time
import hmac
import re


def expected_runtime_directory(home=None):
    """Return the per-user runtime root without trusting process environment."""
    trusted_home = home if home is not None else pwd.getpwuid(os.getuid()).pw_dir
    return os.path.realpath(
        os.path.join(trusted_home, "Library", "Application Support", "MK-OrbitControl")
    )


RUNTIME_DIR = expected_runtime_directory()
MODULES_DIR = os.path.join(RUNTIME_DIR, "antelope_modules")
SERVER_HOST = "127.0.0.1"
VALID_COMMANDS = {"set_volume", "set_mute", "set_dim", "set_mono"}
VALID_CHANNELS = {0, 1, 2, 5}
MAX_COMMAND_BYTES = 4096
PREFERRED_SERVER_PORTS = (2024, 2021, 2023, 2022, 2025, 2020)


def validate_private_path(path, trusted_root, require_directory):
    """Reject links, foreign ownership, writable paths, and root escapes."""
    real_root = os.path.realpath(trusted_root)
    real_path = os.path.realpath(path)
    if os.path.commonpath((real_root, real_path)) != real_root:
        raise RuntimeError("Runtime path escapes the trusted application directory")

    details = os.lstat(path)
    if stat.S_ISLNK(details.st_mode):
        raise RuntimeError("Runtime path must not be a symbolic link")
    if details.st_uid != os.getuid():
        raise RuntimeError("Runtime path is not owned by the current user")
    if details.st_mode & 0o022:
        raise RuntimeError("Runtime path is writable by another user")
    if require_directory and not stat.S_ISDIR(details.st_mode):
        raise RuntimeError("Expected a runtime directory")
    if not require_directory and not stat.S_ISREG(details.st_mode):
        raise RuntimeError("Expected a regular runtime file")
    return real_path


def validate_modules_directory(path=MODULES_DIR):
    validate_private_path(RUNTIME_DIR, RUNTIME_DIR, require_directory=True)
    return validate_private_path(path, RUNTIME_DIR, require_directory=True)


def load_trusted_bytecode_module(module, relative_path):
    modules_root = validate_modules_directory()
    bytecode_path = os.path.join(modules_root, relative_path)
    trusted_path = validate_private_path(
        bytecode_path, modules_root, require_directory=False
    )
    loader = importlib.machinery.SourcelessFileLoader(module.__name__, trusted_path)
    module.__file__ = trusted_path
    module.__loader__ = loader
    module.__spec__ = importlib.util.spec_from_loader(module.__name__, loader)
    loader.exec_module(module)


def candidate_ports():
    """Return likely ports first, then Antelope's dynamic local port range."""
    return list(PREFERRED_SERVER_PORTS) + [
        port for port in range(2020, 2101) if port not in PREFERRED_SERVER_PORTS
    ]


def validate_command(message, expected_token=None):
    """Return a validated (command, channel, value) tuple."""
    command = message.get("cmd", "")
    channel = int(message.get("ch", -1))
    value = int(message.get("val", -1))
    if expected_token is not None:
        supplied_token = str(message.get("token", ""))
        if not expected_token or not hmac.compare_digest(supplied_token, expected_token):
            raise ValueError("unauthorized")
    if command not in VALID_COMMANDS:
        raise ValueError("unknown command")
    if channel not in VALID_CHANNELS:
        raise ValueError("invalid channel")
    if command == "set_volume" and not 0 <= value <= 96:
        raise ValueError("volume must be between 0 and 96")
    if command != "set_volume" and value not in (0, 1):
        raise ValueError("toggle value must be 0 or 1")
    return command, channel, value


def find_device():
    """Auto-detect device slug and report format from Antelope installation."""
    base = "/Users/Shared/.AntelopeAudio"
    if not os.path.exists(base):
        return None, None, None, None

    candidates = []
    for entry in sorted(os.listdir(base)):
        panels_dir = os.path.join(base, entry, "panels")
        if not os.path.isdir(panels_dir):
            continue
        if entry in ("managerserver", "antelopelauncher"):
            continue
        formats = [name for name in os.listdir(panels_dir) if name.startswith("report_format_")]
        if formats:
            formats.sort(key=natural_sort_key, reverse=True)
            candidates.append((entry, os.path.join(panels_dir, formats[0])))

    if not candidates:
        return None, None, None, None

    device_name, serial = get_device_info_from_server()
    if device_name:
        normalized_name = normalize_device_name(device_name)
        matches = [item for item in candidates if normalize_device_name(item[0]) in normalized_name]
        if len(matches) == 1:
            slug, report_path = matches[0]
            return slug, report_path, device_name, serial or "0000000000000"

    # Multiple unmatched panels are unsafe because their report formats and
    # channel maps may differ. Only fall back when exactly one panel exists.
    if len(candidates) == 1:
        slug, report_path = candidates[0]
        return slug, report_path, device_name or slug, serial or "0000000000000"
    return None, None, None, None


def natural_sort_key(value):
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", value)]


def normalize_device_name(value):
    return "".join(character for character in value.lower() if character.isalnum())


def is_cyclic_greeting(data):
    """Accept the compact cyclic greeting used by newer Antelope servers."""
    return b'"type": "cyclic"' in data or b'"type":"cyclic"' in data


def get_device_info_from_server():
    """Read device name and serial from the admin server welcome message."""
    for port in candidate_ports():
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2)
            s.connect((SERVER_HOST, port))
            h = s.recv(4)
            if len(h) < 4:
                s.close()
                continue
            total_length = struct.unpack(">I", h)[0]
            payload_length = total_length - 4
            if not 0 < payload_length <= 2_000_000 - 4:
                s.close()
                continue
            data = recv_exact(s, payload_length)
            s.close()
            if data is None:
                continue
            text = data.decode("utf-8", errors="replace")
            if "notification" in text and "Plugged devices" in text:
                # Parse device name and serial
                # Format: "DeviceName with SN:1234567890"
                # Parse JSON to get the contents text
                try:
                    import json as _json
                    msg = _json.loads(text[:text.rindex('}') + 1])
                    contents = msg.get("contents", text)
                except Exception:
                    contents = text
                match = re.search(r"([A-Za-z][A-Za-z0-9_]+)\s+with\s+SN:(\d+)", contents)
                if match:
                    return match.group(1), match.group(2)
        except Exception:
            try:
                s.close()
            except Exception:
                pass
    return None, None


DEVICE_SLUG = None
REPORT_FORMAT_PATH = None
DEVICE_NAME = None
DEVICE_SERIAL = None


def setup_environment():
    global DEVICE_SLUG, REPORT_FORMAT_PATH, DEVICE_NAME, DEVICE_SERIAL
    if DEVICE_SLUG is None:
        DEVICE_SLUG, REPORT_FORMAT_PATH, DEVICE_NAME, DEVICE_SERIAL = find_device()
    if not DEVICE_SLUG or not REPORT_FORMAT_PATH:
        raise RuntimeError("Cannot safely identify one installed Antelope device panel")
    try:
        modules_root = validate_modules_directory()
    except (OSError, RuntimeError) as error:
        raise RuntimeError("Antelope modules are missing or unsafe; run setup.sh again") from error
    sys.path.insert(0, modules_root)
    os.environ["SETTINGSPY_MODULE"] = ""
    os.environ["SETTINGSPY_CATALOG"] = ""
    from settingspy import spy
    spy["DEVICE_SLUG"] = DEVICE_SLUG
    spy["USE_DEVICE"] = True
    spy["FORMATTER_FULL"] = False


def fix_circular_imports():
    import antelope.dev.device_info

    reports_mod = types.ModuleType("antelope.dev.reports")
    reports_mod.__path__ = []
    reports_mod.__package__ = "antelope.dev"
    reports_mod.ReportFactory = type("DummyRF", (), {})
    reports_mod.Request = type("DummyReq", (), {})
    sys.modules["antelope.dev.reports"] = reports_mod

    beacon_mod = types.ModuleType("antelope.networking.beacon")
    beacon_mod.__path__ = []
    beacon_mod.__package__ = "antelope.networking"
    beacon_mod.ServiceInfo = type("SI", (), {})
    beacon_mod.BeaconBrowser = type("BB", (), {})
    beacon_mod.BeaconServer = type("BS", (), {})
    sys.modules["antelope.networking.beacon"] = beacon_mod

    import antelope.dev.base

    for module, relative_path in [
        (reports_mod, "antelope/dev/reports.pyc"),
        (beacon_mod, "antelope/networking/beacon.pyc"),
    ]:
        load_trusted_bytecode_module(module, relative_path)


class FakeServiceInfo:
    def __init__(self, host=SERVER_HOST, port=2021, serial=None):
        self.port = port
        self.name = DEVICE_NAME + "._antelope_control._tcp.local."
        self.type = "_antelope_control._tcp.local."
        self.ip = host
        self.server = host
        self.address = socket.inet_aton(host)
        actual_serial = serial or DEVICE_SERIAL
        self.properties = {
            "device_name": DEVICE_NAME,
            "serial_number": actual_serial,
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
    for port in candidate_ports():
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2)
            s.connect((SERVER_HOST, port))
            h = recv_exact(s, 4)
            if h is None:
                s.close()
                continue
            total_length = struct.unpack(">I", h)[0]
            payload_length = total_length - 4
            if not 0 < payload_length <= 2_000_000 - 4:
                s.close()
                continue
            data = recv_exact(s, payload_length)
            s.close()
            if data is not None and is_cyclic_greeting(data):
                return port
        except Exception:
            try:
                s.close()
            except Exception:
                pass
    return None


def recv_exact(sock, count):
    data = bytearray()
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            return None
        data.extend(chunk)
    return bytes(data)


def connect():
    from antelope.dev.remote_device import RemoteDevice

    port = find_device_port()
    if port is None:
        raise RuntimeError("Cannot find Antelope device server")

    with open(REPORT_FORMAT_PATH) as f:
        report_format = json.load(f)

    si = FakeServiceInfo(port=port)
    device = RemoteDevice(si)
    if hasattr(device, "try_connect"):
        # Older Antelope panels connect and start in two steps.
        device.try_connect(report_format=report_format)
        device.start()
    else:
        # Current panels accept the report format directly in start().
        device.start(report_format=report_format)
    time.sleep(2)

    is_running = getattr(device, "is_running", None)
    if callable(is_running):
        running = is_running()
    else:
        running = bool(getattr(device, "is_alive", False))
    is_connected = getattr(device, "is_connected", None)
    if callable(is_connected):
        connected = is_connected()
    elif is_connected is None:
        connected = running
    else:
        connected = bool(is_connected)
    if not running or not connected:
        raise RuntimeError("RemoteDevice failed to start")

    return device


def run_daemon():
    """Stay connected. Listen on TCP port 17580 for JSON commands."""
    auth_token = os.environ.get("MK_ORBIT_AUTH_TOKEN", "")
    if len(auth_token) < 32:
        raise RuntimeError("MK_ORBIT_AUTH_TOKEN is missing or invalid")

    setup_environment()
    fix_circular_imports()
    # Keep the command endpoint alive even when Antelope is temporarily down.
    # A command can then trigger recovery instead of finding a dead bridge.
    device = None
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 17580))
    srv.listen(5)
    srv.settimeout(1)

    sys.stderr.write("Bridge daemon listening on 127.0.0.1:17580\n")
    sys.stderr.flush()

    try:
        device = connect()
    except Exception as connect_error:
        sys.stderr.write("Initial Antelope connection failed: %s\n" % connect_error)
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
                if len(data) > MAX_COMMAND_BYTES:
                    raise ValueError("command is too large")
                if b"\n" in data:
                    break

            line = data.decode("utf-8", errors="replace").strip()
            if not line:
                client.close()
                continue

            cmd, ch, val = validate_command(json.loads(line), auth_token)
            result = False
            if device is not None:
                try:
                    result = device.request(cmd, ch, val, timeout=5)
                except Exception:
                    result = False

            if not result:
                # One failed monitor command is enough evidence to replace the
                # stale RemoteDevice session. Reconnect and retry once.
                if device is not None:
                    try:
                        device.stop()
                    except Exception:
                        pass
                    device = None
                try:
                    device = connect()
                    result = device.request(cmd, ch, val, timeout=5)
                except Exception as reconnect_error:
                    resp = '{"ok":false,"error":' + json.dumps(
                        "reconnect failed: " + str(reconnect_error)
                    ) + '}\n'
                else:
                    resp = '{"ok":true}\n' if result else '{"ok":false}\n'
            else:
                resp = '{"ok":true}\n'

            client.sendall(resp.encode())
            client.close()
        except Exception as e:
            try:
                client.sendall(('{"ok":false,"error":' + json.dumps(str(e)) + '}\n').encode())
                client.close()
            except Exception:
                pass

    srv.close()
    if device is not None:
        device.stop()


def run_single():
    """Single command mode — connect, send, disconnect."""
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]
    channel_id = int(sys.argv[2])
    value = int(sys.argv[3])

    try:
        command, channel_id, value = validate_command(
            {"cmd": command, "ch": channel_id, "val": value}
        )
    except ValueError as error:
        print(str(error))
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

    sys.stdout.write('{"ready":true}\n')
    sys.stdout.flush()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            cmd, ch, val = validate_command(json.loads(line))
            result = device.request(cmd, ch, val, timeout=5)
            sys.stdout.write('{"ok":true}\n' if result else '{"ok":false}\n')
        except Exception as error:
            sys.stdout.write('{"ok":false,"error":' + json.dumps(str(error)) + '}\n')
        sys.stdout.flush()

    device.stop()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--daemon":
        run_daemon()
    elif len(sys.argv) > 1 and sys.argv[1] == "--stdin":
        run_stdin()
    else:
        run_single()
