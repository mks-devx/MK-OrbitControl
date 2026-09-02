import importlib.util
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "mk_release_tools", ROOT / "scripts" / "release_tools.py"
)
TOOLS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOLS)


class ReleaseToolsTests(unittest.TestCase):
    def test_sanitise_neutralises_private_home_without_changing_file_size(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = pathlib.Path(temporary_root)
            binary = root / "runtime.bin"
            private_home = b"/" + b"Users" + b"/private-builder"
            original = b"prefix:" + private_home + b"/.pyenv/runtime\x00suffix"
            binary.write_bytes(original)

            TOOLS.sanitise_home_paths(root)

            sanitised = binary.read_bytes()
            self.assertEqual(len(sanitised), len(original))
            self.assertNotIn(private_home, sanitised)
            self.assertIn(b"/.pyenv/runtime", sanitised)

    def test_sanitise_preserves_users_shared(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = pathlib.Path(temporary_root)
            source = root / "source.txt"
            source.write_bytes(b"/Users/Shared/.AntelopeAudio")

            TOOLS.sanitise_home_paths(root)

            self.assertEqual(source.read_bytes(), b"/Users/Shared/.AntelopeAudio")

    def test_artifact_audit_rejects_private_paths_and_credentials(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = pathlib.Path(temporary_root)
            private_home = b"/" + b"Users" + b"/private"
            email = b"person" + b"@" + b"example.invalid"
            token = b"gh" + b"p_" + b"abcdefghijklmnopqrstuvwxyz123456"
            (root / "bad.txt").write_bytes(
                private_home + b"/repo " + email + b" " + token
            )
            with self.assertRaisesRegex(TOOLS.ReleaseCheckError, "artifact audit failed"):
                TOOLS.audit_artifact(root, [])

    def test_artifact_audit_requires_licences_and_rejects_python_cache(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = pathlib.Path(temporary_root)
            (root / "module.pyc").write_bytes(b"bytecode")
            with self.assertRaisesRegex(TOOLS.ReleaseCheckError, "Python cache residue"):
                TOOLS.audit_artifact(root, ["Licences/Required.txt"])

    def test_artifact_audit_rejects_personal_consumer_email(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = pathlib.Path(temporary_root)
            address = b"private.person" + b"@" + b"gmail.com"
            (root / "metadata.txt").write_bytes(address)
            with self.assertRaisesRegex(
                TOOLS.ReleaseCheckError, "personal email address"
            ):
                TOOLS.audit_artifact(root, [])

    def test_artifact_audit_allows_upstream_contact_email(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = pathlib.Path(temporary_root)
            address = b"maintainer" + b"@" + b"example.org"
            (root / "licence.txt").write_bytes(address)
            TOOLS.audit_artifact(root, [])

    def test_artifact_audit_allows_vendored_consumer_email(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = pathlib.Path(temporary_root)
            source = root / "Contents" / "Resources" / "python" / "module.py"
            source.parent.mkdir(parents=True)
            address = b"upstream.author" + b"@" + b"gmail.com"
            source.write_bytes(address)
            TOOLS.audit_artifact(root, [])

    def test_artifact_audit_allows_vendored_email_in_nested_app(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = pathlib.Path(temporary_root)
            source = (
                root
                / "Product.app"
                / "Contents"
                / "Resources"
                / "python"
                / "module.py"
            )
            source.parent.mkdir(parents=True)
            address = b"upstream.author" + b"@" + b"gmail.com"
            source.write_bytes(address)
            TOOLS.audit_artifact(root, [])

    def test_artifact_audit_accepts_sanitised_package(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = pathlib.Path(temporary_root)
            licence = root / "Licences" / "Required.txt"
            licence.parent.mkdir()
            licence.write_text("licence", encoding="utf-8")
            (root / "runtime.bin").write_bytes(b"/opt/____________/.pyenv/runtime")

            TOOLS.audit_artifact(root, ["Licences/Required.txt"])


if __name__ == "__main__":
    unittest.main()
