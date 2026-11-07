# OpenWrt Wi-Fi Coordinator

Coordinated channel selection and client steering for OpenWrt, developed and live-tested on the **Linksys WRT3200ACM with OpenWrt 25.12.6**.

The package combines channel planning, Radio Preference, and a LuCI interface under **Network → Wi-Fi Coordinator**. It uses `usteer` for measurements while keeping competing steering decisions passive. It preserves your Wi-Fi names, passwords, and LAN/WAN topology; automatic operation changes radio channels and widths.

## What it does

- Surveys the surrounding spectrum with paced scans and serving gaps.
- Plans channels and widths jointly, preferring separate spectrum and usable wide channels: 20 MHz on 2.4 GHz; 20/40/80 MHz on 5 GHz.
- Defaults to live driver-derived channel lists for every radio; optional explicit lists restrict selection.
- Keeps evidence for each alternative even when different channels take turns ranking first.
- Uses live channel-switch announcements where supported. Otherwise it tries a compatible client handoff, then briefly restarts only the changing radio if clients remain.
- Checks reconnection and service after a change, with rollback and temporary exclusions after failures.
- Coordinates DFS preparation without bypassing kernel radar restrictions. Recent radar detections add a decaying planning penalty.
- Records channel placement, spectrum surveys, traffic summaries, and actions. Recent history stays in RAM; older history moves to flash in six-hour batches. Orderly shutdown saves pending records.
- Draws history locally with bundled Chart.js; no CDN is required.
- Shows short help beside every setting, with full explanations on hover, focus or click/tap.

**This is an experimental third-party package, not an official OpenWrt package.** Spectrum scores are estimates, not measured throughput. Brief reconnects can interrupt calls, streams, or other traffic. The live validation is specific to the hardware above; other routers need validation.

## Install the release

Download the APK, public key, and `SHA256SUMS` from [GitHub Releases](https://github.com/audrius-paskevicius/openwrt-wifi-coordinator/releases/latest). Generated APKs and package indexes are kept there, separate from source. The [public signing key](radio-prefer/release/radio-prefer-public.pem) is also tracked here.

1. Use OpenWrt 25.12 with `apk` v3, LuCI, and full hostapd/wpad support for 802.11k/v. This APK is not for older `opkg` firmware.
2. Configure the real country, working APs, and the intended Wi-Fi networks first. The package does not create SSIDs or set passwords.
3. Review [installation and behavior](docs/INSTALL.md), including the automatic defaults and service interactions.
4. Copy the public key and APK to the router, then run:

   ```sh
   cp /tmp/radio-prefer-public.pem /etc/apk/keys/radio-prefer-public.pem
   apk update
   # Substitute the filename of the release you downloaded.
   apk add /tmp/luci-app-wifi-coordinator-VERSION.apk
   ```

Alternatively, after installing the key, upload the APK through LuCI's software page. Dependencies must already be installed or reachable through your configured OpenWrt feeds. Do not bypass signature verification.

## Build from source

You need a Linux/OpenWrt environment with native **apk-tools v3 `mkpkg` and `mkndx`**, POSIX shell utilities, and your own signing key. No compilation of the application or downloading JavaScript dependencies is needed.

```sh
# Keep private keys outside this repository.
mkdir -p ../wifi-coordinator-signing/public
chmod 700 ../wifi-coordinator-signing
openssl ecparam -name prime256v1 -genkey -noout \
  -out ../wifi-coordinator-signing/private.pem
chmod 600 ../wifi-coordinator-signing/private.pem
openssl ec -in ../wifi-coordinator-signing/private.pem -pubout \
  -out ../wifi-coordinator-signing/public/local-public.pem

SIGN_KEY="$(pwd)/../wifi-coordinator-signing/private.pem" \
KEYS_DIR="$(pwd)/../wifi-coordinator-signing/public" \
APK_TOOL=apk sh wifi-coordinator/build-apk.sh
```

Outputs are written to `wifi-coordinator/dist/`. [VERSION](VERSION) sets the package version and the UI stylesheet cache version. `APK_TOOL` can name a native `apk.static` or OpenWrt SDK host tool. Packages built with your key require your corresponding public key on the destination router. The published APK's private signing key is not included.

## Test

```sh
# On a development machine with Python 3 and Node.js:
python3 scripts/check-project.py
node tests/check-ui.cjs
python3 scripts/prepare-tests.py

# On OpenWrt with ucode, fs, nl80211, ubus, uci, and uloop modules:
sh scripts/test-ucode.sh
```

The automated controller tests mock hardware operations; they do not switch live radios. History tests write only their dedicated `/tmp/wifi-history-test*` files and can take several minutes. Run one test suite at a time. See [validation](docs/TESTING.md) for what was and was not verified. GitHub Actions runs the portable project and UI checks; the ucode suite requires the OpenWrt runtime.

## Project layout

| Path | Contents |
| --- | --- |
| `channel-coordinator/files/` | Planner, survey scheduler, executor, radar/history storage, LuCI views |
| `radio-prefer/files/` | Preferred-radio steering and coordination protocol |
| `wifi-coordinator/` | APK builder, package hooks, shared UI files, ucode tests |
| `scripts/`, `tests/` | Portable validation and test preparation |
| `docs/` | [Installation](docs/INSTALL.md), [current architecture](docs/ARCHITECTURE.md), [settings audit](docs/SETTINGS.md), [validation](docs/TESTING.md) |

This source distribution contains no router passwords, Wi-Fi credentials, private signing keys, browser automation, client inventories, or router backups. Test addresses and Wi-Fi names are synthetic fixtures.

## Scope and limitations

- The current manager supports AP-only HT/VHT arrangements and a bounded joint search of up to four radios. It does not claim validated HE/EHT, MLO, or multi-interface support.
- Client roaming decisions remain client-dependent. Protected clients and explicit quiet-only/empty-only policies override the automatic reconnect fallback.
- Regulatory eligibility comes from the running kernel. DFS management currently requires matching global/per-radio ETSI regions. Radar memory never overrides a non-occupancy period or a required CAC.
- Firmware-upgrade preservation entries are included, but a full firmware-upgrade cycle has not been validated. Reinstall a compatible package and dependencies as needed.
- On WRT3200ACM/WRT32X, the country helper copies the administrator's common radio country into the auxiliary driver's module setting when appropriate. It never chooses a country for you; a changed module setting needs a reboot.

## License

MIT; see [LICENSE](LICENSE). Bundled Chart.js 4.5.1 is MIT-licensed; its [license](channel-coordinator/files/Chart.js-LICENSE.txt) is retained. See [third-party notices](THIRD_PARTY.md).
