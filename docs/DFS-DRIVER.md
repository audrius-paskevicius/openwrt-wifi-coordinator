# WRT3200ACM DFS investigation

The r44 history fix restores radar shading from retained detection events,
independently of the planner's bounded and separately checkpointed memory. CAC
completion and non-occupancy expiry are not detections. Shared reports for the
same region and block within five seconds count as one incident.

## Driver finding

On the development WRT3200ACM running OpenWrt 25.12.6, the main 5 GHz mwlwifi
driver reported `dfs_region: 0`. Kernel regulatory reports were ETSI and hostapd
was configured for Sweden. Firmware reported region `0x30`; radar test mode was
disabled. These observations cannot establish which radar patterns the firmware
actually detects.

The installed package identifies source commit
`db97edf20fadea2617805006f5230665fadc6a8c` (driver 10.4.11.0, firmware 0x0903020c).
Its [regulatory callback](https://github.com/kaloz/mwlwifi/blob/db97edf20fadea2617805006f5230665fadc6a8c/core.c)
returns from the factory-locked path before assigning `priv->dfs_region`. The
[firmware command](https://github.com/kaloz/mwlwifi/blob/db97edf20fadea2617805006f5230665fadc6a8c/hif/fwcmd.c)
uses that field to choose the radar profile: unset selects code 0, while ETSI
selects code 151. The reviewed
[OpenWrt patches](https://github.com/openwrt/openwrt/tree/openwrt-25.12/package/kernel/mwlwifi/patches)
do not change those assignments. This is a driver/firmware concern, not evidence
that a coordinator algorithm rewrite disabled the detector.

Retained logs contain four detection incidents across November 6–7, 2026,
including two 160 MHz incidents at 11:37:42 and 12:05:15 CET on November 7 with
evacuation records. Shared PHY notifications do not prove independent detection
by both radios. No radar signals or debugfs radar simulations were generated.

## Mitigation and country changes

r44 blocks new DFS placements and CAC-helper use on a mwlwifi radio whose
internal radar region is missing or differs from the kernel region. The known
driver is identified through sysfs as well as debugfs, so an unavailable debugfs
report does not silently pass this check. Other drivers still use their kernel
regulatory reports. An explanation appears in the affected radio's status.

The development router's main radio is moved to a permitted non-DFS block, with
a non-DFS channel and width saved for startup. Channel and width candidate lists
remain automatic: the restriction checks every member of a block against live
driver/regulatory rules, rather than assuming a particular country's channels.
The auxiliary radio retains DFS eligibility when its own checks pass.

The guard restricts coordinator choices; it does not rewrite arbitrary existing
AP configurations. An administrator applying it to another router must also move
an already-operating affected AP off DFS and save suitable startup settings.

When moving countries, set the actual country on **every radio** in OpenWrt's
wireless settings, Save & Apply, and reboot this WRT hardware. Wireless reloads
refresh the coordinator and its auxiliary-driver country hint; that module hint
only takes effect when the driver loads. The project does not infer location,
override factory country locks, or make unsupported hardware legal elsewhere.
Automatic pools follow the new live rules; explicit pools remain restrictions
and cannot permit a forbidden channel. Missing or conflicting DFS regions block
DFS. FCC, ETSI and Japan region matching is tested in software; live validation
remains limited to the Swedish development installation.

This mitigation does not repair the driver or certify its detector. Restoring
DFS/160 MHz on the affected radio requires a reviewed driver/firmware correction
and hardware validation. Do not change country to evade restrictions or write
debugfs controls to fabricate CAC clearance.
