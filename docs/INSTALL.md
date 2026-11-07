# Installation and operation

## Requirements

- OpenWrt 25.12 and APK v3. Live development used 25.12.6 on a Linksys WRT3200ACM.
- LuCI, `iw`, `usteer`, `ucode`, and ucode modules `fs`, `ubus`, `uci`, `uloop`, and `nl80211`. The APK declares these dependencies.
- A full hostapd/wpad variant with the required neighbor reporting, beacon measurements, and BSS transition APIs. Reduced `wpad-basic` builds may lack these capabilities. Choose the appropriate full variant from your firmware's official feed; this package does not automatically replace it.
- Working AP interfaces and an explicitly configured legal country. Shared-network handoffs require compatible security and LAN membership.

See the official [OpenWrt APK documentation](https://openwrt.org/docs/guide-user/additional-software/apk) and [package-signing documentation](https://openwrt.org/docs/guide-user/security/signatures).

## How dependencies are handled

The APK builder declares these dependencies in the package metadata:

| Dependency | Purpose |
| --- | --- |
| `luci-base` | LuCI views, forms, RPC and filesystem client libraries |
| `iw` | Wireless information and driver interactions |
| `usteer` | Client measurements and neighbor information |
| `ucode` | Controller runtime |
| `ucode-mod-fs`, `ucode-mod-ubus`, `ucode-mod-uci`, `ucode-mod-uloop`, `ucode-mod-nl80211` | Files, service APIs, configuration, event loop and wireless APIs |

`apk add` resolves those requirements and their dependencies using installed packages and the router's configured feeds. Missing packages need reachable feeds or separately supplied packages; a standalone APK does not bundle the OpenWrt runtime. The package hooks do not run a separate downloader or a blanket package upgrade. Chart.js is bundled, so the graphs need no CDN, npm or internet access.

Full hostapd/wpad is a manual prerequisite, not an automatically selected dependency. Several mutually exclusive variants exist, and silently replacing an installed variant could disrupt wireless service. Install a suitable full variant for your firmware and verify its required APIs before enabling automatic coordination. Development and live validation used `wpad-mbedtls`.

Runtime package versions are not pinned to one router's installed builds. Use feeds matching the firmware release; the supported/tested baseline is OpenWrt 25.12.6. This does not guarantee compatibility with every future API change. Preview the exact transaction before installing:

```sh
# Replace VERSION with the downloaded release version.
apk add --simulate /tmp/luci-app-wifi-coordinator-VERSION.apk
```

The local APK is checked against its installed signing key. Dependencies use the keys and repositories configured by OpenWrt. The custom signing key does not replace OpenWrt's keys.

## Trust and install

Obtain the APK, public key and `SHA256SUMS` from [GitHub Releases](https://github.com/audrius-paskevicius/openwrt-wifi-coordinator/releases/latest). In a directory containing the downloaded assets, run `sha256sum -c SHA256SUMS` to check them. Copy `radio-prefer-public.pem` into `/etc/apk/keys/`, then install the APK with `apk add` or the LuCI software page. Keep normal OpenWrt feeds enabled to resolve dependencies.

The public key authenticates future packages signed with the same private key; verify that you trust the repository owner before installing it. Neither a checksum nor a public key obtained from an untrusted source establishes authenticity by itself.

This merged package conflicts with the earlier standalone `luci-app-radio-prefer` and `luci-app-channel-coordinator` packages. Preserve their settings and remove those standalone packages before migration. Do not run multiple channel-selection or steering controllers simultaneously.

## What installation changes

The package enables and starts the channel coordinator and Radio Preference according to their configuration. **Fresh installations use Automatic mode**, with paced scans and the shared reconnect fallback enabled. It fills missing radio roles without overwriting existing administrator choices.

Radio Preference keeps usteer's competing steering rules passive while using its measurements and neighbor information. Stopping Radio Preference restores the saved rules while preserving administrator edits. The coordinator detects known competing services rather than silently running alongside them.

The package does not create networks, replace Wi-Fi credentials, or change the LAN/WAN topology. WRT3200ACM/WRT32X-specific defaults select the known restart paths and synchronize the auxiliary driver's country hint with an already consistent configured country.

Candidate primary channels default to `auto` for every radio. The daemon derives the list from that radio's live driver capabilities in its current band, so changes in country or driver restrictions are reflected without saving another static list. Regulatory rules, supported widths, DFS clearance and recovery exclusions still apply. Existing explicit lists are preserved during package upgrades; set each radio's **Candidate primary channels** to `auto` to remove an old restriction. This expands eligibility, not an instruction to move immediately.

Manual lists restrict primary channels only. Width is selected separately: for example, primary 36 may use a legal 80 MHz block even if 40, 44 and 48 are not explicitly listed. All secondary frequencies still require driver and regulatory eligibility.

Both channel and width settings are plain text fields accepting `auto` or space-separated numbers. Width Auto follows the radio's advertised HT/VHT capabilities in its current band. On the tested router, radio0 offers 160/80/40/20 MHz, radio1 40/20 MHz, and radio2 80/40/20 MHz in 5 GHz. Regulatory checks, legal block geometry, radar clearance and HT40 coexistence still restrict placements. Explicit unsupported widths are reported and excluded rather than substituted. Existing manual lists remain unchanged during upgrades.

Both switching-method settings default to Auto. On the tested WRT3200ACM, Auto selects CSA on radio0/radio1 and restart on radio2; width changes use restart. HT40 channel moves also use the width-change method to run hostapd's coexistence checks; an explicit CSA method cannot bypass them. A recent CSA failure makes Auto temporarily choose restart. Explicit choices are never substituted for planned moves, though recovery can restore service after failure. Applied methods, reasons, driver widths and timed exclusions appear beside each radio's settings. Existing explicit choices survive upgrades; select Auto to enable adaptation.

## Client handling

Automatic channel changes follow one rule on every managed radio:

1. Use live CSA when the selected method supports it.
2. For a required restart, attempt a compatible same-network, same-band handoff.
3. If handoff cannot finish, clear temporary return restrictions and briefly restart only the changing radio. If no compatible AP exists, skip the impossible handoff.
4. Let clients reconnect and check recovery using available ping responses, bidirectional traffic and associations. If clients cannot be probed, a longer association check is used; this does not prove internet access. Restore the prior channel if recovery fails.

The shared setting **Change channel even if handoff cannot finish** is under **Protect playback**. Explicit protected clients and quiet-only/empty-only policies remain restrictions. A restart is an interruption, not seamless roaming. DFS preparation continues to require an empty compatible helper.

## Configuration and history

Configuration lives in `/etc/config/channel_coordinator` and `/etc/config/radio_prefer`. Use LuCI for explanations of each setting. Fresh normal Radio Preference uses gentle recommendations; strong mode is an administrator choice and still does not set an AP disconnect timer.

Every setting uses the same native LuCI help behavior: a short explanation is always visible; hover or focus that text for full details, or click/tap to open them. Click again or press Escape to close. The existing LuCI styling and help icon are retained. Specialist controls are under Advanced; conditional controls appear in their applicable modes. See the [complete settings audit](SETTINGS.md) for the purpose and exact scope of every retained control and the six retired implementation-timing knobs.

History retention ranges from 1 to 200 hours. Recent records use a 1 MiB RAM buffer; immutable flash batches are written at most once every six hours during normal operation, keeping at least 4 MiB of flash free. There is no fixed archive-size cap. Heavy activity or failed offloads can shorten retained history when the RAM buffer fills. Orderly shutdown checkpoints pending history and radar memory. Unexpected power loss can lose unsaved recent data. Disabling recording pauses new history; **Clear recorded history** explicitly deletes recorded graphs, surveys, and actions while preserving radar-avoidance memory. Only current `batch-*.json` history archives are supported; legacy `history.json` archives are not imported. See [architecture](ARCHITECTURE.md) for scoring, timing and storage details.

## Stop or remove

Disable automatic coordination in LuCI or stop its service:

```sh
/etc/init.d/channel-coordinator stop
/etc/init.d/radio-prefer stop
```

Stopping the coordinator during an active operation can restore a recovery journal and latch a safety stop. Inspect wireless status before clearing it. Removing the package disables the services; do not delete the public key if another installed package still relies on it.

## Upgrades

Use matching OpenWrt dependencies. The package supplies preservation entries for configuration, runtime code, its public key, and retained flash history, but full sysupgrade testing remains outstanding. An ordinary package/service restart does not force extra history flash writes. Upgrade hooks stop the services and run recovery as needed.
