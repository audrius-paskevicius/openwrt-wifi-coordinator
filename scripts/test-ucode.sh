#!/bin/sh
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
command -v ucode >/dev/null || { echo 'OpenWrt ucode runtime is required.' >&2; exit 1; }
[ -f "$BASE/wifi-coordinator/history-test-module.uc" ] || {
 echo 'Run python3 scripts/prepare-tests.py on your development machine first.' >&2; exit 1;
}
LOCK=/tmp/wifi-coordinator-project-test.lock
mkdir "$LOCK" 2>/dev/null || { echo 'Another test run owns the test lock.' >&2; exit 1; }
trap 'rmdir "$LOCK"' EXIT HUP INT TERM
cd "$BASE"
ucode wifi-coordinator/test-policy.uc
ucode wifi-coordinator/test-widths.uc
ucode radio-prefer/files/main.uc --self-test
ucode radio-prefer/files/coordination.uc --self-test
ucode wifi-coordinator/test-redesign.uc
ucode wifi-coordinator/test-service.uc
ucode wifi-coordinator/test-executor.uc
ucode wifi-coordinator/test-restart.uc
ucode wifi-coordinator/test-client-memory.uc
ucode wifi-coordinator/test-reconnect-recovery.uc
ucode wifi-coordinator/test-comparison-snapshot.uc
ucode wifi-coordinator/test-width-limit.uc
ucode wifi-coordinator/test-radar-storage.uc
ucode wifi-coordinator/test-history.uc
ucode wifi-coordinator/test-history-export.uc
ucode wifi-coordinator/test-history-storage.uc
