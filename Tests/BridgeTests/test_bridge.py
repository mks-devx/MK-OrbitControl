import importlib.util
import os
import pathlib
import socket
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("mk_orbit_bridge", ROOT / "bridge.py")
BRIDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIDGE)


class BridgeValidationTests(unittest.TestCase):
    def test_dynamic_port_candidates_include_shifted_device_endpoint(self):
        ports = BRIDGE.candidate_ports()
        self.assertEqual(ports[:6], [2024, 2021, 2023, 2022, 2025, 2020])
        self.assertIn(2027, ports)
        self.assertEqual(len(ports), len(set(ports)))

    def test_accepts_authenticated_supported_command(self):
        self.assertEqual(
            BRIDGE.validate_command(
                {"cmd": "set_volume", "ch": 0, "val": 40, "token": "a" * 64},
                "a" * 64,
            ),
            ("set_volume", 0, 40),
        )

    def test_rejects_missing_or_incorrect_authentication(self):
        for token in (None, "", "b" * 64):
            message = {"cmd": "set_mute", "ch": 1, "val": 1}
            if token is not None:
                message["token"] = token
            with self.assertRaisesRegex(ValueError, "unauthorized"):
                BRIDGE.validate_command(message, "a" * 64)

    def test_rejects_unknown_channels_commands_and_ranges(self):
        invalid_messages = [
            {"cmd": "set_volume", "ch": 3, "val": 40},
            {"cmd": "delete_all", "ch": 0, "val": 1},
            {"cmd": "set_volume", "ch": 0, "val": 97},
            {"cmd": "set_mute", "ch": 0, "val": 2},
        ]
        for message in invalid_messages:
            with self.assertRaises(ValueError):
                BRIDGE.validate_command(message)

    def test_natural_report_version_sorting(self):
        versions = ["report_format_2.9", "report_format_2.10", "report_format_1.99"]
        versions.sort(key=BRIDGE.natural_sort_key, reverse=True)
        self.assertEqual(versions[0], "report_format_2.10")

    def test_accepts_compact_cyclic_server_greeting(self):
        greeting = b'{"type": "cyclic", "protocol_version": 1, "contents": {}}'
        self.assertLess(len(greeting), 500)
        self.assertTrue(BRIDGE.is_cyclic_greeting(greeting))
        self.assertFalse(BRIDGE.is_cyclic_greeting(b'{"type": "notification"}'))

    def test_recv_exact_handles_fragmented_frames(self):
        reader, writer = socket.socketpair()
        self.addCleanup(reader.close)
        self.addCleanup(writer.close)
        writer.sendall(b"ab")
        writer.sendall(b"cdef")
        self.assertEqual(BRIDGE.recv_exact(reader, 6), b"abcdef")

    def test_expected_runtime_directory_does_not_use_process_home(self):
        self.assertEqual(
            BRIDGE.expected_runtime_directory("/trusted-home"),
            "/trusted-home/Library/Application Support/MK-OrbitControl",
        )

    def test_private_runtime_paths_reject_links_and_shared_writes(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            runtime = pathlib.Path(temporary_root) / "runtime"
            modules = runtime / "antelope_modules"
            runtime.mkdir(mode=0o700)
            modules.mkdir(mode=0o700)

            self.assertEqual(
                BRIDGE.validate_private_path(str(modules), str(runtime), True),
                os.path.realpath(modules),
            )

            modules.chmod(0o722)
            with self.assertRaisesRegex(RuntimeError, "writable by another user"):
                BRIDGE.validate_private_path(str(modules), str(runtime), True)
            modules.chmod(0o700)

            linked_modules = runtime / "linked-modules"
            os.symlink(modules, linked_modules)
            with self.assertRaisesRegex(RuntimeError, "symbolic link"):
                BRIDGE.validate_private_path(str(linked_modules), str(runtime), True)

    def test_private_runtime_file_must_be_regular_and_owner_only(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            runtime = pathlib.Path(temporary_root) / "runtime"
            runtime.mkdir(mode=0o700)
            bytecode = runtime / "module.pyc"
            bytecode.write_bytes(b"test")
            bytecode.chmod(0o600)

            self.assertEqual(
                BRIDGE.validate_private_path(str(bytecode), str(runtime), False),
                os.path.realpath(bytecode),
            )

            bytecode.chmod(0o666)
            with self.assertRaisesRegex(RuntimeError, "writable by another user"):
                BRIDGE.validate_private_path(str(bytecode), str(runtime), False)


if __name__ == "__main__":
    unittest.main()
