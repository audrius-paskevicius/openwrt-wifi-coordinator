// No credentials, SSIDs, BSSIDs or device-specific interface names are stored here.
import * as system_fs from 'fs';
import * as ubus from 'ubus';
import * as uci from 'uci';
import * as nl from 'nl80211';

import {protected_client,next_step,begin_attempt,reserve_force,target_ok,transition_request} from '../../channel-coordinator/files/handoff.uc';

const STATE = '/tmp/radio-prefer-state.json';
const PASSIVE = {
    assoc_steering: false, probe_steering: false, min_connect_snr: 0,
    min_snr: 0, roam_scan_snr: 0, roam_trigger_snr: 0,
    signal_diff_threshold: 0, load_balancing_threshold: 0,
    load_kick_enabled: false, band_steering_interval: 0,
    initial_connect_delay: 0, aggressiveness: 0
};

function avoided_until(entries,mac,radio,g,t){
    if(!g)return 0;
    let times=map(filter(entries,e=>e.until>t&&e.until<=t+21600&&e.radio==radio&&e.mac==lc(mac)&&
        e.freq==g.freq&&e.center==g.center&&e.width==g.width),e=>e.until);
    return max(0,...times);
}

function decision(c,s,now,target,cfg){
    if(!c['bss-transition-management']&&cfg.escalation!='decisive')return 'unsupported';
    if(now-s.source_since<cfg.settle_time||c.connected<cfg.settle_time*1000)return 'settling';
    if(!target_ok(c.measurements,target,cfg.min_rssi))return 'target-weak';
    return 'recommend';
}
function request(mac,nr,token,mode){return transition_request(mac,nr,token,mode=='strong');}

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

export function selftest(){
    let checks=0;function eq(a,b){if(a!=b)die(sprintf('FAIL %J != %J\n',a,b));checks++;}
    let cfg={min_rssi:-67,settle_time:30,escalation:'strong'},c={connected:60000,'bss-transition-management':true,measurements:[]},s={source_since:0};
    eq(decision(c,s,1000,'target',cfg),'recommend');
    eq(decision(c,{source_since:990},1000,'target',cfg),'settling');
    c.measurements=[{node:'target',age:0,rcpi:80,rssi:-75}];
    eq(decision(c,s,1000,'target',cfg),'target-weak');
    c.measurements[0].age=30001;eq(decision(c,s,1000,'target',cfg),'recommend');
    c['bss-transition-management']=false;eq(decision(c,s,1000,'target',cfg),'unsupported');
    cfg.escalation='decisive';eq(decision(c,s,1000,'target',cfg),'recommend');
    let nr='020000000001ef1900008024090603022a00';
    eq(request('client',nr,1,'advisory').neighbors[0],nr+'0301ff');
    eq(request('client',nr+'030101',1,'strong').neighbors[0],nr+'0301ff');
    eq(request('client',nr,1,'strong').disassociation_imminent,true);
    eq(request('client',nr,1,'advisory').disassociation_imminent,false);
    let bad=false;try{request('',nr+'0603',1,'strong');}catch(e){bad=true;}eq(bad,true);
    eq(operating_class(5180,36),115);eq(operating_class(2462,11),81);eq(operating_class(5975,5),null);
    let g={freq:5180,center:5250,width:160},avoid=[{...g,mac:'client',radio:'r',until:2000}];
    eq(avoided_until(avoid,'CLIENT','r',g,1000),2000);
    eq(avoided_until(avoid,'client','r',{...g,width:80},1000),0);
    eq(avoided_until(avoid,'client','r',g,2001),0);
    printf('PASS: %d preference policy/protocol checks\n',checks);
};

