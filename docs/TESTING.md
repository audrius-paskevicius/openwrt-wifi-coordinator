# Validation

Source release: **0.7.0-r17**. Automated runtime tests use OpenWrt 25.12.6 on a Linksys WRT3200ACM. Checks for each revision are distinguished below; earlier RF experiments are listed separately. Historical counts describe the source tested then, not the current test inventory. The r22 presentation changes were included in the public r23 release; there was no separate public r22 release. Some historical release downloads have been withdrawn; entries below are validation evidence, not a promise of current download availability.

## Reproducing current checks

Run the portable source/documentation checks with `python3 scripts/check-project.py` and the UI checks with `node tests/check-ui.cjs`. These require no router access. The UI suite includes 54 history/cache assertions and 30 interruption/recovery cases. For actual LuCI and Chart.js browser component checks, use the fixture generators described below; the current healthy three-radio LuCI fixture expects 52 setting descriptions, with one additional recovery acknowledgement when applicable.

Generate isolated runtime fixtures with `python3 scripts/prepare-tests.py`, then run `scripts/test-ucode.sh` on an OpenWrt environment with the required ucode modules. This suite includes scanner continuity/quality, the service model, executor, recovery and archive tests. It redirects test state to dedicated temporary paths and does not operate live radios. A successful portable check does not imply this runtime suite or live RF tests were rerun.

## 0.7.0-r17 History header and readable durations (2026-11-10)

The History period selector sits at the right of the page title and wraps below
it when the available width is too narrow. Its label remains associated with
the native select control. Viewing-window behavior and graph data are unchanged.
Displayed elapsed times use at most two decimal places, removing floating-point
precision tails in Recent actions, radar preparation and residence times. Stored
values and export precision are unchanged. Portable UI checks passed; no backend
behavior changed in this revision.

The signed package and index verified; all 46 payload files matched source and
sensitive-data checks passed. Installation preserved the six checked router
configuration files. Live Chrome checks at 1280 and 390 pixels verified title
alignment, narrow-screen wrapping, the associated label and period changes.
Floating-point examples displayed as 0.2, 2.52, 3.58 and 0.28 seconds; live action
rows contained no long decimal tails. The clean navigation check completed
without browser exceptions.

## 0.7.0-r16 UI wording and empty-history state (2026-11-10)

Status and help text across Channels, Clients, Comparison, History, Settings
and Storage & export now focus on current state, value meanings and user
choices. Historical migration notes, repeated notices and internal bookkeeping
explanations were removed. Comparison column help retains score definitions;
setting help retains disruption, recovery, radar and data-loss consequences.
Empty History distinguishes recording enabled, recording disabled and a failed
history read, using the recorder state with configured recording as fallback.

Portable source and UI checks passed. The actual LuCI Chrome fixture passed
with 52 setting descriptions, hover/focus/tap help, retained editing during
polling, comparison refresh, export selectors and the empty-history states.
There were no browser exceptions. Backend coordination, scoring, steering,
recording and export logic are unchanged; the runtime suite was not repeated
for this UI revision.

The signed APK and package index verified, all 46 payload files matched source,
and source/package sensitive-data scans passed. Installation preserved all six
checked configuration files. All six live LuCI pages rendered without warnings
or browser exceptions; History displayed all three charts with the revised
help. Comparison and Settings were also visually reviewed in Chrome.

## 0.7.0-r15 quiet zero-congestion areas and survey documentation (2026-11-10)

Documentation was rechecked against scanner selection, visit accounting,
recording/export allowlists, service startup and the existing UI. It now states
that continuity resolves exact cost ties, resets on restart and remembers a
completed scan even when it detects no neighbours. Export descriptions separate
sweep elapsed time from summed visit duration, attempted frequencies from
successful coverage, and per-visit detections from sweep-level distinct BSSIDs.
Cancelled sweeps need not have a matching survey frame or neighbour count.
The strongest-signal aggregation remains explicitly documented; no averaging or
new sparse-survey scoring was introduced.

Zero-congestion cells now produce no congestion popup. Nonzero readings and
radio/event/radar tooltips remain available. The actual Chart.js Chrome fixture
reproduced the zero-popup case before the fix and passed afterward, including
mixed zero/nonzero/radio selections and existing ribbon deduplication checks.
Portable source, link/privacy and UI checks passed. Controller, recorder and
export logic are unchanged from r14; the full isolated runtime suite passed for
r14 and is not repeated for this tooltip/documentation change. Historical
validation entries remain unchanged.

The signed APK and index verified, all 46 payload files matched source, and
source/package sensitive-data scans passed. Comparison with the r14 payload
found only the graph tooltip filter and embedded version changes. Installation
preserved all six checked configuration files. On the live History chart,
zero-only congestion selection produced no tooltip content; mixed selection
kept the nonzero reading and radio entry. All three charts rendered without
warnings or exceptions on a clean reload. Authenticated quality exports completed.

## 0.7.0-r14 scanner continuity and quality evidence (2026-11-10)

Automatic scanning retains the last successful receiver for each band only when
eligible choices have equal service cost. A cheaper scanner, fixed selection,
reservations, safety/capability checks and serving gaps remain authoritative.
The sweep action records compact per-radio quality summaries; existing retry
and abort events keep radio/frequency/timing context and a sweep ID. No extra
scan visits, longer dwell, additional retries or separate diagnostic flash log
are introduced. Signal aggregation and sparse-survey scoring are unchanged.

All 21 new injected scanner cases passed, including ties, changing enumeration,
cheaper alternatives, reservations, fixed/unsafe scanners, no extra scan visits,
existing serving gaps, two-retry limits, cancelled partial coverage, fresh BSS
counting and omission of identities. The 23 history checks and 42 export checks
include nested quality allowlists and JSON/Actions CSV retention. Portable and
native LuCI browser checks passed. The full isolated OpenWrt suite passed,
including the 120-hour archive simulation. The APK/index signatures verified;
all 46 payload files matched source and sensitive-data scans passed.

Live installation preserved all six checked configuration files. The History
page rendered three charts without warnings or exceptions on a clean reload.
Two normal sweeps completed 41/41 frequencies: the summaries identified radio2
and recorded zero and two retries respectively. The second sweep recorded 43
visits, including its two aborts. The short monitored interval kept owner status
within one second, without a halt, archive error or dropped records. Authenticated
JSON and Recent actions CSV included the quality data and completeness results;
the History action table showed its compact summary. These observations verify
recording and operation, not a sustained improvement in RF measurement accuracy.

## 0.7.0-r13 documentation alignment (2026-11-10)

The current documentation was traced against the LuCI menu and views, settings
parsers/defaults, service scripts, history reader/recorder, exporter and package
hooks. Corrections cover all seven tabs, the single supervised service, the
standalone Comparison page, client-count clearing/exports and the exact 120-hour
read limits. The settings audit now distinguishes the earlier presentation change
from the later retention migration. Historical validation remains dated evidence.

This release changes documentation and the package version only. Runtime source
is unchanged from r12. Portable source/link/privacy and UI checks passed; the full
isolated runtime suite passed for r12 and is not repeated for these documentation
changes.

The APK and package index signatures verified. All 46 extracted payload files
matched source; comparison with the r12 payload confirmed that only embedded
version strings changed. Source and package secret scans passed, including checks
against saved router credentials. Installation changed none of the six checked
configuration files. The shared service ran, retention remained 120 hours, and
History rendered all three charts without warnings or exceptions on a clean
reload. Live Storage/export checks confirmed the 120-hour selectors, rejected
121/200-hour requests and completed a one-hour JSON export tagged r13.

## 0.7.0-r12 bounded history windows (2026-11-10)

Retention, History Show and export Period now stop at 120 hours. Upgrade migration
reduces larger saved values to 120 and preserves smaller values. The recorder
also clamps legacy configurations. History and exports skip expired archive
batches before reading them; cached batches expire without another fetch.
Physical deletion keeps the existing six-hour schedule.

