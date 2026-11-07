#!/usr/bin/ucode
// No credentials, SSIDs, BSSIDs or device-specific interface names are stored here.
import * as fs from 'fs';
import * as ubus from 'ubus';
import * as uci from 'uci';
import * as uloop from 'uloop';

const STATE = '/tmp/radio-prefer-state.json';
const PASSIVE = {
    assoc_steering: false, probe_steering: false, min_connect_snr: 0,
    min_snr: 0, roam_scan_snr: 0, roam_trigger_snr: 0,
    signal_diff_threshold: 0, load_balancing_threshold: 0,
    load_kick_enabled: false, band_steering_interval: 0,
    initial_connect_delay: 0, aggressiveness: 0
};

function signed(n) { return n > 2147483647 ? n - 4294967296 : n; }
function protected_client(mac,list) {
    return index(map(type(list)=='array'?list:split(list ?? '',/\s+/),x=>lc(x)),lc(mac))>=0;
}

function decision(c, s, now, target, cfg) {
    if (!c['bss-transition-management']) return 'unsupported';
    if (now - s.source_since < cfg.settle_time || c.connected < cfg.settle_time * 1000) return 'settling';
    if (s.attempts >= cfg.max_attempts && now-(s.last_btm ?? now)<cfg.cooldown*cfg.max_attempts) return 'attempt-limit';
    if (s.last_btm != null && now - s.last_btm < cfg.cooldown) return 'cooldown';
    for (let m in c.measurements ?? []) {
        if (m.node != target || m.age < 0 || m.age > 30000) continue;
        if (m.rcpi <= 0 || m.rcpi > 220) continue;
        let rssi = signed(m.rssi);
        return rssi >= cfg.min_rssi && rssi < 0 ? 'recommend' : 'target-weak';
    }
    if (s.last_scan != null && now - s.last_scan < 60) return 'await-measurement';
    let modes = c['beacon-measurement-modes'] ?? [];
    return index(modes, 'ACTIVE') >= 0 || index(modes, 'PASSIVE') >= 0 ? 'measure' : cfg.mode=='strong'?'no-measurement-support':'recommend-unmeasured';
}

function request(mac, nr, token, mode) {
    // Keep the report's fixed header and optional channel information. Replace
    // any existing preference subelement instead of creating duplicate fields.
    if (type(nr) != 'string' || length(nr) < 26 || length(nr) % 2 || !match(nr, /^[0-9a-fA-F]+$/)) die('Invalid neighbor report');
    let report = substr(nr, 0, 26);
    for (let p = 26; p < length(nr); ) {
        if (p + 4 > length(nr)) die('Truncated neighbor subelement');
        let size = int(substr(nr, p + 2, 2), 16) * 2 + 4;
        if (p + size > length(nr)) die('Truncated neighbor subelement');
        if (lc(substr(nr, p, 2)) != '03') report += substr(nr, p, size);
        p += size;
    }
    return { addr: mac, disassociation_imminent: mode == 'strong',
        disassociation_timer: 0, validity_period: 100,
        neighbors: [report + '0301ff'], abridged: true, dialog_token: token,
        mbo_reason: 0, cell_pref: 0, reassoc_delay: 0 };
}

function operating_class(freq, channel) {
    if (freq < 2500 && channel >= 1 && channel <= 13) return 81;
    if (freq == 2484 && channel == 14) return 82;
    if (freq >= 5000 && freq < 5925) {
        if (channel >= 36 && channel <= 48) return 115;
        if (channel >= 52 && channel <= 64) return 118;
        if (channel >= 100 && channel <= 144) return 121;
        if (channel >= 149 && channel <= 177) return 125;
    }
    // Six GHz and MLO need separate validation; fail closed for now.
    return null;
}

