# Installation and operation

## Requirements

- OpenWrt 25.12 and APK v3. Live development used 25.12.6 on a Linksys WRT3200ACM.
- LuCI, `iw`, `usteer`, `ucode`, and ucode modules `fs`, `ubus`, `uci`, `uloop`, and `nl80211`. The APK declares these dependencies.
- A full hostapd/wpad variant with the required neighbor reporting, beacon measurements, and BSS transition APIs. Reduced `wpad-basic` builds may lack these capabilities. Choose the appropriate full variant from your firmware's official feed; this package does not automatically replace it.
- Working AP interfaces and an explicitly configured legal country. Shared-network handoffs require compatible security and LAN membership.

See the official [OpenWrt APK documentation](https://openwrt.org/docs/guide-user/additional-software/apk) and [package-signing documentation](https://openwrt.org/docs/guide-user/security/signatures).

## Trust and install

Obtain the APK and public key from this repository or its GitHub release. Check `release/SHA256SUMS` against downloaded files. Copy `radio-prefer-public.pem` into `/etc/apk/keys/`, then install the APK with `apk add` or the LuCI software page. Keep normal OpenWrt feeds enabled to resolve dependencies.

The public key authenticates future packages signed with the same private key; verify that you trust the repository owner before installing it. Neither a checksum nor a public key obtained from an untrusted source establishes authenticity by itself.

This merged package conflicts with the earlier standalone `luci-app-radio-prefer` and `luci-app-channel-coordinator` packages. Preserve their settings and remove those standalone packages before migration. Do not run multiple channel-selection or steering controllers simultaneously.

## What installation changes

The package enables and starts the channel coordinator and Radio Preference according to their configuration. **Fresh installations use Automatic mode**, with paced scans and the shared reconnect fallback enabled. It fills missing radio roles without overwriting existing administrator choices.

Radio Preference keeps usteer's competing steering rules passive while using its measurements and neighbor information. Stopping Radio Preference restores the saved rules while preserving administrator edits. The coordinator detects known competing services rather than silently running alongside them.

The package does not create networks, replace Wi-Fi credentials, or change the LAN/WAN topology. WRT3200ACM/WRT32X-specific defaults select the known restart paths and synchronize the auxiliary driver's country hint with an already consistent configured country.

## Client handling

Automatic channel changes follow one rule on every managed radio:

1. Use live CSA when the selected method supports it.
2. For a required restart, attempt a compatible same-network, same-band handoff.
3. If handoff cannot finish, clear temporary return restrictions and briefly restart only the changing radio. If no compatible AP exists, skip the impossible handoff.
4. Let clients reconnect, verify their service, and restore the prior channel if recovery fails.

The shared setting **Change channel even if handoff cannot finish** is under **Protect playback**. Explicit protected clients and quiet-only/empty-only policies remain restrictions. A restart is an interruption, not seamless roaming. DFS preparation continues to require an empty compatible helper.

## Configuration and history

Configuration lives in `/etc/config/channel_coordinator` and `/etc/config/radio_prefer`. Use LuCI for explanations of each setting. Fresh normal Radio Preference uses gentle recommendations; strong mode is an administrator choice and still does not set an AP disconnect timer.

History retention ranges from 1 to 200 hours. Recent records use a bounded RAM buffer; immutable flash batches are written at most once every six hours during normal operation. Orderly shutdown checkpoints pending history and radar memory. Unexpected power loss can lose unsaved recent data. Disabling recording pauses new history; **Clear recorded history** explicitly deletes recorded graphs, surveys, and actions while preserving radar-avoidance memory.

## Stop or remove

Disable automatic coordination in LuCI or stop its service:

```sh
/etc/init.d/channel-coordinator stop
/etc/init.d/radio-prefer stop
```

Stopping the coordinator during an active operation can restore a recovery journal and latch a safety stop. Inspect wireless status before clearing it. Removing the package disables the services; do not delete the public key if another installed package still relies on it.

## Upgrades

Use matching OpenWrt dependencies. The package supplies preservation entries for configuration, runtime code, its public key, and retained flash history, but full sysupgrade testing remains outstanding. An ordinary package/service restart does not force extra history flash writes. Upgrade hooks stop the services and run recovery as needed.