Portable checks, the native LuCI fixture and actual Chart.js Chrome fixture
passed. The UI fixture starts with a legacy 200-hour setting and verifies all
three limits. Cache tests cover the cutoff boundary and expiry. The full isolated
ucode suite passed, including migration/idempotency, 38 streaming export checks
and 552 archive-storage checks: a 216-hour simulation retained all 4,323 original
samples and 1,441 surveys in the final 120-hour window (21 boundary-inclusive
batches). No live RF experiment was required for this storage change.

The signed APK verified and all 46 payload files matched source. Source and
extracted-package secret scans passed, including comparison with saved router
credentials. Installation changed only history retention from 200 to 120 among
the six checked configuration files. The live recorder reported 120 hours; all
three charts rendered without warnings or browser exceptions. Retention, Show
and export selectors stopped at 120. Authenticated 121/200-hour requests returned
400; a one-hour JSON export completed with retention metadata of 120.

## 0.7.0-r11 single-entry ribbon tooltips (2026-11-10)

Closing a channel ribbon repeats its first corner. The tooltip now includes
each recorded interval once even if multiple outline vertices are selected.
Decorative fill/halo layers remain excluded. Distinct intervals and radios
remain separate entries; event markers are unaffected.

The actual Chart.js Chrome fixture reproduced the duplicate before the fix and
passed afterward. It selects both closing vertices and decorative layers, and
checks that distinct intervals/radios remain visible. Portable UI/cache checks
also passed. This is a tooltip-only change; radio algorithms and recording are
unchanged, so the full runtime/RF suite was not repeated.

On the installed router History chart, selecting both closing vertices produced
one tooltip entry. All 46 package payload files matched source; signatures and
source/package secret scans passed. All six checked router configuration files
remained unchanged.

## 0.7.0-r10 clearer comparison notes (2026-11-10)

Comparison separates width restrictions from deferred channels and groups
channels sharing a reason and width. The notes explain the observed result and
client-service restrictions in plain language. End times are derived from the
saved comparison's wall clock and uptime; older snapshots without both omit
the time. A radio-wide width pause replaces redundant per-channel width notes
only when it covers the same width reduction and at least the same interval.
Event tooltips keep the description and timestamp without the marker-height
explanation. This release changes presentation only.

Portable UI checks, the actual LuCI browser fixture and Chart.js render fixture
passed. The LuCI fixture verifies grouped reasons, distinct width notes, correct
snapshot-based end times, missing-time handling and retained tables across
refreshes. The graph fixture checks concise event tooltips. Runtime algorithms
are unchanged; the full ucode/RF suite was not rerun for this presentation change.

The signed APK verified and all 46 payload files matched source. Secret scans
passed for source and extracted payload. On the router, the Comparison page
showed separate width/client notes, grouped channels 12 and 13 and their distinct
end times without warnings. All six checked configuration files remained unchanged.

## 0.7.0-r9 responsive planning and history evidence (2026-11-10)

Candidate scoring and the final pre-move comparison run in one read-only worker.
The decision owner keeps observing and processing radar/steering events. Helper
configuration checks are cached within the captured calculation. The candidate
spectrum, scoring algorithm, movement costs and execution safeguards are retained.

Tests cover worker isolation, timer responsiveness during CPU work, identical
search results, changed inputs, timeout, failure and shutdown (11 checks), plus
15 snapshot-validity checks. Executor tests now cover deferred/accepted/rejected
asynchronous validation (1,130 cases total). History checks distinguish missed
samples from confirmed unavailability, split short outages and merge interval
extensions (20 client-history cases). The 38 export checks include timings,
missed samples, interval deduplication, UTC boundaries and private-field filtering.
The existing 200-hour archive simulation and portable UI/cache tests also run.
The actual Chart.js fixture checks unknown-gap, unavailable and action markers,
tooltips and retained spectrum/traffic geometry in Chrome.

Live validation uses the normal configured planner and saved history. The first
comparisons took about 2.5 seconds while observed owner updates stayed within
1–2 seconds. This is evidence for responsive live operation, not a guarantee of
zero wireless outages or proof that every historical gap had the same cause.
Radar/CAC and real channel moves can still interrupt service. Old gaps remain
unknown; new records distinguish positive AP-unavailability observations.

The final full isolated suite passed, including 668 archive-storage checks with
7,203 original samples and 2,401 surveys retained for 200 hours. The signed APK
verified and all 46 payload files matched source. Source and extracted payload
secret scans passed, including checks against the router's saved credentials.
Installation preserved all six checked network/coordinator configuration files.
The final monitored run kept owner updates within three seconds under concurrent
test/export load, with no observations older than five seconds. Live JSON and
Actions CSV downloads completed and included calculation timings without private
runtime fields. The actual LuCI History page rendered three charts with no
warnings or exceptions on a clean reload.

## 0.7.0-r8 configuration audit and settings redesign (2026-11-10)

One Settings page owns both existing configuration namespaces. Channels and
Clients are status-only views. All active operational controls are retained;
conditional values remain saved. Explanations cover shared-policy scope,
independent Observe/steering behaviour, signal restrictions, movement-cost
scaling and evidence/retry coupling. Recovery acknowledgement is contextual.
Client Recent attempts now reports the current shared budget and its expiry.

The full isolated OpenWrt suite passed, including 39 shared steering/integration
checks, 1,127 executor cases, 1,023 restart checks, 148 planner cases, 33 export
checks and 668 storage checks. The added counter cases verify shared-path updates
and expiry. Portable checks and the native LuCI fixture passed with 52 setting
descriptions, explicit cross-configuration read/write bindings, Automatic empty
choices, retained hidden values, nested radio forms and delegated help.

Live Chrome exercised the real form dependency and parse methods with writes
intercepted: independent enable/configuration bindings, preference-only versus
shared controls, hidden-value retention and Automatic helper/scanner selections.
The live test found and corrected an unqualified cross-namespace validation lookup
and the former required-empty Automatic choices. Draft changes were discarded;
no experimental policy changes were applied. Live checks also passed for draft
timing updates, managed-radio versus scanning quiet dependencies, the direct
steering link, and status pages without save controls. There were no page
exceptions in the final live checks; the test browser was logged out and closed.

The signed APK and index passed native verification. All 45 payload files matched
source/generated content, and installed application files matched the package.
All six configuration files remained byte-identical after installation and UI
tests. The coordinator reported no safety stop or steering integration error.
Source and extracted package scans found no credentials; private signing material
remained outside the repository and was removed from temporary build locations.

## 0.7.0-r7 shared steering escalation (2026-11-10)

Preference and channel/radar handoffs use the same escalation policy, neighbour
request builder, signal/protection checks, client/destination attempt ledger and
forced-disconnect budget. The separate preference strength and measured-signal
threshold are migrated into the existing shared settings. Channel selection and
failed-return placement penalties are not changed by this release.

The full isolated OpenWrt suite passed, including 36 shared-policy and actual
preference integration checks, 17 preference protocol checks, 1,127 executor cases,
1,023 restart checks, 148 planner cases and the existing history/export/storage
suites. The new tests exercise all three strengths, absent and weak measurements,
cross-band safeguards, shared budgets, protection and placement changes, lost
clients, successful return, expired reservations and shutdown cleanup. The native
LuCI browser fixture passed with 53 setting descriptions and no page exceptions.
These simulated checks do not establish universal client roaming support.

The final signed APK and index passed native signature verification; all 44
payload files matched the source or documented build substitutions. The installed
application files matched that payload. An isolated migration test passed,
including idempotence, and the live upgrade retained the existing Decisive choice
and other settings apart from the documented migration. Network, wireless,
firewall and DHCP configuration files remained byte-identical.

