# Security Policy

## Supported version

Security fixes are applied to the current `main` branch and the latest GitHub Release.

## Reporting a vulnerability

Please use [GitHub private vulnerability reporting](https://github.com/mks-devx/MK-OrbitControl/security/advisories/new). Do not disclose a suspected vulnerability in a public issue.

Include the affected version, macOS version, device model, reproduction steps, impact, and any suggested mitigation. Do not include credentials, serial numbers, account information, private logs, or other personal data.

## Security boundaries

MK-OrbitControl is a user-level app. It connects directly to a local Antelope device service on `127.0.0.1` and exposes only four validated monitor commands: volume, mute, dim, and mono. It does not install a helper, open a listening port, accept inbound network connections, require administrator access, or copy and load Antelope executable code.

The client verifies a valid cyclic device-state message before sending a command, restricts commands to known output mappings, bounds all values, and waits for matching device-state confirmation. Network access remains local to the Mac; the app includes no analytics or cloud service.

The official distribution is Developer ID signed and Apple notarised. Release automation rejects private home paths, personal consumer email addresses, credential-like content, Python bytecode, escaping symlinks, dependency drift, and missing licence files before packaging.

The native interoperability scope and implementation provenance are documented in [docs/INTEROPERABILITY.md](docs/INTEROPERABILITY.md).
