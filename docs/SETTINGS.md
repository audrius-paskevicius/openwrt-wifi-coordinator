# Settings audit (r11)

This is a source and behavior review, not a runtime system that rewrites preferences. Explicit policies remain explicit. Auto resolves capabilities and known hardware behavior. Mandatory radio regulations, configuration checks and recovery remain authoritative; they do not silently turn an explicit planned CSA into a planned restart. After a failed operation, recovery may restart the affected radio to restore service.

The applied channel and width-change methods appear beside each radio's settings, with reasons. Confirmed radio failures during CSA affect Auto for six hours; explicit methods remain fixed. Confirmed failed destinations and unresolved client compatibility receive six-hour deferrals, with the reason and remaining time displayed. Inconclusive client evidence initially uses the evidence-freshness interval; verified alternate service instead creates a client-specific six-hour steering restriction. See the recovery policy in ARCHITECTURE.md. Choosing a fixed method does not erase failed-destination evidence. Unsupported explicit methods prevent the corresponding moves. Status describes applied settings until Save & Apply.

## Removed controls

These controls adjusted implementation timing rather than an administrator's Wi-Fi objective. They are no longer read as UCI settings and the defaults script removes the retired keys on installation. They are internal constants, not hidden advanced overrides.

| Retired key | Fixed behavior |
| --- | --- |
| `retry_delay` | 30-second gate after an attempt or non-executor deferral; completed/aborted executor operations use the survey interval. |
| `scan_wait` | 60-second extra scanner-wait budget per survey; normal serving gaps do not consume it. |
| `scan_batch` | At most five frequencies in non-paced, unrestricted scan batches; paced/restricted scans use one. |
| `cac_timeout` | 720-second preparation timeout, accommodating ten-minute weather-radar clearance. Never shortens mandatory clearance. |
| `csa_count` | 15 advance beacon announcements. |
| `ban_seconds` | 20-second return restriction after a decisive handoff; cleared on failed relocation or before restart fallback. |

## Channel coordination: retained controls

Every remaining control has a distinct operational purpose. Specialist controls are on the Advanced tab; conditional controls appear only in their applicable mode. Numeric integer settings reject fractional or malformed values rather than truncating them.

| Key | Why keep it / precise scope |
| --- | --- |
| `enabled` | Stops this controller; distinct from observation, which still scans and proposes. Client steering has its own switch. |
| `mode` | Observe versus automatic channel changes. Does not control preferred-radio steering. |
| `interval` | Administrator's scan-overhead budget: minimum wait after completed surveys/operations, including close comparisons. Startup begins after 15 seconds. |
| `improvement` | Minimum service-index gain for every capacity move, including widening. Only improved spectrum separation bypasses it; evidence uncertainty can raise it. |
| `min_dwell` | Avoids repeated moves after successful verification. Independent of survey frequency. |
| `persist` | Whether verified wireless placements are checkpointed, at most every six hours. Separate from graph history and radar memory. |
| `clear_stop` | One-shot recovery acknowledgement, reset after use. Does not erase remembered failed destinations. |
| `handoff_wait` | Time to give compatible clients a chance to roam before restart. Skipped if no compatible target exists. |
| `handoff_escalation` | Gentle, Strong or Decisive handoff requests. Does not disable the separately selected restart fallback. |
| `allow_reconnect` | Allows occupied restart after handoff fails. Protected clients and explicit quiet/empty policies still restrict it. |
| `protected_clients` | Protects selected clients from both preference and channel handoffs, and blocks occupied restart of their AP. Does not prohibit CSA, scans or kernel radar evacuation. |
| `max_mbps` | Advanced: shared traffic threshold for quiet-only moves and low-traffic scanning. Irrelevant to paced scanning and Automatic CSA. |
| `quiet_seconds` | Advanced: sustained duration below that threshold. Distinct from the threshold itself. |
| `verify_unprobed` | Advanced: observation time for clients without usable ICMP probes (150–600 seconds). Handles differing client sleep/probe behavior. |
| `handoff_target_min` | Advanced: weakest measured destination allowed for forced handoff. |
| `handoff_source_min` | Advanced: proximity requirement when destination cannot be measured. Co-located radio estimate, not a promised destination signal. |
| `dfs_mode` | Exclude, use already cleared channels, or prepare using a spare. Requires matching global/per-radio ETSI regions; a conflict is reported. |
| `dfs_helper` | Optional explicit helper for installations with unequal radio coverage. Only shown for Prepare. An unavailable explicit helper is waited for, not replaced. |
| `radar_half_life` | Default 3600 seconds (one hour): interruption-history weight halves each hour. Independent of mandatory kernel non-occupancy time. |
| `scan_policy` | Paced, empty-only or sustained-quiet scanning: direct disruption/coverage tradeoff. |
| `scan_duty` | Paced only: maximum off-channel duty calculated from measured visit duration. |
| `scan_gap` | Paced only: minimum serving time between occupied-radio visits; duty may require a longer gap. |
| `scan_type` | Passive or active where legal. Restricted frequencies always use passive listening, with an explicit status reason. |
| `scanner` | Advanced: Auto or a fixed scanner. A fixed scanner is never silently substituted; unreachable bands can therefore remain unmeasured. |
| `max_age` | Advanced: freshness ceiling for evidence; also bounds the cross-primary retry pause after HT40 setup retains 20 MHz. The active width constraint and remaining time are shown. Too short for a full scan can prevent decisions; unknown spectrum is never assumed clear. |
| `separate_radios` | Whether separation ranks before width/cost, or overlap is a cost term. Distinct priorities, not interchangeable thresholds. |
| `overlap_penalty` | Shown only when strict separation is disabled: allows the administrator to trade overlap against other costs. |