function selftest() {
    let cfg = { min_rssi: -67, cooldown: 300, settle_time: 30, max_attempts: 3 };
    let c = { connected: 60000, 'bss-transition-management': true,
        'beacon-measurement-modes': ['ACTIVE'], measurements: [] };
    let s = { attempts: 0, source_since: 0 };
    let count = 0;
    function eq(a, b) { if (a != b) die(sprintf('FAIL %J != %J\n', a, b)); count++; }
    function choose() { return decision(c, s, 1000, 'preferred', cfg); }
    eq(protected_client('02:00:00:00:00:aa',['02:00:00:00:00:AA']),true);
    eq(protected_client('02:00:00:00:00:aa','02:00:00:00:00:aa'),true);
    eq(protected_client('02:00:00:00:00:aa',null),false);
    eq(choose(), 'measure');
    s.source_since = 990; eq(choose(), 'settling'); s.source_since = 0;
    s.last_scan = 990; eq(choose(), 'await-measurement');
    c.measurements = [{ node: 'preferred', age: 1000, rcpi: 120, rssi: -50 }];
    eq(choose(), 'recommend');
    c.measurements[0].rssi = 4294967246; eq(choose(), 'recommend');
    c.measurements[0].rssi = -68; eq(choose(), 'target-weak');
    c.measurements[0].rssi = -67; eq(choose(), 'recommend');
    c.measurements[0].age = 30001; eq(choose(), 'await-measurement');
    c.measurements[0].age = 1000; c.measurements[0].rcpi = 255;
    eq(choose(), 'await-measurement'); c.measurements[0].rcpi = 120;
    c.measurements[0].node = 'another'; eq(choose(), 'await-measurement');
    c.measurements[0].node = 'preferred'; s.last_btm = 950; eq(choose(), 'cooldown');
    s.last_btm = 700; eq(choose(), 'recommend');
    s.attempts = 3; eq(choose(), 'attempt-limit');
    s.last_btm=100;eq(choose(),'recommend');
    s.attempts=0;c.measurements=[];delete s.last_scan;delete s.last_btm;
    c['beacon-measurement-modes']=[];eq(choose(),'recommend-unmeasured');
    cfg.mode='strong';eq(choose(),'no-measurement-support');
    c.measurements=[{node:'preferred',age:1000,rcpi:120,rssi:-50}];eq(choose(),'recommend');
    c.measurements=[];cfg.mode='advisory';
    eq(request('02:00:00:00:00:02','020000000001ef190000802409',1,'advisory').disassociation_imminent,false);
    s.attempts = 0; c['bss-transition-management'] = false; eq(choose(), 'unsupported');
    let nr = '020000000001ef1900008024090603022a00';
    let req = request('02:00:00:00:00:02', nr, 1, 'advisory');
    eq(req.disassociation_imminent, false);
    eq(request('02:00:00:00:00:02', nr, 1, 'strong').disassociation_imminent, true);
    eq(req.disassociation_timer, 0); eq(req.reassoc_delay, 0);
    eq(req.neighbors[0], nr + '0301ff');
    eq(request('', nr + '030101', 1, 'advisory').neighbors[0], nr + '0301ff');
    let rejected = false;
    try { request('', nr + '0603', 1, 'advisory'); } catch (e) { rejected = true; }
    eq(rejected, true);
    eq(operating_class(5180, 36), 115);
    eq(operating_class(2462, 11), 81);
    eq(operating_class(5975, 5), null);
    printf('PASS: %d policy/protocol checks\n', count);
}

if (ARGV[0] == '--self-test') { selftest(); exit(0); }
let bus = ubus.connect();
if (!bus) die('ubus unavailable\n');
function call(node, method, args) {
    let out = bus.call(node, method, args ?? {});
    let error = bus.error();
    if (error) die(`${node}.${method}: ${error}`);
    return out;
}

let cursor = uci.cursor();
let raw = cursor.get_all('radio_prefer', 'main') ?? {};
if(raw.enabled!=null&&index(['0','1'],raw.enabled)<0)die('Invalid enabled setting\n');
for(let key in ['min_rssi','cooldown','settle_time','max_attempts'])
    if(raw[key]!=null&&!match(raw[key],/^-?[0-9]+$/))die('Expected an integer for '+key+'\n');
