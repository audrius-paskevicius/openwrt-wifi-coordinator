#!/usr/bin/ucode
import * as fs from 'fs';
import * as nl from 'nl80211';
import * as ubus from 'ubus';
import * as uci from 'uci';
import * as uloop from 'uloop';
import {create_job} from './planning-job.uc';
import {open_history} from './history.uc';
import {channel, group, same, same_block, overlap, permitted, delta_busy, dfs_ready, uses_dfs, traffic_sample,declared_bands,dfs_policy,placement_rejected} from './policy.uc';
import {survey_covers,move_method,configured_channels,configured_widths,frequency,switch_methods,setting_integer,hardware_widths,placements,live_width} from './policy.uc';
import {assess,choose,decide,spatial_streams} from './planner.uc';
import {open_memory} from './radar.uc';
import {create_survey} from './survey.uc';
import {create_executor} from './executor.uc';
import {reservations,action_valid,create_returns,refresh_learning,learn_disruption,learning_scope,movement_effect} from './controller.uc';
import {create_preference} from '../../radio-prefer/files/steering.uc';
import {begin_restart_check,check_restart,schedule_recovery} from './recovery.uc';

const N=nl.const, STATE='/tmp/channel-coordinator-state.json', LEASE='/tmp/channel-coordinator-lease.json', JOURNAL='/tmp/channel-coordinator-cac.json';
const CLIENT_AVOIDS='/tmp/wifi-coordinator-client-avoids.json';
let bus=ubus.connect(), cursor=uci.cursor();
if (!bus) die('ubus unavailable\n');
function call(obj,method,args) {
    let r=bus.call(obj,method,args ?? {}), e=bus.error();
    if(e) die(`${obj}.${method}: ${e}`);
    return r;
}
function request(cmd,flags,args) {
    let r=nl.request(cmd,flags,args ?? {}),e=nl.error();
    if(e) die(`nl80211: ${e}`);
    return r;
}
function now() { return int(split(fs.readfile('/proc/uptime'),' ')[0]); }
function precise() { return +split(fs.readfile('/proc/uptime'),' ')[0]; }
function config_fingerprint(name) {
    let c=uci.cursor();
    if(length(c.changes('wireless') ?? {}))die('Unapplied wireless edits exist; channel changes deferred');
    return sprintf('%J',[c.get('wireless',name,'channel'),c.get('wireless',name,'htmode'),c.get('wireless',name,'country')]);
}
function readjson(path,otherwise) { try { return json(fs.readfile(path) ?? 'null') ?? otherwise; } catch(e) { return otherwise; } }
function atomic(path,data) { if(!fs.writefile(path+'.new',sprintf('%J\n',data)) || !fs.rename(path+'.new',path)) die(`Cannot save ${path}`); }
function log(s) { printf('%s\n',s); fs.stdout.flush(); }
let raw=cursor.get_all('channel_coordinator','main') ?? {};
for(let key in ['enabled','separate_radios','allow_reconnect','persist','history_enabled','clear_history','clear_stop'])
    if(raw[key]!=null&&index(['0','1'],raw[key])<0)die('Invalid boolean setting '+key+'\n');
function number(k,d,lo,hi) { try{return setting_integer(raw[k] ?? d,lo,hi);}catch(e){die(`Invalid ${k}: ${e}\n`);} }
let board=trim(fs.readfile('/tmp/sysinfo/board_name') ?? '');
let wrt=index(['linksys,wrt3200acm','linksys,wrt32x'],board)>=0;
let cfg={enabled:raw.enabled=='1',mode:raw.mode ?? 'observe',interval:number('interval',60,30,86400),
    cooldown:number('min_dwell',180,30,86400),retry_delay:30,
    improvement:number('improvement',3,1,200),
    overlap_penalty:number('overlap_penalty',25,0,500),max_mbps:+(raw.max_mbps ?? '0.05'),
    separate:raw.separate_radios!='0',

    verify_unprobed:number('verify_unprobed',180,150,600),
    allow_reconnect:raw.allow_reconnect!='0',
    protected_clients:map(type(raw.protected_clients)=='array'?raw.protected_clients:split(raw.protected_clients ?? '',/\s+/),x=>lc(x)),
    scan_policy:raw.scan_policy ?? 'paced',scanner:raw.scanner ?? '',max_age:number('max_age',900,60,7200),
    scan_duty:number('scan_duty',10,1,30),radar_half_life:number('radar_half_life',3600,900,604800),
    scan_gap:number('scan_gap',3,1,30),scan_wait:60,
    persist:raw.persist!='0',csa_count:15,scan_batch:5,scan_type:raw.scan_type ?? 'passive',
    dfs_mode:raw.dfs_mode ?? 'off',dfs_helper:raw.dfs_helper ?? '',cac_timeout:720,
    quiet_seconds:number('quiet_seconds',60,10,600),handoff_wait:number('handoff_wait',90,60,300),
    escalation:raw.handoff_escalation ?? 'decisive',ban_seconds:20,
    target_min:number('handoff_target_min',-72,-90,-30),source_min:number('handoff_source_min',-65,-90,-30)};
