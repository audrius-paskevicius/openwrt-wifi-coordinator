import * as system_fs from 'fs';
import * as nl from 'nl80211';
import {channel,group,same,same_block,overlap,permitted,uses_dfs,dfs_ready,preparation_text,reconfigure_text,same_network,force_signal_ok,private_ipv4,liveness_progress,move_method,quiet_ready} from './policy.uc';
export function data_flow(previous,current){
    if(!previous||!current)return false;
    let reset=current.rx<previous.rx||current.tx<previous.tx;
    return current.rx-(reset?0:previous.rx)>4096&&current.tx-(reset?0:previous.tx)>4096;
};
function counter_snapshot(data){let copy={};for(let mac,d in data ?? {})copy[mac]={rx:d.rx,tx:d.tx};return copy;}
// Positive service evidence is separate from mere association. Per-AP samples
// prevent stale station records or counters from another radio proving service.
export function client_health(before,liveness,radios,t,ping){
    let locations={},proven={},working={},results={};
    liveness.samples=liveness.samples ?? {};liveness.good=liveness.good ?? {};
    for(let r in radios){
        let samples=liveness.samples[r.name] ?? {},good=liveness.good[r.name] ?? {};
        for(let mac in keys(good))if(!r.authorized[mac]||t-good[mac]>30)delete good[mac];
        proven[r.name]={};
        for(let mac in keys(r.authorized)){
            locations[mac]=locations[mac] ?? [];push(locations[mac],r.name);
            let current=r.client_data?.[mac];
            if(data_flow(samples[mac],current))good[mac]=t;
            if(good[mac]!=null&&t-good[mac]<=30){proven[r.name][mac]=true;working[mac]=true;}
        }
        liveness.samples[r.name]=counter_snapshot(r.client_data);liveness.good[r.name]=good;
    }
    for(let mac in keys(before)){
        let present=length(locations[mac] ?? [])>0,ip=liveness.probes?.[mac];
        if(present&&ip&&!working[mac]&&ping(ip)){
            working[mac]=true;
            if(length(locations[mac])==1)proven[locations[mac][0]][mac]=true;
        }
        results[mac]=present&&(!ip||!!working[mac]);
    }
    return {results,working,locations,proven};
};
export function failure_kind(r,target,health){
    if(!r||!same(r.current,target)||r.aps?.[0]?.status?.status&&r.aps[0].status.status!='ENABLED')return 'radio';
    return length(health.proven[r.name] ?? {})?'client':'inconclusive';
};
export function create_executor(io) {
let fs=io.fs ?? system_fs;
let cfg=io.cfg,state=io.state,now=io.now,save=io.save,lease=io.lease,release=io.release,call=io.call,request=io.request,config_fingerprint=io.config_fingerprint,phy_caps=io.phy_caps,allclients=io.allclients,empty_interface=io.empty_interface,apply_empty_config=io.apply_empty_config,restore_preparation=io.restore_preparation,private_json=io.private_json,coordination_ready=io.coordination_ready,dfs_mode=io.dfs_mode,history=io.history,boot=io.boot;
let N=nl.const,JOURNAL='/tmp/channel-coordinator-cac.json',pending=null,handoff,rechecks={};
function log(s){io.log(s);}
function reconnect_allowed(r){return cfg.allow_reconnect&&r.config.occupied=='handoff'&&length(r.aps)==1&&!r.unsafe&&
    !length(filter(keys(r.clients),m=>index(cfg.protected_clients,lc(m))>=0));}
function move_allowed(r){return !length(r.clients)||pending?.reconnect&&reconnect_allowed(r)||r.config.method=='csa'&&(r.config.occupied=='handoff'||r.config.occupied=='quiet'&&quiet_ready(io.quiet_since[r.name],now(),cfg.quiet_seconds));}
function handoff_before_move(clients,method,policy){return clients>0&&method!='csa'&&policy=='handoff';}
function start(r,target,radios) {
    coordination_ready();
    if(!target)die('Unsupported target channel or width');
    if(config_fingerprint(r.name)!=r.fingerprint)die('Wireless configuration differs from running radio; apply administrator edits first');
    if(r.unsafe)die('Radio configuration is not supported for channel moves');
    // Watch clients affected by this operation. A natural departure on an
    // untouched band must not roll back an otherwise successful channel move.
    pending={kind:'move-wait',radio:r.name,source:r.current,target,started:now(),before:{...r.clients},fingerprint:r.fingerprint,disconnects:0,method:move_method(r.config,r.current,target)};
    state.radios[r.name].last_attempt=now();state.last_action=now();
    state.pending='move';lease(75,'Preparing coordinated channel switch');state.status='Preparing '+pending.method+' on '+r.name;save();
};
function start_cac(r,g,radios) {
    let rules=request(N.NL80211_CMD_GET_REG,0,{}).reg_rules ?? [];
    let suitable=[];
    // Clearance is per-frequency. A narrower helper can prepare a wide block
    // in pieces, but every piece must become AVAILABLE on the serving PHY too.
    for(let h in radios){
        if(!h.config.managed||h.unsafe||h.band!='5g'||length(h.aps)!=1||
            cfg.dfs_helper&&h.name!=cfg.dfs_helper||dfs_mode(h)!='prepare')continue;
        let groups=[];
        for(let w in [160,80,40,20]){
            let bit=w==160?32:w==80?8:w==40?4:2;
            if(w>g.width||!(h.radar_widths&bit)||h.config.widths&&index(h.config.widths,w)<0)continue;
            for(let f in g.members){
                let part=w==g.width?g:group(f,w);
                if(!part||length(filter(part.members,m=>index(g.members,m)<0))||dfs_ready(part,r.caps))continue;
                if(!length(filter(groups,x=>same_block(x,part))))push(groups,part);
            }
        }
        for(let part in groups)if(permitted(part,h.caps,rules,h.config.channels,'prepare')&&
            preparation_text(fs.readfile('/var/run/hostapd-phy'+h.phy+'.conf'),part))push(suitable,{...h,cac_part:part});
    }
    let choices=filter(suitable,h=>!length(h.clients));
    choices=sort(choices,(a,b)=>(a.name==r.name?1:0)-(b.name==r.name?1:0)||b.cac_part.width-a.cac_part.width);
    let h=choices[0];
    if(!h){
        let busy=sort(filter(suitable,h=>h.config.occupied=='handoff'&&!length(filter(keys(h.clients),m=>index(cfg.protected_clients,lc(m))>=0))),(a,b)=>
            length(filter(keys(a.clients),m=>index(cfg.protected_clients,lc(m))>=0))-
            length(filter(keys(b.clients),m=>index(cfg.protected_clients,lc(m))>=0))||length(a.clients)-length(b.clients)||a.mbps-b.mbps||
            (a.name==r.name?-1:0)-(b.name==r.name?-1:0))[0];
        if(busy&&!pending.spare_attempted){
            let sent=handoff(busy,radios,r.name);
            if(sent||cfg.escalation=='decisive'&&pending.handoff_target){
                pending.kind='spare-handoff';pending.spare=busy.name;pending.started=now();pending.spare_attempted=true;
                state.status='Asking clients to leave '+busy.name+' so it can listen for radar';lease(90,state.status);save();return;
            }
        }
        die('Waiting for an empty, compatible 5 GHz radio to prepare DFS');
    }
    g=h.cac_part;
    if(config_fingerprint(h.name)!=h.fingerprint)die('Spare radio settings changed');
    if(!empty_interface(h.ifname)){
        pending.cac_idle_wait=pending.cac_idle_wait ?? now();
        if(now()-pending.cac_idle_wait>=60)die('Spare radio retains station records; radar preparation deferred');
        state.status='Waiting for spare-radio station records to clear before radar preparation';lease(90,state.status);save();return;
    }
    let path='/var/run/hostapd-phy'+h.phy+'.conf';
    let original=reconfigure_text(fs.readfile(path),h.current,h.band,h.band_caps),temporary=preparation_text(original,g);
    if(!original||!temporary)die('Cannot construct live-channel CAC recovery configuration');
    private_json(JOURNAL,{boot,phy:'phy'+h.phy,ifname:h.ifname,path,original,temporary,source:h.current});
    pending.kind='cac';pending.started=now();pending.helper={name:h.name,phy:h.phy,ifname:h.ifname,source:h.current,fingerprint:h.fingerprint};
    pending.cac_seen=false;
    pending.cac_target=g;
    state.pending='DFS preparation';state.dfs={phase:'listening',helper:h.name,radio:r.name,channel:channel(g.freq),width:g.width,started:now(),timeout:cfg.cac_timeout};
    state.status='Starting radar check on '+h.name+'; other radios continue serving clients';
    lease(90,'Spare radio is listening for radar');save();
    if(!fs.writefile(path,temporary))die('Cannot write temporary CAC configuration');
    apply_empty_config('phy'+h.phy,path,h.ifname);
    history({event:'cac-start',helper:h.name,radio:r.name,channel:channel(g.freq),width:g.width});
}
function handoff_destination(r,radios,preferred,selected) {
    if(length(r.aps)!=1)return null;
    let a=r.aps[0],ac=a.config;
    // Keep security and LAN membership identical; credentials never enter status/logs.
    let targets=filter(radios,h=>h.name!=r.name&&!h.unsafe&&h.band==r.band&&length(h.aps)==1&&
        same_network(h.aps[0].config,ac)&&(!h.aps[0].status?.status||h.aps[0].status.status=='ENABLED')&&
        !length(filter(selected ?? keys(r.clients),m=>io.client_avoided&&io.client_avoided(h.name,m,h.current)))&&
        (h.aps[0].status.airtime?.utilization ?? 0)<180);
    return sort(targets,(a,b)=>(a.name==preferred?-100:0)-(b.name==preferred?-100:0)+length(a.clients)-length(b.clients))[0];
}
// Forward-declared: occupied-helper preparation calls this earlier in the module.
handoff=function(r,radios,preferred,strong) {
    for(let mac in keys(r.clients))pending.before[mac]=true;
    if(!pending.handoff_clients){pending.handoff_clients=keys(r.clients);pending.handoff_source=r.name;}
    let target=handoff_destination(r,radios,preferred);if(!target)return 0;
    pending.handoff_target=target.name;
    let nr=call('hostapd.'+target.ifname,'rrm_nr_get_own').value?.[2];
    if(!match(nr ?? '',/^[a-fA-F0-9]{26,}$/))return 0;
    let stations=call('usteer','connected_clients')['hostapd.'+r.ifname] ?? {},count=0;
    for(let mac in keys(r.clients)){
        // Protected work devices must not be interrupted by handoff requests.
        if(index(cfg.protected_clients,lc(mac))>=0)continue;
        if(!stations[mac]||!stations[mac]['bss-transition-management'])continue;
        call('hostapd.'+r.ifname,'bss_transition_request',{addr:mac,disassociation_imminent:!!strong&&index(cfg.protected_clients,lc(mac))<0,
            disassociation_timer:0,validity_period:100,neighbors:[substr(nr,0,26)+'0301ff'],abridged:true,
            dialog_token:(now()%254)+1});count++;
    }
    history({event:strong?'handoff-strong':'handoff-request',from:r.name,to:target.name,clients:count});
    return count;
};
function clear_bans() {
    for(let ban in pending?.bans ?? []){
        try{
            // del_client also sends a frame: never call it on a client that has
            // already returned to this AP. The bounded ban expires by itself.
            let clients=call(ban.node,'get_clients').clients ?? {};
            if(!clients[ban.mac])call(ban.node,'del_client',{addr:ban.mac,reason:12,deauth:false,ban_time:0});
        }catch(e){}
    }
}
function forced_relocated(radios) {
    for(let mac in pending?.forced_clients ?? []){
        if(!length(filter(radios,r=>r.name!=pending.forced_source&&r.authorized[mac])))return false;
    }
    return true;
}
function handoff_relocated(radios) {
    return !length(filter(pending.handoff_clients ?? [],m=>!length(filter(radios,r=>r.name!=pending.handoff_source&&r.authorized[m]))));
}
function escalate_handoff(r,radios) {
    let elapsed=now()-pending.started;
    if(elapsed>=int(cfg.handoff_wait/3)&&!pending.strong_sent&&cfg.escalation!='gentle'){
        handoff(r,radios,pending.handoff_target,true);pending.strong_sent=true;
    }
    if(elapsed>=int(cfg.handoff_wait*2/3)&&pending.force_sent==null&&cfg.escalation=='decisive'){
        pending.force_sent=now();
        let target=handoff_destination(r,radios,pending.handoff_target);if(!target)return;
        let clients=call('usteer','connected_clients')['hostapd.'+r.ifname] ?? {},count=0;
        state.forced=state.forced ?? {};
        for(let mac in keys(r.clients)){
            if(index(cfg.protected_clients,lc(mac))>=0)continue;
            if(now()-(state.forced[mac] ?? -100000)<300)continue;
            if(state.forced[mac]==null&&length(state.forced)>=256)continue;
            if(!force_signal_ok(clients[mac]?.measurements,'hostapd.'+target.ifname,r.signals[mac],cfg.target_min,cfg.source_min))continue;
            state.forced[mac]=now();save(); // consume the retry budget before sending
            pending.bans=pending.bans ?? [];pending.forced_clients=pending.forced_clients ?? [];
            push(pending.bans,{node:'hostapd.'+r.ifname,mac});push(pending.forced_clients,mac);pending.forced_source=r.name;
            call('hostapd.'+r.ifname,'del_client',{addr:mac,reason:12,deauth:true,ban_time:cfg.ban_seconds*1000});count++;
        }
        state.radios[r.name].last_attempt=now();
        history({event:'handoff-disconnect',from:r.name,to:target.name,clients:count,ban_seconds:cfg.ban_seconds});
    }
    if(pending.force_sent!=null&&now()-pending.force_sent>=cfg.ban_seconds&&!forced_relocated(radios)){
        clear_bans();
        if(pending.kind=='handoff'&&reconnect_allowed(r)){
            pending.handoff_done=true;pending.kind='move-wait';pending.started=now()-12;
            state.status='Handoff did not finish; proceeding with brief client reconnection';save();return;
        }
        die('Client did not reconnect elsewhere; temporary restriction removed and handoff stopped');
    }
}
function ping_client(ip) {
    if(!private_ipv4(ip))return false;
    let p=fs.popen('ping -c 1 -W 1 '+ip+' >/dev/null 2>&1','r');
    if(!p)return false;p.read('all');return p.close()==0;
}
function capture_liveness(radios,source,before) {
    let addresses={};
    for(let line in split(fs.readfile('/tmp/dhcp.leases') ?? '','\n')){
        let fields=split(trim(line),/\s+/);
        if(length(fields)>=3&&private_ipv4(fields[2]))addresses[lc(fields[1])]=fields[2];
    }
    let clients=keys(before ?? pending.before),probes={},attempts=0;
    clients=sort(clients,(a,b)=>(source.clients[b]?1:0)-(source.clients[a]?1:0));
    for(let mac in clients){
        let ip=addresses[lc(mac)];if(!ip||attempts>=8)continue;attempts++;
        if(ping_client(ip))probes[mac]=ip;
    }
    // No addresses or identifiers are persisted in history/status. Unprobeable
    // clients require a longer association watch, not an invented success.
    let samples={};for(let r in radios)samples[r.name]=counter_snapshot(r.client_data);
    return {probes,samples,good:{},unprobed:length(clients)-length(probes),failed:{}};
}
// Failed radios are re-observed, never reset merely because a timer expired.
// This RAM-only evidence contains client identities; it is not status/history.
function reassess(radios) {
    if(!pending&&fs.stat(JOURNAL))return;
    let t=now();
    for(let name in keys(rechecks))if(!state.radios[name]?.failed&&!state.radios[name]?.unavailable)delete rechecks[name];
    for(let name,s in state.radios){
        if(!s.failed&&!s.unavailable)continue;
        if(pending&&index([pending.radio,pending.helper?.name,pending.spare,pending.handoff_target,pending.handoff_source],name)>=0)continue;
        if(t<(s.recovery_next ?? 0))continue;
        let r=filter(radios,r=>r.name==name)[0],q=rechecks[name];
        if(!q){q={started:t};rechecks[name]=q;}
        let ready=r&&!r.unsafe&&length(r.aps)&&!length(filter(r.aps,a=>a.status?.status!='ENABLED'||a.status?.dfs?.cac_active||a.status.freq&&a.status.freq!=r.current.freq));
        if(ready){
            let rules=request(N.NL80211_CMD_GET_REG,0,{}).reg_rules ?? [];
            ready=permitted(r.current,r.caps,rules,[channel(r.current.freq)],'available');
        }
        if(ready){
            let signature=sprintf('%J',[r.current,sort(keys(r.authorized))]);
            if(q.signature!=signature){q.signature=signature;q.stable=t;q.live=capture_liveness(radios,r,r.authorized);}
            let h=client_health(r.authorized,q.live,[r],t,ping_client);
            let proven=!length(filter(keys(r.authorized),m=>!h.working[m]));
            s.recovery_status=proven?'Checking stable AP and client service':'Waiting for positive client traffic or reachability evidence';
            if(proven&&t-q.stable>=60){
                // A legacy command-rejection latch gets the same bounded Auto fallback.
                if(index(s.failure ?? '',"switch_chan")>=0)s.csa_failed_until=t+21600;
                delete s.failed;delete s.failure;delete s.unavailable;delete s.recovery_status;
                delete s.recovery_next;delete s.recovery_attempts;delete rechecks[name];
                s.last_attempt=t;history({event:'radio-recovered',radio:name,clients:length(r.authorized)});if(!pending)io.completed();save();continue;
            }
        }else {delete q.signature;delete q.stable;s.recovery_status='Waiting for an enabled, consistent and legal AP';}
        if(t-q.started>=max(180,cfg.verify_unprobed ?? 180)){
            s.recovery_attempts=min(4,(s.recovery_attempts ?? 0)+1);
            s.recovery_next=t+[0,60,120,240,300][s.recovery_attempts];
            s.recovery_status='Automatic service recheck scheduled';delete rechecks[name];save();
        }
    }
}
function begin_client_rescue(r,radios,clients,preflight){
    if(!length(clients)||length(filter(clients,m=>index(cfg.protected_clients,lc(m))>=0)))return false;
    let target=handoff_destination(r,radios,null,clients);if(!target)return false;
    pending.rescue={clients:[...clients],target:target.name,started:now(),stage:-1,preflight:!!preflight};
    pending.rescue_attempted=true;
    history({event:'client-recovery-start',radio:r.name,to:target.name,clients:length(clients),preflight:!!preflight});
    return true;
}
// A bounded attempt affects only clients with failed service. Healthy clients
// and the functioning AP remain in place. Association alone cannot finish it.
function client_rescue(r,radios,health){
    let rescue=pending.rescue,t=now(),elapsed=t-rescue.started;
    if(!r||length(r.aps)!=1){clear_bans();delete pending.rescue;return 'failed';}
    let recovered=filter(rescue.clients,m=>length(filter(radios,h=>h.name!=r.name&&
        h.band==r.band&&length(h.aps)==1&&same_network(h.aps[0].config,r.aps[0].config)&&health.proven[h.name]?.[m])));
    if(length(recovered)==length(rescue.clients)){
        if(!rescue.preflight&&io.avoid_client)for(let mac in recovered)io.avoid_client(r.name,mac,pending.target,t+21600);
        history({event:'client-recovery-verified',radio:r.name,clients:length(recovered),preflight:rescue.preflight});
        clear_bans();delete pending.rescue;pending.last_problem=t;return 'recovered';
    }
    let target=handoff_destination(r,radios,rescue.target,rescue.clients);
    if(!target||target.name!=rescue.target||elapsed>=cfg.handoff_wait+cfg.ban_seconds){
        history({event:'client-recovery-unresolved',radio:r.name,clients:length(rescue.clients)-length(recovered),preflight:rescue.preflight});
        clear_bans();delete pending.rescue;return 'failed';
    }
    let stage=elapsed>=int(cfg.handoff_wait*2/3)?2:elapsed>=int(cfg.handoff_wait/3)?1:0;
    if(stage>rescue.stage){
        rescue.stage=stage;
        let stations=call('usteer','connected_clients')['hostapd.'+r.ifname] ?? {};
        let nr=call('hostapd.'+target.ifname,'rrm_nr_get_own').value?.[2],count=0;
        for(let mac in rescue.clients){
            if(index(recovered,mac)>=0||!r.authorized[mac]||index(cfg.protected_clients,lc(mac))>=0)continue;
            if(stage==2&&cfg.escalation=='decisive'){
                state.forced=state.forced ?? {};
                if(t-(state.forced[mac] ?? -100000)<300||state.forced[mac]==null&&length(state.forced)>=256)continue;
                if(!force_signal_ok(stations[mac]?.measurements,'hostapd.'+target.ifname,r.signals[mac],cfg.target_min,cfg.source_min))continue;
                state.forced[mac]=t;save();pending.bans=pending.bans ?? [];
                push(pending.bans,{node:'hostapd.'+r.ifname,mac});
                call('hostapd.'+r.ifname,'del_client',{addr:mac,reason:12,deauth:true,ban_time:cfg.ban_seconds*1000});count++;
            }else if(stage==0||stage==1&&cfg.escalation!='gentle'){
                if(!stations[mac]?.['bss-transition-management']||!match(nr ?? '',/^[a-fA-F0-9]{26,}$/))continue;
                call('hostapd.'+r.ifname,'bss_transition_request',{addr:mac,disassociation_imminent:stage==1,
                    disassociation_timer:0,validity_period:100,neighbors:[substr(nr,0,26)+'0301ff'],abridged:true,dialog_token:(t%254)+1});count++;
            }
        }
        if(count)history({event:'client-recovery-request',radio:r.name,to:target.name,clients:count,stage});
    }
    state.status='Keeping the working radio in place; checking alternate service for '+length(rescue.clients)+' affected clients';
    lease(90,state.status);save();return 'waiting';
}
function reconfigure_idle(r,g) {
    // Explicit opt-in, AP-only HT/VHT configurations, no global network reload.
    if(length(r.clients))die('Idle reconfiguration requires an empty radio');
    if(!empty_interface(r.ifname))return false;
    let path='/var/run/hostapd-phy'+r.phy+'.conf',original=reconfigure_text(fs.readfile(path),r.current,r.band,r.band_caps);
    let content=reconfigure_text(original,g,r.band,r.band_caps);
    if(!content)die('Generated hostapd configuration is not supported for idle reconfiguration');
    let backup=path+'.channel-coordinator-before';
    if(!fs.writefile(backup,original)||!fs.chmod(backup,0600))die('Cannot save runtime configuration backup');
    // Preserve permissions: OpenWrt runs hostapd as the unprivileged network user.
    pending.command_started=true;
    if(!fs.writefile(path,content))die('Cannot update runtime configuration');
    try{apply_empty_config('phy'+r.phy,path,r.ifname);}
    catch(e){
        if(!fs.writefile(path,original))die('Cannot restore runtime configuration after deferred restart');
        if(index(''+e,'Selected radio acquired clients; restart deferred')>=0){pending.command_started=false;return false;}
        die(e);
    }
    return true;
}
function reconfigure_reconnect(r,g) {
    if(!reconnect_allowed(r))die('Brief client reconnection is not allowed on this radio');
    let current_clients=call('hostapd.'+r.ifname,'get_clients').clients ?? {};
    if(length(filter(keys(current_clients),m=>index(cfg.protected_clients,lc(m))>=0)))die('Protected client joined; brief restart deferred');
    for(let mac in keys(current_clients))if(!pending.before[mac]){
        pending.before[mac]=true;pending.verify_seconds=cfg.verify_unprobed;
    }
    let path='/var/run/hostapd-phy'+r.phy+'.conf';
    let original=reconfigure_text(fs.readfile(path),r.current,r.band,r.band_caps),temporary=reconfigure_text(original,g,r.band,r.band_caps);
    if(!original||!temporary)die('Unsupported configuration for brief radio restart');
    if(fs.stat(JOURNAL))die('Another radio recovery journal is active');
    // RAM-only journal: service interruption restores the old live channel.
    // Power loss boots the existing saved UCI configuration instead.
    private_json(JOURNAL,{kind:'reconnect',boot,phy:'phy'+r.phy,ifname:r.ifname,path,original,temporary,source:r.current});
    pending.command_started=true;
    if(!fs.writefile(path,temporary))die('Cannot write reconnect configuration');
    history({event:'radio-reconnect',radio:r.name,from:channel(r.current.freq),to:channel(g.freq),width:g.width,clients:length(r.clients)});
    io.apply_radio_config('phy'+r.phy,path,r.ifname,true);
}
function switch_radio(r,g) {
    // force=false is essential: never fall back to disabling/restarting the AP.
    pending.command_started=true;
    return call('hostapd.'+r.ifname,'switch_chan',{freq:g.freq,center_freq1:g.center,center_freq2:0,
        bandwidth:g.width,sec_channel_offset:g.sec,ht:true,vht:r.band=='5g',he:false,
        block_tx:false,bcn_count:cfg.csa_count,force:false});
}
function operation(radios) {
    let t=now();if(!pending)return;
    if(pending.kind=='client-handoff'){
        let r=filter(radios,x=>x.name==pending.radio)[0];
        if(!r||r.fingerprint!=pending.fingerprint||!same(r.current,pending.source))die('Client recovery source changed');
        let health=client_health(pending.before,pending.liveness,radios,t,ping_client);
        let result=client_rescue(r,radios,health);
        if(result=='waiting')return;
        if(result=='recovered'){
            pending.preflight_done=true;pending.kind='move-wait';pending.started=t-12;save();return;
        }
        let s=state.radios[r.name];s.rejected=s.rejected ?? [];
        push(s.rejected,{target:pending.target,until:t+21600,kind:'client',reason:'Known client-placement conflict; alternate service did not verify'});
        while(length(s.rejected)>16)shift(s.rejected);
        state.status='Placement deferred for six hours to preserve clients without verified alternate service';
        pending=null;delete state.pending;release();io.completed();save();return;
    }
    if(pending.kind=='reconcile'){
        lease(90,'Reconciling external channel change');
        let r=filter(radios,x=>x.name==pending.radio)[0];
        if(r&&!r.unsafe){
            let rules=request(N.NL80211_CMD_GET_REG,0,{}).reg_rules ?? [];
            if(permitted(r.current,r.caps,rules,r.config.channels,dfs_mode(r)=='off'?'off':'available')){
                pending.target=r.current;pending.fingerprint=r.fingerprint;pending.method=move_method(r.config,pending.source,r.current);
                pending.kind='verify';pending.started=t;pending.verify_seconds=45;pending.last_problem=null;
                pending.external=true;pending.switch_clients={};pending.liveness=pending.liveness ?? capture_liveness(radios,r);
                state.pending='verification';state.status='External channel change settled; checking service';save();return;
            }
        }
        if(t-pending.started>cfg.cac_timeout){
            state.radios[pending.radio].unavailable=true;
            history({event:'external-recovery-unresolved',radio:pending.radio,reason:'Radio did not return within the radar-clearance window'});
            clear_bans();pending=null;delete state.pending;release();io.completed();save();
        }
        return;
    }

    // Keep the selected operation method through handoff, verification and
    // recovery even after the new width becomes visible in the inventory.
    for(let r in radios)if(r.name==pending.radio&&pending.method)r.config.method=pending.method;
    if(pending.kind=='verify')lease(90,'Checking client reachability after channel switch');
    if(pending.kind=='rollback'){
        lease(90,'Checking recovery to the previous channel');
        if(t-pending.started>=30){
            let r=filter(radios,x=>x.name==pending.radio)[0];
            let restored=r&&same(r.current,pending.source);
            let health=client_health(pending.before,pending.liveness,radios,t,ping_client);
            let missing=filter(keys(pending.before),m=>!health.results[m]);
            if(restored&&length(missing)&&t-pending.started<cfg.verify_unprobed){
                state.status='Previous channel restored; waiting for clients to reconnect';save();return;
            }
            let unconfirmed=restored&&length(missing)&&length(health.proven[r.name] ?? {})&&
                !length(filter(missing,m=>health.locations[m]?.[0]||index(cfg.protected_clients,lc(m))>=0));
            restored=restored&&!length(missing);
            if(restored&&pending.failed_entry?.kind=='inconclusive'&&
                !length(filter(pending.failure_clients ?? [],m=>!health.working[m]))){
                pending.failed_entry.kind='client';pending.failed_entry.until=t+21600;
                pending.failed_entry.reason='Client service recovered on previous placement; six-hour compatibility cooldown';
            }
            history({event:restored?'rollback-verified':unconfirmed?'recovery-client-unconfirmed':'rollback-failed',radio:pending.radio,channel:channel(pending.source.freq),clients_missing:length(missing)});
            if(restored||unconfirmed){
                if(state.halted==pending.own_stop)delete state.halted;
                delete state.radios[pending.radio].failed;
                delete state.radios[pending.radio].failure;
                state.radios[pending.radio].last_attempt=t;
                if(unconfirmed)state.radios[pending.radio].recheck_until=t+(cfg.max_age ?? 900);
            }
            state.status=restored?'Clients recovered on previous placement; see the recorded exclusion reason and expiry':unconfirmed?
                'Previous placement serves clients; absent clients remain unconfirmed. Moves briefly deferred':'Recovery needs attention; inspect wireless status';
            clear_bans();io.completed();
            pending=null;delete state.pending;release();save();
            
        }
        return;
    }
    if(index(['cac','restore','handoff','spare-handoff'],pending.kind)>=0)lease(90,'Coordinating radar preparation and client handoff');
    if(pending.kind=='spare-handoff'){
        let h=filter(radios,r=>r.name==pending.spare)[0];if(!h)die('Spare radio unavailable during handoff');
        escalate_handoff(h,radios);
        if(!length(h.clients)&&forced_relocated(radios)&&handoff_relocated(radios)){
            pending.kind='move-wait';pending.started=t-12;
            delete pending.strong_sent;delete pending.force_sent;delete pending.handoff_target;delete pending.forced_clients;
            delete pending.handoff_clients;delete pending.handoff_source;
        }
        else if(t-pending.started>=cfg.handoff_wait)die('Clients stayed on the spare radio; radar preparation deferred');
        save();return;
    }
    if(pending.kind=='cac'){
        let h=pending.helper,caps=phy_caps(h.phy),r=filter(radios,x=>x.name==pending.radio)[0],g=pending.cac_target;
        state.dfs.elapsed=t-pending.started;
        let live_status;try{live_status=call('hostapd.'+h.ifname,'get_status');}catch(e){}
        state.status=live_status?.dfs?.cac_active?'Listening for radar on '+h.name+'; other radios continue serving clients':
            'Waiting for confirmed radar clearance on '+h.name;
        if(t-pending.started>20&&live_status?.status=='ENABLED'&&live_status.freq!=g.freq)
            die('Radio did not enter the requested DFS channel; restoring its live source channel');
        if(pending.radar||length(filter(g.members,f=>caps[f]?.dfs_state==1)))die('Radar detected; candidate rejected');
        if(t-pending.started>cfg.cac_timeout)die('Radar check timed out; restoring spare radio');
        let helper=filter(radios,x=>x.name==h.name)[0];
        let targetcaps=r?.caps ?? (pending.radio==h.name?caps:{});
        if(pending.cac_seen&&helper&&same(helper.current,g)&&dfs_ready(g,caps)&&dfs_ready(g,targetcaps)){
            history({event:'cac-shared',helper:h.name,radio:pending.radio,channel:channel(g.freq),width:g.width,elapsed:t-pending.started});
            restore_preparation();pending.kind='restore';pending.started=t;state.dfs.phase='restoring';
            state.status='Radar check passed; restoring spare radio before handoff';save();
        }
        return;
    }
    if(pending.kind=='restore'){
        let h=filter(radios,x=>x.name==pending.helper.name)[0],r=filter(radios,x=>x.name==pending.radio)[0];
        if(t-pending.started>cfg.cac_timeout)die('Spare radio did not return to its original channel');
        if(h&&same(h.current,pending.helper.source)&&r){
            if(!dfs_ready(pending.cac_target,r.caps))die('Shared radar clearance is no longer available');
            state.dfs.phase='ready';state.dfs.completed=t;state.status='DFS block prepared; spare radio restored';
            if(ARGV[0]=='--test-prepare'&&dfs_ready(pending.target,r.caps)){
                clear_bans();pending=null;delete state.pending;release();save();io.completed();return;
            }
            pending.kind='move-wait';pending.started=t;save();
        }
        return;
    }
    if(pending.kind=='handoff'){
        let r=filter(radios,x=>x.name==pending.radio)[0];if(!r)die('Serving radio unavailable during handoff');
        escalate_handoff(r,radios);
        if(pending.kind!='handoff')return;
        state.status='Client handoff: '+length(r.clients)+' remain on '+r.name+'; quiet for '+(state.radios[r.name]?.quiet_seconds ?? 0)+' seconds';
        let remaining=length(r.clients);
        let quiet_csa=r.config.method=='csa'&&move_allowed(r)&&forced_relocated(radios);
        if((!remaining&&forced_relocated(radios)&&handoff_relocated(radios))||quiet_csa||t-pending.started>=cfg.handoff_wait){
            pending.handoff_done=true;pending.kind='move-wait';pending.started=t-12;pending.disconnects=0;
        }
        save();return;
    }
    if(pending.kind=='move-wait'&&t-pending.started>=12){
        coordination_ready();
        let r=filter(radios,x=>x.name==pending.radio)[0];
        if(!r||r.fingerprint!=pending.fingerprint||config_fingerprint(r.name)!=pending.fingerprint||!same(r.current,pending.source))die('Radio settings changed; proposed move cancelled');
        let rules=request(N.NL80211_CMD_GET_REG,0,{}).reg_rules ?? [];
        let dm=dfs_mode(r);
        if(!permitted(pending.target,r.caps,rules,r.config.channels,dm))die('Target no longer permitted');
        if(r.config.hardware_widths&&index(r.config.hardware_widths,pending.target.width)<0)die('Target width is not advertised by this radio');
        if(r.band=='2g'&&pending.target.width==40&&pending.method=='csa')die('HT40 requires restart for hostapd coexistence checks; explicit CSA remains unchanged');
        if(cfg.separate){
            let others=filter(radios,x=>x.name!=r.name),before=0,after=0;
            for(let x in others){before+=overlap(r.current,x.current);after+=overlap(pending.target,x.current);}
            if(after>before+0.000001)die('Another radio now occupies the destination; move cancelled');
        }
        if(uses_dfs(pending.target,r.caps)&&!dfs_ready(pending.target,r.caps)){
            if(dm!='prepare')die('Waiting for completed radar clearance');
            start_cac(r,pending.target,radios);return;
        }
        if(ARGV[0]=='--test-prepare'){
            state.dfs={phase:'ready',radio:r.name,channel:channel(pending.target.freq),width:pending.target.width,completed:t};
            state.status='DFS block already cleared by the kernel';pending=null;delete state.pending;release();save();io.completed();return;
        }
        if(io.client_avoided&&!pending.repair_attempted){
            let affected=filter(keys(r.clients),m=>io.client_avoided(r.name,m,pending.target));
            if(length(affected)){
                pending.liveness=capture_liveness(radios,r);
                if(!pending.preflight_done&&begin_client_rescue(r,radios,affected,true)){
                    pending.kind='client-handoff';state.pending='client compatibility handoff';save();return;
                }
                let s=state.radios[r.name];s.rejected=s.rejected ?? [];
                push(s.rejected,{target:pending.target,until:t+21600,kind:'client',reason:'Known client-placement conflict; no permitted compatible fallback'});
                while(length(s.rejected)>16)shift(s.rejected);
                die('Placement deferred for six hours: affected client has no permitted fallback');
            }
        }
        if(handoff_before_move(length(r.clients),r.config.method,r.config.occupied)&&!pending.handoff_done){
            if(handoff_destination(r,radios)){
                let sent=handoff(r,radios);pending.kind='handoff';pending.started=t;
                state.status='Sent '+sent+' voluntary roaming requests; waiting for clients or quiet traffic';lease(90,state.status);save();return;
            }
            pending.handoff_done=true;
            if(!reconnect_allowed(r))die('No compatible handoff AP; enable brief client reconnection or wait until this radio is empty');
        }
        let stranded=length(filter(keys(pending.before),m=>!allclients(radios)[m]));
        if((length(r.clients)||stranded)&&r.config.method=='idle_reconfigure'&&pending.handoff_done&&reconnect_allowed(r)){
            clear_bans();pending.reconnect=true;
        }
        if(!move_allowed(r))die(r.config.occupied=='empty'||r.config.method=='idle_reconfigure'?
            'Waiting for clients to leave this radio':'Waiting for '+cfg.quiet_seconds+' quiet seconds below '+cfg.max_mbps+' Mbps');
        if(!pending.repair_attempted&&!pending.reconnect&&stranded)die('Client disappeared during preparation; move deferred');
        for(let mac in keys(r.clients))pending.before[mac]=true;
        pending.liveness=capture_liveness(radios,r);
        pending.verify_seconds=pending.liveness.unprobed?cfg.verify_unprobed:45;
        pending.kind='verify';pending.started=now();pending.command_started=false;pending.command_done=false;
        state.pending='verification';state.status='Verifying '+r.config.method+' and client reachability on '+r.name;save();
        pending.switch_clients={...r.clients};
        if(pending.reconnect){
            pending.reconnect_until=now()+60;
            state.status='Brief restart of '+r.name+'; waiting for its clients to reconnect';save();
            reconfigure_reconnect(r,pending.target);
        }
        else if(r.config.method=='idle_reconfigure'){
            if(!reconfigure_idle(r,pending.target)){
                pending.idle_wait=pending.idle_wait ?? t;
                pending.kind='move-wait';pending.started=t-10;
                if(t-pending.idle_wait>=60)die('Driver still retains station records; restart deferred to a later evaluation');
                state.pending='move';state.status='Waiting for driver station records to clear before restarting this radio';save();return;
            }
        }
        else try{switch_radio(r,pending.target);}catch(e){
            // RPC rejection does not establish an outage (or even prove no move).
            // Retain the client baseline and observe the actual placement first.
            pending.command_error=''+e;
            state.status='Channel switch request failed; checking existing service';
            history({event:'switch-request-failed',radio:r.name,reason:''+e});save();
        }
        pending.command_done=true;
    }else if(pending.kind=='verify'&&t-pending.started>=5){
        let r=filter(radios,x=>x.name==pending.radio)[0];
        pending.liveness=pending.liveness ?? {probes:{},samples:{},good:{},failed:{}};
        let health=client_health(pending.before,pending.liveness,radios,t,ping_client);
        let results=health.results,working=health.working;
        if(pending.reconnect&&t<pending.reconnect_until&&length(filter(values(results),v=>!v))){
            state.status='Waiting for clients to reconnect after the brief radio restart';save();return;
        }
        let progress=liveness_progress(pending.liveness?.failed ?? {},results,t,15);
        if(pending.liveness)pending.liveness.failed=progress.failed;
        let missing=progress.lost;
        if(length(progress.failed))pending.last_problem=t;
        let stable=t-(pending.last_problem ?? pending.started)>=30;
        let channel_ok=r&&same(r.current,pending.target);
        let constrained=r&&r.band=='2g'&&pending.target.width==40&&r.current.width==20&&
            index(pending.target.members,r.current.freq)>=0&&!pending.external;
        if(constrained&&t-pending.started<30){
            state.status='Waiting for HT40 setup to settle before checking the resulting width';save();return;
        }
        if(constrained&&!pending.coexistence){
            // Hostapd may retain 20 MHz after its coexistence scan. Accept only
            // after client verification; do not keep trying the same HT40 block.
            let requested=pending.target,s=state.radios[r.name];
            s.rejected=s.rejected ?? [];
            push(s.rejected,{target:requested,until:t+(cfg.max_age ?? 900),reason:'20 MHz retained during HT40 setup: coexistence or driver constraint'});
            // Trying a different primary immediately does not remove a width
            // constraint. Let fresh evidence accumulate before another attempt.
            s.width_limit={actual:r.current.width,requested:requested.width,until:t+(cfg.max_age ?? 900),reason:'HT40 setup retained 20 MHz'};
            while(length(s.rejected)>16)shift(s.rejected);
            history({event:'width-constrained',radio:r.name,channel:channel(r.current.freq),width:r.current.width,requested_width:40});
            pending.target=r.current;pending.coexistence=true;channel_ok=true;
            state.status='HT40 setup retained 20 MHz; checking clients';
        }
        if(r&&!channel_ok&&!same(r.current,pending.source)&&!pending.external){
            clear_bans();delete pending.rescue;
            pending.kind='reconcile';pending.started=t;state.pending='external recovery';
            state.status='Driver changed the operating channel; reconciling actual placement';save();return;
        }
        if(!channel_ok&&t-pending.started<30){state.status='Waiting for the announced channel to become active';save();return;}
        if(pending.rescue&&!channel_ok){clear_bans();delete pending.rescue;}
        if(pending.rescue){
            let outcome=client_rescue(r,radios,health);
            if(outcome=='waiting'||outcome=='recovered')return;
        }else if(channel_ok&&length(missing)&&!pending.rescue_attempted&&!pending.repair_attempted&&
            failure_kind(r,pending.target,health)=='client'&&begin_client_rescue(r,radios,keys(progress.failed),false)){
            client_rescue(r,radios,health);return;
        }
        let unknown=length(filter(keys(pending.before),m=>!working[m]));
        let deadline=unknown?(pending.verify_seconds ?? 180):45;
        if((channel_ok||r&&same(r.current,pending.source))&&!length(missing)&&t-pending.started<deadline+60&&
            (t-pending.started<deadline||length(progress.failed)||!stable)){
            state.status=length(progress.failed)?'Waiting for previously reachable clients to respond; rollback if failure persists':
                'Checking stable client connectivity for '+max(0,deadline-(t-pending.started),30-(t-(pending.last_problem ?? pending.started)))+' more seconds';
            save();return;
        }
        // A completed reassociation is not persistent loss. Rolling back solely
        // because a client rejoined would cause a second avoidable interruption.
        let ok=channel_ok&&!length(missing)&&!length(progress.failed)&&stable;
        let unchanged=!channel_ok&&r&&same(r.current,pending.source)&&!length(missing)&&!length(progress.failed)&&stable;
        if(unchanged){
            // An ignored command with the original channel and healthy clients
            // is not an outage. Quarantine this target and keep serving.
            let s=state.radios[pending.radio];
            if(pending.command_error)s.csa_failed_until=t+21600;
            else {
                s.rejected=filter(s.rejected ?? [],x=>x.until>t&&!same_block(x.target,pending.target));
                push(s.rejected,{target:pending.target,until:t+21600,reason:'Driver left the original channel/width unchanged'});
                while(length(s.rejected)>16)shift(s.rejected);
            }
            delete s.failed;delete s.failure;delete s.unavailable;
            if(pending.reconnect)restore_preparation();
            history({event:'switch-ignored',radio:pending.radio,from:channel(pending.source.freq),to:channel(pending.target.freq),width:pending.target.width,method:pending.method});
            state.status=pending.command_error?'Switch request failed; original service verified. Auto will temporarily use restart fallback':'Driver left channel unchanged; target deferred and clients verified';
            clear_bans();pending=null;delete state.pending;release();io.completed();save();
            
            return;
        }
        let entry={event:ok?(pending.external?'external-recovery-verified':'switch-verified'):'switch-recovery',radio:pending.radio,
            from:channel(pending.source.freq),to:channel(pending.target.freq),width:pending.target.width,
            clients_missing:length(missing),clients_unproven:unknown,disconnect_events:pending.disconnects,method:pending.method};
        history(entry);log(sprintf('%J',entry));
        let s=state.radios[pending.radio];if(ok){s.last_move=t;state.last_move=t;delete s.failed;delete s.failure;delete s.unavailable;}
        if(ok&&pending.repair_attempted&&pending.failed_entry?.kind=='inconclusive'&&
            !length(filter(pending.failure_clients ?? [],m=>!working[m]))){
            pending.failed_entry.kind='client';pending.failed_entry.until=t+21600;
            pending.failed_entry.reason='Client service recovered on previous placement; six-hour compatibility cooldown';
        }
        // A repair is already on the original placement. Never bounce back to
        // the failed destination merely because a client is still absent.
        if(!ok&&pending.repair_attempted&&channel_ok){
            let absent=length(progress.failed)>0&&!length(filter(keys(progress.failed),m=>
                health.locations[m]?.[0]||index(cfg.protected_clients,lc(m))>=0));
            let serving=length(health.proven[r.name] ?? {})>0;
            if(absent&&serving){
                delete s.failed;s.recheck_until=t+(cfg.max_age ?? 900);
                state.status='Previous placement serves clients; absent clients remain unconfirmed. Moves briefly deferred';
            }else {s.failed=true;state.status='Previous placement restored; client recovery needs attention';}
            if(pending.reconnect)fs.unlink(JOURNAL);
            history({event:'recovery-client-unconfirmed',radio:r.name,clients_missing:length(progress.failed),reason:state.status});
            clear_bans();pending=null;delete state.pending;release();io.completed();save();return;
        }
        if(!ok){
            s.last_attempt=t;s.failed=true;
            let kind=failure_kind(r,pending.target,health);
            if(pending.method=='csa'&&kind=='radio')s.csa_failed_until=t+21600;
            pending.own_stop='Service verification failed';
            s.rejected=filter(s.rejected ?? [],x=>x.until>t&&!same_block(x.target,pending.target));
            pending.failure_clients=keys(progress.failed);
            pending.failed_entry={target:pending.target,kind,until:t+(kind=='inconclusive'?(cfg.max_age ?? 900):21600),
                reason:kind=='radio'?'Radio did not establish the requested placement':kind=='client'?
                    'Radio serves other clients; affected clients lack verified alternate service':'Client check inconclusive; short retry deferral pending recovery evidence'};
            push(s.rejected,pending.failed_entry);
            while(length(s.rejected)>16)shift(s.rejected);
            history({event:'move-evidence',radio:pending.radio,kind,affected:length(pending.failure_clients),retry_seconds:pending.failed_entry.until-t});
            if(pending.reconnect){
                if(!restore_preparation())die('Reconnect recovery journal is missing');
                pending.kind='rollback';pending.started=t;
                state.status='Reconnection failed; previous channel restored and clients being checked';
                history({event:'radio-repair',radio:pending.radio,channel:channel(pending.source.freq)});
                lease(90,state.status);save();return;
            }
            let rules=request(N.NL80211_CMD_GET_REG,0,{}).reg_rules ?? [];
            if(r&&!pending.repair_attempted&&permitted(pending.source,r.caps,rules,r.config.channels,dfs_mode(r)=='off'?'off':'available')){
                if(!length(r.clients)||handoff_destination(r,radios)||reconnect_allowed(r)){
                    let original=pending.source;pending.source=r.current;pending.target=original;
                    pending.method='idle_reconfigure';pending.repair_attempted=true;pending.handoff_done=false;
                    pending.kind='move-wait';pending.started=t-12;pending.fingerprint=r.fingerprint;
                    delete pending.strong_sent;delete pending.force_sent;delete pending.forced_clients;
                    delete pending.handoff_clients;delete pending.handoff_target;
                    state.status='Recovering data service: evacuate and reinitialize affected radio';
                    history({event:'radio-repair',radio:r.name,channel:channel(original.freq)});lease(90,state.status);save();return;
                }
                if(r.csa&&!same(r.current,pending.source)){
                    pending.kind='rollback';pending.started=t;state.status='Restoring the previous legal channel';
                    lease(90,state.status);save();switch_radio(r,pending.source);
                }else {pending=null;delete state.pending;release();io.completed();save();}
                return;
            }
        }
        else {
            if(pending.reconnect)fs.unlink(JOURNAL);
            if(cfg.persist)io.remember(r,pending);
        }
        clear_bans();pending=null;delete state.pending;release();
        state.status=ok?'Channel service verified':'Affected radio needs recovery; other radios remain available';io.completed();save();
        
    }
}
function abort(e,force) {
    
    
    let reason=''+e;log(reason);state.status=reason;
    if(!force&&(pending?.kind=='rollback'||pending?.kind=='verify'&&(pending.command_done||pending.external))){
        pending.observation_failed_since=pending.observation_failed_since ?? now();
        if(now()-pending.observation_failed_since<(cfg.verify_unprobed ?? 180)+60){
            state.status='Service check interrupted; retrying: '+reason;lease(90,state.status);save();return;
        }
    }
    clear_bans();
    if(pending?.radio){state.radios[pending.radio].last_attempt=now();state.last_action=now();}
    if(fs.stat(JOURNAL)){
        try{
            let restored=restore_preparation();
            if(restored&&pending?.reconnect&&!force){
                state.radios[pending.radio].failed=true;state.radios[pending.radio].failure=reason;
                pending.kind='rollback';pending.started=now();state.pending='verification';
                state.status='Configuration restored after command error; checking clients';lease(90,state.status);save();return;
            }
            if(!pending?.reconnect)state.dfs={...state.dfs,phase:'restored-after-error',reason};
        }
        catch(err){state.halted='Spare-radio recovery needs attention: '+err;}
    }
    if(pending&&(pending.kind=='rollback'||pending.kind=='verify'&&(pending.command_started||pending.external))){state.radios[pending.radio].failed=true;state.radios[pending.radio].failure=reason;}
    pending=null;delete state.pending;release();io.completed();history({event:'error',reason});save();
    
}

function event(e,radios){
    if(e.cmd==N.NL80211_CMD_DEL_STATION&&pending?.kind=='verify'&&pending.switch_clients?.[e.msg?.mac]){
        pending.disconnects++;pending.last_problem=now();return;
    }
    if(e.cmd!=N.NL80211_CMD_RADAR_DETECT)return;
    let msg=e.msg??{};
    if(pending?.kind=='cac'&&msg.wiphy==pending.helper.phy&&index(pending.cac_target.members,msg.wiphy_freq)>=0){
        if(msg.radar_event==1)pending.cac_seen=true;
        if(msg.radar_event==0)pending.radar=true;
        return;
    }
    if(msg.radar_event!=0)return;
    let r=filter(radios,r=>r.phy==msg.wiphy&&index(r.current.members,msg.wiphy_freq)>=0)[0];
    if(!r)return;
    if(pending&&pending.radio!=r.name){abort('Radar invalidated operation reservation',true);}
    if(!pending)pending={radio:r.name,source:r.current,target:r.current,before:{...r.authorized},fingerprint:r.fingerprint,disconnects:0};
    clear_bans();
    if(fs.stat(JOURNAL))try{restore_preparation();}catch(err){history({event:'helper-recovery-deferred',reason:''+err});}
    pending.kind='reconcile';pending.started=now();pending.external=true;pending.switch_clients={};
    state.pending='radar evacuation';state.status='Radar evacuation: waiting for the driver to establish legal service';
    history({event:'radar-evacuation',radio:r.name,channel:channel(msg.wiphy_freq)});lease(90,state.status);save();
}
function tick(radios){operation(radios);if(pending)delete pending.observation_failed_since;}
return {start,tick,abort,event,reassess,busy:()=>pending!=null,pending:()=>pending};
};