Live Chrome checks confirmed the shared control and Clients-page link, removal
of the retired preference controls, and no page exceptions. After installation,
both 5 GHz clients were on the preferred radio; two legacy clients remained
connected on 2.4 GHz without a qualifying target measurement. There was no
integration error or safety stop. Later live history recorded gentle requests,
Strong warnings approximately 30 seconds later, and one client arriving at the
preferred radio six seconds after the warning. Another remained on the alternate
radio; its disconnect was withheld, with a subsequent source signal of -81 dBm
against the configured -70 dBm source threshold and no recent forced-disconnect
budget use. No forced disconnection was needed for the successful return. These
observations do not establish universal roaming success or improved throughput.
Source, extracted package and release assets were checked for credentials before
publication. Temporary signing material and the test browser login were removed.

## 0.7.0-r6 client-aware movement balance (2026-11-10)

The same movement rule now applies to every radio, with affected-client counts,
observed CSA departures, helper preparation and staging included. Temporary holds
retain comparison alternatives without making them executable. Width-refusal
attempts survive pause expiry and also cover narrower 5 GHz outcomes. Decision
and observed outcome fields are retained in history and JSON/CSV action exports.

The full isolated OpenWrt suite passed, including 41 controller checks, 148
planner/radar/survey cases, 30 service-model cases, 1,127 executor cases and 1,023
restart-recovery checks. Regressions exercise client-count weighting, learned
CSA cost and ageing, helper selection, repeated staging exposure, held alternatives,
retry expiry, configuration changes, distinct departures and 160-to-80 MHz fallback.
The 20 history and 33 export checks include the new fields and identity filtering.
The 668 storage checks retained all 7,203 samples and 2,401 surveys across 200 hours.
Portable source/UI checks and the actual LuCI browser fixture passed, including
55 setting descriptions, visible alternatives during holds, candidate and route
costs, and outcome metrics displayed alongside the event reason.

Forty additional client-aware comparisons matched an exhaustive feasible-layout
reference with separation both enabled and disabled, including unusual explicit
channel/width methods. An optimistic cost bound skips uncompetitive branches
before route search. A read-only replay of one saved router comparison took about
0.03 seconds with the new planner and 4.91 seconds with the old one; they made
different decisions under their different movement policies. This single snapshot
is not a general performance benchmark.

The signed APK/index verified, and all 43 extracted payload files matched source
or generated content. Installation preserved all six checked configurations. The
installed CGI passed 15 authorization/download checks. Temporary signing copies
were removed. Source and package payloads were checked against private router
credentials without publishing those values.

Chrome verified the installed Comparison page with 161 candidate rows, direct
movement costs and complete-route client exposure, without page exceptions. A
live automatic operation prepared and shared DFS clearance, then reconsidered the
move after newer survey evidence: the changed benefit did not meet the new
uncertainty margin. It restored the helper and cancelled before moving the serving
radio; no client departures were recorded. The coordinator continued scanning with
no failure latch. Two additional authenticated download checks confirmed that the
actual recorded decision fields appeared in both JSON and action CSV.

These tests establish policy and serialization behaviour, not throughput benefit
or the optimum movement frequency in a changing RF environment. The new exported
figures support evaluating actual moves over time.

## 0.7.0-r5 Comparison tab and history presentation (2026-11-10)

The full placement comparison moved from Channels to a dedicated Comparison tab
before History, displayed directly. The page retains its completed results through
scans and read failures, shows current operation and comparison age, and preserves
the table DOM when only status changes. Channels retains settings and live status.
The package also includes the client-line fins, matching legend, 80-pixel aligned
axis gutter and Recent actions title tooltip previously tried on the router.

Portable source/UI checks passed, including ten JavaScript syntax checks. The
native LuCI browser fixture passed all 55 setting descriptions and its updated
comparison checks: direct display, retained results, replacement, stable table DOM,
failed-read warning and recovery. Chrome verified the installed menu order, 152
candidate rows, removal from Channels, fin legend and Recent actions tooltip with
no page exceptions. The actual Chart.js render fixture passed after the fin and
axis changes. The signed APK/index verified; all 43 payload files matched source
or generated content. Six configuration hashes were preserved. Runtime, storage
and radio algorithms are unchanged, so native RF/storage suites were not repeated.

## 0.7.0-r4 client-count history (2026-11-10)

The new graph sits between placement and traffic history and uses the traffic
chart's colours, line weight, dimensions and time axis. Counts are whole-number
observations; older data is left blank. All three graph explanations are title
tooltips, with keyboard activation and tap support.

Portable source/UI checks passed, including 52 history/cache assertions and new
count-step, zero, gap, reboot-boundary and title-order cases. Native OpenWrt checks
passed: 19 history cases, 13 client-count recording/migration/storage cases, 31
streaming export cases and 668 archive-storage cases. The 200-hour simulation
retained all 7,203 traffic samples and 2,401 surveys, with client intervals sharing
the existing RAM cap and archive policy. Fifteen live CGI checks covered access
denial, invalid requests and authenticated JSON/CSV downloads for all six datasets.

Chrome rendered the actual Chart.js fixture and the installed History page. The
live page showed the three graphs in order, omitted explanatory paragraphs, and
opened title help with the keyboard. An authenticated JSON download contained
newly recorded client intervals and a complete result. The signed APK and index
verified; all 42 payload files matched source/generated content. Configuration
hashes for network, firewall, DHCP, wireless and both coordinator files were
unchanged after installation. Source and payload secret scans passed, including
an on-router comparison with private configuration values. Channel-planning and
steering behavior are unchanged; their unrelated RF trials were not repeated.

## 0.7.0 shared controller (2026-11-09)

The complete isolated OpenWrt suite passed again on the final release after the
live findings: 24 shared-controller checks, 60 preference/protocol checks, 108
planner/radar/survey cases, 18 actual candidate cases and 1,122 executor cases.
The full run also covered 1,023 restart-recovery
checks and 668 archive-storage checks. These are assertions and simulated
sequences, not equivalent numbers of RF trials.

Four checks extracted from the actual owner error handlers ensure that a busy
scanner cancels/retries its survey without aborting a separate radio operation,
and that an execution error does not cancel an unrelated survey.

New regressions cover movement cost, incumbent retention, no confidence gained
from repetition alone, scoped reservations, early complete-band publication,
fresh-plan validation, width retry backoff, bounded return accounting, one gentle
return request, late handoff departure notifications, and an expired stability
watch without persistent loss. Radar arrival, legal evacuation, interrupted
preparation and repeated failed-radio recovery remain covered by simulation.

On the development router, a read-only comparison of both planners against the
same live candidate snapshot retained the existing layout in both cases. This is
a sanity check, not a performance comparison. The shared process ran alongside
the existing network services without a second preference daemon. Chrome loaded
Channels, Clients and both History charts successfully.

Controlled trials moved the occupied preferred radio from channel 120 to 128 at
160 MHz while its two clients used the auxiliary radio. The first trial exposed
an unnecessary rollback: late departure notifications and an inconclusive
stability deadline were being treated as evidence of a failed placement. Both
paths now have regressions. The corrected repeat retained channel 128 and began
the separate return observation, recording a client rejection instead of calling
service on another radio a successful return. A temporary reassociation was used
to reset the trial's starting point; that setup is not attributed to automatic
preference. The erroneous inconclusive restriction from the failed trial was
removed before the repeat; other restrictions and settings were retained.

The final controlled 128-to-120/160 MHz trial also verified without rollback.
The preferred radio remained available during its bounded return window. Both
clients still rejected the gentle return request (status 7); neither was missing,
and both remained served by the auxiliary radio. Keeping the target available
therefore did not establish automatic return for these clients. They were placed
back on the preferred radio as test cleanup, not counted as automatic steering
success. A busy-scan response observed during this trial motivated the separate
owner error-handler regressions. No new forced-disconnect policy was added to
ordinary preference.

