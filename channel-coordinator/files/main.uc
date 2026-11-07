#!/usr/bin/ucode
import * as fs from 'fs';
import * as nl from 'nl80211';
import * as ubus from 'ubus';
import * as uci from 'uci';
import * as uloop from 'uloop';
import {open_history} from './history.uc';
import {channel, group, same, overlap, permitted, delta_busy, dfs_ready, uses_dfs, traffic_sample,declared_bands} from './policy.uc';
import {survey_covers,move_method,configured_channels,configured_widths,frequency,switch_methods,setting_integer,hardware_widths,placements,live_width} from './policy.uc';
import {assess,choose,decide} from './planner.uc';
import {open_memory} from './radar.uc';
import {create_survey} from './survey.uc';
import {create_executor} from './executor.uc';

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

    wide_threshold:number('wide_threshold',70,10,100),
    verify_unprobed:number('verify_unprobed',180,150,600),
    allow_reconnect:raw.allow_reconnect!='0',
    protected_clients:map(type(raw.protected_clients)=='array'?raw.protected_clients:split(raw.protected_clients ?? '',/\s+/),x=>lc(x)),
    scan_policy:raw.scan_policy ?? 'paced',scanner:raw.scanner ?? '',max_age:number('max_age',900,60,7200),
    scan_duty:number('scan_duty',10,1,30),radar_half_life:number('radar_half_life',21600,900,604800),
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
    if(restore_preparation()){
        let s=readjson(STATE,{});
        if(s.boot==boot){
            if(!reconnect)s.dfs={...s.dfs,phase:'recovered'};delete s.pending;
            s.status=reconnect?'Previous channel restored after interrupted reconnect operation':'Spare radio configuration restored after interruption';
            s.halted='Interrupted radio operation recovered; check radios before clearing safety stop';
            atomic(STATE,s);
        }
    }
    exit(0);
}
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
if(state.pending&&state.pending!='scan') state.halted='Service restarted during an operation; inspect radios before clearing safety stop';
if(fs.stat(JOURNAL)){restore_preparation();state.halted='Interrupted radio operation recovered; inspect radios before clearing safety stop';}
if(!state.pending&&index(['listening','restoring'],state.dfs?.phase)>=0)state.dfs.phase='inactive';
delete state.pending;
if(raw.clear_stop=='1'&&!length(ARGV)){
    delete state.halted;for(let name,r in state.radios)delete r.failed;
    cursor.set('channel_coordinator','main','clear_stop','0');cursor.commit('channel_coordinator');
}
let evidence={}, previous={}, traffic={}, rates={}, quiet_since={}, discovered=[], next_eval=now()+15,scanner,executor;
let scan_result=null, one_shot=ARGV[0]=='--evaluate',estimate_cache={},admission=null,intent=null;
let persist_queue=state.persist_queue ?? {},next_persist=state.next_persist ?? now()+21600;
let radar=open_memory('/etc/wifi-coordinator/radar-memory.json',cfg.radar_half_life,time,now,state.radar?.events);
// ucode resolves function references at declaration time, unlike JavaScript.
let evaluate,timer;
if(one_shot){cfg.mode='observe';next_eval=now()+1;}
function save() { state.updated=now(); state.mode=cfg.mode; state.next_evaluation=next_eval;state.persist_queue=persist_queue;state.next_persist=next_persist;atomic(STATE,state); }
function lease(seconds,reason,reserved) { atomic(LEASE,{boot,until:now()+seconds,reason,reserved}); }
function release() { fs.unlink(LEASE); }
function history(event) { let e={time:time(),...event};push(state.history,e);history_store.event(e);while(length(state.history)>30)shift(state.history); }
function coordination_ready() {
    let services=call('service','list');
    function running(name) { for(let k,v in services[name]?.instances ?? {}) if(v.running)return true;return false; }
    for(let name in ['wifi-auto-channel','dawn','linksys-steering'])
        if(running(name))die(`Stop competing service ${name} before channel coordination`);
    if(running('radio-prefer')&&trim(fs.readfile('/usr/share/radio-prefer/integration-version') ?? '')!='1')
        die('A compatible Radio Preference coordination protocol is required for scan/switch handoff');
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
    let occupied=r.occupied_policy ?? 'handoff';
    if(index(['empty','quiet','handoff'],occupied)<0)die('Invalid occupied-radio policy');
    return {managed:r.managed!='0',occupied,...methods,channels:ch,widths,hardware_widths:hardware,
        unavailable_widths:filter(requested,w=>index(hardware,w)<0)};
}
function inventory() {
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
            info.bands[key]={ht_capa:band.ht_capa ?? old.ht_capa,vht_capa:band.vht_capa ?? old.vht_capa};
            for(let f in band.freqs ?? [])if(f)info.caps[f.freq]=f;
        }
    }
    let out=[];
    for(let name,data in ws) {
        if(!match(name,/^[A-Za-z0-9_-]+$/)||!data.up||data.disabled) continue;
        let aps=[],unsafe=!match(data.config.htmode ?? '',/^(HT(20|40[+-]?)|VHT(20|40|80|160))$/);
        for(let i in data.interfaces ?? []) {
            if(i.config?.mode!='ap') { unsafe=true; continue; }
            if(!match(i.ifname ?? '',/^[A-Za-z0-9_.-]+$/)) continue;
            let status; try { status=call('hostapd.'+i.ifname,'get_status'); } catch(e) { unsafe=true; continue; }
            if(status.status!='ENABLED'||status.dfs?.cac_active) {unsafe=true;continue;}
            push(aps,{ifname:i.ifname,status,config:i.config});
        }
        if(!length(aps)) continue;
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
    let reg=request(N.NL80211_CMD_GET_REG,0,{});
    let effective=reg.dfs_region==2 && r.dfs_region==2 ? cfg.dfs_mode : 'off';
    if(state.radios[r.name])state.radios[r.name].dfs_constraint=cfg.dfs_mode!='off'&&effective=='off'?'DFS blocked: global and radio ETSI regions must match':null;
    return effective;
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
        if(s.width_limit?.until<=t)delete s.width_limit;
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
    history_store.record(history_rows);
}
function candidates(r,radios,rules) {
    let s=state.radios[r.name],t=now(),dm=dfs_mode(r),list=[],busy={},maxw=max(r.current.width,...r.config.widths);
    for(let f in scan_result.frequencies){
        let e=evidence[r.name+':'+f] ?? evidence[scan_result.scanners[f]+':'+f];
        let own=length(filter(radios,x=>length(x.clients)&&overlap(group(int(f),20),x.current)>0));
        if(e&&t-e.at<=cfg.max_age&&!own)busy[f]=e.busy;
    }
    let snapshot={...scan_result,busy};
    function rated(g){
        let key=r.name+':'+g.center+':'+g.width;
        let q=assess(g,snapshot,maxw,radar.records(),time(),cfg.radar_half_life,r.dfs_region,estimate_cache[key]);
        estimate_cache[key]=q;
        let powers=map(g.members,f=>r.caps[f]?.max_tx_power ?? 0);
        return {...q,max_width:maxw,power:min(...powers)};
    }
    let current=rated(r.current);
    s.rejected=filter(s.rejected ?? [],x=>x.until>t);
    s.planning_hold=!r.config.managed?'Excluded from planning':r.unsafe?'Unsupported or inactive configuration':s.failed?'Unresolved recovery on this radio':
        s.recheck_until>t?'Previous service restored; waiting for fresh client evidence':
        !survey_covers(rules,r,scan_result.frequencies,dm)?'Incomplete fresh survey':
        t-(s.last_move ?? -100000)<cfg.cooldown?'Minimum residence after verified move':
        t-(s.last_attempt ?? -100000)<cfg.retry_delay?'Short retry delay':null;
    if(s.planning_hold)return [current];
    for(let w in r.config.widths)for(let ch in r.config.channels)for(let g in placements(frequency(ch,r.band),w)){
        if(s.width_limit?.until>t&&w>s.width_limit.actual)continue;
        if(!permitted(g,r.caps,rules,r.config.channels,dm))continue;
        let method=move_method(r.config,r.current,g);
        if(!same(g,current)&&method=='csa'&&!r.csa)continue;
        if(!same(g,current)&&r.band=='2g'&&g.width==40&&method=='csa')continue;
        if(!same(g,current)&&method=='idle_reconfigure'&&length(filter(keys(r.clients),m=>index(cfg.protected_clients,lc(m))>=0)))continue;
        if(length(filter(s.rejected,x=>same(g,x.target))))continue;
        if(length(filter(g.members,f=>index(scan_result.frequencies,f)<0)))continue;
        if(length(filter(list,x=>same(x,g))))continue;
        push(list,same(g,current)?current:rated(g));
    }
    if(!length(filter(list,g=>same(g,current))))push(list,current);
    return sort(list,(a,b)=>a.cost-b.cost);
}
function sum_overlap(g,models,name){let n=0;for(let m in models)if(m.name!=name)n+=overlap(g,m.current);return n;}
evaluate=function(radios){
    next_eval=now()+cfg.interval;
    if(!scan_result||now()-scan_result.at>cfg.max_age){state.status='Waiting for a fresh survey';save();return;}
    let rules=request(N.NL80211_CMD_GET_REG,0,{}).reg_rules ?? [],models=[];
    for(let r in radios){let choices=candidates(r,radios,rules),s=state.radios[r.name];push(models,{name:r.name,current:filter(choices,g=>same(g,r.current))[0],candidates:choices,last_action:max(s.last_attempt ?? 0,s.last_move ?? 0)});}
    let result=choose(models,cfg),decision=decide(result,models,admission,scan_result.at,cfg,intent?.until>now()?intent.signature:null);
    admission=decision.signature?decision:null;
    let changes=[];for(let i,r in radios)if(!same(r.current,result.choices[i]))push(changes,{radio:r.name,from:channel(r.current.freq),to:channel(result.choices[i].freq),width:result.choices[i].width});
    state.proposal={evaluated_at:time(),evaluated_uptime:now(),placements_changed:false,
        current_cost:result.base.cost,best_cost:result.cost,improvement:result.gain,changes,
        current_overlap:result.base.overlap,target_overlap:result.overlap,separate:cfg.separate,
        decision:{action:decision.action,reason:decision.reason,margin:decision.required,observations:decision.count,comparisons:decision.comparisons},
        steps:map(result.path,s=>({radio:models[s.index].name,to:channel(s.target.freq),width:s.target.width,staging:s.staging})),
        alternatives:map(models,m=>({radio:m.name,current:m.current,hold:state.radios[m.name].planning_hold,rejected:json(sprintf('%J',state.radios[m.name].rejected ?? [])),
            channels:state.radios[m.name].candidate_channels,widths:state.radios[m.name].candidate_widths,
            width_limit:state.radios[m.name].width_limit,
            candidates:map(m.candidates,g=>({...g,channel:channel(g.freq),shared:sum_overlap(g,models,m.name),current:same(g,m.current)}))})),
        scan_age:now()-scan_result.at,neighbors:length(scan_result.observations)};
    state.status=decision.reason;
    if(decision.action=='hold')intent=null;
    // A close comparison collects evidence on the configured schedule, never earlier.
    if(!state.halted&&cfg.mode=='automatic'&&decision.action=='move'){
        intent={signature:decision.signature,until:now()+cfg.max_age};
        history({event:'plan-start',radio:models[decision.next.index].name,to:channel(decision.next.target.freq),width:decision.next.target.width,reason:decision.reason});
        executor.start(radios[decision.next.index],decision.next.target,radios);
    }
    save();
};

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
function completed(){next_eval=now()+cfg.interval;if(one_shot||ARGV[0]=='--test-switch'||ARGV[0]=='--test-prepare')uloop.end();}
function record_radar(e){
    let msg=e.msg ?? {},live=filter(discovered,r=>r.phy==msg.wiphy)[0],p=executor?.pending();
    let width=[20,20,40,80,80,160][msg.channel_width] ?? (p?.helper?.phy==msg.wiphy?(p.cac_target ?? p.target).width:live?.current.width) ?? 20;
    let freq=msg.wiphy_freq,center=msg.center_freq1 ?? group(freq,width)?.center ?? freq;
    let event={event:'radar-state',time:time(),phy:msg.wiphy,radar_event:msg.radar_event,freq,center,width,region:live?.dfs_region ?? 2};
    history(event);radar.add(event);state.radar={half_life:cfg.radar_half_life,events:radar.records()};
    if(msg.radar_event==0){intent=null;admission=null;if(scanner?.busy())scanner.cancel('Radar event invalidated survey');}
    executor.event(e,discovered);
}
let io={cfg,state,boot,now,precise,save,lease,release,history,history_store,call,request,inventory,
    client_avoided,avoid_client,
    config_fingerprint,phy_caps,allclients,empty_interface,apply_empty_config,apply_radio_config,restore_preparation,private_json,
    coordination_ready,dfs_mode,log,rates,quiet_since,remember:remember_channel,completed};
