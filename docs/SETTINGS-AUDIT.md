# Algorithm-to-settings audit

The settings redesign was reviewed for 0.7.0-r8; this reference was rechecked against 0.7.0-r15. The algorithm determines which administrator choices are
needed. This review traces controls through configuration parsing and their
runtime consumers, rather than treating a parsed key as proof of an effect.
The [settings reference](SETTINGS.md) lists every key and its precise scope.

## Findings and decisions

No exposed operational control was found to be wholly unused. Previously retired
internal timing keys and the separate preference strength/signal keys remain
retired. The new UI does not resurrect them or create replacement aliases in UCI.

| Algorithm responsibility | Settings retained | Evidence and disposition |
| --- | --- | --- |
| Decide whether to operate | Both enable flags, channel mode | The shared service may run for either subsystem. Observe suppresses planned channel execution, not independent steering or regulatory evacuation. Keep independent switches; clarify their scope in Operation. |
| Choose eligible placements | Per-radio management, channels, widths | `main.uc` and `policy.uc` build candidate pools; `executor.uc` also respects management for helpers. Real deployment restrictions, retained under Radios. Management does not exclude scanning or steering. |
| Admit a move | Improvement, separation, overlap penalty, minimum residence | `controller.uc` scales movement cost with clients, restart risk, helpers and learned disruption. `planner.uc` applies separation priority and the net-benefit margin; `main.uc` applies residence. Keep them in Advanced. Rename improvement to Movement caution and explain both effects. |
| Restrict occupied-radio work | Occupied policy, reconnect permission, quiet threshold/duration | `executor.uc` gates execution and restart fallback; `survey.uc` shares quiet detection. Keep explicit administrator restrictions. Group global permission with steering; keep radio-specific restrictions under Radios and show quiet tuning conditionally. |
| Gather usable observations | Survey policy, interval, duty, gap, method, scanner, maximum age | `survey.uc` schedules legal visits and serving gaps; `main.uc` controls cadence and freshness. Fixed scanner choice can deliberately reduce coverage. Retain all under Survey & radar, with explanations of coverage/disruption trade-offs. |
| Prepare DFS spectrum | DFS mode/helper, radar-memory half-life | Kernel eligibility and clearance remain authoritative; `executor.uc` selects an eligible helper and `radar.uc` supplies decaying interruption risk. Keep policy/helper in Survey & radar and memory decay in Advanced. No UI setting bypasses mandatory clearance. |
| Move clients | Preferred radio, strength, handoff window, protection, both signal thresholds, preference settling, cooldown/attempt cap | `steering.uc`, `handoff.uc` and `executor.uc` share relevant policy and budgets. Consolidate under Client steering. Settling is preference-specific; cooldown and cap still affect handoffs when preference is disabled. |
| Select a hardware method | Channel and width methods | `policy.uc` resolves Auto from capabilities, known hardware behaviour and recent failures. Explicit overrides remain useful and can intentionally block unsupported moves. Retain under each radio's Driver overrides. |
| Verify and recover service | Unprobeable-client observation, clear-stop action | `executor.uc` and recovery logic distinguish association from service evidence. Retain the deployment-dependent observation window; show acknowledgement only when a global/per-radio recovery problem is reported. Automatic recovery remains active. |
| Preserve state and observations | Placement persistence, history enable/retention/clear | Placement checkpoints, radar memory and chart history serve distinct purposes. Keep placement persistence in Operation and history controls in Storage & export. Do not merge their meanings. |

## Couplings reviewed, not silently changed

**Movement caution (`improvement`)** controls the base movement cost as well as
the required net gain. That gives one monotonic caution control for ordinary
service improvements while client count and operation type determine exposure.
Splitting it would add a new policy degree of freedom and require new calibration.
Keep the current rule and make the double role explicit. Separation priority can
bypass the net-gain margin; movement cost still participates in selecting a route.

**Evidence lifetime (`max_age`)** bounds survey duration, evidence and plan
validity. It also provides the initial retry/recheck interval for uncertain
results and refused widths; repeated width refusals back off independently up
to six hours. The coupling is material and now documented. It is retained to
avoid changing established recovery timing as an incidental UI edit. A future
split should be supported by observed cases requiring different intervals.

**Quiet threshold and duration** deliberately serve both quiet-only radio moves
and sustained-quiet scanning. **Strength and retries** deliberately serve both
preference and handoff. Consolidating their presentation does not create new
algorithms or independent copies of the same settings.

## Presentation corrections

- Shared steering policy is no longer spread across three locations.
- Automatic scanner/helper use empty UCI values. Their former required-field
  declarations could reject Save & Apply with Automatic selected. They now accept
  the empty choice; absence has the same automatic meaning in the algorithm.
- Fresh weak destination measurements block requests as well as disconnection;
  missing measurements do not suppress Strong warnings. Source-only inference
  for Decisive disconnection is restricted to the same band.
- The independent radio-restart fallback is clearly separate from steering
  strength. Gentle steering alone does not prohibit an explicitly allowed restart.
- Obsolete measurement-wait statuses were removed. Recent attempts counts the
  active shared client/destination budget, not sent frames, and expires with it.
- A draft timing preview explains the selected escalation window without applying
  settings or implying that eligibility checks are bypassed.
- Channels and Clients display state; their forms and save controls were removed.
- Driver overrides and live applied-method explanations remain with each radio.
- Conditional fields use LuCI retention. Hidden values are not removed, and shared
  retry controls remain editable independently of the preference enable switch.

## Compatibility and boundaries

The 0.7.0-r8 settings redesign preserved UCI names, defaults and configured policy values. One chained
LuCI map writes both original namespaces, with explicit bindings for the second
enable flag and preference fields. Nested radio forms retain the original radio
section names. No new write ACL, daemon API or network service is required.

In 0.7.0-r8, the only runtime change was the displayed attempt count; it does not admit or
reject attempts. Planner scoring, movement admission, DFS, escalation, signal
checks, retry budgets and recovery algorithms are unchanged by that presentation revision. The later 0.7.0-r12 history cap is separate: retention, Show and export periods stop at 120 hours; larger saved retention values are reduced on installation or service startup. This does not change movement policy.
The later 0.7.0-r14 scanner change adds an exact-cost tie-breaker within Automatic:
it remembers the last successful scanner per band until service restart. It does
not add a control or override fixed scanner choice, service cost, eligibility or
serving gaps. Quality recording uses the existing history enable/retention/clear
controls and exports. It adds no independent log or scan-frequency setting.

Any future consolidation should be judged against those behaviours and tested
separately from presentation work.
