# Agreement review, 8 November 2026

This review compares the requested behavior with the current implementation and deployment evidence. It distinguishes an implementation from proof of universal radio performance.

## Current behavior review

The current implementation uses native LuCI help on all setting descriptions (52 in the healthy three-radio fixture; recovery acknowledgement adds one when needed), including opaque tooltip backgrounds, keyboard and touch interaction. Applied methods and temporary restrictions remain visible during refreshes. The browser component fixture uses the target LuCI rendering and tooltip methods with synthetic configuration; it is not an authenticated end-to-end router test.

Width Auto follows advertised HT/VHT capabilities. The tested router advertises 160 MHz on radio0, 40 MHz on radio1, and 80 MHz on radio2 in 5 GHz. The joint planner compares estimated service across eligible widths rather than always ranking the widest first. Regulatory limits, coexistence and verification still apply. Historical fixes and their validation remain in [the test record](TESTING.md).

## Agreements retained

The operating goal is opportunistic use of available spectrum, including DFS.
Occasional radar-triggered interruptions are an accepted tradeoff. Prepare mode
may clear an eligible block on an empty helper while another radio serves clients,
use the block after clearance, and reconsider it after a radar exclusion expires.
There is no non-DFS-only preference or private-debug-field veto. Kernel country
rules, CAC, non-occupancy periods and service verification remain mandatory.
Eligibility does not promise an immediate return: fresh survey evidence, service
scoring and any active recovery restrictions still govern the next move.

