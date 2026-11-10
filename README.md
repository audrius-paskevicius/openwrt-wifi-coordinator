# OpenWrt Wi-Fi Coordinator

<!-- project-disclaimer:start -->
> [!WARNING]
> **EXPERIMENTAL, AI-GENERATED SOFTWARE — USE AT YOUR OWN RISK**
>
> This is a free, open-source project. The person behind it supplied the ideas, requirements, and direction; AI generated the code. That person cannot independently verify every aspect of its implementation or behaviour. Testing does not guarantee correctness, reliability, or safety.
>
> The software automatically changes wireless operation. Errors may disrupt network access, damage configurations, expose security weaknesses, or cause data loss or other harm.
>
> It is provided “as is,” without promised support, maintenance, or repair. To the fullest extent permitted by applicable law, the provider excludes warranties and liability arising from its use.
>
> Use only if you understand and accept the risks, have suitable backups and recovery arrangements, and can bear the resulting disruption, costs, or losses. Do not rely on it where failure could cause harm.
<!-- project-disclaimer:end -->

Coordinated channel selection and client steering for OpenWrt, developed and live-tested on the **Linksys WRT3200ACM with OpenWrt 25.12.6**.

The package combines channel planning, Radio Preference, and a LuCI interface under **Network → Wi-Fi Coordinator**. It uses `usteer` for measurements while keeping competing steering decisions passive. It preserves your Wi-Fi names, passwords, and LAN/WAN topology; automatic operation changes radio channels and widths.

The tabs are **Channels**, **Clients**, **Comparison**, **History**, **Settings**, **Storage & export**, and the full disclaimer. Channels and Clients show live operation without save controls. Comparison explains the last completed placement assessment. Settings brings channel and steering configuration together, preserving their existing storage and policies. History displays observations; Storage & export controls retention and downloads, with an independent export-period selector.

## What it does

- Surveys the surrounding spectrum with paced scans and serving gaps.
- Plans channels and widths jointly, following each radio's HT/VHT capabilities: up to 40 MHz on 2.4 GHz and 160 MHz on 5 GHz, subject to regulatory and coexistence checks.
- Defaults to live driver-derived channel lists for every radio; optional explicit lists restrict selection.
- Ranks joint layouts by usable bandwidth and advertised radio spatial capacity, accounting for the primary channel and radar memory. Width alone does not outrank estimated service; the objective is independent of today's client mix.
- Uses one decision owner with per-radio reservations, allowing unrelated scans and preference requests during an operation.
- Prices disruption across all radios using affected-client counts, observed CSA departures, helper use and staging. Repeated noisy surveys alone cannot manufacture confidence.
- Uses one Gentle / Strong / Decisive escalation policy for preference and channel/radar handoffs, with shared protection and retry limits.
- Separately observes preferred-radio return after a move and records decision costs and observed outcomes in history and JSON/CSV exports.
- Uses live channel-switch announcements where supported. Otherwise it tries a compatible client handoff, then briefly restarts only the changing radio if clients remain.
- Checks reconnection and service after a change, with rollback and temporary exclusions after failures.
- Uses eligible DFS spectrum opportunistically, preparing it on an empty compatible helper while another radio serves clients when possible. Recent radar detections add a planning penalty with a one-hour default half-life, separate from mandatory kernel clearance and exclusion periods.
- Records channel placement, spectrum surveys, traffic summaries, and actions. Recent history stays in RAM; older history moves to flash in six-hour batches. Orderly shutdown saves pending records.
- Draws history locally with bundled Chart.js; no CDN is required.
- Streams authenticated JSON and CSV [history downloads](docs/EXPORT.md) without creating export files or writing flash.
- Shows short help beside every setting, with full explanations on hover, focus or click/tap.

**This is an experimental third-party package, not an official OpenWrt package.** Spectrum scores are estimates, not measured throughput. Brief reconnects can interrupt calls, streams, or other traffic. The live validation is specific to the hardware above; other routers need validation.

## Install the release