let cfg = {
    enabled: raw.enabled == '1', preferred_radio: raw.preferred_radio ?? '',
    mode: raw.mode ?? 'advisory', min_rssi: int(raw.min_rssi ?? '-67'),
    cooldown: int(raw.cooldown ?? '300'), settle_time: int(raw.settle_time ?? '30'),
    max_attempts: int(raw.max_attempts ?? '3')
};
if (ARGV[0] == '--check' && ARGV[1]) cfg.preferred_radio = ARGV[1];
if (!match(cfg.preferred_radio, /^[A-Za-z0-9_-]+$/)) die('Select a preferred radio first\n');
if (index(['advisory', 'strong'], cfg.mode) < 0 || cfg.min_rssi < -90 || cfg.min_rssi > -30 ||
    cfg.cooldown < 60 || cfg.cooldown > 3600 || cfg.settle_time < 10 || cfg.settle_time > 300 ||
    cfg.max_attempts < 1 || cfg.max_attempts > 10) die('Invalid radio preference settings\n');

function inventory() {
    let wireless = call('network.wireless', 'status');
    let nodes = call('usteer', 'local_info');
    let aps = {};
    for (let radio, data in wireless) {
        for (let iface in data.interfaces ?? []) {
            let c = iface.config ?? {};
            let node = 'hostapd.' + iface.ifname;
            if (c.mode != 'ap' || !nodes[node]) continue;
            let methods = bus.list(node, true)?.[0];
            if (!methods?.bss_transition_request || !methods?.rrm_beacon_req) continue;
            // Credentials are compared in memory only; never saved or logged.
            aps[node] = { radio, config: c, info: nodes[node] };
        }
    }
    return aps;
}

function target_for(aps, source) {
    let a = aps[source];
    if (!a || a.radio == cfg.preferred_radio) return null;
    // Enterprise and uncommon security configurations need separate validation.
    if (!match(a.config.encryption ?? '', /^(psk|sae|owe|none)/)) return null;
    for (let node, b in aps) {
        if (b.radio != cfg.preferred_radio || a.info.ssid != b.info.ssid) continue;
        if (a.config.encryption != b.config.encryption || a.config.key != b.config.key ||
            a.config.ieee80211w != b.config.ieee80211w) continue;
        let an = sort(type(a.config.network) == 'array' ? [...a.config.network] : split(a.config.network ?? '', /\s+/));
        let bn = sort(type(b.config.network) == 'array' ? [...b.config.network] : split(b.config.network ?? '', /\s+/));
        if (length(an) == 0 || sprintf('%J', an) != sprintf('%J', bn)) continue;
        return node;
    }
    return null;
}

if (ARGV[0] == '--check') {
    let aps = inventory();
    let preferred = 0, pairs = 0;
    for (let node, ap in aps) {
        if (ap.radio == cfg.preferred_radio) {
            preferred++;
            let status = call(node, 'get_status');
            if (status.status != 'ENABLED' || !operating_class(status.freq, status.channel))
                die('Preferred AP is down or its band/channel is not supported\n');
        }
        if (target_for(aps, node)) pairs++;
    }
    printf('Discovered %d APs, %d on preferred radio, %d matching source APs\n', length(aps), preferred, pairs);
    if (!preferred || !pairs) die('No usable matching AP pair\n');
    print('PASS: read-only topology check; no steering request or configuration change\n');
    exit(0);
}
if (!cfg.enabled) exit(0);
let boot = trim(fs.readfile('/proc/sys/kernel/random/boot_id'));
let state = { boot, preferred_radio: cfg.preferred_radio, clients: {} };
try {
    let saved = json(fs.readfile(STATE) ?? '{}');
    if (saved.boot == boot && saved.preferred_radio == cfg.preferred_radio && type(saved.clients) == 'object') state = saved;
} catch (e) {}