if(index(['observe','automatic'],cfg.mode)<0||index(['idle','low_traffic','paced'],cfg.scan_policy)<0||index(['passive','active'],cfg.scan_type)<0) die('Invalid mode\n');
if(index(['off','available','prepare'],cfg.dfs_mode)<0)die('Invalid DFS mode\n');
if(index(['gentle','strong','decisive'],cfg.escalation)<0)die('Invalid handoff escalation\n');
if(!(cfg.max_mbps>=0.01&&cfg.max_mbps<=1000))die('Invalid traffic threshold\n');
for(let mac in cfg.protected_clients)if(length(mac)&&!match(mac,/^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/))die('Invalid protected client address\n');
let boot=trim(fs.readfile('/proc/sys/kernel/random/boot_id'));
// Accept legacy saved values; the recorder enforces the 120-hour maximum.
let history_store=open_history(boot,raw.history_enabled!='0',number('history_hours',24,1,200));
if(raw.clear_history=='1'&&!length(ARGV)){history_store.clear();cursor.set('channel_coordinator','main','clear_history','0');cursor.commit('channel_coordinator');}
function private_json(path,data) {
    let f=fs.open(path+'.new','w',0600); if(!f)die('Cannot save private runtime state');
    f.write(sprintf('%J',data));f.close();
    if(!fs.rename(path+'.new',path))die('Cannot commit private runtime state');
}
function empty_interface(ifname) {
    // config_set may otherwise optimize away a channel change against its
    // stale cache after CSA/DFS evacuation. Explicitly replace only this empty
    // PHY, using the same per-PHY removal API as netifd.
    let interfaces=request(N.NL80211_CMD_GET_INTERFACE,N.NLM_F_DUMP,{});
    if(length(filter(interfaces,x=>x.ifname==ifname))){
        let clients=bus.call('hostapd.'+ifname,'get_clients'),error=bus.error();
        if(error&&index(lc(error),'not found')<0)die('Cannot check selected radio clients: '+error);
        let stations=request(N.NL80211_CMD_GET_STATION,N.NLM_F_DUMP,{dev:ifname});
        if(length(clients?.clients ?? {})||length(stations ?? []))return false;
    }
    return true;
}
function apply_radio_config(phy,path,ifname,allow_occupied) {
    if(!allow_occupied&&!empty_interface(ifname))die('Selected radio acquired clients; restart deferred');
    call('hostapd','config_set',{phy,config:''});
    call('hostapd','config_set',{phy,config:path});
}
function apply_empty_config(phy,path,ifname) { apply_radio_config(phy,path,ifname,false); }
function restore_preparation() {
    let j=readjson(JOURNAL,null); if(!j)return false;
    if(j.boot!=boot){fs.unlink(JOURNAL);return false;}
    if(!match(j.path ?? '',/^\/var\/run\/hostapd-phy[0-9]+\.conf$/)||!match(j.phy ?? '',/^phy[0-9]+$/))die('Invalid CAC recovery journal');
    let live=filter(request(N.NL80211_CMD_GET_INTERFACE,N.NLM_F_DUMP,{}),x=>x.ifname==(j.ifname ?? j.phy+'-ap0'))[0];
    let width=live?live_width(live.channel_width):null;
    let on_source=j.source&&live&&same({freq:live.wiphy_freq,center:live.center_freq1 ?? live.wiphy_freq,width},j.source);
    let current=fs.readfile(j.path);
    if(current==j.temporary){
        if(!fs.writefile(j.path,j.original))die('Cannot restore spare radio configuration');
        if(!on_source)apply_radio_config(j.phy,j.path,j.ifname ?? j.phy+'-ap0',j.kind=='reconnect');
    }else if(current!=j.original){
        fs.unlink(JOURNAL);die('Radio configuration changed externally; preserved administrator changes');
    }else {
        // A crash after successful restoration must not restart joined clients.
        if(!on_source)
            apply_radio_config(j.phy,j.path,j.ifname ?? j.phy+'-ap0',j.kind=='reconnect');
    }
    fs.unlink(JOURNAL);return true;
}
if(ARGV[0]=='--recover'){
    let reconnect=readjson(JOURNAL,{})?.kind=='reconnect';
    let s=readjson(STATE,{});
    try{if(restore_preparation()){
        if(s.boot==boot){
            if(!reconnect)s.dfs={...s.dfs,phase:'recovered'};delete s.pending;
            s.status=reconnect?'Previous channel restored after interrupted reconnect operation':'Spare radio configuration restored after interruption';
            begin_restart_check(s,now());
            atomic(STATE,s);
        }
    }}catch(err){
        if(s.boot==boot){s.halted='Restart recovery needs attention: '+err;delete s.restart_check;atomic(STATE,s);}
        die('Restart recovery needs attention: '+err);
    }
    exit(0);
}
let method_identity=board+'|'+trim(fs.readfile('/etc/openwrt_release') ?? '')+'|'+trim(fs.readfile('/proc/version') ?? '');
let method_limits=readjson('/etc/wifi-coordinator/methods.json',{});
if(method_limits.identity!=method_identity)method_limits={identity:method_identity,radios:{}};
let state=readjson(STATE,{});
if(state.boot!=boot) state={boot,radios:{},history:[],last_move:0};
let client_avoids=readjson(CLIENT_AVOIDS,{});
if(client_avoids.boot!=boot||type(client_avoids.entries)!='array')client_avoids={boot,entries:[]};
client_avoids.entries=slice(client_avoids.entries,-256);
function prune_client_avoids(){
    let active=filter(client_avoids.entries,e=>e.until>now()&&e.until<=now()+21600);
    if(length(active)!=length(client_avoids.entries)){
        client_avoids.entries=active;private_json(CLIENT_AVOIDS,client_avoids);
    }
}
function client_avoided(radio,mac,g){
    return length(filter(client_avoids.entries,e=>e.until>now()&&e.radio==radio&&e.mac==lc(mac)&&
        e.freq==g.freq&&e.center==g.center&&e.width==g.width))>0;
}
function avoid_client(radio,mac,g,until){
    client_avoids.entries=filter(client_avoids.entries,e=>e.until>now()&&!(e.radio==radio&&e.mac==lc(mac)&&e.freq==g.freq&&e.center==g.center&&e.width==g.width));
    push(client_avoids.entries,{radio,mac:lc(mac),freq:g.freq,center:g.center,width:g.width,until});
    client_avoids.entries=sort(client_avoids.entries,(a,b)=>a.until-b.until);
    while(length(client_avoids.entries)>256)shift(client_avoids.entries);
    private_json(CLIENT_AVOIDS,client_avoids);
}
if(state.pending&&state.pending!='scan') begin_restart_check(state,now());
if(fs.stat(JOURNAL)&&ARGV[0]!='--inspect'){
    try{restore_preparation();begin_restart_check(state,now());}
    catch(err){state.halted='Restart recovery needs attention: '+err;delete state.restart_check;}
}
if(!state.pending&&index(['listening','restoring'],state.dfs?.phase)>=0)state.dfs.phase='inactive';
delete state.pending;
if(raw.clear_stop=='1'&&!length(ARGV)){
    delete state.halted;delete state.restart_check;for(let name,r in state.radios)delete r.failed;
    cursor.set('channel_coordinator','main','clear_stop','0');cursor.commit('channel_coordinator');
}
let steering,returns,steering_ready=false,steering_error=null,last_steering=0,urgent_eval=false;
let evidence={}, previous={}, traffic={}, rates={}, quiet_since={}, discovered=[], next_eval=now()+15,scanner,executor;
let scan_result=null, band_surveys={},one_shot=ARGV[0]=='--evaluate',estimate_cache={},admission=null,intent=null;
let persist_queue=state.persist_queue ?? {},next_persist=state.next_persist ?? now()+21600;
let radar=open_memory('/etc/wifi-coordinator/radar-memory.json',cfg.radar_half_life,time,now,state.radar?.events);
// ucode resolves function references at declaration time, unlike JavaScript.
let evaluate,timer;
if(one_shot){cfg.mode='observe';next_eval=now()+1;}
let manual_switch=ARGV[0]=='--test-switch',manual_done=false;
if(manual_switch||ARGV[0]=='--test-prepare')cfg.mode='observe';
function save() { state.updated=now(); state.mode=cfg.mode; state.next_evaluation=next_eval;state.persist_queue=persist_queue;state.next_persist=next_persist;state.radar={half_life:cfg.radar_half_life,events:radar.records()};atomic(STATE,state); }
// Reservations are owned in memory by this process; no cross-daemon lease.
function lease(seconds,reason,reserved) {}
function release() {}
function survey_action(action) {
    try { action(); }
    catch(err) { scanner.cancel('Survey deferred: '+err);next_eval=now()+cfg.retry_delay; }
}
function execution_action(action) {
    try { action(); }
    catch(err) { executor.abort(err); }
}
function history(event) { let e={time:time(),...event};push(state.history,e);history_store.event(e);while(length(state.history)>30)shift(state.history); }
function coordination_ready() {
    let services=call('service','list');
    function running(name) { for(let k,v in services[name]?.instances ?? {}) if(v.running)return true;return false; }
    for(let name in ['wifi-auto-channel','dawn','linksys-steering'])
        if(running(name))die(`Stop competing service ${name} before channel coordination`);
    if(running('radio-prefer'))die('Legacy Radio Preference process still running; stop it before starting the shared controller');
    if(running('usteer')){
        let c=call('usteer','get_config');
        for(let k in ['assoc_steering','probe_steering','min_connect_snr','min_snr','roam_scan_snr','roam_trigger_snr','load_kick_enabled','band_steering_interval'])
            if(c[k])die(`usteer ${k} is active; use passive usteer with Radio Preference or disable that policy first`);
    }
}
function rcfg(name,band,caps,csa,band_caps) {
    let r=cursor.get_all('channel_coordinator',name) ?? {};
    if(r.managed!=null&&index(['0','1'],r.managed)<0)die('Invalid managed setting for '+name);
    let ch=configured_channels(r.channels,band,caps);
    let hardware=hardware_widths(band,band_caps),requested=configured_widths(r.widths,band,hardware);
    let widths=filter(requested,w=>index(hardware,w)>=0);
    let methods=switch_methods(r.method,r.width_method,wrt,name,band,csa,state.radios[name]?.csa_failed_until,now());
    if(method_limits.radios?.[name]?.csa && (r.method ?? 'auto')=='auto'){
        methods.method='idle_reconfigure';methods.method_reason='CSA unsupported by this hardware/software; retained until it changes';
        methods.csa_unsupported=true;
        if((r.width_method ?? 'auto')=='inherit')methods.width_method=methods.method;
    }
    let occupied=r.occupied_policy ?? 'handoff';
    if(index(['empty','quiet','handoff'],occupied)<0)die('Invalid occupied-radio policy');
    return {managed:r.managed!='0',occupied,...methods,channels:ch,widths,hardware_widths:hardware,
        unavailable_widths:filter(requested,w=>index(hardware,w)<0)};
}
let unavailable_rows=[],regulatory=null;
function measured(stage,fn){
    let start=precise(),result,error;
    try{result=fn();}catch(e){error=e;}
    let elapsed=precise()-start;
    if(elapsed>=1)history({event:'slow-stage',kind:stage,elapsed});
    if(error)die(error);
    return result;
}
function inventory() {
    unavailable_rows=[];
    regulatory=request(N.NL80211_CMD_GET_REG,0,{});
    let ws=call('network.wireless','status'), interfaces=request(N.NL80211_CMD_GET_INTERFACE,N.NLM_F_DUMP,{});
    let phys=request(N.NL80211_CMD_GET_WIPHY,N.NLM_F_DUMP,{split_wiphy_dump:true});
    state.declared_bands=declared_bands(phys);
    let phyinfo={};
    for(let p in phys ?? []) {
        let info=phyinfo[p.wiphy] ?? {caps:{},csa:false,bands:{}}; phyinfo[p.wiphy]=info;
        if(index(p.supported_commands ?? [],N.NL80211_CMD_CHANNEL_SWITCH)>=0) info.csa=true;
        for(let c in p.interface_combinations ?? [])info.radar_widths=(info.radar_widths ?? 0)|(c.radar_detect_widths ?? 0);
        for(let index,band in p.wiphy_bands ?? []) if(band){
            let first=band.freqs?.[0]?.freq,key=first?(first<3000?'2g':'5g'):(index==0?'2g':'5g');
            let old=info.bands[key] ?? {};
            info.bands[key]={ht_capa:band.ht_capa ?? old.ht_capa,vht_capa:band.vht_capa ?? old.vht_capa,
                ht_mcs_set:band.ht_mcs_set ?? old.ht_mcs_set,vht_mcs_set:band.vht_mcs_set ?? old.vht_mcs_set};
            for(let f in band.freqs ?? [])if(f)info.caps[f.freq]=f;
        }
    }
    let out=[];
    for(let name,data in ws) {
        if(!match(name,/^[A-Za-z0-9_-]+$/)||!data.up||data.disabled) continue;
        let observed=0,unknown=false,aps=[],unsafe=!match(data.config.htmode ?? '',/^(HT(20|40[+-]?)|VHT(20|40|80|160))$/);
        for(let i in data.interfaces ?? []) {
            if(i.config?.mode!='ap') { unsafe=true; continue; }
            if(!match(i.ifname ?? '',/^[A-Za-z0-9_.-]+$/)) continue;
            let status; try { status=call('hostapd.'+i.ifname,'get_status'); } catch(e) { unsafe=true;unknown=true; continue; }
            if(status.status)observed++;else unknown=true;
            if(status.status!='ENABLED'||status.dfs?.cac_active) {unsafe=true;continue;}
            push(aps,{ifname:i.ifname,status,config:i.config});
        }
        if(!length(aps)){
            if(observed&&!unknown)push(unavailable_rows,{radio:name,availability:'unavailable'});
            continue;
        }
        let live=null;
        for(let i in interfaces ?? []) if(i.ifname==aps[0].ifname) live=i;
        if(!live) continue;
        let width=live_width(live.channel_width);
        if(!width||live.wiphy_freq>=5925) {unsafe=true;width=width ?? 160;}
        let clients={},authorized={},signals={},client_data={},bytes=0,client_capacity=0;
        for(let ap in aps) {
            let c=call('hostapd.'+ap.ifname,'get_clients');
            for(let mac,v in c.clients ?? {}) if(v.assoc||v.authorized||v.auth) clients[mac]=true;
            for(let mac,v in c.clients ?? {}) if(v.authorized) authorized[mac]=true;
            let stations=request(N.NL80211_CMD_GET_STATION,N.NLM_F_DUMP,{dev:ap.ifname});
            for(let st in stations ?? []) {
                if(clients[st.mac])client_capacity+=max(st.sta_info?.tx_bitrate?.bitrate32 ?? st.sta_info?.tx_bitrate?.bitrate ?? 0,
                    st.sta_info?.rx_bitrate?.bitrate32 ?? st.sta_info?.rx_bitrate?.bitrate ?? 0)/10.0;
                bytes+=(st.sta_info?.rx_bytes64 ?? st.sta_info?.rx_bytes ?? 0)+(st.sta_info?.tx_bytes64 ?? st.sta_info?.tx_bytes ?? 0);
                client_data[st.mac]={rx:st.sta_info?.rx_bytes64 ?? st.sta_info?.rx_bytes ?? 0,tx:st.sta_info?.tx_bytes64 ?? st.sta_info?.tx_bytes ?? 0};
                let signal=st.sta_info?.signal;if(signal>2147483647)signal-=4294967296;
                if(signal!=null&&signal<0)signals[st.mac]=signal;
            }
        }
        let t=now(),prev=traffic[name];
        let identities=join(' ',sort(keys(clients)));
        let reading=traffic_sample(prev,rates[name],quiet_since[name],t,bytes,identities,cfg.max_mbps);
        rates[name]=reading.rate;quiet_since[name]=reading.quiet;traffic[name]=reading.sample;
        let band=live.wiphy_freq<3000?'2g':'5g', g=group(live.wiphy_freq,width,live.center_freq1) ?? {freq:live.wiphy_freq,center:live.center_freq1,width,members:[live.wiphy_freq],sec:0};
        g.center=live.center_freq1 ?? g.center;
        let p=phyinfo[live.wiphy] ?? {caps:{},csa:false},config=rcfg(name,band,p.caps,p.csa,p.bands?.[band]);
        let reg=request(N.NL80211_CMD_GET_REG,0,{wiphy:live.wiphy});
        if(length(filter(interfaces,i=>i.wiphy==live.wiphy))!=length(aps))unsafe=true;
        push(out,{name,band,aps,ifname:aps[0].ifname,phy:live.wiphy,caps:p.caps,csa:p.csa,
            band_caps:p.bands?.[band],
            radar_widths:p.radar_widths ?? 0,dfs_region:reg?.dfs_region,
            current:g,clients,authorized,signals,client_data,client_capacity,mbps:rates[name] ?? 0,config,unsafe,
            fingerprint:config_fingerprint(name),
            own_bssids:map(aps,a=>lc(a.status.bssid))});
    }
    if(length(out)>4) die('At most four radios are supported by this experimental planner');
    return sort(out,(a,b)=>a.name<b.name?-1:1);
}
function allclients(radios) { let c={}; for(let r in radios) for(let m in keys(r.authorized)) c[m]=true; return c; }
function phy_caps(phy) {
    let caps={};
    for(let p in request(N.NL80211_CMD_GET_WIPHY,N.NLM_F_DUMP,{split_wiphy_dump:true}))
        if(p.wiphy==phy)for(let b in p.wiphy_bands ?? [])if(b)for(let f in b.freqs ?? [])if(f)caps[f.freq]=f;
    return caps;
}
function dfs_mode(r) {
    if(r.band!='5g'){if(state.radios[r.name])state.radios[r.name].dfs_constraint=null;return 'off';}
    let reg=request(N.NL80211_CMD_GET_REG,0,{});
    let result=dfs_policy(cfg.dfs_mode,reg.dfs_region,r.dfs_region);
    if(state.radios[r.name])state.radios[r.name].dfs_constraint=result.reason;
    return result.mode;
}
function sample(radios) {
    prune_client_avoids();
    let t=now(),pending=executor?.pending();
    // Keep the last completed comparison as an explanatory snapshot. Execution
    // uses its own target and rechecks eligibility; this is never a work queue.
    if(state.proposal?.alternatives){
        let old=state.proposal.alternatives;
        state.proposal.placements_changed=length(old)!=length(radios)||!!length(filter(radios,r=>{
            let previous=filter(old,x=>x.radio==r.name)[0];
            return !previous||!same(previous.current,r.current);
        }));
    }
    for(let mac,at in state.forced ?? {})if(t-at>max(cfg.cooldown,300))delete state.forced[mac];
    for(let r in radios) {
        let rows=request(N.NL80211_CMD_GET_SURVEY,N.NLM_F_DUMP,{dev:r.ifname});
        for(let x in rows ?? []) {
            let v=x.survey_info; if(!v?.frequency) continue;
            let key=r.name+':'+v.frequency,b=delta_busy(previous[key],v);
            previous[key]=v;
            if(b!=null) evidence[key]={busy:b,at:t};
        }
        let s=state.radios[r.name] ?? {}; state.radios[r.name]=s;
        if(s.channel!=null&&(s.channel!=channel(r.current.freq)||s.width!=r.current.width||s.center!=r.current.center))
            history({event:'placement-observed',radio:r.name,from:s.channel,to:channel(r.current.freq),width:r.current.width});
        s.channel=channel(r.current.freq); s.width=r.current.width;s.center=r.current.center;
        s.clients=length(r.clients);s.mbps=r.mbps;s.csa=r.csa;s.managed=r.config.managed;s.method=r.config.method;
        s.width_method=r.config.width_method;s.requested_method=r.config.requested_method;s.requested_width_method=r.config.requested_width_method;
        s.method_reason=r.config.method_reason;s.width_reason=r.config.width_reason;s.csa_recovery_left=r.config.csa_recovery_left;
        delete s.method_note;
        s.dfs_region=r.dfs_region;s.dfs=uses_dfs(r.current,r.caps);s.dfs_ready=dfs_ready(r.current,r.caps);
        s.quiet_seconds=quiet_since[r.name]==null?0:t-quiet_since[r.name];s.occupied_policy=r.config.occupied;
        s.cooldown_left=max(0,cfg.cooldown-(t-(s.last_move ?? -100000)));
        s.candidate_channels=r.config.channels;
        s.candidate_widths=r.config.widths;
        s.hardware_widths=r.config.hardware_widths;s.unavailable_widths=r.config.unavailable_widths;
        refresh_learning(s,r,t);
        s.client_avoid_count=length(filter(client_avoids.entries,e=>e.radio==r.name&&e.until>t));
        s.ht40_constraint=r.band=='2g'&&r.config.width_method=='csa'?'HT40 requires restart for coexistence checks; explicit CSA cannot apply it':null;
    }
    let history_rows=map(radios,r=>{
        let b=evidence[r.name+':'+r.current.freq],signals=values(r.signals);
        return {radio:r.name,channel:channel(r.current.freq),center:r.current.center,width:r.current.width,clients:length(r.clients),traffic:r.mbps,
            busy:b&&t-b.at<=15?b.busy:null,signal:length(signals)?min(...signals):null,
            role:pending?.kind=='cac'&&pending.helper.name==r.name?'radar preparation':'serving'};
    });
    if(pending?.kind=='cac'&&!length(filter(history_rows,r=>r.radio==pending.helper.name)))
        push(history_rows,{radio:pending.helper.name,channel:channel((pending.cac_target ?? pending.target).freq),center:(pending.cac_target ?? pending.target).center,width:(pending.cac_target ?? pending.target).width,
            clients:0,traffic:0,busy:null,signal:null,role:'radar preparation'});
    history_store.record([...history_rows,...unavailable_rows]);
}
function candidates(r,radios,rules,revalidate,context) {
    let s=state.radios[r.name],t=context?.now ?? now(),dm=context?.modes[r.name] ?? dfs_mode(r),list=[],busy={},maxw=max(r.current.width,...r.config.widths);
    for(let f in scan_result.frequencies){
        let e=evidence[r.name+':'+f] ?? evidence[scan_result.scanners[f]+':'+f];
        let own=length(filter(radios,x=>length(x.clients)&&overlap(group(int(f),20),x.current)>0));
        if(e&&t-e.at<=cfg.max_age&&!own)busy[f]=e.busy;
    }
    let snapshot={...scan_result,busy},preparation_cache=context?.preparation ?? {};
    function rated(g){
        let key=r.name+':'+g.freq+':'+g.center+':'+g.width;
        let caps=r.band=='2g'?{ht_mcs_set:r.band_caps?.ht_mcs_set}:r.band_caps;
        let cached=estimate_cache[key],stamp=scan_result.stamps?.[r.band] ?? scan_result.at;
        let previous=cached&&cached.stamp==stamp?cached.previous:cached?.current;
        let q=assess(g,snapshot,maxw,context?.radar ?? radar.records(),context?.wall ?? time(),cfg.radar_half_life,r.dfs_region,previous,spatial_streams(caps));
        estimate_cache[key]={stamp,previous,current:q};
        let powers=map(g.members,f=>r.caps[f]?.max_tx_power ?? 0);
        return {...q,max_width:maxw,power:min(...powers)};
    }
    let current=rated(r.current);
    s.rejected=filter(s.rejected ?? [],x=>x.until>t);
    s.planning_hold=!r.config.managed?'Excluded from planning':r.unsafe?'Unsupported or inactive configuration':s.failed||s.unavailable?(s.recovery_status ?? 'Automatic recovery check pending'):
        index(steering?.reserved() ?? [],r.name)>=0?'Client reconnection observation':
        index(returns?.radios() ?? [],r.name)>=0?'Bounded preferred-radio return observation':
        s.recheck_until>t?'Previous service restored; waiting for fresh client evidence':
        !survey_covers(rules,r,scan_result.frequencies,dm)?'Incomplete fresh survey':
        !revalidate&&t-(s.last_move ?? -100000)<cfg.cooldown?'Minimum residence after verified move':
        !revalidate&&t-(s.last_attempt ?? -100000)<cfg.retry_delay?'Short retry delay':null;
    if(s.planning_hold&&index(['Minimum residence after verified move','Short retry delay','Bounded preferred-radio return observation','Previous service restored; waiting for fresh client evidence'],s.planning_hold)<0)return [current];
    for(let w in r.config.widths)for(let ch in r.config.channels)for(let g in placements(frequency(ch,r.band),w)){
        if(s.width_limit?.until>t&&w>s.width_limit.actual)continue;
        if(!permitted(g,r.caps,rules,r.config.channels,dm))continue;
        let method=move_method(r.config,r.current,g);
        if(!same(g,current)&&method=='csa'&&!r.csa)continue;
        if(!same(g,current)&&r.band=='2g'&&g.width==40&&method=='csa')continue;
        if(!same(g,current)&&method=='idle_reconfigure'&&length(filter(keys(r.clients),m=>index(cfg.protected_clients,lc(m))>=0)))continue;
        if(placement_rejected(g,s.rejected,r.band,t))continue;
        if(length(filter(g.members,f=>index(scan_result.frequencies,f)<0)))continue;
        if(length(filter(list,x=>same(x,g))))continue;
        let candidate=same(g,current)?current:rated(g);
        if(!same(g,current)){
            candidate.preparation=executor?.preparation(r,g,radios,rules,preparation_cache);
            let active=executor?.pending();
            if(revalidate&&active&&same(g,active.target)&&(active.spare_attempted||active.helper))
                candidate.preparation=active.target.preparation ?? candidate.preparation;
        }
        push(list,candidate);
    }
    if(!length(filter(list,g=>same(g,current))))push(list,current);
    return sort(list,(a,b)=>a.cost-b.cost);
}
function sum_overlap(g,models,name){let n=0;for(let m in models)if(m.name!=name)n+=overlap(g,m.current);return n;}
// Only stable eligibility inputs invalidate a calculation. Traffic and airtime
// remain timestamped observations; client identities and DFS permission do not.
function planning_key(radios,p) {
    return sprintf('%J',[map(radios,r=>({name:r.name,current:r.current,
        config:map(['managed','occupied','method','width_method','channels','widths','hardware_widths'],k=>r.config[k]),
        fingerprint:r.fingerprint,unsafe:r.unsafe,csa:r.csa,
        clients:sort(keys(r.clients)),authorized:sort(keys(r.authorized)),
        caps:map(sort(keys(r.caps)),f=>{let c=r.caps[f];return [f,c.disabled,c.no_ir,c.radar,c.dfs_state,c.max_tx_power,c.no_80mhz,c.no_160mhz,c.no_20mhz,c.no_ht40_plus,c.no_ht40_minus];}),
        band_caps:r.band_caps,radar_widths:r.radar_widths,dfs_region:r.dfs_region,
        state:map(['last_move','last_attempt','rejected','width_limit','failed','unavailable','recheck_until','disruption'],k=>state.radios[r.name]?.[k])})),
        scan_result?.stamps,steering?.reserved(),returns?.radios(),state.halted,state.restart_check,
        radar.records(),regulatory,p?[p.id,p.kind,p.target,p.spare_attempted,p.helper]:null,
        fs.readfile('/etc/config/channel_coordinator'),fs.readfile('/etc/config/radio_prefer'),fs.readfile('/etc/config/wireless')]);
}
function planning_report(event,kind,elapsed,reason,timings) {
    history({event,kind,elapsed,reason,...(timings ?? {})});
    state.planning={event,kind,elapsed,...(timings ?? {})};
}
let planning=create_job({now:precise,report:planning_report}),validation=null;
function calculation(radios,p) {
    let reg=request(N.NL80211_CMD_GET_REG,0,{}),context={now:now(),wall:time(),radar:radar.records(),modes:{},preparation:{}};
    for(let r in radios){
        let mode=r.band=='5g'?dfs_policy(cfg.dfs_mode,reg.dfs_region,r.dfs_region).mode:'off';
        context.modes[r.name]=mode;
        context.preparation[r.name]={mode,text:fs.readfile('/var/run/hostapd-phy'+r.phy+'.conf'),valid:{}};
    }
    // fork() captures this context and the evidence/state together. No ubus,
    // netlink, UCI mutation, radio command or shared socket is used in the child.
    return ()=>{
        let start=precise(),models=[];
        for(let r in radios){
            let choices=candidates(r,radios,reg.reg_rules ?? [],p&&r.name==p.radio,context),s=state.radios[r.name];
            push(models,{name:r.name,current:filter(choices,g=>same(g,r.current))[0],candidates:choices,
                hold:s.planning_hold,disruption:s.disruption,config:r.config,
                clients:max(length(r.clients),p&&r.name==p.radio?length(p.return_before ?? p.before):0),
                last_action:p&&r.name==p.radio?(p.previous_action ?? 0):max(s.last_attempt ?? 0,s.last_move ?? 0)});
        }
        let scored=precise(),result=choose(models,cfg),decision=decide(result,models,p?null:admission,scan_result.at,cfg,p?null:intent?.until>context.now?intent.signature:null);
        return {models,result,decision,cache:estimate_cache,
            timings:{candidates_seconds:scored-start,search_seconds:precise()-scored},
            radio_state:map(radios,r=>({name:r.name,hold:state.radios[r.name].planning_hold,rejected:state.radios[r.name].rejected}))};
    };
}
function planning_result(kind,radios,p) {
    let key=planning_key(radios,p),answer=planning.take(kind,key);
    if(answer?.error)die(answer.error);
    if(answer){
        if(!scan_result||now()-scan_result.at>cfg.max_age)return null;
        estimate_cache=answer.value.cache;
        for(let s in answer.value.radio_state){state.radios[s.name].planning_hold=s.hold;state.radios[s.name].rejected=s.rejected;}
        return {key,value:answer.value};
    }
    if(!planning.busy())planning.start(kind,key,measured('planning-snapshot',()=>calculation(radios,p)));
    return null;
}
function accept_comparison(radios,answer){
    let models=answer.models,result=answer.result,decision=answer.decision;
    admission=decision.signature?decision:null;
    let changes=[];for(let i,r in radios)if(!same(r.current,result.choices[i]))push(changes,{radio:r.name,from:channel(r.current.freq),to:channel(result.choices[i].freq),width:result.choices[i].width});
    state.proposal={evaluated_at:time(),evaluated_uptime:now(),placements_changed:false,
        current_cost:result.base.cost,best_cost:result.cost,improvement:result.gain,movement_cost:result.movement_cost ?? 0,affected_clients:result.affected_clients ?? 0,client_moves:result.client_moves ?? 0,changes,
        current_overlap:result.base.overlap,target_overlap:result.overlap,separate:cfg.separate,
        decision:{action:decision.action,reason:decision.reason,margin:decision.required,observations:decision.count,comparisons:decision.comparisons},
        steps:map(result.path,s=>({radio:models[s.index].name,to:channel(s.target.freq),width:s.target.width,staging:s.staging})),
        alternatives:map(models,m=>({radio:m.name,current:m.current,hold:state.radios[m.name].planning_hold,rejected:json(sprintf('%J',state.radios[m.name].rejected ?? [])),
            channels:state.radios[m.name].candidate_channels,widths:state.radios[m.name].candidate_widths,
            width_limit:state.radios[m.name].width_limit?.until>now()?state.radios[m.name].width_limit:null,
            candidates:map(m.candidates,g=>({...g,movement:movement_effect(m,g,cfg),channel:channel(g.freq),shared:sum_overlap(g,models,m.name),current:same(g,m.current)}))})),
        scan_age:now()-scan_result.at,neighbors:length(scan_result.observations)};
    state.status=decision.reason;
    if(decision.action=='hold')intent=null;
    // A close comparison collects evidence on the configured schedule, never earlier.
    if(cfg.enabled&&!state.halted&&!executor.busy()&&cfg.mode=='automatic'&&decision.action=='move'){
        intent={signature:decision.signature,until:now()+cfg.max_age};
        executor.start(radios[decision.next.index],decision.next.target,radios);
        history({event:'plan-start',operation:executor.pending().id,radio:models[decision.next.index].name,to:channel(decision.next.target.freq),width:decision.next.target.width,reason:decision.reason,estimated_gain:result.gain,movement_cost:result.movement_cost,required_gain:decision.required,affected_clients:result.affected_clients,client_moves:result.client_moves,scan_age:now()-scan_result.at});
    }
    save();
    if(one_shot)uloop.end();
}
evaluate=function(radios){
    next_eval=now()+cfg.interval;
    if(!scan_result||now()-scan_result.at>cfg.max_age){state.status='Waiting for a fresh survey';save();return;}
    if(planning.busy())return;
    planning_result('comparison',radios,null);
};
function poll_planning(radios){
    if(planning.kind()!='comparison')return;
    if(executor.busy()||state.halted||state.restart_check){planning.cancel('Controller is recovering or executing');return;}
    if(!scan_result||now()-scan_result.at>cfg.max_age){planning.cancel('Survey evidence expired');return;}
    let answer=planning_result('comparison',radios,null);
    if(answer)measured('planning-accept',()=>accept_comparison(radios,answer.value));
}

