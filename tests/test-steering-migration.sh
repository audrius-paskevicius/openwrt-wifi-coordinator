#!/bin/sh
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MIGRATION_DIR=$(mktemp -d /tmp/wifi-steering-migration.XXXXXX)
trap 'rm -rf "$MIGRATION_DIR"' EXIT HUP INT TERM
cat > "$MIGRATION_DIR/wireless" <<'EOF'
config wifi-device 'radio0'
 option band '5g'
EOF
cat > "$MIGRATION_DIR/channel_coordinator" <<'EOF'
config channel_coordinator 'main'
 option handoff_escalation 'decisive'
 option handoff_target_min '-72'
EOF
cat > "$MIGRATION_DIR/radio_prefer" <<'EOF'
config radio_prefer 'main'
 option mode 'strong'
 option min_rssi '-67'
 option cooldown '420'
 option max_attempts '4'
EOF
WIFI_COORDINATOR_CONFIG_DIR="$MIGRATION_DIR" ucode "$BASE/channel-coordinator/files/defaults.uc" --apply >/dev/null
test "$(uci -c "$MIGRATION_DIR" get channel_coordinator.main.handoff_escalation)" = decisive
test "$(uci -c "$MIGRATION_DIR" get channel_coordinator.main.handoff_target_min)" = -67
test "$(uci -c "$MIGRATION_DIR" get radio_prefer.main.cooldown)" = 420
test "$(uci -c "$MIGRATION_DIR" get radio_prefer.main.max_attempts)" = 4
! uci -q -c "$MIGRATION_DIR" get radio_prefer.main.mode
! uci -q -c "$MIGRATION_DIR" get radio_prefer.main.min_rssi
sha256sum "$MIGRATION_DIR/channel_coordinator" "$MIGRATION_DIR/radio_prefer" > "$MIGRATION_DIR/hashes"
WIFI_COORDINATOR_CONFIG_DIR="$MIGRATION_DIR" ucode "$BASE/channel-coordinator/files/defaults.uc" --apply >/dev/null
sha256sum -c "$MIGRATION_DIR/hashes" >/dev/null
uci -c "$MIGRATION_DIR" delete channel_coordinator.main.handoff_escalation
uci -c "$MIGRATION_DIR" set radio_prefer.main.mode=advisory
uci -c "$MIGRATION_DIR" commit channel_coordinator
uci -c "$MIGRATION_DIR" commit radio_prefer
WIFI_COORDINATOR_CONFIG_DIR="$MIGRATION_DIR" ucode "$BASE/channel-coordinator/files/defaults.uc" --apply >/dev/null
test "$(uci -c "$MIGRATION_DIR" get channel_coordinator.main.handoff_escalation)" = gentle
echo 'PASS: steering migration preserves policy/retries, retains stricter signal minimum, removes retired keys and is idempotent'