Download the five release files: the APK, `packages.adb`, public key, `DISCLAIMER.txt`, and `SHA256SUMS` from [GitHub Releases](https://github.com/audrius-paskevicius/openwrt-wifi-coordinator/releases/latest). Generated APKs and package indexes are kept there, separate from source. The index is included in the checksum manifest; it is not needed to install the APK directly. The [public signing key](radio-prefer/release/radio-prefer-public.pem) is also tracked here.

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

You need a Linux/OpenWrt build environment with native **apk-tools v3 `mkpkg` and `mkndx`**, `ucode` with its `fs` module, POSIX shell utilities, and your own signing key. The example below also uses OpenSSL to create the key. The builder uses `ucode` to embed the canonical disclaimer in the UI; it does not compile the controllers or download JavaScript dependencies.

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

The builder writes the APK and signed `packages.adb` index to `wifi-coordinator/dist/`. For a release, separately copy `DISCLAIMER.txt` and the matching public signing key there, then generate `SHA256SUMS` covering those four files. The builder does not create these three extra release assets. [VERSION](VERSION) sets the package version and the UI stylesheet cache version. `APK_TOOL` can name a native `apk.static` or OpenWrt SDK host tool. Packages built with your key require your corresponding public key on the destination router. The published APK's private signing key is not included.

## Test

```sh
# On a development machine with Python 3 and Node.js:
python3 scripts/check-project.py
node tests/check-ui.cjs
python3 scripts/prepare-tests.py

# On OpenWrt with ucode, fs, nl80211, ubus, uci, and uloop modules:
sh scripts/test-ucode.sh
```

The automated controller tests mock hardware operations; they do not switch live radios. Test state uses dedicated temporary files. The archive simulation can take several minutes; it does not modify the live history archive. Run one test suite at a time. See [validation](docs/TESTING.md) for what was and was not verified. GitHub Actions runs the portable project and UI checks; the ucode suite requires the OpenWrt runtime.

## Project layout

| Path | Contents |
| --- | --- |
| `channel-coordinator/files/` | Planner, survey scheduler, executor, radar/history storage, LuCI views |
| `radio-prefer/files/` | Preferred-radio steering and coordination protocol |
| `wifi-coordinator/` | APK builder, package hooks, shared UI files, ucode tests |
| `scripts/`, `tests/` | Portable validation and test preparation |
| `docs/` | [Installation](docs/INSTALL.md), [current architecture](docs/ARCHITECTURE.md), [settings reference](docs/SETTINGS.md), [history export formats](docs/EXPORT.md), [behavior review](docs/AGREEMENTS.md), [validation](docs/TESTING.md) |

This source distribution contains no router passwords, Wi-Fi credentials, private signing keys, saved browser sessions, client inventories, or router backups. Test addresses and Wi-Fi names are synthetic fixtures. This describes the published source and package, not live runtime files on an installed router; see [runtime privacy](docs/ARCHITECTURE.md#history-persistence-and-privacy).

## Scope and limitations

- The current manager supports AP-only HT/VHT arrangements and a bounded joint search of up to four radios. It does not claim validated HE/EHT, MLO, or multi-interface support.
- Client roaming decisions remain client-dependent. Protected clients and explicit quiet-only/empty-only policies override the automatic reconnect fallback.
- Regulatory eligibility comes from the running kernel. DFS management requires matching, known global/per-radio regions (FCC, ETSI or Japan). Radar memory never overrides a non-occupancy period or a required CAC. Expiry makes spectrum eligible for reconsideration; fresh survey evidence and service scoring still determine whether to move. See the [DFS investigation and country guidance](docs/DFS-DRIVER.md).
- Firmware-upgrade preservation entries are included, but a full firmware-upgrade cycle has not been validated. Reinstall a compatible package and dependencies as needed.
- On WRT3200ACM/WRT32X, the country helper copies the administrator's common radio country into the auxiliary driver's module setting when appropriate. It never chooses a country for you; a changed module setting needs a reboot.

## License

MIT; see [LICENSE](LICENSE). Bundled Chart.js 4.5.1 is MIT-licensed; its [license](channel-coordinator/files/Chart.js-LICENSE.txt) is retained. See [third-party notices](THIRD_PARTY.md).

## Publishing releases

Use `python3 scripts/prepare-release-notes.py NOTES.txt RELEASE-NOTES.md` to prepend the full [disclaimer](DISCLAIMER.txt), then pass the generated file to `gh release create --notes-file RELEASE-NOTES.md`. Publish and verify the signed assets. Older releases may remain available for rollback; historical validation notes do not promise download availability. Include `DISCLAIMER.txt` with the release assets and checksum manifest. The same canonical text is embedded in the APK UI; unchanged text preserves browser acknowledgements.