function remember_channel(r,p){persist_queue[r.name]={channel:channel(r.current.freq),width:r.current.width,sec:r.current.sec,fingerprint:p.fingerprint,band:r.band};}
function persist_channels(){
    radar.flush();
    if(!cfg.persist||now()<next_persist||!length(persist_queue)||executor.busy()||scanner.busy())return;
    next_persist=now()+21600;let c=uci.cursor(),changed=false;
    for(let name,p in persist_queue){
        if(config_fingerprint(name)!=p.fingerprint){delete persist_queue[name];continue;}
        c.set('wireless',name,'channel',''+p.channel);c.set('wireless',name,'htmode',(p.band=='2g'?'HT':'VHT')+p.width+(p.band=='2g'&&p.width==40?(p.sec<0?'-':'+'):''));changed=true;
    }
    if(changed&&!c.commit('wireless')){state.persistence_error='Cannot checkpoint verified channels';return;}
    persist_queue={};state.persistence_error=null;
}
function completed(){
    next_eval=now()+(urgent_eval?1:cfg.interval);
    if(manual_switch)manual_done=true;
    else if(one_shot||ARGV[0]=='--test-prepare')uloop.end();
}
function record_radar(e){
    let msg=e.msg ?? {},live=filter(discovered,r=>r.phy==msg.wiphy)[0],p=executor?.pending();
    let width=[20,20,40,80,80,160][msg.channel_width] ?? (p?.helper?.phy==msg.wiphy?(p.cac_target ?? p.target).width:live?.current.width) ?? 20;
    let freq=msg.wiphy_freq,center=msg.center_freq1 ?? group(freq,width)?.center ?? freq;
    let event={event:'radar-state',time:time(),phy:msg.wiphy,radar_event:msg.radar_event,freq,center,width,region:live?.dfs_region ?? null};
    history(event);radar.add(event);state.radar={half_life:cfg.radar_half_life,events:radar.records()};
    if(msg.radar_event==0){planning.cancel('Radar invalidated calculation');validation=null;urgent_eval=true;intent=null;admission=null;if(scanner?.busy())scanner.cancel('Radar event invalidated survey');}
    executor.event(e,discovered);
}
let io={cfg,state,boot,now,precise,save,lease,release,history,history_store,call,request,inventory,
    client_avoided,avoid_client,
    evidence_at:()=>scan_result?.at,
    reserved:()=>uniq([...reservations(executor?.pending()),...(returns?.radios() ?? []),...(steering?.reserved() ?? [])]),
    returning:name=>index(returns?.radios() ?? [],name)>=0,
    priority_bands:()=>{
        let preferred=filter(discovered,r=>r.name==steering?.config.preferred_radio)[0];
        return preferred?.band=='5g'?['5g','2g']:['2g','5g'];
    },
    preferred:()=>steering?.config?.preferred_radio,
    method_unsupported:r=>{
        method_limits.radios[r.name]={csa:true};
        fs.mkdir('/etc/wifi-coordinator',0700);
        private_json('/etc/wifi-coordinator/methods.json',method_limits);
        history({event:'method-unavailable',radio:r.name,reason:'CSA command unsupported; learned hardware/software limitation'});
    },
    valid_action:(p,radios)=>{
        if(ARGV[0]=='--test-switch'||ARGV[0]=='--test-prepare')return true;
        let r=filter(radios,r=>r.name==p.radio)[0];
        if(!action_valid(p,r,now(),cfg.max_age))return false;
        if(!scan_result||now()-scan_result.at>cfg.max_age)return false;
        let key=planning_key(radios,p);
        if(validation?.key!=key||now()-validation.at>5){
            validation=null;
            if(planning.kind()=='comparison')planning.cancel('Final action check takes priority');
            let answer=planning_result('validation',radios,p);
            if(!answer)return null; // Deferred, not a failed safety check.
            validation={...answer,at:now()};
        }
        let models=validation.value.models,plan=validation.value.result,decision=validation.value.decision;
        // Re-evaluate the complete layout: a neutral staging move can still be
        // useful, but neither a stale plan nor its own retry gate may decide it.
        let valid=decision.action=='move'&&models[decision.next.index].name==p.radio&&same(decision.next.target,p.target);
        if(valid)p.admission={estimated_gain:plan.gain,movement_cost:plan.movement_cost,required_gain:decision.required,affected_clients:plan.affected_clients,client_moves:plan.client_moves,scan_age:now()-scan_result.at};
        if(!valid)p.validation_reason='Prepared action reconsidered: '+decision.reason+
            (decision.next?'; current choice '+models[decision.next.index].name+' channel '+channel(decision.next.target.freq):'')+
            '; net benefit '+sprintf('%.1f',plan.gain)+', required '+sprintf('%.1f',decision.required ?? cfg.improvement);
        return valid;
    },
    finished:p=>{
        planning.cancel('Radio operation completed');validation=null;
        let outcome=p.last_event ?? 'cancelled',r=filter(discovered,r=>r.name==p.radio)[0];
        let departed=length(p.departed ?? {}),source_clients=length(p.return_before ?? {});
        if(r&&!p.external&&!p.repair_attempted&&!p.reconnect&&p.command_started&&p.method=='csa'&&source_clients&&index(['switch-verified','switch-unconfirmed','switch-recovery'],outcome)>=0){
            let n=length(filter(keys(p.departed ?? {}),mac=>p.return_before?.[mac]));
            state.radios[p.radio].disruption=learn_disruption(state.radios[p.radio].disruption,source_clients,n,now(),learning_scope(r));
        }
        if(r&&state.radios[p.radio].width_limit&&r.current.width>=state.radios[p.radio].width_limit.requested&&outcome=='switch-verified')delete state.radios[p.radio].width_limit;
        history({event:'operation-complete',operation:p.id,radio:p.radio,reason:outcome,
            disconnect_events:p.disconnects ?? 0,forced_disconnects:p.forced_disconnects ?? 0,observed_clients:length(p.before ?? {}),departed_clients:departed,operation_seconds:now()-(p.started_at ?? p.started),...(p.admission ?? {})});
        state.last_operation={id:p.id,radio:p.radio,outcome,disconnects:p.disconnects ?? 0};
        if(index(['switch-verified','switch-ignored','switch-unconfirmed','external-recovery-verified'],outcome)>=0){
            returns?.add(p,steering?.config.enabled?steering.config.preferred_radio:null);
            steering?.followup(p);
        }
        if(p.external||index(['switch-recovery','error','rollback-failed'],outcome)>=0)urgent_eval=true;
    },
    config_fingerprint,phy_caps,allclients,empty_interface,apply_empty_config,apply_radio_config,restore_preparation,private_json,
    coordination_ready,dfs_mode,log,rates,quiet_since,remember:remember_channel,completed};
