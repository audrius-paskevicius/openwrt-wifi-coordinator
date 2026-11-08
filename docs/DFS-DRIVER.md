# WRT3200ACM DFS investigation and opportunistic operation

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

## Correction in r45

r44 incorrectly promoted the private driver's debug field into an application
veto over kernel-authorized DFS operation. It blocked both candidate placements
and helper preparation on the main radio. That restriction conflicted with the
project's intended opportunistic behavior and is removed in r45.

The coordinator again considers all kernel-permitted channels and widths,
including DFS and 160 MHz where supported. Prepare mode can use an empty helper
for CAC while another radio serves clients. The target radio must itself show
kernel clearance before use. Radar exclusion remains mandatory; a block becomes
eligible for reconsideration when the kernel permits it. Remembered radar risk
decays rather than becoming a permanent exclusion. No non-DFS preference is added.
Fresh survey evidence, service scoring and active recovery restrictions still
determine whether to move; exclusion expiry does not promise immediate reuse.
The [r45 live test](TESTING.md#r45-restore-opportunistic-dfs) confirmed helper CAC
while another radio served clients, followed by an automatic 160 MHz placement.
It does not certify RF radar sensitivity.

The source inspection explains the unset debug value but does not establish how
the closed firmware interprets the profile command on this factory-locked model.
The [upstream maintainer's explanation](https://github.com/kaloz/mwlwifi/issues/172#issuecomment-315896364)
also distinguishes the firmware's programmed region from driver country mapping;
it does not validate every radar profile. The earlier conclusion that the field
justified a blanket DFS ban was too strong. Restoring the normal kernel contract
is not a claim that firmware radar sensitivity has been certified or repaired.

No kernel/firmware replacement, country override, simulated radar event, or
fabricated CAC clearance is part of this correction.

## Country changes

When moving countries, set the actual country on **every radio** in OpenWrt's
wireless settings, check that saved startup channels and widths are valid there,
Save & Apply, and reboot this WRT hardware. The coordinator needs working APs;
automatic candidate pools do not repair an invalid startup placement. Wireless reloads
refresh the coordinator and its auxiliary-driver country hint; that module hint
only takes effect when the driver loads. The project does not infer location,
override factory country locks, or make unsupported hardware legal elsewhere.
Custom auxiliary-driver module settings are preserved and need separate review.
Automatic pools follow the new live rules; explicit pools remain restrictions
and cannot permit a forbidden channel. Missing or conflicting DFS regions block
DFS. FCC, ETSI and Japan region matching is tested in software; live validation
remains limited to the Swedish development installation.

The project does not change regulatory databases, shorten mandatory exclusion
periods, or use private debug controls to force clearance.