scanner=create_survey({...io,complete:(result,radios)=>{scan_result=result;evaluate(radios);if(one_shot)uloop.end();}});
executor=create_executor(io);
// Import existing raw detections without inventing geometry from CAC completion.
let old_history=readjson('/tmp/wifi-coordinator-history.json',{});
for(let e in old_history.events ?? state.history ?? [])if(e.event=='radar-state'&&e.radar_event==0){
    let g=e.center?{center:e.center,width:e.width}:null;
    if(!g){
        let matches=filter(old_history.periods ?? [],p=>p.start<=e.time&&p.end+5>=e.time&&p.center&&e.freq>=p.center-p.width/2&&e.freq<p.center+p.width/2);
        g=length(matches)?{center:matches[0].center,width:matches[0].width}:group(e.freq,20);
    }
    if(g)radar.add({...e,...g,region:e.region ?? 2});
}
old_history=null;
state.radar={half_life:cfg.radar_half_life,events:radar.records()};
if(ARGV[0]=='--inspect'){print(sprintf('%J\n',map(inventory(),r=>({radio:r.name,current:r.current,clients:length(r.clients)}))));exit(0);}
if(one_shot||ARGV[0]=='--test-switch'||ARGV[0]=='--test-prepare'){
    let services=call('service','list',{name:'channel-coordinator'});
    for(let k,v in services['channel-coordinator']?.instances ?? {})if(v.running)die('Stop coordinator before a manual test');
}
if(ARGV[0]=='--clear-stop'){delete state.halted;for(let n,r in state.radios)delete r.failed;save();exit(0);}
if(!cfg.enabled&&!one_shot)exit(0);
uloop.init();
let stopping=false;
let termination=uloop.signal('SIGTERM',()=>{
    stopping=true;
    try{if(scanner.busy())scanner.cancel('Survey stopped for service shutdown');}catch(e){log('Stopping survey: '+e);}
    uloop.end();
});
if(!termination)die('Cannot install graceful shutdown handler');
let listener=nl.listener(e=>{try{
    if(stopping)return;
    if(e.cmd==N.NL80211_CMD_RADAR_DETECT)record_radar(e);
    else if(e.cmd==N.NL80211_CMD_NEW_SCAN_RESULTS||e.cmd==N.NL80211_CMD_SCAN_ABORTED)scanner.event(e);
    else executor.event(e,discovered);
}catch(err){if(executor.busy())executor.abort(err);else scanner.cancel('Survey deferred: '+err);}},
    [N.NL80211_CMD_NEW_SCAN_RESULTS,N.NL80211_CMD_SCAN_ABORTED,N.NL80211_CMD_DEL_STATION,N.NL80211_CMD_RADAR_DETECT]);
if(!listener)die('Cannot subscribe to wireless events');
let test_started=false;
timer=uloop.timer(1000,()=>{try{
    if(stopping)return;
    discovered=inventory();sample(discovered);persist_channels();
    if(!test_started&&(ARGV[0]=='--test-switch'||ARGV[0]=='--test-prepare')){
        if(state.halted)die('Resolve safety stop before manual operation');test_started=true;
        let r=filter(discovered,r=>r.name==ARGV[1])[0];if(!r)die('Unknown radio');
        executor.start(r,group((r.band=='2g'?2407:5000)+5*int(ARGV[2]),int(ARGV[3])),discovered);
    }else if(executor.busy())executor.tick(discovered);
    else if(scanner.busy())scanner.tick(discovered);
    else if(!state.halted&&now()>=next_eval){next_eval=now()+cfg.interval;scanner.start(discovered);}
    save();
}catch(err){if(executor.busy())executor.abort(err);else {scanner.cancel('Operation deferred: '+err);next_eval=now()+cfg.retry_delay;}}
timer.set(scanner.busy()?500:5000);
});
log('Wi-Fi Coordinator: unified observe / plan / execute / verify cycle');
uloop.run();history_store.flush(true);save();