The signed package and index verified. All 42 payload files matched source or
generated content. Source, history and extracted payload scans found no secret
patterns; the on-router build also checked the actual private gateway and Wi-Fi
values without exporting them. Network, firewall, DHCP, wireless and coordinator
configuration hashes matched after the final installation. No artificial radar
signal was transmitted. Long-term performance in changing RF conditions and
universal client acceptance are not established by these trials.

The final installed immutable payload matched the signed APK. One shared owner
was running; its restart check cleared automatically after the interrupted test
operation, and normal scanning and preference resumed without a safety stop.

## r49 bounded preferred-radio measurement wait (2026-11-09)

Policy regressions cover the 60-second measurement deadline, reports for another AP,
missing and table-only measurement support, fresh weak-signal rejection, cooldowns
and attempt limits, and fresh waits after source/target/channel/width changes.
Protocol checks ensure an unmeasured fallback from Strong has neither a
disassociation warning nor a disconnect timer, while a measured recommendation
retains the selected mode. Clients without roaming support remain untouched.

The full isolated native suite passed, including 57 Radio Preference checks,
1118 executor cases, 1023 restart recovery checks and 668 archive-storage checks.
Portable source/documentation and UI checks passed. The signed APK and package
index verified; all 40 payload files matched intended source/generated content.
The installed Clients page matched the verified package, and wireless, network,
firewall, DHCP and both coordinator configuration hashes were preserved.

In the live check, a client advertising table-only measurements received one gentle
recommendation while Strong was selected and associated with the preferred radio
about ten seconds later. Another client was already there before installation;
that move is not attributed to this fix. The missing-report timeout is covered by
simulation, not a forced live-client trial. Client acceptance remains discretionary.

## r48 acknowledgement guidance (2026-11-09)

The acknowledgement note explains that browser and computer restarts preserve
acceptance while site data is retained. Canonical disclaimer wording, stored
acknowledgements and the amber notice styling are unchanged. The cross-project
date audit confirmed that UI timestamps already use readable ISO ordering, while
exports retain precise UTC timestamps; no Wi-Fi timestamp conversion was needed.

Portable source/UI checks passed, including persistence, changed text, unavailable
storage, midnight and DST cases, 51 history/cache assertions and 30 recovery cases.
The signed APK verified and all 40 payload files matched source/generated content.
Controller and recorder code is unchanged; native controller simulations and live
RF trials were not repeated for this explanatory UI change.

The signed package was installed on the development router. Wireless, network,
firewall, DHCP and both coordinator configuration hashes were preserved. Both
services resumed; the disclaimer JavaScript served over HTTP matches the verified
package, including its canonical text and new explanatory note.

## r47 history refresh recovery

A failed archive-directory request was treated like an empty listing, evicting browser-cached batches. The reader now preserves that cache on failure, retains the last successful recent-history and controller snapshots, and retries transport interruptions twice with short delays. A refresh warning distinguishes stale or incomplete browser data from corrupt or inaccessible files. Successful refreshes clear the warning; confirmed deletions still clear cached records. Concurrent callers share one refresh.

Portable source/UI checks passed, including the existing 51 history/cache assertions and 30 new interruption/recovery cases using the production reader. Cases cover aborted requests, timeouts, initial outages, retry limits, cache preservation, restored connectivity, permission errors, invalid JSON/record arrays, confirmed deletion and overlapping refreshes. The router's nine archived batches were readable during investigation. The error message alone did not establish the cause of the interrupted browser request.

This revision changes the History reader and presentation only. The controller algorithms and history recorder are unchanged; the full native controller/storage simulation was not repeated for this UI correction.

The signed APK verified, all 40 packaged files matched source/generated content, and release hashes matched. After installation, an HTTP read of the router's History JavaScript exactly matched the updated source. Automatic operation resumed without a halt, and network, firewall, DHCP and both coordinator configuration hashes were unchanged. The interruption cases use simulated request failures; no live wireless interruption was deliberately induced.

## r46 HT40 fallback retry correction

On November 8, r45 twice selected channel 13/40 MHz, retained channel 13/20 MHz during setup, and then recorded a missing client. The latest attempt began at 09:53:05 CET; rollback to channel 7 was verified at 09:54:53. The 40 MHz width refusal lasted one evidence-freshness interval, while the actual 20 MHz client failure lasted six hours. Expiry of the shorter restriction allowed another wide request to bypass the remaining narrow-placement failure.

The planner now excludes a 2.4 GHz HT40 request when either possible 20 MHz fallback has an active failure restriction. The executor rechecks this before handoff or a channel command. Reversing the primary cannot bypass it. A width refusal alone still permits 20 MHz; unrelated blocks remain eligible, and expiry restores the affected candidates. Recovery can still restore the previous serving placement. DFS policy is unchanged.

Portable source/UI checks passed, including 51 history/cache assertions. The complete isolated OpenWrt suite passed: 144 policy checks, 15 actual candidate-generation checks, 1,118 executor cases, 1,023 restart-recovery checks, and the DFS, service, radar, persistence, history and export suites. The 668 storage checks retained all 7,203 samples and 2,401 surveys across 200 hours. Regression cases cover the two different expiry times, both HT40 primary directions, restrictions added after planning, unaffected alternatives, and width-only refusal without client failure.

The signed APK verified with the native package manager, and all 40 extracted files matched source/generated content. Release checksums, disclaimer and public key matched. These tests verify retry handling; they do not establish why the original client failed on channel 13.

After installation, the controller resumed automatic scanning with radio1 on channel 7/20 MHz and two associated clients. The installed policy was evaluated read-only against the router's retained failures after the old channel 13/40 MHz pause had expired: channel 13/20, channel 13/40 and reversed-primary channel 9/40 remained excluded by the active 20 MHz failure, while channel 1/40 was not excluded by those records. Installed controller files matched the build. Network, firewall, DHCP and both coordinator configuration hashes were unchanged.

## r45 restore opportunistic DFS

Removed r44's private-driver-field veto over DFS placements and helper preparation. The project again uses available DFS spectrum under the kernel's country, CAC and non-occupancy rules. Country-aware operation and the radar-history/snapshot fixes remain. The intended behavior, including accepting occasional radar interruptions and reconsidering cleared spectrum, is recorded in [the agreements](AGREEMENTS.md). The [driver investigation](DFS-DRIVER.md) corrects the earlier overstatement: an unset private debug field did not establish a broken detector.

Portable source/UI checks passed, including all 51 history/cache assertions. Targeted OpenWrt tests passed: 136 policy/regulatory checks, 15 actual DFS-runtime and reuse cases, 40 width/segmented-CAC cases, 103 planner/radar/survey cases, 1,102 executor cases, 11 radar-storage cases, and five radar-snapshot lifecycle cases. The new sequence checks usable-but-uncleared 160 MHz eligibility, required CAC, exclusion when any member reports radar, renewed eligibility after kernel expiry, and fading radar penalties allowing wide quiet spectrum to outrank a non-DFS fallback. The actual runtime test fails if it attempts private-driver inspection. Unchanged archive/storage simulations were not repeated for this policy correction.

The signed APK verified; all 40 extracted files and release hashes matched source/generated content. Installed Channels JavaScript matched the final source over HTTP. These checks do not certify physical radar sensitivity, and no radar signal or synthetic radar detection was generated.

A live coordinated-CAC check used empty radio0 to prepare channel 132/40 MHz for radio2. Hostapd logged CAC start at 09:20:17 CET on November 8 and successful completion at 09:21:18. Both PHYs reported clearance; the coordinator recorded `cac-shared`, restored radio0 to channel 161/80 MHz, cleared its temporary journal, and finished without a halt. During the check radio2 remained enabled on channel 52/80 MHz with two associated clients; its byte counters advanced between samples. This establishes the helper workflow on this installation, not lossless client traffic or RF detection sensitivity. Network, firewall and DHCP configuration hashes remained unchanged.

