# Validation

Source release: **0.6.0-r11**. Automated runtime tests use OpenWrt 25.12.6 on a Linksys WRT3200ACM. Checks for each release are distinguished below; earlier RF experiments are listed separately.

## r11 settings behavior audit

- All 109 channel/policy cases passed, including Auto resolution, WRT execution requirements, driver capability, failure expiry, independent width methods, explicit method preservation and strict integer validation. All 32 preferred-radio checks passed, including Strong with missing measurements and measured Strong eligibility.
- The complete runtime suite passed again: three usteer-restoration scenarios, 97 planner/radar/survey cases, 40 executor cases, five actual recovery-helper cases, 11 radar-persistence cases, 19 history cases and 668 storage cases. Storage tests retained 200 hours of original summaries/surveys without touching the live archive.
- JavaScript syntax, native-help interactions and nine history/cache cases passed. A settings-form harness checks actual option registration, Auto defaults, explicit choices, numeric-list validation, conditional controls, preservation of hidden values, Advanced placement and refreshed method/exclusion status. These use stubs, not a full browser rendering test.
- An isolated UCI fixture confirmed retired timing keys are removed, missing methods become Auto, and explicit CSA/channel lists remain unchanged. Entry-point compilation, package signature and extracted-file comparisons passed.
- The simulated and actual upgrade changed only this package. The installed configuration uses Auto for channels, widths and both switching methods on all three radios, with Automatic occupied-client handling. All six retired keys were removed. Existing failed-destination evidence was retained.
- After installation, both controllers and usteer were running, all four clients remained associated, all six checked UI resources returned HTTP 200, and three router internet probes succeeded. Auto resolved to CSA on radio0, restart on radio2, and restart on radio1 because of its remembered CSA failure. A subsequent paced survey covered all 41 requested frequencies and completed evaluation without a safety stop.
- This release validates policy behavior and live deployment; it does not establish seamless traffic during every future channel change or repeat all historical RF experiments.

## r10 automatic channel discovery and compact help

- 87 geometry/regulatory/policy checks passed, covering automatic discovery, channels 12/13 and 165, band isolation, disabled frequencies, no-initiation restrictions, DFS inclusion, capability changes, numeric overrides, automatic width selection, unsupported widths, invalid settings and channel-14 frequency conversion. Primary-only lists allow wider blocks while still rejecting disallowed secondary frequencies and unlisted primaries.
- The 97 planner/radar/survey cases, 40 executor cases and five recovery-helper cases passed again. Controller entry-point compilation, shell syntax, six JavaScript syntax checks and nine UI/cache cases passed.
- Shared help-control tests cover nested settings, native LuCI tooltip attributes, retained full text, click/tap, keyboard activation, Escape, accessible text, viewport fit and repeated rendering. LuCI supplies hover and focus behavior. These are DOM-stub interaction tests, not a full visual browser test.
- An isolated UCI fixture confirmed missing lists become `auto` while an explicit `1 6 11` list remains unchanged.
- Read-only discovery against live driver capabilities resolved different lists for each PHY. Radio1 offered 1–13; radio2 additionally exposed 5 GHz channels absent from the former fixed list, including 165. Radio0 did not advertise 165 as enabled.
- The signed APK and extracted application files were verified against source. The simulated upgrade changed only Wi-Fi Coordinator; no dependency changes were needed.
- Live installation set both channels and widths to `auto` on all three radios and applied the documented WRT3200ACM switching defaults. Both controllers and usteer were running afterward; all four clients remained present at the final check. The three views, new help module and stylesheet returned HTTP 200.
- During rollout, the expanded pool completed a 41-frequency survey and selected channel 13 on radio1. Client verification failed; the existing recovery path returned it to channel 10, restored both clients and temporarily excluded channel 13 for six hours. Automatic lists remain unrestricted by a fixed 1–11 cap. This is recovery evidence, not proof that every advertised channel works with every client.

## Baseline automated checks (r8)

The development validation passed:

- 63 geometry/regulatory/coordination checks and 30 Radio Preference policy/protocol checks. Three tests of the removed, unused planner were retired; the current planner remains covered by the suite below.
- usteer restoration checks for original values, absent values and administrator edits.
- 97 planner, radar, and survey cases, including changing winners without lost comparison evidence.
- 40 executor cases: active CSA, compatible handoff first, occupied restart fallback, stranded clients, reconnection grace, rollback, protected clients, and peer-radio isolation.
- 5 tests extracted from the actual recovery helper: interrupted restarts, already-restored radios, administrator edits, DFS empty-radio requirements, and stale-boot journals.
- 19 history checks, 668 storage checks, and 11 radar-persistence checks. Current batch retention and rejection of obsolete archives replace legacy import coverage.
- 9 browser history/cache checks. The portable Node version runs the same history/cache cases without browser automation.

The full history simulation preserved 7,203 summaries, 2,401 surveys, and 2,401 actions for a 200-hour retention window in about 4.8 MB across 34 flash-style batches. It also checked pause/resume, explicit clearing, orderly shutdown, and unchanged-save behavior. Test storage is redirected to `/tmp`; the test does not write the router's real history archive.

Run `python3 scripts/prepare-tests.py` before the ucode suite. This creates test modules from the current production source, redirecting storage and injecting time. Generated fixtures are not the production daemon. `scripts/test-ucode.sh` prevents concurrent runs of this test suite.

## r8 installation checks

- The simulated transaction upgraded only Wi-Fi Coordinator; all declared dependencies were already present. Full `wpad-mbedtls` exposed the required client, neighbor, BSS-transition and channel-switch APIs.
- The signed APK upgraded r7 to r8 successfully. Channel Coordinator, Radio Preference and usteer were running afterward, with no coordinator safety stop.
- Wireless and both coordinator configuration files remained byte-identical. All three APs remained available, with the same client counts and frequencies at the before/after checks.
- All six UI JavaScript/CSS resources returned HTTP 200. These HTTP and syntax checks do not replace a full browser interaction test.
- The router answered all three internet probes at approximately 3 ms. This installation check does not establish lossless client traffic or retest RF throughput.

## Historical live observations (r7 and earlier)

- Paced scanning completed all 36 configured frequencies. In the tested scan schedule, a monitored 5 GHz client answered 120/120 probes with at most 4 ms latency.
- The expanded channel-comparison panel remained open while status refreshed.
- Shutdown checkpointing was exercised without rebooting the router. Repeating a checkpoint with no new data left archive hashes unchanged.
- The reconnect fallback changed the occupied 2.4 GHz radio from channel 1 to 8 at 20 MHz. Its client rejoined the same AP. The executor reported zero missing or unproven clients and one disconnect event.
- During that change, 9 of 120 one-second probes were lost around the restart, approximately a ten-second interruption. Subsequent probes from a wired PC succeeded 8/8 at 2–8 ms. These are connectivity observations, not throughput measurements.
- Both 5 GHz radios retained their channels during that targeted test. Other hardware, client combinations, and recovery scenarios are covered by mocks or remain unvalidated.

## Limits

Tests do not prove maximum speed, universal device compatibility, lossless roaming, or regulatory certification. Live radar was not artificially transmitted. A complete firmware-upgrade cycle has not been tested. Release APKs are signed, but publishing the source does not make this an official OpenWrt package.

GitHub Actions runs portable file, documentation-link, syntax, and UI/cache checks. The full ucode suite requires OpenWrt's runtime modules and is documented separately rather than reported as having run in a generic Node CI environment.

## Self-contained project validation

The complete ucode suite passed from an isolated copy of this project, using test modules generated by `scripts/prepare-tests.py`. The portable Node UI/cache tests and project checks also passed. The documented APK builder produced a signed APK and package index from that isolated source, and native `apk verify` accepted the package. Packaged application files were compared with source, accounting for the build-time stylesheet version substitution. The private signing key remained outside the source tree and was removed from the temporary build host afterward.