export function create_preference(options) {
let fs=options.fs ?? system_fs;
let bus = options.bus ?? ubus.connect();
if (!bus) die('ubus unavailable\n');
function call(node, method, args) {
    let out = bus.call(node, method, args ?? {});
    let error = bus.error();
    if (error) die(`${node}.${method}: ${error}`);
    return out;
}

let cursor = options.cursor ?? uci.cursor();
let raw = cursor.get_all('radio_prefer', 'main') ?? {};
if(raw.enabled!=null&&index(['0','1'],raw.enabled)<0)die('Invalid enabled setting\n');
for(let key in ['cooldown','settle_time','max_attempts'])
    if(raw[key]!=null&&!match(raw[key],/^-?[0-9]+$/))die('Expected an integer for '+key+'\n');
let shared=options.shared ?? {},handoff_cfg=options.handoff_cfg ?? {};
let common=cursor.get_all('channel_coordinator','main') ?? {};
if(!options.handoff_cfg)handoff_cfg={escalation:common.handoff_escalation ?? 'decisive',handoff_wait:int(common.handoff_wait ?? 90),ban_seconds:20,target_min:int(common.handoff_target_min ?? -72),source_min:int(common.handoff_source_min ?? -65),protected_clients:common.protected_clients ?? []};
let cfg = {
    enabled: raw.enabled == '1', preferred_radio: raw.preferred_radio ?? '',
    escalation:handoff_cfg.escalation,min_rssi:handoff_cfg.target_min ?? -72,
    cooldown: int(raw.cooldown ?? '300'), settle_time: int(raw.settle_time ?? '30'),
    max_attempts: int(raw.max_attempts ?? '3')
};
if (options.preferred) cfg.preferred_radio = options.preferred;
if ((cfg.enabled || options.check) && !match(cfg.preferred_radio, /^[A-Za-z0-9_-]+$/)) die('Select a preferred radio first\n');
if (index(['gentle', 'strong','decisive'], cfg.escalation) < 0 || cfg.min_rssi < -90 || cfg.min_rssi > -30 ||
    cfg.cooldown < 60 || cfg.cooldown > 3600 || cfg.settle_time < 10 || cfg.settle_time > 300 ||
    cfg.max_attempts < 1 || cfg.max_attempts > 10) die('Invalid radio preference settings\n');

handoff_cfg.handoff_cooldown=cfg.cooldown;handoff_cfg.handoff_attempts=cfg.max_attempts;
function now(){return options.now?options.now():int(split(fs.readfile('/proc/uptime'),' ')[0]);}
function inventory() {
    let interfaces=options.interfaces?options.interfaces():nl.request(nl.const.NL80211_CMD_GET_INTERFACE,nl.const.NLM_F_DUMP,{});
    if(!options.interfaces&&nl.error())die('Cannot read live radio placements');
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
            let live=filter(interfaces ?? [],x=>x.ifname==iface.ifname)[0];
            let placement=live?{freq:live.wiphy_freq,center:live.center_freq1 ?? live.wiphy_freq,width:[20,20,40,80,null,160][live.channel_width]}:null;
            aps[node] = { radio, config: c, info: nodes[node],placement };
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

function check() {
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
    return true;
}
let boot = trim(fs.readfile('/proc/sys/kernel/random/boot_id'));
let state = { boot, preferred_radio: cfg.preferred_radio, clients: {} };
try {
    let saved = json(fs.readfile(STATE) ?? '{}');
    if (saved.boot == boot && saved.preferred_radio == cfg.preferred_radio && type(saved.clients) == 'object') state = saved;
} catch (e) {}
for(let mac,v in state.clients)delete v.episode; // a restart never replays a warning/disconnect

function tick(reserved) {
    reserved=reserved ?? [];
    let t=now();
    if (!cfg.enabled) return;
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
    let memory;try{memory=json(fs.readfile('/tmp/wifi-coordinator-client-avoids.json') ?? '{}');}catch(e){memory={};}
    let avoids=memory.boot==boot&&type(memory.entries)=='array'?memory.entries:[];
    let protected_list=handoff_cfg.protected_clients;
    let live=options.radios?.(),locations={};
    if(live){for(let r in live)for(let mac in keys(r.authorized))locations[mac]='hostapd.'+r.ifname;}
    else for(let node,stations in clients)for(let mac in keys(stations))locations[mac]=node;
    function finish(mac,s,reason){
        let e=s.episode;if(!e)return;
        if(e.force_sent!=null){
            try{if(!call(e.source,'get_clients').clients?.[mac])call(e.source,'del_client',{addr:mac,reason:12,deauth:false,ban_time:0});}catch(err){}
        }
        options.history?.({event:'steering-complete',operation:e.operation,from:e.source_radio,to:e.target_radio,clients:1,reason});
        delete s.episode;s.decision=reason;delete s.last_scan;
    }
    function scope(source,target){return sprintf('%J',[aps[source]?.placement,aps[target]?.placement]);}
    // Observe outstanding moves even while a disconnected client is absent.
    for(let mac,s in state.clients){
        let e=s.episode;if(!e)continue;
        if(locations[mac]==e.target){finish(mac,s,'on-preferred-radio');continue;}
        let source=aps[e.source],target=aps[e.target],blocked=index(reserved,e.source_radio)>=0||index(reserved,e.target_radio)>=0;
        if(protected_client(mac,protected_list)||!source||!target||target_for(aps,e.source)!=e.target||scope(e.source,e.target)!=e.scope||target&&avoided_until(avoids,mac,target.radio,target.placement,t)>t){finish(mac,s,'steering-cancelled');continue;}
        if(t-e.started>=handoff_cfg.handoff_wait||e.force_sent!=null&&t-e.force_sent>=handoff_cfg.ban_seconds){
            finish(mac,s,locations[mac]?'stayed-elsewhere':'return-not-observed');continue;
        }
        if(blocked){
            if(e.force_sent!=null)finish(mac,s,'steering-cancelled');
            else s.decision='coordinator-reservation';
            continue;
        }
        if(locations[mac]&&locations[mac]!=e.source){finish(mac,s,'stayed-elsewhere');continue;}
        let client=clients[e.source]?.[mac];if(!client){s.decision='checking-reconnection';continue;}
        let st=call(e.target,'get_status');
        if(st.status!='ENABLED'||st.freq!=target.placement.freq||!target_ok(client.measurements,e.target,cfg.min_rssi)||target.info.load>=80||target.info.max_assoc>0&&target.info.n_assoc>=target.info.max_assoc){finish(mac,s,'steering-cancelled');continue;}
        let step=next_step(e,t,handoff_cfg);
        if(step=='strong'){
            e.strong_sent=true;
            if(client['bss-transition-management']){
                let message=request(mac,target.info.rrm_nr?.[2],((s.dialog ?? 0)%255)+1,'strong');
                s.dialog=message.dialog_token;s.last_btm=t;delete s.response;
                call(e.source,'bss_transition_request',message);
                options.history?.({event:'steering-request',operation:e.operation,from:e.source_radio,to:e.target_radio,mode:'strong',clients:1});
            }
            s.decision=client['bss-transition-management']?'strong-request':'no-request-support';
        }else if(step=='force'){
            e.force_sent=t;
            let source_radio=filter(live ?? [],r=>r.name==e.source_radio)[0];
            let same_band=(source.placement.freq<3000)==(target.placement.freq<3000);
            if(reserve_force(shared,mac,client.measurements,e.target,source_radio?.signals?.[mac],same_band,t,handoff_cfg)){
                options.save?.();fs.writefile(STATE,sprintf('%J\n',state));
                call(e.source,'del_client',{addr:mac,reason:12,deauth:true,ban_time:handoff_cfg.ban_seconds*1000});
                options.history?.({event:'steering-disconnect',operation:e.operation,from:e.source_radio,to:e.target_radio,clients:1,ban_seconds:handoff_cfg.ban_seconds});
                s.decision='checking-reconnection';
            }else finish(mac,s,'disconnect-not-eligible');
        }else s.decision=e.force_sent!=null?'checking-reconnection':!client['bss-transition-management']?'no-request-support':e.strong_sent?'strong-request':'gentle-request';
    }
    if(!length(aps))die('No compatible APs: full wpad/hostapd with BSS transition support is required');
    for(let source,stations in clients){
        if(!aps[source])continue;
        let target=target_for(aps,source);
        for(let mac,client in stations){
            let s=state.clients[mac] ?? {attempts:0};state.clients[mac]=s;
            if(s.return_once&&t-s.return_since>=120)delete s.return_once;
            if(s.source!=source)s.source_since=t;
            s.source=source;s.last_seen=t;
            let reply=client['bss-transition-response'];
            if(s.last_btm!=null&&t-s.last_btm<=120&&reply?.age>0&&reply.age<=(t-s.last_btm)*1000+1000){
                s.response=reply['status-code'];
                if(s.reply_for!=s.last_btm){s.reply_for=s.last_btm;options.history?.({event:'steering-response',radio:aps[source].radio,response:s.response,clients:1});}
            }
            if(s.episode)continue;
            if(protected_client(mac,protected_list)){s.decision='protected';continue;}
            if(aps[source].radio==cfg.preferred_radio){if(t-s.source_since>=60)s.attempts=0;s.decision='on-preferred-radio';continue;}
            if(!target){s.decision='no-matching-target';continue;}
            if(!aps[target].placement){s.decision='target-unavailable';continue;}
            s.compatibility_until=avoided_until(avoids,mac,aps[target].radio,aps[target].placement,t);
            if(s.compatibility_until>t){s.decision='client-placement-cooldown';continue;}
            if(index(reserved,aps[source].radio)>=0||index(reserved,aps[target].radio)>=0){s.decision='coordinator-reservation';continue;}
            let info=aps[target].info,status=call(target,'get_status'),op=operating_class(status.freq,status.channel);
            if(status.status!='ENABLED'||!op||type(info.rrm_nr?.[2])!='string'){s.decision='target-unavailable';continue;}
            if(info.load>=80||info.max_assoc>0&&info.n_assoc>=info.max_assoc){s.decision='target-busy';continue;}
            s.decision=decision(client,s,t,target,cfg);if(s.decision!='recommend')continue;
            let message=request(mac,info.rrm_nr[2],((s.dialog ?? 0)%255)+1,'advisory');
            let gate=begin_attempt(shared,mac,aps[target].radio,t,handoff_cfg,s.return_once);
            if(gate){s.decision=gate;continue;}
            s.attempts=shared.handoff_attempts[lc(mac)+'|'+aps[target].radio].count;
            s.episode={started:t,source,target,source_radio:aps[source].radio,target_radio:aps[target].radio,
                scope:scope(source,target),operation:s.return_once?s.return_operation:null};
            delete s.return_once;delete s.response;
            // Measurements enrich the episode but never delay its first request.
            let modes=client['beacon-measurement-modes'] ?? [];
            if(index(modes,'ACTIVE')>=0||index(modes,'PASSIVE')>=0){
                try{call(source,'rrm_beacon_req',{addr:mac,mode:index(modes,'ACTIVE')>=0?1:0,op_class:op,channel:status.channel,duration:50,bssid:info.bssid,ssid:info.ssid,reporting_detail:0});}catch(err){}
            }
            if(client['bss-transition-management']){
                s.dialog=message.dialog_token;s.last_btm=t;
                fs.writefile(STATE,sprintf('%J\n',state));call(source,'bss_transition_request',message);
                options.history?.({event:'steering-request',operation:s.episode.operation,from:aps[source].radio,to:aps[target].radio,mode:'advisory',clients:1});
            }
            s.decision=client['bss-transition-management']?'gentle-request':'no-request-support';
        }
    }
    for(let mac,s in state.clients)if(!s.episode&&t-s.last_seen>300)delete state.clients[mac];
    state.updated_uptime=t;fs.writefile(STATE,sprintf('%J\n',state));
}

function followup(action){
    if(!cfg.enabled||action.radio!=cfg.preferred_radio)return;
    let t=now();
    for(let mac in keys(action.return_before ?? action.before ?? {})){
        let s=state.clients[mac] ?? {attempts:0};state.clients[mac]=s;
        s.return_once=true;s.return_since=t;s.return_operation=action.id;delete s.last_scan;
    }
}
function stop(){
    for(let mac,s in state.clients){let e=s.episode;if(e?.force_sent!=null){
        try{if(!call(e.source,'get_clients').clients?.[mac])call(e.source,'del_client',{addr:mac,reason:12,deauth:false,ban_time:0});}catch(err){}
    }delete s.episode;}
    fs.writefile(STATE,sprintf('%J\n',state));
}
function reserved(){
    let names=[];for(let s in values(state.clients))if(s.episode?.force_sent!=null)push(names,s.episode.source_radio,s.episode.target_radio);
    return uniq(names);
}
return {tick,check,followup,stop,reserved,config:cfg,state};
};
