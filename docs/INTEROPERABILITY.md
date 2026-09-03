# Interoperability Scope and Provenance

MK-OrbitControl is an independent, unofficial client for a narrow set of monitor controls on compatible Antelope Synergy Core hardware. It complements the official Antelope software and does not provide device setup, routing, firmware, licensing, or account functions.

## Implementation boundary

The current native client was implemented from observable input/output behaviour of a lawfully installed local device service and connected hardware. Its public source and distribution:

- send only volume, mute, dim, and mono commands for explicitly mapped outputs;
- connect only to the Antelope service on the local loopback interface;
- use a small length-prefixed JSON request and state-confirmation format;
- do not contain, copy, extract, translate, decompile, disassemble, bundle, or load Antelope executables or bytecode;
- do not use Antelope source code, private keys, credentials, firmware, or confidential documentation;
- do not bypass product activation, licensing, access control, or copy protection.

The protocol client is deliberately limited to what the application needs for hardware interoperability. Contributions must preserve that boundary. Do not submit proprietary files, extracted modules, disassembly, leaked documentation, credentials, serial numbers, or logs containing personal data.

## Project history

An earlier public beta used locally extracted compatibility modules at runtime. That architecture is not present in the current source or release candidate and must not be reintroduced. The native implementation replaces it specifically to reduce security, distribution, dependency, and intellectual-property risk.

## Names and affiliation

“Antelope Audio” and “Synergy Core” identify the products with which compatibility is sought. MK-OrbitControl is not affiliated with, endorsed by, sponsored by, or supported by Antelope Audio. No Antelope logo or product artwork is distributed by this project.

This document records technical scope and provenance; it is not a claim of legal immunity. Laws and licence terms can vary by jurisdiction. Maintainers should obtain qualified legal advice before materially expanding the protocol surface or commercialising the project.