function tick() {
    let now = int(split(fs.readfile('/proc/uptime'), ' ')[0]);
    // Coordinate with the channel manager. Leases expire after crashes/reboot.
    let lease;
    try { lease = json(fs.readfile('/tmp/channel-coordinator-lease.json') ?? '{}'); } catch (e) { lease = {}; }
    let reserved=[];
    if (lease.boot == boot && lease.until > now && lease.until <= now + 120) {
        state.integration_error = null;
        state.coordination_pause = lease.reason ?? 'Channel survey or move';
        state.updated_uptime = now;
        fs.writefile(STATE, sprintf('%J\n', state));
        if(type(lease.reserved)!='array')return;
        reserved=lease.reserved;
    }
    state.coordination_pause = null;
    let current = call('usteer', 'get_config');
    for (let k, v in PASSIVE) {
        if (current[k] != null && current[k] != v)
            die(`Competing usteer policy ${k} is active; steering paused. Disable Radio Preference before editing usteer policies`);
    }
    for (let name in ['dawn', 'linksys-steering']) {
        let service = call('service', 'list', { name });
        for (let instance, data in service?.[name]?.instances ?? {})
            if (data.running) die(`Competing controller ${name} is running; steering paused`);
    }
    state.integration_error = null;
    let aps = inventory();
    let clients = call('usteer', 'connected_clients');
    let protected_list=uci.cursor().get('channel_coordinator','main','protected_clients');
    if (!length(aps)) die('No compatible APs: full wpad/hostapd with BSS transition support is required');
    for (let source, stations in clients) {
        if (!aps[source]) continue;
        let target = target_for(aps, source);
        for (let mac, client in stations) {
            let s = state.clients[mac] ?? { attempts: 0 };
            state.clients[mac] = s;
            if (s.source != source) {
                if (s.source) printf('client %s moved %s -> %s\n', mac, s.source, source);
                s.source_since = now;
            }
            s.source = source;
            s.last_seen = now;
            if(protected_client(mac,protected_list)){s.decision='protected';continue;}
            if (aps[source].radio == cfg.preferred_radio) {
                if (now - s.source_since >= 60) s.attempts = 0;
                s.decision = 'on-preferred-radio'; continue;
            }
            if (!target) { s.decision = 'no-matching-target'; continue; }
            if(index(reserved,aps[source].radio)>=0||index(reserved,aps[target].radio)>=0){s.decision='coordinator-reservation';continue;}
            let t = aps[target].info;
            let status = call(target, 'get_status');
            let op = operating_class(status.freq, status.channel);
            if (status.status != 'ENABLED' || !op) {s.decision='target-unavailable';continue;}
            if (t.load >= 80 || (t.max_assoc > 0 && t.n_assoc >= t.max_assoc)) {s.decision='target-busy';continue;}
            let nr = t.rrm_nr?.[2];
            if (type(nr) != 'string') {s.decision='target-unavailable';continue;}
            s.decision = decision(client, s, now, target, cfg);
            if (s.decision == 'measure') {
                s.last_scan = now;
                call(source, 'rrm_beacon_req', { addr: mac,
                    mode: index(client['beacon-measurement-modes'], 'ACTIVE') >= 0 ? 1 : 0,
                    op_class: op, channel: status.channel, duration: 50,
                    bssid: t.bssid, ssid: t.ssid, reporting_detail: 0 });
            } else if (s.decision == 'recommend'||s.decision=='recommend-unmeasured') {
                let mode=cfg.mode;
                if(now-(s.last_btm ?? now)>=cfg.cooldown*cfg.max_attempts)s.attempts=0;
                let message = request(mac, nr, ((s.dialog ?? 0) % 255) + 1, mode);
                s.last_btm = now; s.attempts++; s.dialog = message.dialog_token;
                fs.writefile(STATE, sprintf('%J\n', state));
                call(source, 'bss_transition_request', message);
                printf('%s recommendation to %s: %s -> %s, attempt %d\n', cfg.mode, mac, source, target, s.attempts);
            }
        }
    }
    for (let mac, s in state.clients) if (now - s.last_seen > 300) delete state.clients[mac];
    state.updated_uptime = now;
    fs.writefile(STATE, sprintf('%J\n', state));
}

uloop.init();
let last_error, timer;
timer = uloop.timer(1000, function() {
    try { tick(); last_error = null; }
    catch (e) {
        let text = `${e}`;
        state.integration_error = text;
        fs.writefile(STATE, sprintf('%J\n', state));
        if (text != last_error) printf('waiting: %s\n', text);
        last_error = text;
    }
    fs.stdout.flush(); timer.set(10000);
});
printf('radio-prefer started: %s mode, no AP disconnect timer\n', cfg.mode);
fs.stdout.flush();
uloop.run();