let scan_state={radios:state.radios};
function accept_survey(result){
    for(let band in result.band?[result.band]:['2g','5g']){
        band_surveys[band]={at:result.at,frequencies:filter(result.frequencies,f=>(f<3000?'2g':'5g')==band),
            observations:filter(result.observations,o=>(o.freq<3000?'2g':'5g')==band),scanners:result.scanners};
    }
    let fresh=filter(values(band_surveys),s=>now()-s.at<=cfg.max_age);
    scan_result={at:now(),frequencies:[],observations:[],scanners:{},stamps:{}};
    for(let band in keys(band_surveys))scan_result.stamps[band]=band_surveys[band].at;
    for(let s in fresh){
        scan_result.at=min(scan_result.at,s.at);
        push(scan_result.frequencies,...s.frequencies);push(scan_result.observations,...s.observations);
        for(let f in s.frequencies)scan_result.scanners[f]=s.scanners[f];
    }
}
scanner=create_survey({...io,state:scan_state,progress:result=>{
    // Use completed, fresh portions without waiting behind another band. The
    // same per-radio coverage rule still forbids treating missing bins as clear.
    accept_survey(result);
    if(now()>=next_eval)urgent_eval=true;
},save:()=>{
    for(let k in ['scan_coverage','scan_deferred','scan_omitted'])if(scan_state[k]!=null)state[k]=scan_state[k];
    state.survey_status=scan_state.status;
    if(!executor?.busy()){state.status=scan_state.status;state.pending=scan_state.pending;}
    save();
},complete:(result,radios)=>{accept_survey(result);if(!executor.busy())evaluate(radios);}});
steering=create_preference({bus,history,shared:state,handoff_cfg:cfg,radios:()=>discovered,save});
returns=create_returns({now,history});
executor=create_executor(io);
// Import existing raw detections without inventing geometry from CAC completion.
let old_history=readjson('/tmp/wifi-coordinator-history.json',{});
for(let e in old_history.events ?? state.history ?? [])if(e.event=='radar-state'&&e.radar_event==0){
    let g=e.center?{center:e.center,width:e.width}:null;
    if(!g){
        let matches=filter(old_history.periods ?? [],p=>p.start<=e.time&&p.end+5>=e.time&&p.center&&e.freq>=p.center-p.width/2&&e.freq<p.center+p.width/2);
        g=length(matches)?{center:matches[0].center,width:matches[0].width}:group(e.freq,20);
    }
    if(g)radar.add({...e,...g,region:e.region ?? null});
}
old_history=null;
state.radar={half_life:cfg.radar_half_life,events:radar.records()};
if(ARGV[0]=='--inspect'){print(sprintf('%J\n',map(inventory(),r=>({radio:r.name,current:r.current,clients:length(r.clients)}))));exit(0);}
if(one_shot||ARGV[0]=='--test-switch'||ARGV[0]=='--test-prepare'){
    let services=call('service','list',{name:'channel-coordinator'});
    for(let k,v in services['channel-coordinator']?.instances ?? {})if(v.running)die('Stop coordinator before a manual test');
}
if(ARGV[0]=='--clear-stop'){delete state.halted;delete state.restart_check;for(let n,r in state.radios)delete r.failed;save();exit(0);}
if(!cfg.enabled&&!steering.config.enabled&&!one_shot)exit(0);
uloop.init();
let stopping=false;
let termination=uloop.signal('SIGTERM',()=>{
    stopping=true;
    planning.cancel('Service stopping');
    try{steering.stop();}catch(e){log('Stopping preference: '+e);}
    try{if(scanner.busy())scanner.cancel('Survey stopped for service shutdown');}catch(e){log('Stopping survey: '+e);}
    uloop.end();
});
if(!termination)die('Cannot install graceful shutdown handler');
let listener=nl.listener(e=>{try{
    if(stopping)return;
    if(e.cmd==N.NL80211_CMD_RADAR_DETECT)record_radar(e);
    else if(e.cmd==N.NL80211_CMD_NEW_SCAN_RESULTS||e.cmd==N.NL80211_CMD_SCAN_ABORTED)survey_action(()=>measured('survey-event',()=>scanner.event(e)));
    else {
        if(e.cmd==N.NL80211_CMD_DEL_STATION){
            let r=filter(discovered,r=>r.phy==e.msg?.wiphy&&r.clients[e.msg?.mac])[0];
            if(r)history({event:'client-departure',radio:r.name,disconnect_events:1});
        }
        executor.event(e,discovered);
    }
}catch(err){if(executor.busy())executor.abort(err);else scanner.cancel('Survey deferred: '+err);}},
    [N.NL80211_CMD_NEW_SCAN_RESULTS,N.NL80211_CMD_SCAN_ABORTED,N.NL80211_CMD_DEL_STATION,N.NL80211_CMD_RADAR_DETECT]);
