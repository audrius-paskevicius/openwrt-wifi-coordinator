#!/usr/bin/ucode
// Own only steering decisions. Leave measurements, SSID filters and networking alone.
import * as fs from 'fs';
import * as uci from 'uci';
import * as ubus from 'ubus';

const SAVED = '/etc/radio-prefer/usteer-policy.json';
const POLICY = {
    assoc_steering: '0', probe_steering: '0', min_connect_snr: '0',
    min_snr: '0', roam_scan_snr: '0', roam_trigger_snr: '0',
    signal_diff_threshold: '0', load_balancing_threshold: '0',
    load_kick_enabled: '0', band_steering_interval: '0',
    initial_connect_delay: '0', aggressiveness: '0'
};

function restore_plan(current, saved) {
    let changes = {};
    for (let k, v in POLICY) {
        // Preserve settings deliberately changed by an administrator while owned.
        if (current[k] == v) changes[k] = saved.original[k];
    }
    return changes;
}

if (ARGV[0] == '--self-test') {
    let saved = { original: { band_steering_interval: '60000', min_snr: null } };
    let plan = restore_plan({ band_steering_interval: '0', min_snr: '0' }, saved);
    if (plan.band_steering_interval != '60000' || plan.min_snr != null)
        die('FAIL restoration of original and absent values\n');
    plan = restore_plan({ band_steering_interval: '120000', network: 'guest' }, saved);
    if (length(plan)) die('FAIL administrator changes must survive\n');
    print('PASS: restore original values, restore absence, preserve administrator edits\n');
    exit(0);
}

let cursor = uci.cursor();
let saved_text = fs.readfile(SAVED);
let saved = saved_text ? json(saved_text) : null;
if (saved && (saved.version != 1 || type(saved.original) != 'object' || !saved.section))
    die('Invalid usteer policy backup; refusing to overwrite it\n');

if (ARGV[0] == '--restore') {
    if (!saved) exit(0);
    let current = cursor.get_all('usteer', saved.section);
    if (!current) die('Original usteer section missing; backup retained\n');
    for (let k, v in restore_plan(current, saved)) {
        if (v == null) cursor.delete('usteer', saved.section, k);
        else cursor.set('usteer', saved.section, k, v);
    }
    if (!cursor.commit('usteer')) die('Cannot restore usteer configuration\n');
    if (!fs.unlink(SAVED)) die('Cannot remove restored policy backup\n');
    print('Restored usteer steering settings; administrator edits retained\n');
    exit(0);
}
if (ARGV[0] != '--prepare') die('Use --prepare, --restore or --self-test\n');
if (cursor.get('radio_prefer', 'main', 'enabled') != '1') exit(0);
let radio = cursor.get('radio_prefer', 'main', 'preferred_radio');
if (!radio || cursor.get('wireless', radio) != 'wifi-device')
    die('Select an existing preferred radio before enabling\n');

let bus = ubus.connect();
if (!bus) die('ubus unavailable\n');
for (let name in ['dawn', 'linksys-steering']) {
    let service = bus.call('service', 'list', { name });
    if (bus.error()) die('Cannot check competing steering services\n');
    for (let instance, data in service?.[name]?.instances ?? {})
        if (data.running) die(`Stop ${name} before enabling Radio Preference\n`);
}
let sections = [];
cursor.foreach('usteer', 'usteer', s => push(sections, s));
if (length(sections) != 1) die('Exactly one usteer configuration section is required\n');
let section = sections[0]['.name'];
if (sections[0].enabled == '0') die('Enable usteer before Radio Preference\n');
if (saved && saved.section != section) die('usteer section changed; restore the saved policy first\n');
if (saved) {
    for (let k, v in POLICY)
        if (sections[0][k] != v) die(`usteer ${k} changed while owned; disable Radio Preference before reconfiguring\n`);
    exit(0);
}
let original = {};
for (let k, v in POLICY) original[k] = sections[0][k] ?? null;
if (!fs.stat('/etc/radio-prefer') && !fs.mkdir('/etc/radio-prefer', 0700))
    die('Cannot create policy backup directory\n');
if (!fs.writefile(SAVED + '.new', sprintf('%J\n', { version: 1, section, original })) ||
    !fs.rename(SAVED + '.new', SAVED)) die('Cannot save original usteer policy\n');
for (let k, v in POLICY) cursor.set('usteer', section, k, v);
if (!cursor.commit('usteer')) die('Cannot save passive usteer policy; backup retained\n');
print('Radio Preference owns steering; usteer measurements and networking preserved\n');
