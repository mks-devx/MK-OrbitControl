#!/usr/bin/env python3
"""Deterministic dependency and privacy gates for MK-OrbitControl packages."""

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys


PERSONAL_HOME = re.compile(rb"/Users/[^/\x00\s\"']+")
PERSONAL_EMAIL_ADDRESS = re.compile(
    rb"[A-Za-z0-9._%+-]+@(?:gmail|hotmail|outlook|icloud)\.com\b", re.IGNORECASE
)
CREDENTIAL_PATTERNS = (
    re.compile(rb"BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY"),
    re.compile(rb"AKIA[0-9A-Z]{16}"),
    re.compile(rb"gh[pousr]_[A-Za-z0-9_]{20,}"),
    re.compile(rb"sk-[A-Za-z0-9_-]{20,}"),
)
NEUTRAL_HOME_PREFIX = b"/opt/"


class ReleaseCheckError(RuntimeError):
    pass


def load_json(path):
    with path.open("r", encoding="utf-8") as source:
        return json.load(source)


def run_checked(command):
    environment = os.environ.copy()
    environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        env=environment,
    )
    if result.returncode != 0:
        raise ReleaseCheckError("command failed: " + command[0])
    return result.stdout.strip()


def verify_dependencies(manifest_path, package_resolved):
    manifest = load_json(manifest_path)
    for name, expected in sorted(manifest["homebrew"].items()):
        output = run_checked(["brew", "list", "--versions", name]).split()
        actual = output[1] if len(output) >= 2 else "missing"
        if actual != expected:
            raise ReleaseCheckError(
                "%s version mismatch: expected %s, found %s" % (name, expected, actual)
            )

    resolved = load_json(package_resolved)
    pins = {pin["identity"]: pin["state"] for pin in resolved.get("pins", [])}
    for name, expected in sorted(manifest["swiftPackages"].items()):
        state = pins.get(name)
        if state is None:
            raise ReleaseCheckError("Swift package is not resolved: " + name)
        for field in ("version", "revision"):
            if state.get(field) != expected[field]:
                raise ReleaseCheckError(
                    "%s %s mismatch: expected %s, found %s"
                    % (name, field, expected[field], state.get(field, "missing"))
                )

    print("Release dependency manifest verified.")


def iter_regular_files(root):
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            continue
        if path.is_file():
            yield path


def neutral_home(original):
    if len(original) < len(NEUTRAL_HOME_PREFIX):
        raise ReleaseCheckError("cannot neutralise an unexpectedly short home path")
    return NEUTRAL_HOME_PREFIX + (b"_" * (len(original) - len(NEUTRAL_HOME_PREFIX)))


def sanitise_home_paths(root):
    replacements = 0
    touched = 0
    for path in iter_regular_files(root):
        data = path.read_bytes()
        homes = sorted(set(PERSONAL_HOME.findall(data)))
        homes = [home for home in homes if home != b"/Users/Shared"]
        if not homes:
            continue
        for home in homes:
            count = data.count(home)
            data = data.replace(home, neutral_home(home))
            replacements += count
        path.write_bytes(data)
        touched += 1
    print(
        "Neutralised %d private build-path occurrences across %d files."
        % (replacements, touched)
    )


def validate_symlinks(root):
    root_real = root.resolve()
    for path in sorted(root.rglob("*")):
        if not path.is_symlink():
            continue
        target = path.resolve()
        try:
            target.relative_to(root_real)
        except ValueError:
            raise ReleaseCheckError("package contains a symlink escaping its root")


def is_vendored_email_scope(root, path):
    relative = path.relative_to(root).as_posix()
    rooted = "/" + relative
    return (
        "/Contents/Resources/ThirdPartyLicenses/" in rooted
        or relative.startswith("ThirdPartyLicenses/")
    )


def audit_artifact(root, required_licences):
    validate_symlinks(root)
    failures = []
    for path in sorted(root.rglob("*")):
        if path.name == "__pycache__" or path.suffix == ".pyc":
            failures.append("Python cache residue")
            continue
        if path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        private_homes = [
            home for home in PERSONAL_HOME.findall(data) if home != b"/Users/Shared"
        ]
        if private_homes:
            failures.append("private macOS home path")
        if PERSONAL_EMAIL_ADDRESS.search(data) and not is_vendored_email_scope(
            root, path
        ):
            failures.append("personal email address")
        if any(pattern.search(data) for pattern in CREDENTIAL_PATTERNS):
            failures.append("credential-like content")

    for relative in required_licences:
        candidate = root / relative
        if not candidate.is_file() or candidate.stat().st_size == 0:
            failures.append("missing required licence: " + relative)

    if failures:
        unique = sorted(set(failures))
        raise ReleaseCheckError("artifact audit failed: " + "; ".join(unique))
    print("Release artifact privacy and licence audit passed.")


def parse_args():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    dependencies = subparsers.add_parser("verify-dependencies")
    dependencies.add_argument("--manifest", type=pathlib.Path, required=True)
    dependencies.add_argument("--package-resolved", type=pathlib.Path, required=True)

    sanitise = subparsers.add_parser("sanitise")
    sanitise.add_argument("root", type=pathlib.Path)

    audit = subparsers.add_parser("audit")
    audit.add_argument("root", type=pathlib.Path)
    audit.add_argument("--require-licence", action="append", default=[])
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        if args.command == "verify-dependencies":
            verify_dependencies(args.manifest, args.package_resolved)
        elif args.command == "sanitise":
            sanitise_home_paths(args.root)
        elif args.command == "audit":
            audit_artifact(args.root, args.require_licence)
    except (OSError, ReleaseCheckError, ValueError, KeyError, json.JSONDecodeError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