## Per-radio controls

| Key | Why keep it / precise scope |
| --- | --- |
| `managed` | Include in channel planning/preparation. Exclusion leaves placement fixed but does not disable scanning, the radio or preference steering. |
| `occupied_policy` | Automatic handoff/reconnect, quiet-only CSA, or empty-only. An explicit restriction can deliberately prevent moves indefinitely. |
| `method` | Auto, explicit CSA or explicit restart. Auto uses advertised CSA unless known hardware behavior or recent failure favors restart. |
| `width_method` | Auto, follow channel method, or a fixed method. Needed because drivers can support frequency CSA but fail width changes. Also applies to HT40 channel moves, which require restart for coexistence checks. Auto is independent; Follow inherits the resolved channel method. |
| `channels` | Auto discovers allowed primary channels in the active band. A manual list restricts primaries only; secondary frequencies still require regulatory/driver permission. |
| `widths` | Auto follows the radio's current-band HT/VHT capability bits, up to 40 MHz in 2.4 GHz and 160 MHz in 5 GHz. Regulatory/coexistence checks determine eligible blocks. Manual restrictions remain useful for client compatibility; unsupported requests are displayed and excluded. |

On WRT3200ACM/WRT32X, Auto uses restart for radio2 frequency changes and width changes. HT40 requires restart for hostapd coexistence checks on all hardware. Other supported radios use capability-based Auto. This is execution knowledge, not a separate planning algorithm. HE/EHT, 6 GHz and noncontiguous 80+80 remain outside the supported HT/VHT scope; this router does not advertise them.

## Preferred-radio steering

| Key | Why keep it / precise scope |
| --- | --- |
| `enabled` | Independent from channel planning. While enabled it owns steering and holds competing usteer policies passive. Disabling restores previous policies while preserving external edits. |
| `preferred_radio` | Explicit target: differing radios have different capabilities/coverage. No silent fallback to another radio. |
| `mode` | Gentle versus Strong recommendation. Strong requires a fresh qualifying measurement; absent measurement support is reported instead of silently sending Gentle. Neither mode sets an AP disconnect timer. |
| `min_rssi` | Required measured target signal. Gentle can still make an unmeasured suggestion to a client without measurement support; the client judges suitability. |
| `settle_time` | Lets a new association settle before measurement/steering. |
| `cooldown` | Minimum interval between recommendations to a client. |
| `max_attempts` | Burst limit before a longer pause (`cooldown × max_attempts`). Distinct from interval; budget also resets after one minute on the preferred radio. |

Channel handoffs and preferred-radio steering have separate signal/request policies because one prepares a necessary channel operation and the other merely recommends a favored AP. A shared lease prevents conflicting simultaneous actions. Busy/full or unavailable preferred APs now produce explicit client status rather than leaving a previous decision displayed.

## History

| Key | Why keep it / precise scope |
| --- | --- |
| `history_enabled` | Pauses new recording without deleting existing history. |
| `history_hours` | Maximum retention and graph-selection range (up to 200 hours), subject to the documented RAM/free-flash safeguards. |
| `clear_history` | Explicit one-shot deletion, reset after use. Independent of pausing recording; does not erase radar memory. |

History recording, retaining working wireless placements, and radar-memory persistence serve different purposes; merging their controls would obscure what survives reboot. Storage mechanics remain fixed: six-hour batched offloads, recent RAM cache, and an orderly shutdown checkpoint. No user-facing flash-write frequency knob is needed.
