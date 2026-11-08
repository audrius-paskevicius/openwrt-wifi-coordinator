# Installation and operation

## Software disclaimer

Read [the full disclaimer](../DISCLAIMER.txt) before installing. The package prints it during installation and includes it at `/usr/share/channel-coordinator/DISCLAIMER.txt`.

The bold **Experimental, AI-generated software. Use at your own risk.** tab beside Channels, Clients, History and Storage & export always provides the full text. The other pages have no recurring banner. First use in a browser requires acknowledgement before displaying that page's controls. The browser remembers the exact text for this router; unchanged notices stay acknowledged across package upgrades. Clearing browser storage, using another browser or router address, or changing the disclaimer requires acknowledgement again. If browser storage is unavailable, acknowledgement lasts only while the loaded page module remains active. This does not change running services or write acknowledgement data to router flash.

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
| `luci-base` | LuCI views, forms, RPC and filesystem clients. Its dependencies include `cgi-io` for large history reads and `liblucihttp-ucode` for the export endpoint's form decoder. |
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

Obtain all five assets: the APK, `packages.adb`, public key, `DISCLAIMER.txt` and `SHA256SUMS` from [GitHub Releases](https://github.com/audrius-paskevicius/openwrt-wifi-coordinator/releases/latest). In a directory containing all five assets, run `sha256sum -c SHA256SUMS` to check them. The manifest covers the APK, index, key and disclaimer; omitting a listed file makes this full check fail. `SHA256SUMS` does not checksum itself. The index is not required for direct APK installation. Copy `radio-prefer-public.pem` into `/etc/apk/keys/`, then install the APK with `apk add` or the LuCI software page. Keep normal OpenWrt feeds enabled to resolve dependencies.

The public key authenticates future packages signed with the same private key; verify that you trust the repository owner before installing it. Neither a checksum nor a public key obtained from an untrusted source establishes authenticity by itself.

This merged package conflicts with the earlier standalone `luci-app-radio-prefer` and `luci-app-channel-coordinator` packages. Preserve their settings and remove those standalone packages before migration. Do not run multiple channel-selection or steering controllers simultaneously.

## What installation changes

The package enables and starts the channel coordinator and Radio Preference according to their configuration. **Fresh installations use Automatic mode**, with paced scans and the shared reconnect fallback enabled. It fills missing radio roles without overwriting existing administrator choices.

Radio Preference keeps usteer's competing steering rules passive while using its measurements and neighbor information. Stopping Radio Preference restores the saved rules while preserving administrator edits. The coordinator refuses to operate alongside running `wifi-auto-channel`, `dawn` or `linksys-steering` services, and checks selected usteer steering policies before scanning or moving. This is a check for known conflicts, not detection of every possible external controller. If Radio Preference is disabled while channel coordination stays enabled, keep usteer's competing policies passive yourself.

Fresh installation also enables DFS preparation and uses a one-hour radar-memory half-life. Package upgrades preserve existing configured values; installing a new default does not change an administrator's saved half-life. The radar-memory setting is independent of six-hour failure exclusions and flash checkpoints.

The package does not create networks, replace Wi-Fi credentials, or change the LAN/WAN topology. WRT3200ACM/WRT32X-specific defaults select the known restart paths and synchronize the auxiliary driver's country hint with an already consistent configured country.

When moving countries, set the actual country on every radio, Save & Apply, and reboot WRT3200ACM/WRT32X hardware so its auxiliary driver loads the updated country hint. Wireless reloads refresh the coordinator. Automatic channel pools follow current kernel rules; explicit lists cannot override those rules. Factory country locks remain in force. The [DFS investigation](DFS-DRIVER.md) distinguishes the kernel's eligibility reports from unverified private-driver diagnostics.

Candidate primary channels default to `auto` for every radio. The daemon derives the list from that radio's live driver capabilities in its current band, so changes in country or driver restrictions are reflected without saving another static list. Regulatory rules, supported widths, DFS clearance and recovery exclusions still apply. Existing explicit lists are preserved during package upgrades; set each radio's **Candidate primary channels** to `auto` to remove an old restriction. This expands eligibility, not an instruction to move immediately.

Manual lists restrict primary channels only. Width is selected separately: for example, primary 36 may use a legal 80 MHz block even if 40, 44 and 48 are not explicitly listed. All secondary frequencies still require driver and regulatory eligibility.

Both channel and width settings are plain text fields accepting `auto` or space-separated numbers. Width Auto follows the radio's advertised HT/VHT capabilities in its current band. On the tested router, radio0 offers 160/80/40/20 MHz, radio1 40/20 MHz, and radio2 80/40/20 MHz in 5 GHz. Regulatory checks, legal block geometry, radar clearance and HT40 coexistence still restrict placements. Explicit unsupported widths are reported and excluded rather than substituted. Existing manual lists remain unchanged during upgrades.

Both switching-method settings default to Auto. On the tested WRT3200ACM, Auto selects CSA on radio0/radio1 and restart on radio2; width changes use restart. HT40 channel moves also use the width-change method to run hostapd's coexistence checks; an explicit CSA method cannot bypass them. A recent CSA failure makes Auto temporarily choose restart. Explicit choices are never substituted for planned moves, though recovery can restore service after failure. Applied methods, reasons, driver widths and timed exclusions appear beside each radio's settings. Existing explicit choices survive upgrades; select Auto to enable adaptation.

## Client handling

Automatic channel changes follow one rule on every managed radio:

1. Use live CSA when the selected method supports it.
2. For a required restart, attempt a compatible same-network, same-band handoff.
3. If handoff cannot finish, clear temporary return restrictions and briefly restart only the changing radio. If no compatible AP exists, skip the impossible handoff.
4. Let clients reconnect and check recovery using available ping responses, bidirectional traffic and associations. If clients cannot be probed, a longer association check is used; this does not prove internet access. If the new AP serves other clients, first try selective recovery of affected clients through a compatible AP. Keep the new placement only after alternate service verifies; otherwise restore the prior channel. Six-hour restrictions apply to confirmed failures or client compatibility, while inconclusive evidence initially uses a shorter deferral. See the scoped recovery policy in [architecture](ARCHITECTURE.md).

The shared setting **Change channel even if handoff cannot finish** is under **Protect playback**. Explicit protected clients and quiet-only/empty-only policies remain restrictions. A restart is an interruption, not seamless roaming. DFS preparation continues to require an empty compatible helper.

## Configuration and history

Configuration lives in `/etc/config/channel_coordinator` and `/etc/config/radio_prefer`. Use LuCI for explanations of each setting. Fresh normal Radio Preference uses gentle recommendations; strong mode is an administrator choice and still does not set an AP disconnect timer.

Every setting uses the same native LuCI help behavior: a short explanation is always visible; hover or focus that text for full details, or click/tap to open them. Click again or press Escape to close. The existing LuCI styling and help icon are retained. Specialist controls are under Advanced; conditional controls appear in their applicable modes. See the [complete settings reference](SETTINGS.md) for the purpose and exact scope of every retained control including the six retired timing controls and the removed width-selection threshold.

History retention ranges from 1 to 200 hours. Recent records use a 1 MiB RAM buffer; immutable flash batches are written at most once every six hours during normal operation, keeping at least 4 MiB of flash free. There is no fixed archive-size cap. Heavy activity or failed offloads can shorten retained history when the RAM buffer fills. Orderly shutdown checkpoints pending history and radar memory. Unexpected power loss can lose unsaved recent data. Disabling recording pauses new history; **Clear recorded history** explicitly deletes recorded graphs, surveys, and actions while preserving radar-avoidance memory. Only current `batch-*.json` history archives are supported; legacy `history.json` archives are not imported. See [architecture](ARCHITECTURE.md) for scoring, timing and storage details.

The **History** tab contains graphs, summaries and recent actions. **Storage & export** contains retention settings, collapsed **History storage** diagnostics and downloads. History's **Show** selector and exports' **Period** selector are independent, and each is capped by the saved retention setting. Exports default to **All retained history**. CSV downloads one selected dataset; JSON downloads all graph data and actions. Both stream directly without creating an export file on the router. See [export formats, privacy and completeness](EXPORT.md).

History loading uses LuCI's authenticated streaming reader for RAM and archive files larger than the ordinary ubus read limit. Read errors appear above the graphs. Opening **History storage** survives refreshes. The survey background carries each last observation forward until another measurement replaces it; hover for its actual measurement time.

## Stop or remove

Choose Observe to keep surveying without automatic channel changes, or turn off **Enable channel coordination** to stop that controller. Client steering has its own enable switch. The following commands stop both services for the current session; they do not disable their configured startup after reboot:

```sh
/etc/init.d/channel-coordinator stop
/etc/init.d/radio-prefer stop
```

After an interrupted operation, the coordinator restores its recovery journal and checks the enabled radios. It resumes automatically after 30 seconds of stable AP state. The fixed recovery deadline is 780 seconds (the internal 720-second radar-check allowance plus 60 seconds); an unresolved journal, inconsistent AP state or existing failure schedules further automatic checks with backoff capped at five minutes. Failed radios need stable AP state and positive service evidence from their currently authorized clients before planning resumes. This verifies AP operation, not end-to-end internet access. No radio is restarted by the observation check. Removing the package disables the services; do not delete the public key if another installed package still relies on it.

## Upgrades

Use matching OpenWrt dependencies. The package supplies preservation entries for configuration, runtime code, its public key, and retained flash history, but full sysupgrade testing remains outstanding. An ordinary package/service restart does not force extra history flash writes. Upgrade hooks stop the services and run recovery as needed. The supplied keep-list names the published key `/etc/apk/keys/radio-prefer-public.pem`; if you build with a differently named signing key, arrange preservation of that key separately. After updating the package, hard-refresh LuCI (Ctrl+F5) so cached JavaScript does not mix old and new views.

## WRT3200ACM LED-control caution

On firmware that exposes `rango:white:wlan_2g` and `rango:white:wlan_5g` as LEDs, do not assign triggers or turn those controls on. OpenWrt identified these GPIOs as Wi-Fi card reset lines; using them as LEDs can disable a card and cause driver errors. Remove such LED configurations before restarting to recover. The underlying fix is in the firmware device tree, not this coordinator. See [OpenWrt issue 9517 and its linked fix](https://github.com/openwrt/openwrt/issues/9517).