After automatic operation resumed, the planner selected channel 124/160 MHz for radio0 from a fresh survey and completed the move without a forced target. Service verification reported zero missing clients, zero unproven clients and zero recorded disconnect events. The verified channel/width was saved, restoring the pre-r44 startup placement; candidate channel and width pools remain automatic.

## r44 radar history and country-aware DFS checks

Historical note: the extra mwlwifi restriction described in this revision was removed in r45. Its successful tests established implementation of that restriction, not that the private driver field justified it.

r44 introduced merging retained radar detections with planner memory, preserving old shading after pruning or reboot checkpoints and deduplicating shared PHY reports. It refreshed the daemon's radar snapshot after pruning so service restarts would not resurrect expired entries. DFS eligibility changed to matching known kernel regions rather than assuming ETSI. r44 also blocked new DFS placements and CAC-helper use when a known mwlwifi driver's internal region was missing or mismatched; **r45 removed that extra restriction**. Wireless configuration reloads began refreshing the coordinator and country hint. Historical records with unknown region were left without an invented country. The history, snapshot and country-handling fixes remain in r45.

Portable source/UI checks passed, including 51 history/cache assertions. An independent read of the development router's saved archive and RAM through the actual updated reader restored all four retained detection incidents, including both previously missing 160 MHz incidents, without counting shared PHY reports twice. The full isolated controller suite passed: 140 policy/regulatory cases, 40 width/DFS cases, 103 planner/radar/survey cases, 1,102 executor cases, 1,023 restart-recovery cases, and the service, persistence, history and export suites. The archive simulation retained all 7,203 samples and 2,401 surveys across 200 hours. Five new tests exercise the actual daemon save function through radar pruning and restart; nine tests exercise the actual DFS wrapper, including unavailable debugfs, driver mismatch, auxiliary-radio eligibility, FCC/ETSI/Japan matching, and 2.4 GHz behavior. The latter focused checks were rerun after the final wrapper adjustment.

The signed package verified with the native package manager; all 40 extracted files matched source/generated content and release hashes matched. Installed History and Channels JavaScript matched the final source over HTTP. See the [driver investigation](DFS-DRIVER.md) for evidence, the withdrawal of the non-DFS restriction, and country-change instructions. These tests do not establish RF radar sensitivity or regulatory certification; no live radar signal was generated and FCC/Japan operation was not physically tested.

On the development router, the actual runtime reported the mwlwifi restriction on radio0 while leaving radio2's DFS eligibility available. A controlled move changed radio0 from channel 124/160 MHz to channel 36/80 MHz. The executor verified service with zero missing clients, zero unproven clients and zero recorded disconnect events; these counters do not establish lossless client traffic. The non-DFS startup placement was saved, with channel/width candidate pools still automatic. Network, firewall and DHCP configuration hashes remained unchanged.

## r43 revised software disclaimer

Replaced the canonical disclaimer with the revised experimental-software notice, including the limits of AI-generated implementation, possible harm, legally limited warranty/liability exclusions, and user recovery responsibilities. The README, release notice, packaged text, installation output and LuCI notice use the same wording. The tab label now reads **Experimental, AI-generated software. Use at your own risk.** Existing browser acknowledgements expire when the revised text is first loaded.

Portable source/documentation and UI checks passed, including canonical wording, first-use acknowledgement and changed-text checks. The signed APK verified with both the build tool and the installed OpenWrt package manager; all 40 extracted files matched intended source or generated content, and release checksums matched. The package was installed on the development router without restarting controller processes; network and coordinator configuration hashes remained unchanged. Installed disclaimer and menu files matched the verified package. Controller simulations and live radio-switch tests were not repeated for this notice-only update.

## r42 documentation alignment and release audit

Reviewed the documentation against the current menu, settings, planner, recovery, history storage, export engine and package builder. Corrected the tab count, automatic recovery description, numeric radar legend, independent retention-capped export/view selectors and CSV quoting conventions. Installation guidance now locates storage controls and explains the export decoder's transitive LuCI dependency, confirmed against the installed package metadata. The export endpoint's GET error message now points to Storage & export. Controller behavior, dependencies and UI layout are unchanged.

Portable source/documentation and UI checks passed, as did the 26 isolated export-engine checks and 14 CGI authorization/download checks. The signed APK verified; all 40 extracted payload files matched intended source or generated content, and release hashes, public key and disclaimer matched. Source, extracted payload and release assets were scanned for known private values and recognizable secret patterns; none were found. This is a bounded release audit, not a guarantee that every possible secret format is detectable.

The package installed without restarting the unchanged controller processes or changing dependency versions. The installed CGI passed all 14 checks again; an HTTP GET confirmed the corrected page guidance. The full controller simulation suite and RF throughput tests were not repeated for this documentation/text-only revision.

## r41 remove timezone caption

Removed the standalone Local time caption from History. Browser-local graph ticks, full timestamps, date rules and export UTC timestamps are unchanged. Portable source/UI checks passed. Authenticated Chrome confirmed the caption is absent and both graphs render on the installed History page.

## r40 protected-client help

Keeps the native LuCI list widget and MAC-address validation. Short help explains entering an address and clicking +. Hover help supplies an example, the Associated Stations location, private-address guidance, add/remove/save instructions, empty-list meaning and the protection limits. No widget, storage format or controller behavior changes. Portable source/UI checks and the native LuCI browser fixture passed. Authenticated Chrome confirmed the original + widget and the updated visible/hover text on the installed router.

## r39 export row layout

The period selector occupies its own row. CSV comes next with a dataset selector and Download button; JSON follows with the explanation All graph data and actions and its own Download button. Accessible button names retain the format. The same selected period applies to both. This changes presentation only. Portable source/UI and LuCI browser component checks passed. Authenticated Chrome confirmed the installed row order and button formats; a screenshot was reviewed. The signed package installed without restarting Wi-Fi services.

## r38 consistent section typography

LuCI form-map titles and custom section headings share an 18-pixel bold style with matching spacing and line height. Page titles remain larger; theme font families are inherited. This covers Channel settings, Client steering settings, History retention, Export history and history graph/table headings. Disclaimer emphasis is preserved. The visible timestamp-format sentence was removed from the export caption; export documentation still specifies UTC. Controller and export behavior are unchanged.

Portable source/UI checks and the LuCI browser fixture passed. Authenticated Chrome measured headings on Channels, Clients, History, Storage & export and Disclaimer: page titles were 24 pixels, section headings 18 pixels at weight 700, and font families matched. A screenshot confirmed the retention/export headings match. The signed UI update was installed without restarting the unchanged controller processes.

## r37 separate storage tab

Moved storage diagnostics, retention settings and exports to Storage & export. History now contains graphs, summaries and recent actions without Save controls. Exports have an independent local period selector, defaulting to All retained history and offering durations within saved retention. Export transport and coordinator algorithms are unchanged.

Portable source/UI checks and the actual LuCI browser fixture cover both pages, independent export windows, both selectors capped by a reduced retention limit, native POST downloads and storage diagnostics remaining expanded across refreshes. The installed tab and a three-hour CSV download were also verified in authenticated Chrome. The engine and authorization tests remain those of r36; no new radio experiment is required for this layout change.

## r36 streamed history exports

The isolated export engine passed 26 checks covering newest-record deduplication, survey context at the window boundary, radar context, time filtering, field whitelists, ISO UTC timestamps, CSV escaping/formula protection, missing sources before and during export, cancellation and a lazily generated 10,000-record export emitted in bounded chunks. The CGI integration check passed 14 checks against retained history, using a temporary session: denied permissions, per-archive access, invalid fields/windows/formats, download headers and all six download choices. The session was destroyed afterward; neither test changes live radio configuration.

