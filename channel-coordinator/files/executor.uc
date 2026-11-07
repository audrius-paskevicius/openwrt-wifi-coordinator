import * as system_fs from 'fs';
import * as nl from 'nl80211';
import {channel,group,same,overlap,permitted,uses_dfs,dfs_ready,preparation_text,reconfigure_text,same_network,force_signal_ok,private_ipv4,liveness_progress,move_method,quiet_ready} from './policy.uc';
export function data_flow(previous,current){
    if(!previous||!current)return false;
    let reset=current.rx<previous.rx||current.tx<previous.tx;
    return current.rx-(reset?0:previous.rx)>4096&&current.tx-(reset?0:previous.tx)>4096;
};
export function create_executor(io) {
let fs=io.fs ?? system_fs;
let cfg=io.cfg,state=io.state,now=io.now,save=io.save,lease=io.lease,release=io.release,call=io.call,request=io.request,config_fingerprint=io.config_fingerprint,phy_caps=io.phy_caps,allclients=io.allclients,empty_interface=io.empty_interface,apply_empty_config=io.apply_empty_config,restore_preparation=io.restore_preparation,private_json=io.private_json,coordination_ready=io.coordination_ready,dfs_mode=io.dfs_mode,history=io.history,boot=io.boot;
let N=nl.const,JOURNAL='/tmp/channel-coordinator-cac.json',pending=null;
function log(s){io.log(s);}
function reconnect_allowed(r){return cfg.allow_reconnect&&r.config.occupied=='handoff'&&length(r.aps)==1&&!r.unsafe&&
    !length(filter(keys(r.clients),m=>index(cfg.protected_clients,lc(m))>=0));}
function move_allowed(r){return !length(r.clients)||pending?.reconnect&&reconnect_allowed(r)||r.config.method=='csa'&&(r.config.occupied=='handoff'||r.config.occupied=='quiet'&&quiet_ready(io.quiet_since[r.name],now(),cfg.quiet_seconds));}
function handoff_before_move(clients,method,policy,ready){return clients>0&&method!='csa'&&policy=='handoff';}
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
    let widthbit=g.width==80?8:g.width==40?4:2;
    let suitable=filter(radios,h=>h.config.managed&&!h.unsafe&&h.band=='5g'&&(h.radar_widths&widthbit)&&length(h.aps)==1&&
        (!cfg.dfs_helper||h.name==cfg.dfs_helper)&&dfs_mode(h)=='prepare'&&
        permitted(g,h.caps,rules,h.config.channels,'prepare')&&
        preparation_text(fs.readfile('/var/run/hostapd-phy'+h.phy+'.conf'),g));
    let choices=filter(suitable,h=>!length(h.clients));
    choices=sort(choices,(a,b)=>(a.name==r.name?1:0)-(b.name==r.name?1:0));
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
    if(config_fingerprint(h.name)!=h.fingerprint)die('Spare radio settings changed');
    if(!empty_interface(h.ifname)){
        pending.cac_idle_wait=pending.cac_idle_wait ?? now();
        if(now()-pending.cac_idle_wait>=60)die('Spare radio retains station records; radar preparation deferred');
        state.status='Waiting for spare-radio station records to clear before radar preparation';lease(90,state.status);save();return;
    }
    let path='/var/run/hostapd-phy'+h.phy+'.conf';
    let original=reconfigure_text(fs.readfile(path),h.current,h.band),temporary=preparation_text(original,g);
    if(!original||!temporary)die('Cannot construct live-channel CAC recovery configuration');
    private_json(JOURNAL,{boot,phy:'phy'+h.phy,ifname:h.ifname,path,original,temporary,source:h.current});
    pending.kind='cac';pending.started=now();pending.helper={name:h.name,phy:h.phy,ifname:h.ifname,source:h.current,fingerprint:h.fingerprint};
    pending.cac_seen=false;
    state.pending='DFS preparation';state.dfs={phase:'listening',helper:h.name,radio:r.name,channel:channel(g.freq),width:g.width,started:now(),timeout:cfg.cac_timeout};
    state.status='Starting radar check on '+h.name+'; other radios continue serving clients';
    lease(90,'Spare radio is listening for radar');save();
    if(!fs.writefile(path,temporary))die('Cannot write temporary CAC configuration');
    apply_empty_config('phy'+h.phy,path,h.ifname);
    history({event:'cac-start',helper:h.name,radio:r.name,channel:channel(g.freq),width:g.width});
}
function handoff_destination(r,radios,preferred) {
    if(length(r.aps)!=1)return null;
    let a=r.aps[0],ac=a.config;
    // Keep security and LAN membership identical; credentials never enter status/logs.
    let targets=filter(radios,h=>h.name!=r.name&&!h.unsafe&&h.band==r.band&&length(h.aps)==1&&
        same_network(h.aps[0].config,ac)&&
        (h.aps[0].status.airtime?.utilization ?? 0)<180);
    return sort(targets,(a,b)=>(a.name==preferred?-100:0)-(b.name==preferred?-100:0)+length(a.clients)-length(b.clients))[0];
}
function handoff(r,radios,preferred,strong) {
    for(let mac in keys(r.clients))pending.before[mac]=true;
    if(!pending.handoff_clients){pending.handoff_clients=filter(keys(r.clients),m=>!pending.only_client||pending.only_client==m);pending.handoff_source=r.name;}
    let target=handoff_destination(r,radios,preferred);if(!target)return 0;
    pending.handoff_target=target.name;
    let nr=call('hostapd.'+target.ifname,'rrm_nr_get_own').value?.[2];
    if(!match(nr ?? '',/^[a-fA-F0-9]{26,}$/))return 0;
    let stations=call('usteer','connected_clients')['hostapd.'+r.ifname] ?? {},count=0;
    for(let mac in keys(r.clients)){
        if(pending.only_client&&pending.only_client!=mac)continue;
        // Explicit manual gentle trials are allowed; background optimisation
        // must not repeatedly interrupt a protected work device's failed roam.
        if(index(cfg.protected_clients,lc(mac))>=0&&ARGV[0]!='--test-handoff')continue;
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
            if(pending.only_client&&pending.only_client!=mac)continue;
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
function capture_liveness(radios,source) {
    let addresses={};
    for(let line in split(fs.readfile('/tmp/dhcp.leases') ?? '','\n')){
        let fields=split(trim(line),/\s+/);
        if(length(fields)>=3&&private_ipv4(fields[2]))addresses[lc(fields[1])]=fields[2];
    }
    let clients=keys(pending.before),probes={},attempts=0,data={};
    for(let r in radios)for(let mac in clients)if(r.client_data?.[mac])data[mac]=r.client_data[mac];
    clients=sort(clients,(a,b)=>(source.clients[b]?1:0)-(source.clients[a]?1:0));
    for(let mac in clients){
        let ip=addresses[lc(mac)];if(!ip||attempts>=8)continue;attempts++;
        if(ping_client(ip))probes[mac]=ip;
    }
    // No addresses or identifiers are persisted in history/status. Unprobeable
    // clients require a longer association watch, not an invented success.
    return {probes,data,unprobed:length(clients)-length(probes),failed:{}};
}
function reconfigure_idle(r,g) {
    // Explicit opt-in, AP-only HT/VHT configurations, no global network reload.
    if(length(r.clients))die('Idle reconfiguration requires an empty radio');
    if(!empty_interface(r.ifname))return false;
    let path='/var/run/hostapd-phy'+r.phy+'.conf',original=reconfigure_text(fs.readfile(path),r.current,r.band);
    let content=reconfigure_text(original,g,r.band);
    if(!content)die('Generated hostapd configuration is not supported for idle reconfiguration');
    let backup=path+'.channel-coordinator-before';
    if(!fs.writefile(backup,original)||!fs.chmod(backup,0600))die('Cannot save runtime configuration backup');
    // Preserve permissions: OpenWrt runs hostapd as the unprivileged network user.
    if(!fs.writefile(path,content))die('Cannot update runtime configuration');
    try{apply_empty_config('phy'+r.phy,path,r.ifname);}
    catch(e){
        if(!fs.writefile(path,original))die('Cannot restore runtime configuration after deferred restart');
        if(index(''+e,'Selected radio acquired clients; restart deferred')>=0)return false;
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
    let original=reconfigure_text(fs.readfile(path),r.current,r.band),temporary=reconfigure_text(original,g,r.band);
    if(!original||!temporary)die('Unsupported configuration for brief radio restart');
    if(fs.stat(JOURNAL))die('Another radio recovery journal is active');
    // RAM-only journal: service interruption restores the old live channel.
    // Power loss boots the existing saved UCI configuration instead.
    private_json(JOURNAL,{kind:'reconnect',boot,phy:'phy'+r.phy,ifname:r.ifname,path,original,temporary,source:r.current});
    if(!fs.writefile(path,temporary))die('Cannot write reconnect configuration');
    history({event:'radio-reconnect',radio:r.name,from:channel(r.current.freq),to:channel(g.freq),width:g.width,clients:length(r.clients)});
    io.apply_radio_config('phy'+r.phy,path,r.ifname,true);
}
function switch_radio(r,g) {
    // force=false is essential: never fall back to disabling/restarting the AP.
    return call('hostapd.'+r.ifname,'switch_chan',{freq:g.freq,center_freq1:g.center,center_freq2:0,
        bandwidth:g.width,sec_channel_offset:g.sec,ht:true,vht:r.band=='5g',he:false,
        block_tx:false,bcn_count:cfg.csa_count,force:false});
}
function operation(radios) {
    let t=now();if(!pending)return;
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
            let restored=r&&same(r.current,pending.source),clients=allclients(radios);
            let missing=filter(keys(pending.before),m=>!clients[m]);
            for(let mac,ip in pending.liveness?.probes ?? {})if(!ping_client(ip)&&index(missing,mac)<0)push(missing,mac);
            if(restored&&length(missing)&&t-pending.started<cfg.verify_unprobed){
                state.status='Previous channel restored; waiting for clients to reconnect';save();return;
            }
            restored=restored&&!length(missing);
            history({event:restored?'rollback-verified':'rollback-failed',radio:pending.radio,channel:channel(pending.source.freq)});
            if(restored){
                if(state.halted==pending.own_stop)delete state.halted;
                delete state.radios[pending.radio].failed;
                state.radios[pending.radio].last_attempt=t;
            }
            state.status=restored?'Clients recovered on previous channel; failed destination excluded for six hours':'Recovery needs attention; inspect wireless status';
            clear_bans();io.completed();
            pending=null;delete state.pending;release();save();
            
        }
        return;
    }
    if(index(['cac','restore','handoff','spare-handoff'],pending.kind)>=0)lease(90,'Coordinating radar preparation and client handoff');
    if(pending.kind=='handoff-grace'){
        if(t-pending.started>=12){
            let r=filter(radios,x=>x.name==pending.radio)[0];if(!r)die('Test radio unavailable');
            handoff(r,radios);pending.kind='handoff';pending.started=t;
        }
        return;
    }
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
        let h=pending.helper,caps=phy_caps(h.phy),r=filter(radios,x=>x.name==pending.radio)[0];
        state.dfs.elapsed=t-pending.started;
        let live_status;try{live_status=call('hostapd.'+h.ifname,'get_status');}catch(e){}
        state.status=live_status?.dfs?.cac_active?'Listening for radar on '+h.name+'; other radios continue serving clients':
            'Waiting for confirmed radar clearance on '+h.name;
        if(t-pending.started>20&&live_status?.status=='ENABLED'&&live_status.freq!=pending.target.freq)
            die('Radio did not enter the requested DFS channel; restoring its live source channel');
        if(pending.radar||length(filter(pending.target.members,f=>caps[f]?.dfs_state==1)))die('Radar detected; candidate rejected');
        if(t-pending.started>cfg.cac_timeout)die('Radar check timed out; restoring spare radio');
        let helper=filter(radios,x=>x.name==h.name)[0];
        let targetcaps=r?.caps ?? (pending.radio==h.name?caps:{});
        if(pending.cac_seen&&helper&&same(helper.current,pending.target)&&dfs_ready(pending.target,caps)&&dfs_ready(pending.target,targetcaps)){
            history({event:'cac-shared',helper:h.name,radio:pending.radio,channel:channel(pending.target.freq),elapsed:t-pending.started});
            restore_preparation();pending.kind='restore';pending.started=t;state.dfs.phase='restoring';
            state.status='Radar check passed; restoring spare radio before handoff';save();
        }
        return;
    }
    if(pending.kind=='restore'){
        let h=filter(radios,x=>x.name==pending.helper.name)[0],r=filter(radios,x=>x.name==pending.radio)[0];
        if(t-pending.started>cfg.cac_timeout)die('Spare radio did not return to its original channel');
        if(h&&same(h.current,pending.helper.source)&&r){
            if(!dfs_ready(pending.target,r.caps))die('Shared radar clearance is no longer available');
            state.dfs.phase='ready';state.dfs.completed=t;state.status='DFS block prepared; spare radio restored';
            if(ARGV[0]=='--test-prepare'){
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
        let remaining=pending.only_client?(r.clients[pending.only_client]?1:0):length(r.clients);
        if(ARGV[0]=='--test-handoff'&&!remaining&&forced_relocated(radios)&&handoff_relocated(radios)){
            let destinations=filter(radios,x=>x.name!=r.name&&length(filter(pending.handoff_clients ?? [],m=>x.clients[m])));
            history({event:'handoff-verified',from:r.name,to:join(', ',map(destinations,x=>x.name))});
            state.status='Client handoff verified; radio channels unchanged';clear_bans();pending=null;delete state.pending;release();save();io.completed();return;
        }
        if(ARGV[0]=='--test-handoff'&&t-pending.started>=cfg.handoff_wait)die('Client handoff test did not complete');
        let quiet_csa=ARGV[0]!='--test-handoff'&&r.config.method=='csa'&&move_allowed(r)&&forced_relocated(radios);
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
        if(handoff_before_move(length(r.clients),r.config.method,r.config.occupied,move_allowed(r))&&!pending.handoff_done){
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
        pending.kind='verify';pending.started=now();state.pending='verification';state.status='Verifying '+r.config.method+' and client reachability on '+r.name;save();
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
        else switch_radio(r,pending.target);
    }else if(pending.kind=='verify'&&t-pending.started>=5){
        let r=filter(radios,x=>x.name==pending.radio)[0],present=allclients(radios);
        let results={},working={};for(let mac in keys(pending.before)){
            results[mac]=!!present[mac];let live=null;
            for(let ap in radios)if(ap.client_data?.[mac])live=ap.client_data[mac];
            working[mac]=!!present[mac]&&data_flow(pending.liveness?.data?.[mac],live);
        }
        for(let mac,ip in pending.liveness?.probes ?? {}){
            // An inbound ICMP failure cannot overrule fresh bidirectional data.
            results[mac]=!!present[mac]&&(working[mac]||ping_client(ip));working[mac]=results[mac];
        }
        if(pending.reconnect&&t<pending.reconnect_until&&length(filter(values(results),v=>!v))){
            state.status='Waiting for clients to reconnect after the brief radio restart';save();return;
        }
        let progress=liveness_progress(pending.liveness?.failed ?? {},results,t,15);
        if(pending.liveness)pending.liveness.failed=progress.failed;
        let missing=progress.lost;
        if(length(progress.failed))pending.last_problem=t;
        let stable=t-(pending.last_problem ?? pending.started)>=30;
        let channel_ok=r&&same(r.current,pending.target);
        if(r&&!channel_ok&&!same(r.current,pending.source)&&!pending.external){
            pending.kind='reconcile';pending.started=t;state.pending='external recovery';
            state.status='Driver changed the operating channel; reconciling actual placement';save();return;
        }
        if(!channel_ok&&t-pending.started<30){state.status='Waiting for the announced channel to become active';save();return;}
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
            s.rejected=filter(s.rejected ?? [],x=>x.until>t&&!same(x.target,pending.target));
            push(s.rejected,{target:pending.target,until:t+21600,reason:'Driver left the original channel/width unchanged'});
            while(length(s.rejected)>16)shift(s.rejected);
            if(pending.reconnect)restore_preparation();
            history({event:'switch-ignored',radio:pending.radio,from:channel(pending.source.freq),to:channel(pending.target.freq),width:pending.target.width,method:pending.method});
            clear_bans();pending=null;delete state.pending;release();
            state.status='Driver left channel unchanged; target deferred and clients verified';io.completed();save();
            
            return;
        }
        let entry={event:ok?(pending.external?'external-recovery-verified':'switch-verified'):'switch-recovery',radio:pending.radio,
            from:channel(pending.source.freq),to:channel(pending.target.freq),width:pending.target.width,
            clients_missing:length(missing),clients_unproven:unknown,disconnect_events:pending.disconnects,method:pending.method};
        history(entry);log(sprintf('%J',entry));
        let s=state.radios[pending.radio];if(ok){s.last_move=t;state.last_move=t;delete s.failed;delete s.unavailable;}
        if(!ok){
            s.last_attempt=t;s.failed=true;
            if(pending.method=='csa')s.csa_failed_until=t+21600;
            pending.own_stop='Service verification failed';
            s.rejected=filter(s.rejected ?? [],x=>x.until>t&&!same(x.target,pending.target));
            push(s.rejected,{target:pending.target,until:t+21600,reason:'Client connectivity did not verify'});
            while(length(s.rejected)>16)shift(s.rejected);
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
function abort(e) {
    
    
    let reason=''+e;log(reason);state.status=reason;
    clear_bans();
    if(pending?.radio){state.radios[pending.radio].last_attempt=now();state.last_action=now();}
    if(fs.stat(JOURNAL)){
        try{restore_preparation();if(!pending?.reconnect)state.dfs={...state.dfs,phase:'restored-after-error',reason};}
        catch(err){state.halted='Spare-radio recovery needs attention: '+err;}
    }
    if(pending?.kind=='verify'){state.radios[pending.radio].failed=true;state.radios[pending.radio].failure=reason;}
    pending=null;delete state.pending;release();io.completed();history({event:'error',reason});save();
    
}

function event(e,radios){
    if(e.cmd==N.NL80211_CMD_DEL_STATION&&pending?.kind=='verify'&&pending.switch_clients?.[e.msg?.mac]){
        pending.disconnects++;pending.last_problem=now();return;
    }
    if(e.cmd!=N.NL80211_CMD_RADAR_DETECT)return;
    let msg=e.msg??{};
    if(pending?.kind=='cac'&&msg.wiphy==pending.helper.phy&&index(pending.target.members,msg.wiphy_freq)>=0){
        if(msg.radar_event==1)pending.cac_seen=true;
        if(msg.radar_event==0)pending.radar=true;
        return;
    }
    if(msg.radar_event!=0)return;
    let r=filter(radios,r=>r.phy==msg.wiphy&&index(r.current.members,msg.wiphy_freq)>=0)[0];
    if(!r)return;
    if(pending&&pending.radio!=r.name){abort('Radar invalidated operation reservation');}
    if(!pending)pending={radio:r.name,source:r.current,target:r.current,before:{...r.authorized},fingerprint:r.fingerprint,disconnects:0};
    clear_bans();
    if(fs.stat(JOURNAL))try{restore_preparation();}catch(err){history({event:'helper-recovery-deferred',reason:''+err});}
    pending.kind='reconcile';pending.started=now();pending.external=true;pending.switch_clients={};
    state.pending='radar evacuation';state.status='Radar evacuation: waiting for the driver to establish legal service';
    history({event:'radar-evacuation',radio:r.name,channel:channel(msg.wiphy_freq)});lease(90,state.status);save();
}
return {start,tick:operation,abort,event,busy:()=>pending!=null,pending:()=>pending};
};
