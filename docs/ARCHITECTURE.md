# Current architecture

The daemon in `channel-coordinator/files/main.uc` runs an observe → plan → execute → verify cycle. Hardware calls go through an injected interface in the survey and executor modules, allowing tests without moving live radios. Radio Preference is a separate service in the same APK; a shared lease prevents its preferred-radio steering from interfering with scans, preparation and channel moves.

## Surveying

`survey.uc` collects full broad sweeps. Paced mode visits one frequency at a time and does not require traffic silence. It prefers empty radios; among occupied radios it estimates interrupted client capacity from negotiated rates, traffic and measured scan duration. It waits for the least-cost scanner rather than borrowing a costlier radio during its serving gap. A ready frequency on another band can be scanned meanwhile.

Defaults are a 10% scan-duty budget and at least three seconds of serving time between occupied-radio visits. Active probes are used only where allowed; DFS and other restricted frequencies use passive listening. Empty-only and sustained-quiet modes remain supported. The latter uses the same traffic threshold and quiet duration as quiet-only channel changes.

Only radios with complete, fresh coverage of their candidate spectrum may move. An incomplete other band does not block a fully measured band. Missing frequencies are unknown, not clear spectrum. On 2.4 GHz, scans also cover neighboring frequencies whose networks can overlap allowed candidate channels.

## Planning and evidence

`policy.uc` supplies geometry, regulatory checks and the neighbor-pressure calculation shared with history graphs. `planner.uc` is the single planning implementation. It evaluates driver-advertised HT/VHT widths (20/40 MHz on 2.4 GHz and 20/40/80/160 MHz on 5 GHz), with at most four radios and a bounded search of 100,000 nodes. HT40 considers both secondary-channel directions. VHT160 uses standard contiguous blocks, not sliding centers or 80+80. AUTO_BW can join contiguous regulatory ranges while preserving per-member width, power and DFS restrictions.

The `channels` setting defaults to `auto`. Each inventory refresh resolves it from the radio's current nl80211 frequency capabilities, confined to its active band. Disabled frequencies and non-DFS frequencies prohibiting AP initiation are excluded. DFS frequencies remain subject to DFS mode, kernel state and clearance checks. An explicit numeric list restricts primary channels, independently of width: listing 36 can permit an 80 MHz block with primary 36 without also listing 40, 44 and 48. Every member frequency must still pass driver, regulatory and DFS checks. No fixed 1–11 or 5 GHz channel list limits automatic discovery. The controller still supports the HT/VHT bands described above, not 6 GHz.

For each 20 MHz member of a candidate block, estimated congestion is the larger of scaled neighbor pressure and available external busy-airtime evidence, capped at 100. The candidate's occupancy is their mean. Busy counters on channels carrying our clients are excluded from planning because they include our own traffic. Missing counters do not add invented congestion; the neighbor estimate remains available.

Estimated capacity is `width × (1 − occupancy/100) × (1 − 0.75 × radar risk)`. Cost is `100 − 100 × capacity / maximum configured width`. These are comparative estimates, not throughput measurements. When separation is disabled, the joint cost also includes the configured overlap penalty; otherwise overlap is ranked separately.

With separation enabled, joint layouts rank by:

1. Least overlap between our radios, including fixed radios.
2. Most usable width, normalized by each radio's configured maximum. A block contributes this width preference only below the congestion threshold (default 70) and radar risk 0.5.
3. Lowest estimated capacity cost.
4. Highest legal transmit power as a tie-breaker.

If separation is disabled, overlap instead competes through its cost penalty. Narrowing must improve cost or separation. Transitions may use one neutral staging move; with separation enabled, no intermediate move may increase overlap. The next step is reevaluated after each completed operation.

Evidence uncertainty starts at one point with complete measured airtime, otherwise three. Changes between surveys can raise it to 15; a changed scanner imposes a floor of six. Each alternative retains its own consecutive supporting-survey count, even if another alternative ranks first. For cost-only changes, the required benefit is the greater of the configured minimum (default three points) and uncertainty reduced by the square root of supporting comparisons. Missing, stale or contrary evidence resets support. Improved separation or usable width can bypass this cost margin; admitted multi-step plans do not repeatedly pay the admission margin while their remaining benefit stays positive.

The comparison table shows individual alternatives sorted by sharing with current peer placements, then cost. It is not the joint-plan ranking: the joint plan can also move peers and prioritizes usable width.

## Execution, clients and timing

`executor.uc` changes one radio at a time. It rechecks configuration, regulatory eligibility and peer overlap immediately before execution. It uses CSA when supported. A restart first attempts a same-band, same-network handoff; if none exists, it skips that wait. With the shared reconnect fallback enabled, it can restart the selected single-AP radio when clients remain. Protected clients and explicit quiet-only/empty-only policies still restrict restart operations.

