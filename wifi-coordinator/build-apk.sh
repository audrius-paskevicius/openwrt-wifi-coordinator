#!/bin/sh
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CC="$BASE/../channel-coordinator"
RP="$BASE/../radio-prefer"
APK_TOOL=${APK_TOOL:-apk}
: "${SIGN_KEY:?Private signing key must be outside the source tree}"
KEYS_DIR=${KEYS_DIR:-"$RP/release"}
VERSION=${VERSION:-$(cat "$BASE/../VERSION")}
case "$VERSION" in *[!0-9A-Za-z._+-]*|'') echo "Invalid package version" >&2; exit 1;; esac
OUT=${OUT:-"$BASE/dist"}
mkdir -p "$OUT"
ROOT=$(mktemp -d "$OUT/root.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT HUP INT TERM
mkdir -p "$ROOT/etc/config" "$ROOT/etc/init.d" "$ROOT/usr/share/channel-coordinator" "$ROOT/usr/share/radio-prefer"
mkdir -p "$ROOT/www/luci-static/resources/view" "$ROOT/usr/share/luci/menu.d" "$ROOT/usr/share/rpcd/acl.d" "$ROOT/lib/upgrade/keep.d"
cp "$CC/files/channel-coordinator.config" "$ROOT/etc/config/channel_coordinator"
cp "$RP/files/radio-prefer.config" "$ROOT/etc/config/radio_prefer"
cp "$CC/files/channel-coordinator.init" "$ROOT/etc/init.d/channel-coordinator"
cp "$RP/files/radio-prefer.init" "$ROOT/etc/init.d/radio-prefer"
cp "$CC/files/main.uc" "$CC/files/policy.uc" "$CC/files/planner.uc" "$CC/files/radar.uc" "$CC/files/executor.uc" "$CC/files/survey.uc" "$CC/files/country.uc" "$CC/files/defaults.uc" "$CC/files/history.uc" "$CC/files/history-shutdown.uc" "$CC/files/history-storage.uc" "$CC/LICENSE" "$ROOT/usr/share/channel-coordinator/"
cp "$RP/files/main.uc" "$RP/files/coordination.uc" "$RP/files/integration-version" "$RP/LICENSE" "$ROOT/usr/share/radio-prefer/"
cp "$CC/files/recovery.uc" "$ROOT/usr/share/channel-coordinator/"
cp "$CC/files/history-export.uc" "$ROOT/usr/share/channel-coordinator/"
mkdir -p "$ROOT/www/cgi-bin"
sed "s/@WIFI_COORDINATOR_VERSION@/$VERSION/g" "$CC/files/wifi-coordinator-export" > "$ROOT/www/cgi-bin/wifi-coordinator-export"
cp "$CC/files/wifi-channels.js" "$CC/files/wifi-history.js" "$CC/files/wifi-disclaimer.js" "$RP/files/wifi-clients.js" "$ROOT/www/luci-static/resources/view/"
for view in "$ROOT/www/luci-static/resources/view/"*.js; do
 sed -i "s/@WIFI_COORDINATOR_VERSION@/$VERSION/g" "$view"
done
mkdir -p "$ROOT/www/luci-static/resources/wifi-coordinator"
cp "$CC/files/wifi-coordinator.chart.js" "$ROOT/www/luci-static/resources/wifi-coordinator/chart.js"
cp "$CC/files/wifi-coordinator.graphs.js" "$ROOT/www/luci-static/resources/wifi-coordinator/graphs.js"
cp "$CC/files/wifi-coordinator.time.js" "$ROOT/www/luci-static/resources/wifi-coordinator/time.js"
cp "$CC/files/wifi-coordinator.help.js" "$ROOT/www/luci-static/resources/wifi-coordinator/help.js"
cp "$BASE/../DISCLAIMER.txt" "$ROOT/usr/share/channel-coordinator/DISCLAIMER.txt"
ucode -e 'import * as fs from "fs"; let source=fs.readfile(ARGV[0]),text=fs.readfile(ARGV[1]); if(!source||!text)die("Missing disclaimer source"); print(replace(replace(source,"@WIFI_COORDINATOR_DISCLAIMER_JSON@",sprintf("%J",text)),"@WIFI_COORDINATOR_VERSION@",ARGV[2]));' "$CC/files/wifi-coordinator.disclaimer.js" "$BASE/../DISCLAIMER.txt" "$VERSION" > "$ROOT/www/luci-static/resources/wifi-coordinator/disclaimer.js"
cp "$CC/files/Chart.js-LICENSE.txt" "$ROOT/usr/share/channel-coordinator/"
cp "$BASE/wifi-coordinator.css" "$ROOT/www/luci-static/resources/view/"
cp "$BASE/menu.json" "$ROOT/usr/share/luci/menu.d/luci-app-wifi-coordinator.json"
cp "$CC/files/acl.json" "$ROOT/usr/share/rpcd/acl.d/luci-app-channel-coordinator.json"
cp "$RP/files/acl.json" "$ROOT/usr/share/rpcd/acl.d/luci-app-radio-prefer.json"
cat > "$ROOT/lib/upgrade/keep.d/wifi-coordinator" <<'EOF'
/etc/config/channel_coordinator
/etc/config/radio_prefer
/etc/radio-prefer/
/etc/wifi-coordinator/
/etc/apk/keys/radio-prefer-public.pem
/etc/init.d/channel-coordinator
/etc/init.d/radio-prefer
/etc/rc.d/S98channel-coordinator
/etc/rc.d/K09channel-coordinator
/etc/rc.d/S49radio-prefer
/etc/rc.d/K10radio-prefer
/usr/share/channel-coordinator/
/usr/share/radio-prefer/
/www/cgi-bin/wifi-coordinator-export
/www/luci-static/resources/view/wifi-channels.js
/www/luci-static/resources/view/wifi-clients.js
/www/luci-static/resources/view/wifi-history.js
/www/luci-static/resources/view/wifi-disclaimer.js
/www/luci-static/resources/wifi-coordinator/
/www/luci-static/resources/view/wifi-coordinator.css
/usr/share/luci/menu.d/luci-app-wifi-coordinator.json
/usr/share/rpcd/acl.d/luci-app-channel-coordinator.json
/usr/share/rpcd/acl.d/luci-app-radio-prefer.json
/lib/upgrade/keep.d/wifi-coordinator
/etc/modules.d/mwifiex
/lib/upgrade/keep.d/mwifiex-regdomain
EOF
find "$ROOT" -type d -exec chmod 755 {} \;
find "$ROOT" -type f -exec chmod 644 {} \;
chmod 755 "$ROOT/etc/init.d/channel-coordinator" "$ROOT/etc/init.d/radio-prefer"
chmod 755 "$ROOT/www/cgi-bin/wifi-coordinator-export"
"$APK_TOOL" mkpkg --files "$ROOT" --sign-key "$SIGN_KEY" \
 --info name:luci-app-wifi-coordinator --info version:"$VERSION" --info arch:noarch \
 --info license:MIT --info description:'AI-generated Wi-Fi channel planning and steering; use at your own risk' \
 --info 'depends:luci-base iw usteer ucode ucode-mod-fs ucode-mod-ubus ucode-mod-uci ucode-mod-uloop ucode-mod-nl80211 !luci-app-radio-prefer !luci-app-channel-coordinator' \
 --script "post-install:$BASE/post-install" --script "pre-upgrade:$BASE/pre-upgrade" \
 --script "post-upgrade:$BASE/post-install" --script "pre-deinstall:$BASE/pre-deinstall" \
 --output "$OUT/luci-app-wifi-coordinator-$VERSION.apk"
"$APK_TOOL" --keys-dir "$KEYS_DIR" mkndx --sign-key "$SIGN_KEY" --output "$OUT/packages.adb" "$OUT/luci-app-wifi-coordinator-$VERSION.apk"
