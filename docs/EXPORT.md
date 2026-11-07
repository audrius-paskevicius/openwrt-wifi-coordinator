# History downloads

Open **Network / Wi-Fi Coordinator / Storage & export**, then **Export history** below History retention. Its independent Period selector offers All retained history (the default) and durations up to the saved retention limit. Changing Show on the History tab does not change the export period. Downloads do not change recording, retention, radio settings or channel planning.

- **CSV data** selects channel placements, traffic summaries, spectrum surveys, radar detections or actions, followed by its Download button.
- **JSON data** downloads all graph data and actions in one structured file using its separate Download button.

The Period selector above these rows applies to both downloads.

The router sends the response directly to the browser download manager. It creates no export file and performs no flash writes. Existing history remains in its normal RAM buffer and flash archive. The exporter holds a fixed RAM snapshot, one bounded archive batch, a lightweight deduplication index for one dataset, and a small output buffer. Index memory grows with the number of retained records; the entire archive or completed download is never assembled in memory. Closing a download stops processing when the next output write detects the closed connection.

## Time, units and completeness

Every export has a fixed request-time cutoff, the saved retention limit, package/schema versions, units and UTC timestamps. ISO timestamps end in `Z`; original Unix seconds are also retained. These are UTC even when the page displays local time. Rows are emitted in source order; sort by `start` or `time` if chronological ordering is required.

Placements and five-minute traffic summaries retain their original interval boundaries. An overlapping interval may begin before the selected window; no estimated partial-bucket traffic is invented. Surveys include the earlier retained observations needed to establish each frequency bin at the beginning of the window. Radar detections come from current radar memory, which is independent of graph retention and may be older. The exported radar half-life lets consumers reconstruct decay.

This is a best-effort snapshot, not a lock on the recorder. The RAM snapshot and archive listing are fixed at request start; closed archive batches are immutable. An archive removed or unreadable during download produces an explicit warning. **Check the final completeness result**: a truncated file without that result is not a completed export. A complete export means all selected sources were read, not that the router recorded every moment. Metadata also reports previously dropped RAM records.

## JSON schema version 1

Top-level metadata includes `format`, `version`, `package_version`, `exported_at`, `window`, `retention_hours`, `declared_bands`, `radar_half_life_seconds`, `units`, `notes` and `dropped_ram_records`.

`datasets` contains:

| Dataset | Contents |
| --- | --- |
| `periods` | Radio, primary channel, centre frequency, width, role and residence interval |
| `traffic` | Original five-minute sums/counts/peaks plus derived mean Mbit/s and measured busy-airtime percent |
| `surveys` | Compact frequency-bin levels and their measurement-time offsets |
| `radar` | Detection time, centre frequency, width, region, PHYs and weight |
| `actions` | Retained action codes and their recorded details |

`result` ends the document with `complete`, `warnings` and record `counts`. Survey counts count frames, not individual bins.

Survey bands use `start` and `step` in MHz. Bin `i` spans `[start + i * step, start + (i + 1) * step)`. Its timestamp is the frame's `time + offsets[i]` (zero when omitted). `levels[i]` is a 0–100 congestion estimate, not airtime percent. `null` means unmeasured, never clear. Traffic `n`, `traffic_sum`, `busy_n` and `busy_sum` preserve the evidence behind means; absent busy measurements stay null.

## CSV conventions

UTF-8, comma delimiter, quoted cells, doubled embedded quotes and CRLF row endings. Each file has a header and `record_type` column:

- `metadata`: export metadata in the `message` column.
- `data`: actual dataset rows. Filter to these for plotting or spreadsheet calculations.
- `warning`: a source could not be read; explanation in `message`.
- `summary`: final completeness result and counts in `message`.

Survey CSV expands each selected frame into frequency bins with `observed_iso`, `low_mhz`, `high_mhz`, `congestion` and `context` (observation before the selected window). Null bins have empty congestion cells. Action CSV includes the raw action code, radio, reason and a JSON `details` cell containing all retained action fields. Text beginning with spreadsheet formula characters receives a leading apostrophe; negative numeric measurements remain numbers. JSON preserves the original text.

## Access and privacy

Downloads use a POST with the existing LuCI session token in the request body, never the URL. The endpoint checks session authorization for coordinator configuration, the history directory, RAM/state files and every selected archive batch. There are no user-supplied paths or shell commands. Cookies alone do not authorize a download. Expired or insufficient sessions receive an error in the download-status area; log in again and retry.

Only history fields and the graph's radar/band context are exported. Full controller state, UCI settings, Wi-Fi credentials and per-client runtime state are not included. Exports still describe your radio activity and operational errors; review them before publishing. See [runtime privacy](ARCHITECTURE.md#history-persistence-and-privacy).
