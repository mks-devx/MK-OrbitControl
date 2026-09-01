# Security Policy

## Supported version

Security fixes are applied to the current `main` branch. There is no public binary release yet.

## Reporting a vulnerability

Please use [GitHub private vulnerability reporting](https://github.com/mks-devx/MK-OrbitControl/security/advisories/new). Do not disclose a suspected vulnerability in a public issue.

Include the affected version, macOS version, device model, reproduction steps, impact, and any suggested mitigation. Do not include real credentials, authentication tokens, proprietary Antelope modules, or personal data.

## Security boundaries

MK-OrbitControl's command bridge is designed to listen only on `127.0.0.1` and requires a per-install authentication token stored with owner-only permissions. Extracted Antelope compatibility modules remain local and must never be committed or attached to an issue.