Portable source/UI checks passed. The actual LuCI browser fixture additionally checked control placement after retention, selected/all-retained windows, JSON/CSV selection, native POST submission and session tokens excluded from the URL. No new RF throughput experiment was performed for this feature.

The signed APK installed without additional dependencies. The installed CGI passed the same authorization checks; archive checksums remained unchanged. An authenticated headless Chrome session rendered the installed controls and downloaded a selected-window JSON file and all-retained actions CSV through the native download manager. Both files parsed successfully with complete final results. These downloads were kept outside the source/release tree. The export itself creates no router files; validation artifacts are separate development files.

Run `ucode wifi-coordinator/test-history-export.uc` for isolated engine checks. On a configured router, `ucode wifi-coordinator/test-export-cgi.uc` checks the installed CGI with a short-lived permission-limited session and reads existing history without printing its contents. An optional first argument selects an isolated copy of the CGI; its module import must point to the matching test source. This integration check requires root and a valid controller state; it is intentionally separate from the isolated runtime suite.

## r35 unattended recovery audit

Corrected rejected CSA commands being classified as permanent radio failures, temporary observation errors discarding operation context, restored restart exceptions losing rollback verification, recovery timeouts lacking automatic retries, and finite process restart limits. Steering preparation is now supervised. Failed-radio reassessment proceeds independently of unrelated radio operations and requires stable legal AP state and fresh service evidence; it never moves or restarts a radio. Existing client/destination restrictions and explicit settings remain authoritative.

The isolated runtime suite passed, including 102 executor assertions plus 1,000 repeated failed-radio retry cycles, and 23 restart-recovery assertions plus 1,000 retry-delay cycles. These are simulated failure/recovery cycles, not a claim of years of live uptime. Portable source and UI checks passed. No deliberate client outage or new throughput test was performed. The signed APK installed on the WRT3200ACM without dependency changes. Its existing radio0 failure latch cleared automatically after positive live evidence from two clients, and Auto selected the six-hour restart fallback. No failure flag was manually cleared. A fresh comparison restored 81 radio0 candidates with no recovery hold, and router internet probes passed. The installed executor matched the final packaged source; procd reported a 30-second respawn delay and retry limit 0.

## r34 matching legend scales

Both legend bars now share a 180-pixel width and five numeric ticks. The amber scale runs from 100% to a true white 0% endpoint; configured decay times remain in its hover explanation. This changes only the legend, not graph shading or radar decay. Portable source/UI checks and signed package verification passed. After installation, the live page reported both bars at 180 pixels with the intended tick labels and a transparent amber endpoint over a white base. The coordinator resumed scanning without a safety stop.

## r33 axis and amber refinement

Removed the date caption beneath both time axes. Date tick lines now require both a span of at least 24 hours and a local midnight crossing; short overnight views show time only. Full timestamps in tooltips and action records are preserved. Amber opacity now falls linearly with remembered strength, with a more saturated colour and similar 100% intensity to the grey scale. The legend fades toward white; graph transparency reveals the survey layer below it. Portable project/UI checks and actual Chart.js browser checks passed, including the 24-hour boundary, short overnight views and the 25-hour daylight-saving day without a midnight crossing. The signed package and packaged source checks passed; installation required no dependency changes. The live six-hour view showed matching time-only ticks and no axis captions on both graphs. The coordinator resumed with no safety stop.

## r32 date/time and radar contrast

Both charts use shared browser-local 24-hour ticks. Same-day axes show their date once; midnight-spanning views use two-line date/time ticks. Tooltips, Recent actions and comparison timestamps use ISO-style dates with seconds. No "Time" axis label is added. Radar shading and its legend share a darker amber colour function; the controller and decay settings are unchanged.

Portable project and UI checks passed, including midnight/year rollover, reduced tick counts, spring/fall daylight-saving transitions and legend colour consistency. The actual bundled Chart.js browser fixture passed at 300 and 950 pixel chart widths for same-day, overnight and 200-hour windows, with identical ticks on both charts. The actual LuCI component fixture passed all 55 setting descriptions and refresh checks. No controller changes or new RF throughput tests are included in this revision. The signed APK verified and installed without dependency changes. Both live services resumed with `halted: null`; router internet probes passed. The live History page rendered both graphs, local timezone and ISO-style action timestamps. All 37 payload files matched current public source or the previously audited unchanged r31 payload; the source privacy checks passed.

## r31 documentation and distribution audit

The documentation was compared with package hooks, declared dependencies, fresh defaults, recovery checks, history/privacy handling, the four-page menu and release assets. Corrected the five-file download/checksum instructions, build-time ucode prerequisite, builder outputs, fixed recovery deadline, unresolved failure handling, stop-versus-disable behavior and historical validation wording. No controller or UI behavior changed.

Validation: portable source and UI checks passed. A history scan covered 320 stored source blobs and found no private-key, credential-token or known private-value matches. The signed APK verified; all 36 extracted payload files matched the intended repository inputs byte for byte, including generated version/disclaimer text and the upgrade keep-list. Its payload, hook metadata and package metadata also had no sensitive-data matches in the performed checks. Package configuration files are generic defaults, not copies of live UCI configuration. These checks are evidence for this artifact, not a guarantee that pattern scanners detect every possible secret. The new APK installed successfully and coordination resumed scanning with no safety stop. The complete radio/runtime suite was not repeated for this documentation-only change; r28 records the latest full run.

## r30 dedicated disclaimer tab

The full notice now has its own tab beside Channels, Clients and History, labelled in bold: **AI-generated software. No warranties. Use entirely at your own risk.** The recurring banner and modal are removed. First-use acknowledgement and exact-text browser persistence remain unchanged, including direct visits to the disclaimer tab.

Validation: portable source/UI checks passed. The signed APK verified and installed. Live LuCI checks confirmed the exact tab label with font weight 700, no recurring banner or acknowledgement prompt for the already-acknowledged browser, full text on the new tab, no settings footer there, and no network errors. Coordination remained active without a safety stop.

## r29 visible software disclaimer

The canonical `DISCLAIMER.txt` appears at the top of the README and release descriptions, inside the APK, and during installation. In r29, the LuCI notice gated first use in each browser and remained visible on all three pages after acknowledgement. The r30 tab replaced that recurring banner. Browser storage records the exact text, not the package version; it does not write to router flash or change running services. Tests cover acknowledgement, changed text, blocked storage, repeated module loads, full-text access, and coverage of all three views.

Validation: portable source/UI checks and the native LuCI fixture (55 descriptions) passed. The signed APK verified. On the installed router, all three views displayed the warning; first use withheld controls until acknowledgement, subsequent pages remembered it, and the full-text button opened the notice. The install log printed the canonical text. Existing radio recovery state was inspected separately before coordination resumed. No planner or steering code changed in this release.

## r28 interrupted-operation recovery

Fixed a ucode forward-reference error in occupied-helper DFS handoff. The executor regression test reaches that branch without touching real interfaces. Restart recovery now observes radio readiness and resumes automatically after 30 seconds of stability. Tests cover missing radios, configuration journals, channel changes during verification, long DFS startup, existing recovery errors, and preservation of timed exclusions.

Validation: the complete isolated OpenWrt runtime suite passed (1,151 checks, including 82 executor and 18 restart-recovery checks). Portable source and UI checks passed. The signed APK verified and installed on the WRT3200ACM. After migrating the inspected old restart latch into automatic verification, the live daemon cleared `halted` and `restart_check`, then resumed surveys. All three APs were enabled before the check; verification required no radio restart. LuCI displayed active scanning without a network error. WireGuard remained up and router internet probes passed. This was a restart-recovery test, not a new RF throughput test.

