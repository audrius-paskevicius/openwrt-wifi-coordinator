# Agreement review, 7 November 2026

This review compares the requested behavior with the implementation and deployment evidence. It distinguishes an implementation from proof of universal radio performance.

## Gaps corrected in r12

**Short explanations with full hover help on every settings page.** r10/r11 created DOM descriptions, but the target LuCI's `Value.renderFrame()` accepts only string descriptions. The controls therefore lost their explanations despite the helper's unit tests passing. The helper now supplies escaped HTML strings, preserving LuCI's own help styling and tooltip implementation. Hovering either the short text or the theme's question mark works; keyboard focus, Enter/Space, Escape and click/tap are supported. Delegated interaction handling survives form re-rendering. Three specialist settings also now have explicit short summaries.

**Visible applied behavior and reasons.** r11 passed a DOM node as a named-section description, which this LuCI likewise omitted. Applied method choices, Auto's reasoning and temporary exclusion reasons/countdowns are now mounted through the section's actual rendering lifecycle and remain attached during polling.

The browser regression fixture exercises the target router's actual Value/NamedSection render methods and native tooltip methods. It checks all 56 setting descriptions across Channels, Clients and History, including dynamic status, retained expansion and unsaved edits. Its UCI data and radio state are synthetic; it does not change wireless configuration. See [validation](TESTING.md) for test scope.

**Width Auto must follow hardware.** The initial review identified a software ceiling of 20 MHz in 2.4 GHz and 80 MHz in 5 GHz. That was not the requested behavior. r12 replaces it with per-band HT/VHT capability discovery, HT40 geometry/coexistence handling, VHT160 execution and segmented spare-radio DFS preparation. The tested router advertises 160 MHz on radio0, 40 MHz on radio1, and 80 MHz on radio2 in 5 GHz. Legal placement and verification still apply.

## Agreements retained

| Request | Current implementation / evidence |
| --- | --- |
| One self-contained installable project | One signed APK includes both cooperating services, all three LuCI pages and bundled Chart.js. Source, build scripts, tests and dependency instructions are published together. |
| Actual libraries and native styling | Charts use Chart.js; forms and help use LuCI's renderer and tooltip behavior. No separate tooltip library or custom help button appearance. |
| Auto channel lists for all radios; manual primary lists independent of width | Per-PHY live capabilities supply Auto. Manual primary-channel and width lists are separate plain text fields. Secondary frequencies still undergo regulatory/driver checks. |
| Auto can adapt, explicit choices stay explicit | r11 method resolution preserves fixed planned CSA/restart choices; emergency service recovery remains possible. r12 makes the previously hidden explanation visible. |
| Fewer settings, short explanations, detailed help | Six internal timing knobs were removed; specialist controls are under Advanced. Conditional controls preserve their saved values while hidden. [Settings audit](SETTINGS.md) records why each remaining control exists. |
| Paced scans without requiring silence | Paced scanning schedules short visits and serving gaps; quiet-only scanning remains an explicit alternate policy. Live r11 completed 41/41 requested frequencies. |
| Coordinate radios and prefer useful width | The joint planner ranks separation, useful width and capacity cost; it checks overlap at intermediate steps. Missing evidence is not treated as empty spectrum. |
| Try handoff first, then move despite stubborn clients | The common reconnect policy applies to all serving radios, subject to explicit protected-client and quiet/empty restrictions. No compatible target skips an impossible handoff wait. |
| Spare-radio DFS preparation and radar memory | Empty compatible helpers can perform clearance while other radios serve. Kernel clearance is verified on the destination PHY. Radar memory decays; it never overrides mandatory non-occupancy or listening. |
| One channel/time plot with both bands | One vertically ordered band/channel axis and a time axis show radio residence and width. |
| Gray survey background as ordinary datasets | Survey datasets share the chart and retained history. No separate enable switch or artificial 15-minute graph expiry. Planning evidence still has a separate freshness limit. |
| Distinct radios, hatching, narrow white edging and legend | Radio0 is magenta/diagonal, radio1 orange/vertical, radio2 blue/opposite diagonal. Transparent hatches preserve background visibility. Colored outlines are 2.5 px, white outlines 3.8 px; traffic curves have no area fill. Legend samples match the patterns. |
| Subtle decaying radar bands and explanatory legend | Amber bands cover detected spectrum and fade according to the configured half-life; the legend explains the decay. No large lightning markers. |
| Congestion information when airtime is unavailable | Summaries can show the shared survey estimate; measured airtime and inferred congestion remain distinct. Source times are in hover detail rather than repeated table lines. |
| Retention up to 200 hours; Show follows retention | Retention and viewing ranges use coordinated dropdowns. The view cannot request more than the configured retention. |
| Recent RAM history, older flash archive; infrequent writes | Immutable batches are offloaded every six hours. Original five-minute summaries, surveys and actions retain their detail. Flash has no arbitrary 256 KiB cap; writes reserve free space. RAM remains bounded. |
| Reboot survival; pause and clear are separate | Orderly shutdown checkpoints pending history and radar memory. Ordinary service restarts reuse RAM. Disabling recording pauses it; explicit clearing deletes graph history/actions. Recent actions share the selected retention. |
| Refresh must preserve expanded comparison and editing | The comparison details element is reused, and polling updates status without rebuilding the form. The native-browser fixture checks expansion and unsaved input preservation. |
| No credentials in the public project | Published source/release checks reject private keys and credential tokens. Router configuration and signing secrets remain outside the repository. |

## Boundaries still requiring explicit distinction

- **Hardware scope is HT/VHT.** Auto now covers this router's advertised contiguous widths. HE/EHT, 6 GHz and noncontiguous 80+80 require separate support; this router advertises none of them.
- **Connectivity is verified, not guaranteed seamless.** Some clients ignore roaming requests; restarts and CAC can interrupt service. Historical live reconnect testing recorded an interruption. DFS helper preparation still requires an empty helper; it does not strand attached clients for a long radar check.
- **A spectrum score is not a throughput measurement.** Survey and airtime evidence guide decisions; they do not prove a global maximum speed in a changing environment. Hardware/client coverage remains specific to the documented tests.
- **Upgrade preservation is implemented, a complete firmware-upgrade cycle is untested.** Keep-list entries and reinstallable signed APKs exist. The project is a GitHub/local package, not an accepted official OpenWrt feed package.

These are explicit scope limits, not hidden runtime changes to administrator preferences.