if(!listener)die('Cannot subscribe to wireless events');
let test_started=false;
timer=uloop.timer(1000,()=>{try{
    if(stopping)return;
    discovered=measured('inventory',inventory);measured('observation',()=>sample(discovered));measured('persistence',persist_channels);
    poll_planning(discovered);
    scan_state.halted=state.halted;scan_state.radios=state.radios;
    if(cfg.enabled)executor.reassess(discovered);
    state.operation=executor.pending()?{id:executor.pending().id,radio:executor.pending().radio,stage:executor.pending().kind,reserved:reservations(executor.pending())}:null;
    if(!one_shot&&now()-last_steering>=5){
        last_steering=now();
        try{
            if(!steering_ready){
                if(system('/usr/bin/ucode /usr/share/radio-prefer/coordination.uc --prepare')!=0)die('Could not prepare shared steering policy');
                system('if /etc/init.d/usteer running; then /etc/init.d/usteer reload; fi');
                steering_ready=true;
            }
            let locked=reservations(executor.pending());
            let scan=scanner.pending?.();
            if(scan?.scanner&&index(['scan','scan-recovery'],scan.kind)>=0)push(locked,scan.scanner.name);
            if(state.halted||state.restart_check)locked=map(discovered,r=>r.name);
            measured('steering',()=>{steering.tick(uniq(locked));returns.tick(discovered,steering.state.clients);});
            steering_error=null;
        }catch(e){
            steering.state.integration_error=''+e;
            atomic('/tmp/radio-prefer-state.json',steering.state);
            if(steering_error!=''+e)log('Preference waiting: '+e);
            steering_error=''+e;
        }
    }
    if(state.halted&&!state.restart_check&&!executor.busy()&&!scanner.busy()&&now()>=(state.recovery_retry_at ?? 0)){
        try{
            if(fs.stat(JOURNAL))restore_preparation();
            begin_restart_check(state,now(),true);
            history({event:'restart-retry'});
        }catch(err){state.status='Automatic recovery retry deferred: '+err;schedule_recovery(state,now());}
    }
    if(state.restart_check){
        let enabled=[];
        cursor.foreach('wireless','wifi-iface',s=>{
            if(s.mode=='ap'&&s.disabled!='1'&&cursor.get('wireless',s.device,'disabled')!='1'&&index(enabled,s.device)<0)push(enabled,s.device);
        });
        let result=check_restart(state,discovered,enabled,now(),!!fs.stat(JOURNAL),cfg.cac_timeout+60);
        if(result=='resumed'){history({event:'restart-recovered'});next_eval=now()+1;}
        else if(result=='failed')history({event:'restart-recovery-failed',message:state.halted});
    }
    if(!test_started&&(ARGV[0]=='--test-switch'||ARGV[0]=='--test-prepare')){
        if(state.halted)die('Resolve safety stop before manual operation');test_started=true;
        let r=filter(discovered,r=>r.name==ARGV[1])[0];if(!r)die('Unknown radio');
        executor.start(r,group((r.band=='2g'?2407:5000)+5*int(ARGV[2]),int(ARGV[3])),discovered);
    }else {
        if(executor.busy())execution_action(()=>measured('execution',()=>executor.tick(discovered)));
        if(scanner.busy())survey_action(()=>measured('survey',()=>scanner.tick(discovered)));
        else if(cfg.enabled&&!state.halted&&!planning.busy()&&now()>=next_eval){
            next_eval=now()+cfg.interval;
            if(urgent_eval&&!executor.busy()&&scan_result&&now()-scan_result.at<=cfg.max_age){urgent_eval=false;evaluate(discovered);}
            else survey_action(()=>measured('survey-start',()=>scanner.start(discovered)));
        }
        if(urgent_eval&&!executor.busy()&&scanner.phase()!='scan'&&scan_result&&now()-scan_result.at<=cfg.max_age){
            urgent_eval=false;evaluate(discovered);
        }
    }
    save();
    if(manual_done&&!executor.busy()&&!returns.busy())uloop.end();
}catch(err){if(executor.busy())executor.abort(err);else {scanner.cancel('Operation deferred: '+err);next_eval=now()+cfg.retry_delay;}}
timer.set(scanner.busy()?500:1000);
});
log('Wi-Fi Coordinator: unified observe / plan / execute / verify cycle');
uloop.run();planning.cancel('Controller stopped');history_store.flush(true);save();