Correction to earlier live-validation notes: the safety-stop check inspected `halt` instead of the actual `halted` field. Earlier claims that installation resumed without a safety stop were not established by those checks. This revision checks the actual field and the recovery lifecycle.

## r27 legend heading alignment

Legend headings share regular font weight and align with the gradient bars, with both numeric scales underneath. This corrects r25's alignment of headings with the lower numeric row.

## r26 congestion label

The spectrum legend is labelled **Estimated congestion**, matching its 0-100 index. This changes the label and hover wording only.

## r25 aligned legend scales

Both ramps and their labels align. Radar labels combine elapsed time and avoidance strength on one line. Neighbour activity has a 0-100 estimate scale; its gradient follows the graph's square-root intensity mapping. Hover text distinguishes this index from airtime percentages. Portable source/UI checks and the native LuCI fixture passed; a rendered preview confirmed aligned ramps and single-line labels. Package signature and extracted source matched. Both service processes ran after installation, and internet probes succeeded (3/3). The safety-stop check was invalid; see the r28 correction.

## r24 compact spectrum legends

Neighbour activity and radar memory share one horizontal legend row when space permits. On narrow screens, the groups wrap rather than overlap. The radar ramp, decay values and hover explanations are unchanged. This is a layout-only change. Portable source/UI checks and the native LuCI fixture passed (55 descriptions). A browser-rendered legend preview confirmed the side-by-side layout. The signed APK verified, extracted files matched source, and installation upgraded only this package. Both service processes ran; router internet probes succeeded (3/3). The safety-stop check was invalid; see the r28 correction.

## r23 one-hour radar memory

The configured default, daemon fallback, shutdown reader, settings UI and graph fallbacks now use a 3600-second radar-memory half-life. The target router is explicitly updated to the same value; other installations retain their existing configured preference on upgrade. Mandatory kernel DFS restrictions and radar clearance are unchanged. Six-hour recovery exclusions and flash checkpoints are separate settings and are unchanged.

## r22 quieter history presentation

Survey and radar bars disable Chart.js rectangle inflation: adjacent translucent cells no longer overlap into dark boundary marks. The actual Chart.js browser fixture renders 360 consecutive survey readings and checks that boundary opacity does not darken while the background stays visible. Existing radio colours, patterns, white edging, axis labels and radar-decay legend remain.

History captions are shortened; technical interpretation stays in hover text. Storage diagnostics are collapsed by default and retain their expanded state across refreshes. No planner, radio settings, recorded data or retention changes.

## r21 large-history reads

A live RAM history file exceeded 256 KiB: ordinary ubus file reads returned `Operation not supported`, leaving only archived radio ribbons visible. The data was intact. History now uses LuCI `fs.read_direct()` for both RAM and closed batches, with CGI download permission and the existing path-specific file ACLs. Read errors appear above the graphs, including when no radio records can be loaded. Storage limits, offload frequency and the planner are unchanged.

The history/cache regression covers RAM and archive files over 300 kB, newest-period merging, immutable-batch caching, retrying failed reads and identifying unreadable sources. The actual installed CGI download helper successfully returned the live history over 272 kB using a temporary session restricted to that file; parsed radio periods extended to within seconds of the test. The temporary session was destroyed afterward.

## r20 service-based joint planning

The planner uses one service objective in place of width-first ranking and the separate narrowing gate. The new isolated service suite covers clean 160 MHz headroom without connected clients, primary-only moves, nested narrower transmission capacity, avoiding repeated counting of one wide neighbouring BSS, distinct subchannel interferers, clean narrow versus crowded wide spectrum, minimum-gain admission for widening, fractional radar half-lives, HT/VHT stream decoding, unequal AP capacity, incumbent primary ties and invariance to client names/counts/offered traffic. Candidate tests also ensure a different primary cannot evade a failed-footprint exclusion. The exhaustive small-layout reference and existing executor/recovery tests remain in the runtime suite.

The isolated runtime suite passed 1,131 checks, including 30 new service cases and 7 candidate-limit cases. Portable UI checks and the offline fixture using actual LuCI methods passed, including all 55 setting descriptions. The signed APK verified, packaged files matched source, and installation required no dependency changes. Both services resumed, all three APs remained present, and router internet probes succeeded (3/3). A fresh 33-frequency survey completed and live scoring decoded the expected 3/3/1 spatial streams. Its automatic 2.4 GHz attempt on channel 13 requested 40 MHz, but the driver retained 20 MHz and one client failed to reconnect. The existing recovery restored channel 9, verified both clients, and recorded a six-hour destination exclusion plus a temporary 20 MHz width limit. The final state had no pending operation. The safety-stop check was invalid; see the r28 correction. No 5 GHz throughput benchmark was run for this release.

The service index is a spectrum/capability model, not a measured throughput result. These tests establish policy behavior and regression coverage; they do not establish globally optimal client speeds or uninterrupted roaming for every device.

## r19 axis label order

The spectrum axis title now reads "Band / channel", matching the band-first tick labels. This is a text-only correction; the r18 mapping and rendering behavior are unchanged.

## r18 standard band axes

The axis now uses PHY band declarations to select full standard band layouts. Portable tests cover a 5 GHz-only declaration, the full upper 5 GHz range, retained channel 14, 6 GHz display geometry, compressed gaps, unchanged channel widths, and shared survey/radar clipping. An offline fixture renders actual bundled Chart.js with mixed-band and 5 GHz-only plots, verifies gap pixels and full rectangular outlines, and displays the existing pattern legend. Run `python3 scripts/prepare-graph-check.py OUTPUT.html` and open that HTML in a browser to repeat the render check without router data.

r18 validation passed: 114 policy/band-declaration checks, 40 hardware-width checks, 6 retained-comparison checks, portable UI/geometry/history-cache checks and the actual Chart.js browser render fixture. The signed APK verified and its contents matched source. After installation, the controller reported `2g 5g`, both services ran without a safety stop, and router internet probes succeeded (3/3).

## r17 scoped client recovery

The isolated OpenWrt suite passed: 109 policy, 40 hardware-width, 37 Radio Preference, 3 usteer integration, 103 planner/radar/survey, 80 executor, 8 client-memory, 5 journal-recovery, 6 comparison-snapshot, 6 candidate-limit, 11 radar-storage, 19 history and 668 archive-storage checks. New executor cases simulate healthy service with one affected client, duplicate station records, selective handoff, proof of alternate service, protected clients, weak signals, escalation limits, preflight compatibility checks and restoration without bouncing back to a failed placement. Memory tests cover six-hour expiry, placement scope, same-boot lifetime, replacement, the 256-entry cap and removal of expired identities. These are controlled simulations, not deliberate live client outages.

Portable JavaScript, settings, graph and history/cache checks passed. The isolated browser fixture using the router's actual LuCI methods passed all 56 setting descriptions, hover/focus/tap behavior, retained comparison rendering and status refresh. The signed APK verified and its packaged files matched source. Live r17 installation preserved settings; both controllers resumed without an integration error or safety stop. All three APs remained available, radio0 retained 36/160 MHz, and router internet probes succeeded (3/3). The A55 remained associated with radio0. No live client failure was deliberately induced; simulated recovery does not establish uninterrupted roaming for every physical client.

## r16 absent optional UI lines

The native browser fixture now also uses the target LuCI `dom.append()` method from `luci.js`. Unlike the earlier stub, that version stringifies null entries inside child arrays. The regression reproduced literal null text before the fix; absent optional comparison/card lines now use empty strings. The fixture passes with absent fields, comparison refresh, retained expansion and the existing help interactions. Client recovery and exclusion behavior are unchanged.

## r15 progress toward wide-channel plans