| Request | Current implementation / evidence |
| --- | --- |
| One self-contained installable project | One signed APK includes channel coordination and Radio Preference under one decision owner, six LuCI pages (Channels, Clients, Comparison, History, Storage & export and the disclaimer tab) and bundled Chart.js. Source, build scripts, tests and dependency instructions are published together. Required OpenWrt runtime packages are resolved separately by apk. |
| Visible disclaimer without a recurring banner | The README and release start with the full notice. The APK prints and bundles it; a boldly labelled LuCI tab always exposes it. First use requires browser acknowledgement, preserved across upgrades while the text is unchanged. |
| Automatic restart recovery | Interrupted operations restore temporary configuration and check AP readiness for 30 seconds before resuming. Unresolved recovery and failed radios are reassessed automatically with backoff capped at five minutes. Failed radios need stable AP state and positive service evidence; restarting or an expired timer alone does not clear a failure. Manual acknowledgement remains available after administrator checks. |
| Actual libraries and native styling | Charts use Chart.js; forms and help use LuCI's renderer and tooltip behavior. No separate tooltip library or custom help button appearance. |
| Auto channel lists for all radios; manual primary lists independent of width | Per-PHY live capabilities supply Auto. Manual primary-channel and width lists are separate plain text fields. Secondary frequencies still undergo regulatory/driver checks. |
| Auto can adapt, explicit choices stay explicit | Fixed planned CSA/restart choices remain fixed; Auto adapts to capabilities and recent failures. Applied choices and reasons are visible. Emergency service recovery remains possible. |
| Fewer settings, short explanations, detailed help | Six internal timing knobs and the obsolete narrowing threshold were removed; settings are consolidated by algorithm responsibility, with driver overrides per radio. Conditional controls preserve their saved values while hidden. [Settings reference](SETTINGS.md) records why each remaining control exists. |
| Paced scans without requiring silence | Paced scanning schedules short visits and serving gaps; quiet-only scanning remains an explicit alternate policy. Live r11 completed 41/41 requested frequencies. |
| Coordinate radios and prefer useful width | The joint planner ranks separation and hardware-based service for present and future clients; it checks overlap at intermediate steps. Missing evidence is not treated as empty spectrum. |
| Try handoff first, then move despite stubborn clients | The common reconnect policy applies to all serving radios, subject to explicit protected-client and quiet/empty restrictions. No compatible target skips an impossible handoff wait. |
| Spare-radio DFS preparation and radar memory | Empty compatible helpers can perform clearance while other radios serve. Kernel clearance is verified on the destination PHY. Radar memory decays; it never overrides mandatory non-occupancy or listening. |
| One channel/time plot with both bands | One vertically ordered band/channel axis shows residence and width over time. Each declared band gets its full standard layout, with gaps compressed; display does not imply local permission or hardware support. |
| Gray survey background as ordinary datasets | Survey datasets share the chart and retained history. No separate enable switch or artificial 15-minute graph expiry. Adjacent cells do not add dark seams. Planning evidence still has a separate freshness limit. |
| Distinct radios, hatching, narrow white edging and legend | Radio0 is magenta/diagonal, radio1 orange/vertical, radio2 blue/opposite diagonal. Transparent hatches preserve background visibility. Colored outlines are 2.5 px, white outlines 3.8 px; traffic curves have no area fill. Legend samples match the patterns. |
| Subtle decaying radar bands and explanatory legend | Amber bands cover detected spectrum and fade with a one-hour default half-life. Both legend bars are 180 pixels wide with five numeric ticks. Radar strength runs from 100% to a white 0% endpoint; decay times appear on hover. Congestion uses a separate 0–100 estimate scale. No large lightning markers. |
| Congestion information when airtime is unavailable | Summaries can show the shared survey estimate; measured airtime and inferred congestion remain distinct. Source times are in hover detail rather than repeated table lines. |
| Retention up to 200 hours; independent viewing and export windows | Storage & export contains retention and download controls. History's Show and exports' Period selectors are independent, each capped by saved retention. Exports default to All retained history. |
| Download graph data and actions without router export files | Authenticated POST downloads stream JSON or dataset-specific CSV. They use bounded source batches and a per-dataset deduplication index, with no temporary export file or export-related flash writes. CSV and JSON have separate Download rows; both use the export Period selector. See [formats and completeness checks](EXPORT.md). |
| ISO-style dates and uncluttered graph captions | Graph ticks use browser-local 24-hour time. Dates appear only for windows spanning at least 24 hours and crossing local midnight. No Time axis label or standalone timezone caption. Full timestamps include date and seconds; exported timestamps are UTC. |
| Recent RAM history, older flash archive; infrequent writes | Immutable batches are offloaded every six hours. Original five-minute summaries, surveys and actions retain their detail. Flash has no arbitrary 256 KiB cap; writes reserve free space. RAM is bounded at 1 MiB. Authenticated streaming reads avoid the ordinary ubus file-size limit; read errors are visible. Storage diagnostics stay collapsed unless opened. |
| Reboot survival; pause and clear are separate | Orderly shutdown checkpoints pending history and radar memory. Ordinary service restarts reuse RAM. Disabling recording pauses it; explicit clearing deletes recorded history/actions but preserves planner radar memory, which can still appear as shading. Recent actions share the selected retention. |
| Refresh must preserve expanded comparison and editing | The comparison details element is reused, and polling updates status without rebuilding the form. The native-browser fixture checks expansion and unsaved input preservation. |
| No credentials in the public project | Portable source checks reject recognizable private-key and GitHub-token patterns; release audits also inspect the extracted APK and compare its files with the intended source. Router configuration and signing secrets remain outside the repository. |

## Boundaries still requiring explicit distinction

- **Hardware scope is HT/VHT.** Auto now covers this router's advertised contiguous widths. HE/EHT, 6 GHz and noncontiguous 80+80 require separate support; this router advertises none of them.
- **Connectivity is verified, not guaranteed seamless.** Some clients ignore roaming requests; restarts and CAC can interrupt service. Historical live reconnect testing recorded an interruption. DFS helper preparation still requires an empty helper; it does not strand attached clients for a long radar check.
- **A spectrum score is not a throughput measurement.** Survey and airtime evidence guide decisions; they do not prove a global maximum speed in a changing environment. Hardware/client coverage remains specific to the documented tests.
- **Upgrade preservation is implemented, a complete firmware-upgrade cycle is untested.** Keep-list entries and reinstallable signed APKs exist. The project is a GitHub/local package, not an accepted official OpenWrt feed package.

These are explicit scope limits, not hidden runtime changes to administrator preferences.

Preferred-radio steering and radar/channel handoffs share one Gentle / Strong / Decisive policy, escalation timing, protection rules and retry budgets. Failed return requests do not automatically penalize a channel placement.

The settings redesign retains operational controls after tracing their consumers; it does not reduce configurability to meet a UI target. See [the audit](SETTINGS-AUDIT.md). Channels and Clients have no Save/Apply controls; shared steering policy appears once in Settings.
