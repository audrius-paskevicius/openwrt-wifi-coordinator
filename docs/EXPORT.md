# History downloads

Open **Network / Wi-Fi Coordinator / Storage & export**, then **Export history** below History retention. Its independent Period selector offers All retained history (the default) and durations up to the saved retention limit (maximum 120 hours). Changing Show on the History tab does not change the export period. Downloads do not change recording, retention, radio settings or channel planning.

- **CSV data** selects channel placements, client counts, traffic summaries, spectrum surveys, radar detections or actions, followed by its Download button.
- **JSON data** downloads all six datasets below in one structured file using its separate Download button.

The Period selector above these rows applies to both downloads. Requests over 120 hours are rejected by the endpoint as well as excluded by the UI. Older saved retention values are clamped to 120. Batches saved before that retention cutoff are skipped; a shorter export period still reads retained sources to preserve earlier survey context. Whole intervals overlapping the cutoff may begin earlier than it.

The router sends the response directly to the browser download manager. It creates no export file and performs no flash writes. Existing history remains in its normal RAM buffer and flash archive. The exporter holds a fixed RAM snapshot, one bounded archive batch from the retention window, a lightweight deduplication index for one dataset, and a small output buffer. Index memory grows with the number of retained records; the entire archive or completed download is never assembled in memory. Closing a download stops processing when the next output write detects the closed connection.

## Time, units and completeness

Every export has a fixed request-time cutoff, the saved retention limit clamped to 120 hours, package/schema versions, units and UTC timestamps. ISO timestamps end in `Z`; original Unix seconds are also retained. These are UTC even when the page displays local time. Rows are emitted in source order; sort by `start` or `time` if chronological ordering is required.

Placements and five-minute traffic summaries retain their original interval boundaries. An overlapping interval may begin before the selected window; no estimated partial-bucket traffic is invented. Surveys include the earlier retained observations needed to establish each frequency bin at the beginning of the window.

The `radar` dataset (and radar CSV) contains only current planner memory, capped at 128 incidents. It is independent of graph retention and the selected export period, and may contain older detections. The History graph also reconstructs detections from all retained actions, so this dataset alone need not reproduce its radar shading. JSON `actions` and action CSV include raw radar notifications within the selected period: only `event: "radar-state"` with `radar_event: 0` represents a detection. Shared reports for the same region/block within five seconds represent one incident; CAC completion and exclusion expiry are not detections. The exported half-life supplies the decay rate. A detection before the export window that has left planner memory can still affect the graph but be absent from the download. Choosing **All retained history** includes the retained action context.

This is a best-effort snapshot, not a lock on the recorder. The RAM snapshot and archive listing are fixed at request start; closed archive batches are immutable. An archive removed or unreadable during download produces an explicit warning. **Check the final completeness result**: a truncated file without that result is not a completed export. A complete export means all selected sources were read, not that the router recorded every moment. Metadata also reports previously dropped RAM records.

## JSON schema version 1

Top-level metadata includes `format`, `version`, `package_version`, `exported_at`, `window`, `retention_hours`, `declared_bands`, `radar_half_life_seconds`, `units`, `notes` and `dropped_ram_records`.

`datasets` contains:

| Dataset | Contents |
| --- | --- |
| `periods` | Radio, primary channel, centre frequency, width, role and residence interval |
| `clients` | Radio, boot source, observed count and constant-count interval (`start`, `end`, plus UTC ISO timestamps) |
| `traffic` | Original five-minute sums/counts/peaks plus derived mean Mbit/s and measured busy-airtime percent |
| `surveys` | Compact frequency-bin levels and their measurement-time offsets |
| `radar` | Current planner-memory incidents: detection time, centre frequency, width, region, PHYs and weight |
| `actions` | Action codes and recorded details within the selected period, including raw radar notifications |

New action records can include an `operation` ID linking preparation, channel
verification and client return. Return counts distinguish `returned`, `elsewhere`,
`absent` and `declined`; `disconnect_events` and `forced_disconnects` describe
different things. Older records omit these optional fields. They contain counts,
not client addresses. A `switch-unconfirmed` outcome means the AP was ready but
the bounded observation did not establish stable client service.

From 0.7.0-r6, `plan-start` and admitted `operation-complete` records can also include:

| Field | Meaning |
| --- | --- |
| `estimated_gain` | Net service-score benefit after movement cost |
| `movement_cost` | Whole-route movement penalty, in score points |
| `required_gain` | Evidence/minimum-improvement margin at admission |
| `affected_clients` | Sum of current associations on affected radios, counting each radio once |
| `client_moves` | Estimated exposure including repeated staging and helper moves |
| `scan_age` | Age of the oldest combined survey snapshot, in seconds |
| `observed_clients` | Clients tracked during this operation, including helper handoffs |
| `departed_clients` | Distinct tracked clients observed leaving during the operation |
| `operation_seconds` | Total operation duration; **not** measured outage time |

`width-constrained` records also retain `requested_width` alongside the actual
`width`. These optional fields use the existing bounded recorder and retention.
They appear in JSON actions and in the JSON `details` cell of action CSV, without
changing existing CSV columns or schema version. Older records omit them; absence
means unknown, not zero. Departures can be voluntary and do not by themselves
establish service loss or prove that a move caused an outage. Estimated affected
counts describe the admitted route, while observed counts describe the completed
step. Replanning can change the estimates between start and admission. No client
addresses, names or traffic contents are included.

`result` ends the document with `complete`, `warnings` and record `counts`. Survey counts count frames, not individual bins.

From 0.7.0-r9, the same **Actions** CSV and JSON `actions` dataset also contain:

| Event | Additional information |
| --- | --- |
| `planning-complete` | `kind` (comparison or validation), total `elapsed`, `candidates_seconds`, `search_seconds` |
| `planning-discarded`, `planning-failed` | Calculation kind, duration and reason |
| `slow-stage` | Controller stage in `kind` and `elapsed` seconds; recorded from one second upwards |
| `observation-gap` | `start`, `end`, `elapsed`, `missed_samples` against the five-second target |
| `radio-unavailable` | Radio, boot `source`, `start` and `end` of consecutive positive hostapd observations with no enabled AP |
| `placement-observed`, `client-departure` | Observed placement change or identifiable station-departure event; no client identity |

These fields are also included in the action CSV `details` JSON cell. Interval
timestamps include UTC ISO companions. Unavailability intervals retain their
original boundaries and deduplicate by event, radio, boot and start. A successful
enabled observation or a gap longer than 15 seconds separates intervals.
Missing RPC responses do not prove downtime, and older gaps cannot be diagnosed
retroactively. Ordinary observation gaps do not invent zero clients or extend a
radio ribbon. Graph squares identify unknown gaps, crosses identify confirmed
unavailability and triangles identify recorded actions, including departures
counted in completed operations. Their height is a nearby recorded placement or
count, not a measurement inside a missing interval. History's existing RAM limit,
retention and archive cadence apply to all these records; no new settings or
unbounded diagnostic log are introduced.

Client counts are sampled every five seconds and stored as whole-number intervals.
When the next observation is within 15 seconds, a changed count closes the old
interval at that observation and starts a new one. Longer gaps remain unknown.
Intervals retain their original boundaries, including those overlapping the
window start. Deduplication uses radio, boot source, start and count, retaining
the latest end. Old archives without this dataset export an empty client list;
five-minute `clients_peak` values are not converted into invented observations.
No client addresses or names are recorded. This is an additive schema-version-1
dataset; consumers should ignore datasets they do not use.

Survey bands use `start` and `step` in MHz. Bin `i` spans `[start + i * step, start + (i + 1) * step)`. Its timestamp is the frame's `time + offsets[i]` (zero when omitted). `levels[i]` is a 0–100 congestion estimate, not airtime percent. `null` means unmeasured, never clear. Traffic `n`, `traffic_sum`, `busy_n` and `busy_sum` preserve the evidence behind means; absent busy measurements stay null.

## Survey quality in Actions

From 0.7.0-r14, `scan-complete` and `scan-partial` actions include `survey_cycle`
(the matching survey frame's `cycle`), wall-clock sweep `elapsed` seconds, and
`scan_quality`: up to four per-radio objects with these fields:

| Field | Meaning |
| --- | --- |
| `radio` | Scanner radio identifier |
| `frequencies` | Attempted centre frequencies in MHz, including aborted visits |
| `visits` | Visits whose success or abort was observed |
| `scan_seconds` | Sum of trigger-to-result processing durations for those visits; not measured airtime or outage |
| `retries` | Retry requests scheduled after observed aborts |
| `aborts` | Observed aborts, including ones followed by a successful retry |
| `detections` | Fresh distinct BSS entries per successful visit, summed across visits; repeated networks can contribute in several visits |
| `active_visits`, `passive_visits` | Visit counts by the requested scan mode |

The existing sweep-level `neighbors` count remains the number of unique detected
networks in that sweep. Successful `scanned_frequencies` and `missing_frequencies`
remain distinct from attempted frequencies. A cancelled sweep records finished
visits; an in-flight visit without a result is not included in these counts.

`scan-retry` and `scan-aborted` additionally retain `radio`, `frequencies`,
`attempt`, `elapsed`, `mode` and `survey_cycle`. `attempt` is the retry number
(1 or 2); the final abort can also report 2. These events distinguish repeated
abort notifications from successful coverage; they do not diagnose the driver's
reason for aborting.

These fields appear in JSON `actions` and **Recent actions** CSV's existing
`details` cell. No additional dataset or CSV columns are needed. Old records
omit them. Nested fields and frequencies are allowlisted at both recording and
export; raw BSS entries, SSIDs, addresses and credentials are excluded.

## CSV conventions

UTF-8, comma delimiter and CRLF row endings. Data cells are quoted with doubled embedded quotes; null values are empty cells. The fixed header names are unquoted. Each file has a header and `record_type` column:

- `metadata`: export metadata in the `message` column.
- `data`: actual dataset rows. Filter to these for plotting or spreadsheet calculations.
- `warning`: a source could not be read; explanation in `message`.
- `summary`: final completeness result and counts in `message`.

Survey CSV expands each selected frame into frequency bins with `observed_iso`, `low_mhz`, `high_mhz`, `congestion` and `context` (observation before the selected window). Null bins have empty congestion cells. Action CSV includes the raw action code, radio, reason and a JSON `details` cell containing all retained action fields. Text beginning with spreadsheet formula characters receives a leading apostrophe; negative numeric measurements remain numbers. JSON preserves the original text.

## Access and privacy

Downloads use a POST with the existing LuCI session token in the request body, never the URL. The endpoint checks session authorization for coordinator configuration, the history directory, RAM/state files and every listed batch filename before filtering expired batches. There are no user-supplied paths or shell commands. Cookies alone do not authorize a download. Expired or insufficient sessions receive an error in the download-status area; log in again and retry.

Only history fields and the graph's radar/band context are exported. Full controller state, UCI settings, Wi-Fi credentials and per-client runtime state are not included. Exports still describe your radio activity and operational errors; review them before publishing. See [runtime privacy](ARCHITECTURE.md#history-persistence-and-privacy).

Preference escalation records `steering-request` with `mode` (advisory or strong), `steering-disconnect` with the ban duration, and `steering-complete` with the observed outcome. These anonymous action records use the existing JSON action dataset and Recent actions CSV details, with no new dataset or client identities.