Live r14 evidence showed a selected 160 MHz joint plan repeatedly deferred behind radio1 HT40 attempts, each reduced to 20 MHz by hostapd. The route traversal used radio enumeration order and execution reevaluated after each first step. The corrected traversal serves the oldest eligible radio first while retaining overlap dependencies. All 103 planner/radar/survey cases passed, including the exact three-radio widening sequence, intermediate separation, replanning after the prerequisite move and shuffled enumeration. All 48 executor cases passed, including the cross-primary width constraint after an observed fallback. Four cases extracted from actual candidate generation verify narrower optimization during the constraint, no bypass by changing primary, restoration after expiry and unchanged configured widths. Portable UI checks, entry-point compilation, signed APK verification and extracted-source comparisons passed.

Live r15 completed the intended automatic sequence: radio2 moved from 52/80 to 149/80 with zero missing/unproven clients, then radio0 moved from 100/80 to 36/160. `iw` independently reported 160 MHz and center frequency 5250 MHz. The radio0 operation ended with zero missing clients and one unproven data-service result after the longer association observation. Its client had reconnected on 2.4 GHz after handoff escalation. Router internet probes succeeded (3/3). This verifies actual AP width and scheduling progress, not uninterrupted roaming or 160 MHz client throughput. After manually reconnecting a Samsung A55, the user confirmed working internet. Station records identified it on radio0 with bidirectional traffic; an observed data link rate was 866.7 Mbit/s at 80 MHz. This establishes service through the 160 MHz AP while the client uses 80 MHz, not full-width client throughput.

## r14 retained channel comparison

The last completed comparison remains available during surveys, moves and temporarily absent radios. Sampling marks changed placements instead of deleting evidence. Evaluation time, age and current progress distinguish the snapshot from live state; channel pools, widths and exclusions belong to that comparison. Six extracted production-sampling cases cover retention and placement changes. The native LuCI browser fixture checks retained rows, advancing age, progress/placement notices, replacement by a new comparison, and preserved expansion/unsaved edits.

## r13 tooltip readability

Opaque light/dark tooltip surfaces, a border, padding and a subtle shadow distinguish settings help from the page beneath it. The existing native LuCI browser fixture passes all 56 descriptions and interaction checks; its rendered light and dark tooltips were visually inspected. This release changes presentation only.

## r12 help integration and hardware width discovery

- The native browser regression reproduced the r11 bug: DOM setting descriptions were omitted by LuCI's string-only Value/NamedSection render methods. With r12, all 56 setting descriptions across the three pages render. Native text/icon hover, focus, click/tap, Escape, viewport fit, polling, preserved expansion/unsaved edits and form re-rendering passed. The fixture uses actual renderer/tooltip methods and the theme downloaded from the target router; UCI data, widgets and radio state are synthetic. This is a browser component integration check, not an authenticated end-to-end router session.
- Portable help tests cover HTML/attribute escaping and delegated interaction handling. Form registration, conditional-value retention, six JavaScript syntax checks, nine history/cache cases and graph checks for HT40/VHT160 geometry and retained colors/patterns passed.
- All 109 policy checks and 40 new hardware-width/regulatory/segmented-DFS cases passed. Coverage includes the three observed PHY capability sets, both HT40 directions, VHT160 geometry/configuration, per-frequency restrictions, contiguous AUTO_BW ranges, rejection of regulatory gaps, and an 80 MHz helper preparing both halves of a 160 MHz target. Helper-only clearance cannot authorize the serving radio.
- Executor integration expanded from 40 to 47 passing cases: actual 160 MHz restart configuration, successful verification, HT40 coexistence setup, verified 20 MHz fallback, bounded coexistence refusal, early fallback on a changed primary, and rejection of explicit CSA that would bypass the HT40 check.
- The remaining full suite passed: 32 preference cases, usteer restoration, 97 planner/radar/survey cases, five extracted recovery cases, 11 radar-persistence cases, 19 history cases and 668 storage cases. Entry-point compilation, signed APK verification and extracted source comparisons passed.
- A read-only execution of the actual inventory/configuration functions against the router resolved radio0 to 160/80/40/20, radio1 to 40/20, and radio2 to 80/40/20 MHz in its current band. Kernel data allowed lower and DFS 160 MHz blocks; the upper 149-based block remained ineligible. This capability check did not change radios.

- The signed r12 upgrade changed only this package and preserved Auto channels, widths and switching methods on all three radios. Both controllers and usteer were running afterward; six UI resources returned HTTP 200, and three router internet probes succeeded. Two paced surveys completed all 41 requested frequencies. The first automatic move changed radio0 from channel 149/80 to 100/80 and finished with zero missing or unproven clients; four disconnect/reassociation events were recorded, so this was not a lossless-roaming result.

- The live planner attempted HT40 on radio1 with primary 9/secondary 13. Hostapd explicitly rejected 40 MHz because of overlapping BSSes and retained 20 MHz. Both clients recovered with zero missing/unproven clients and two disconnect events. This exposed an early-fallback classification bug in the initial staging APK; the final r12 build waits for width setup to settle, records the constrained width, and keeps normal client verification. The exact early-tick/new-primary sequence passes the executor regression. VHT160 execution and segmented clearance passed injected tests; sustained live 160 MHz operation and throughput have not yet been demonstrated.

To reproduce the browser component check, download the target's `luci-static/resources/luci.js`, `form.js`, `ui.js` and its theme's `cascade.css` into a temporary directory, then run `python3 scripts/prepare-browser-check.py RESOURCE_DIR OUTPUT_HTML`. Open the result in an isolated browser profile; its status must read PASS. The generated fixture contains no router credentials and makes no router changes.

## r11 settings behavior audit

- All 109 channel/policy cases passed, including Auto resolution, WRT execution requirements, driver capability, failure expiry, independent width methods, explicit method preservation and strict integer validation. All 32 preferred-radio checks passed, including Strong with missing measurements and measured Strong eligibility.
- The complete runtime suite passed again: three usteer-restoration scenarios, 97 planner/radar/survey cases, 40 executor cases, five actual recovery-helper cases, 11 radar-persistence cases, 19 history cases and 668 storage cases. Storage tests retained 200 hours of original summaries/surveys without touching the live archive.
- JavaScript syntax, native-help interactions and nine history/cache cases passed. A settings-form harness checks actual option registration, Auto defaults, explicit choices, numeric-list validation, conditional controls, preservation of hidden values, Advanced placement and refreshed method/exclusion status. These use stubs, not a full browser rendering test.
- An isolated UCI fixture confirmed retired timing keys are removed, missing methods become Auto, and explicit CSA/channel lists remain unchanged. Entry-point compilation, package signature and extracted-file comparisons passed.
- The simulated and actual upgrade changed only this package. The installed configuration uses Auto for channels, widths and both switching methods on all three radios, with Automatic occupied-client handling. All six retired keys were removed. Existing failed-destination evidence was retained.
- After installation, both controllers and usteer were running, all four clients remained associated, all six checked UI resources returned HTTP 200, and three router internet probes succeeded. Auto resolved to CSA on radio0, restart on radio2, and restart on radio1 because of its remembered CSA failure. A subsequent paced survey covered all 41 requested frequencies and completed evaluation. The safety-stop check was invalid; see the r28 correction.
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
- The signed APK upgraded r7 to r8 successfully. Channel Coordinator, Radio Preference and usteer were running afterward. The safety-stop check was invalid; see the r28 correction.
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

## Earlier self-contained project validation

This is historical build evidence, not a claim that the complete runtime suite was rerun for every documentation or UI release. Consult the revision-specific entries above.

The complete ucode suite passed from an isolated copy of this project, using test modules generated by `scripts/prepare-tests.py`. The portable Node UI/cache tests and project checks also passed. The documented APK builder produced a signed APK and package index from that isolated source, and native `apk verify` accepted the package. Packaged application files were compared with source, accounting for the build-time stylesheet version substitution. The private signing key remained outside the source tree and was removed from the temporary build host afterward.
