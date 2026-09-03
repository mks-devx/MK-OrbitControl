# Contributing to MK-OrbitControl

Thank you for helping improve MK-OrbitControl. Keep contributions small, testable, and within the project's monitor-control purpose.

## Interoperability boundary

Contributions must follow [docs/INTEROPERABILITY.md](docs/INTEROPERABILITY.md). Submit only work you have the right to publish. Do not include or derive a patch from proprietary executables, extracted modules, bytecode, firmware, disassembly, leaked or confidential documentation, credentials, private keys, serial numbers, or access-control bypasses.

Protocol changes must be limited to observable behaviour needed for interoperability, include a clear provenance note, and add a regression test. Do not expand into device activation, licensing, firmware, account access, or unrelated control surfaces.

## Privacy

Use synthetic values in tests and reports. Remove usernames, personal paths, email addresses, account data, device serial numbers, tokens, and other identifying information. Do not attach complete diagnostic archives or third-party application files to public issues or pull requests.

Report security problems through [GitHub private vulnerability reporting](https://github.com/mks-devx/MK-OrbitControl/security/advisories/new).

## Validation

Run before opening a pull request:

```bash
swift test
python3 -m unittest discover -s Tests/ReleaseTests -v
bash scripts/interoperability-audit.sh
bash scripts/privacy-audit.sh HEAD
```

Hardware-dependent changes must state the exact model tested and whether commands were exercised at a safe monitoring level. Do not claim compatibility for untested models.

By contributing, you confirm that the contribution is your original work or that you have sufficient rights to submit it under the project's MIT Licence.
