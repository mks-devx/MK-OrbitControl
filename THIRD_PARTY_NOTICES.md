# Third-Party Notices

MK-OrbitControl distributions include the following third-party components.
Their complete licence texts are bundled inside the application under
`Contents/Resources/ThirdPartyLicenses`.

| Component | Version | Licence | Project |
|---|---:|---|---|
| HotKey | 0.2.1 | MIT | <https://github.com/soffes/HotKey> |
| Python | 3.8.20 | Python Software Foundation Licence | <https://www.python.org/> |
| async-timeout | 5.0.1 | Apache-2.0 | <https://github.com/aio-libs/async-timeout> |
| ifaddr | 0.2.0 | MIT | <https://github.com/pydron/ifaddr> |
| netifaces | 0.11.0 | MIT | <https://pypi.org/project/netifaces/> |
| zeroconf | 0.136.2 | LGPL-2.1-or-later | <https://github.com/python-zeroconf/python-zeroconf> |
| GNU gettext / libintl | 1.0 | GPL-3.0-or-later; bundled library terms apply | <https://www.gnu.org/software/gettext/> |
| OpenSSL | 3.6.3 | Apache-2.0 | <https://www.openssl.org/> |
| XZ Utils / liblzma | 5.8.3 | 0BSD and component-specific free-software licences | <https://tukaani.org/xz/> |

The release manifest in `Config/release-dependencies.json` is authoritative for
the versions accepted by the packaging script. A release build stops when the
local toolchain differs from that manifest so that dependency changes are
reviewed deliberately.