Handoff defaults to 90 seconds, progressing from gentle requests to stronger requests and then a bounded disconnect if decisive escalation is enabled. Temporary return bans are cleared before the reconnect fallback. Recovery uses reachable private-LAN ping targets, bidirectional data counters and associations. Missing clients get a 60-second reconnection grace period before persistent-failure handling; unprobeable clients require a longer association observation. Association alone does not establish working internet. Failed moves trigger rollback and six-hour destination exclusions. Interrupted operations use a recovery journal; ambiguous recovery can latch a safety stop.

Default timing is 60 seconds between completed surveys and a 180-second minimum residence after a verified move. Close comparisons respect the configured survey interval. The fixed 30-second retry gate covers recent failed attempts and non-executor deferrals; completed or aborted executor operations return to the normal survey interval. These are not promises of a channel change every fixed number of seconds: coverage, service verification, radar clearance and eligibility also matter.

Switch methods default to Auto, which resolves driver support, known WRT execution behavior and recent CSA failures. Explicit methods remain fixed for planned moves; unsupported choices block their corresponding moves. Emergency restoration can still restart the affected radio. Configured/effective methods, reasons and timed destination exclusions are reported in the UI. See the [settings audit](SETTINGS.md) for every setting's scope and removed controls. Strong preferred-radio steering requires a fresh qualifying signal measurement and never silently becomes a gentle request.

## DFS and radar memory

DFS management requires matching global and per-radio ETSI regions. In preparation mode, an empty compatible 5 GHz helper temporarily listens on the target while another radio serves clients. Handoff may empty the helper; preparation does not forcibly restart an occupied helper. Its original AP is restored before the serving radio moves. Clearance must be confirmed on the target radio too; no assumption is made that all drivers share it.

A helper narrower than the proposed block can prepare its uncleared pieces sequentially. Each piece is checked on both PHYs and the helper is restored between checks. The original wide target remains pending; it cannot move until every required member is cleared. Thus an 80 MHz helper can prepare a 160 MHz destination without claiming 160 MHz hardware support.

HT40 setup retains hostapd coexistence checks (`noscan=0`) and periodic overlapping-BSS checks. If setup retains 20 MHz on a member of the requested block, service must still verify. The rejected HT40 placement is remembered for the configured evidence-freshness period, with an explicit reason; it is not mislabeled as failed client connectivity. A verified HT40 checkpoint preserves its secondary direction.

Capability interpretation follows [Linux HT/VHT definitions](https://github.com/torvalds/linux/blob/v6.12/include/linux/ieee80211.h), regulatory range handling follows [cfg80211 AUTO_BW behavior](https://github.com/torvalds/linux/blob/v6.12/net/wireless/reg.c), and hostapd performs [HT40 coexistence and VHT configuration checks](https://github.com/vanhoefm/hostap-wpa3/blob/master/hostapd/hostapd.conf). Kernel and hostapd enforcement remains authoritative.

`radar.uc` remembers at most 128 recent incidents independently of optional graph history. Each detection's weight halves over the configured half-life (default six hours). Overlapping incidents accumulate, capped at a risk of one. This affects planning and the fading channel bands in history; it is not radar probability. Kernel non-occupancy periods and CAC requirements always remain authoritative.

## History, persistence and privacy

`history.uc` records channel residence, five-minute traffic summaries, compact spectrum surveys and recent actions. They share the selected retention window of up to 200 hours. The graph's Show selector limits the visible window; it does not change stored retention. Recent actions have no separate count cap. The daemon's small operational event list is distinct from retained history.

Recent history is bounded to 1 MiB in RAM. `history-storage.uc` offloads immutable batches every six hours during normal operation, keeping the most recent hour cached in RAM. Batches retain original summary detail; no new two-hour aggregation is performed. Flash has no fixed archive-size cap, but writes must leave at least 4 MiB free. Heavy activity or failed offloads can fill RAM and discard oldest buffered records. Expired archive batches are deleted at scheduled maintenance rather than rewritten on each refresh.

Ordinary service restarts reuse same-boot RAM history without forcing flash writes. The orderly shutdown hook saves pending history and radar memory once after the daemon stops. Unexpected power loss loses unsaved data. Disabling recording pauses new records; clearing history removes graph data and actions without erasing radar memory. Only current immutable batch archives are read. Legacy `history.json` archives and two-hour aggregation are no longer supported.

Verified channel settings and radar memory also use periodic six-hour persistence. Radar memory has a shutdown checkpoint; ordinary service restarts recover its same-boot RAM events. Runtime recovery journals can contain the local AP configuration and are not exported. History records no SSIDs, passwords, browsing activity or client identities.

## Supported scope

Live validation is specific to the WRT3200ACM and its single-AP HT/VHT radios. HE/EHT and MLO are outside current support. Multi-interface arrangements are not validated; restart and preparation paths require a compatible single BSS. Hardware-specific defaults and the WRT3200ACM/WRT32X country helper are intentional compatibility code, not a second planning algorithm.

Fresh packaged configurations enable automatic operation, active-where-permitted paced scanning and DFS preparation. If core settings are missing from a damaged or older configuration, the daemon falls back conservatively to observation, passive scanning and DFS off. Existing current-format administrator settings are preserved; obsolete `move_clients` settings are not interpreted.
