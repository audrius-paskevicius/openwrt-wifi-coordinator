import * as system_fs from 'fs';
import * as nl from 'nl80211';
import {group,permitted,channel,frequency,neighbor,quiet_ready} from './policy.uc';
export function scan_cost(r,duration) {
    if(!length(r.clients))return 0;
    // Link rates are a service-capacity proxy, not measured goodput. Preserve
    // higher-capacity client links when another radio can provide the evidence.
    return ((r.client_capacity>0?r.client_capacity:100*length(r.clients))+max(0,r.mbps ?? 0))*(duration ?? 0.25);
};
export function create_survey(io) {
let fs=io.fs ?? system_fs;
let cfg=io.cfg,state=io.state,now=io.now,precise=io.precise,save=io.save,request=io.request,coordination_ready=io.coordination_ready,dfs_mode=io.dfs_mode,allclients=io.allclients,inventory=io.inventory,history=io.history,history_store=io.history_store,rates=io.rates,quiet_since=io.quiet_since;
let N=nl.const,pending=null,scan_result=null;
let scan_ended={},scan_duration={};
function lease(seconds,reason){io.lease(seconds,reason,pending?.scanner?[pending.scanner.name]:[]);}
function release(){io.release();}
function eligible(r,ignore_gap){
    if(now()<(state.radios[r.name]?.scan_until ?? 0))return false;
    if(!length(r.clients))return true;
    if(cfg.scan_policy=='idle')return false;
    if(cfg.scan_policy=='low_traffic')return (rates[r.name]??1000)<=cfg.max_mbps&&quiet_ready(quiet_since[r.name],now(),cfg.quiet_seconds);
    let gap=max(cfg.scan_gap,(scan_duration[r.name]??0)*(100-cfg.scan_duty)/cfg.scan_duty);
    return ignore_gap||scan_ended[r.name]==null||precise()-scan_ended[r.name]>=gap;
}
function find_scanner(radios,freqs,ignore_gap) {
    let choices=[];
    for(let r in radios) {
        if(r.unsafe || cfg.scanner && r.name!=cfg.scanner) continue;
        if(!eligible(r,true))continue;
        let supported=true;
        for(let f in freqs) if(!r.caps[f]||r.caps[f].disabled) supported=false;
        if(supported) push(choices,r);
    }
    let best=sort(choices,(a,b)=>scan_cost(a,state.radios[a.name]?.scan_duration)-scan_cost(b,state.radios[b.name]?.scan_duration))[0];
    // A serving gap is not a reason to borrow a more disruptive scanner. The
    // job scheduler can visit another ready band while this scanner serves.
    return best&&(ignore_gap||eligible(best,false))?best:null;
}
function record_visit(){
    let name=pending.scanner.name,duration=max(0.01,precise()-(pending.clock_started ?? precise()));
    scan_ended[name]=precise();scan_duration[name]=duration;
    let s=state.radios[name];s.scan_duration=s.scan_duration==null?duration:0.7*s.scan_duration+0.3*duration;
}
function scan(radios) {
    coordination_ready();
    let freqs=[],required=[];
    let rules=request(N.NL80211_CMD_GET_REG,0,{}).reg_rules ?? [];
    // Cover adjacent 2.4 GHz channels as well, not merely the three candidate centers.
    for(let r in radios) if(r.config.managed) {
        let valid=[],dm=dfs_mode(r);
        for(let w in r.config.widths)for(let ch in r.config.channels){
            let f=frequency(ch,r.band),g=group(f,w);
            if(permitted(g,r.caps,rules,r.config.channels,dm))for(let m in g.members)if(index(valid,m)<0)push(valid,m);
        }
        for(let f in valid)if(index(required,f)<0)push(required,f);
        let channels=r.band=='2g'?[1,2,3,4,5,6,7,8,9,10,11,12,13,14]:map(valid,f=>channel(f));
        for(let ch in channels) {let f=frequency(ch,r.band);if(index(freqs,f)<0)push(freqs,f);}
    }
    freqs=filter(freqs,f=>length(filter(radios,r=>r.caps[f]&&!r.caps[f].disabled))>0);
    // Adjacent channels improve visibility but must not require interrupting an
    // occupied radio when the eligible scanner cannot tune them.
    state.scan_omitted=cfg.scan_policy=='paced'?[]:filter(freqs,f=>index(required,f)<0&&!find_scanner(radios,[f]));
    freqs=filter(freqs,f=>index(state.scan_omitted,f)<0);
    let jobs=[],deferred=[];
    for(let band in ['2g','5g']){
        let bandfreq=filter(freqs,f=>(f<3000?'2g':'5g')==band);
        for(let start=0;start<length(bandfreq);){
            // Passive DFS visits are kept separate and short on mwifiex.
            let restricted=f=>!!length(filter(radios,r=>r.caps[f]?.radar||r.caps[f]?.no_ir));
            let end=start+1;
            if(cfg.scan_policy!='paced'&&!restricted(bandfreq[start]))while(end<length(bandfreq)&&end-start<cfg.scan_batch&&!restricted(bandfreq[end]))end++;
            let batch=slice(bandfreq,start,end),scanner=find_scanner(radios,batch);start=end;
            if(!scanner&&cfg.scan_policy!='paced'){
                for(let f in batch)push(deferred,f);
                continue;
            }
            push(jobs,{scanner,frequencies:batch});
        }
    }
    state.scan_deferred=deferred;
    if(!length(jobs)){
        
        state.status='No eligible scanner now; retaining earlier survey history';
        save();return;
    }
    let first=shift(jobs);
    // Reserve only the scanner; other radios remain available for steering.
    pending={kind:'scan-wait',...first,jobs,all_frequencies:freqs,observations:[],seen:{},scanners:{},survey_id:''+time()+':'+now(),attempt:0,started:now()-12,sweep_started:now(),waited:0,before:allclients(radios)};
    lease(70,'Surveying channel occupancy'); state.status='Preparing survey on '+(first.scanner?.name ?? 'the next available radio'); state.pending='scan';save();
}
function advance_scan(radios) {
    if(length(pending.jobs)&&!state.halted){
        let ready=0;
        if(cfg.scan_policy=='paced')for(let i,job in pending.jobs)if(find_scanner(radios,job.frequencies)){ready=i;break;}
        let job=pending.jobs[ready];splice(pending.jobs,ready,1);pending.scanner=job.scanner;pending.frequencies=job.frequencies;pending.attempt=0;pending.last_wait=null;
        pending.kind='scan-wait';pending.started=now()-12;
        lease(70,'Surveying the next available portion');state.status='Preparing next scan batch';save();return;
    }
    let completed=map(keys(pending.scanners),f=>int(f));
    let missing=filter(pending.all_frequencies,f=>index(completed,f)<0);
    state.scan_coverage={completed:length(completed),requested:length(pending.all_frequencies),policy:cfg.scan_policy,at:time()};
    state.scan_deferred=missing;
    let expired=cfg.scan_policy=='paced'&&now()-pending.sweep_started>cfg.max_age;
    if(state.halted||expired){
        history({event:'scan-partial',scanned_frequencies:length(completed),missing_frequencies:length(missing)});
        scan_result=null;
        state.status=state.halted?'Survey stopped; completed portions retained':'Survey exceeded the freshness limit; waiting for new measurements';
        pending=null;delete state.pending;release();save();
    }else{
        scan_result={at:now(),observations:pending.observations,frequencies:completed,scanners:pending.scanners,scanner:join(', ',uniq(values(pending.scanners)))};
        scan_result.partial=length(missing)>0;
        history({event:length(missing)?'scan-partial':'scan-complete',scanner:scan_result.scanner,neighbors:length(pending.observations),scanned_frequencies:length(completed),missing_frequencies:length(missing)});
        pending=null;delete state.pending;release();io.complete(scan_result,radios);
    }
    
}
function finish_scan(event) {
    if(!pending||pending.kind!='scan'||event.msg?.wiphy!=pending.scanner.phy) return;
    if(event.cmd==N.NL80211_CMD_SCAN_ABORTED) {
        record_visit();
        if(pending.attempt<2){
            pending.attempt++;pending.kind='scan-wait';pending.started=now()-10;
            lease(70,'Retrying aborted channel scan');state.status='Retrying scan at '+join(', ',pending.frequencies)+' MHz';
            history({event:'scan-retry',frequencies:pending.frequencies,attempt:pending.attempt});save();return;
        }
        
        history({event:'scan-aborted',radio:pending.scanner.name,frequencies:pending.frequencies});
        advance_scan(inventory());return;
    }
    let rows=request(N.NL80211_CMD_GET_SCAN,N.NLM_F_DUMP,{dev:pending.scanner.ifname});
    let radios=inventory(),own={};for(let r in radios) for(let b in r.own_bssids)own[b]=true;
    record_visit();
    let observations=pending.observations,seen=pending.seen;
    for(let x in rows ?? []) {
        let b=x.bss;
        if(!b||b.seen_ms_ago==null||b.seen_ms_ago<0||b.seen_ms_ago>(now()-pending.started+3)*1000||own[lc(b.bssid)])continue;
        let item=neighbor(b);if(item){
            let old=seen[b.bssid];
            if(old){item.signal=max(old.signal,item.signal);for(let key,value in item)old[key]=value;}
            else {push(observations,item);seen[b.bssid]=item;}
        }
    }
    for(let f in pending.frequencies)pending.scanners[f]=pending.scanner.name;
    // Persist immediately, before the next batch can be deferred or aborted.
    // Coalesce one sweep into one bounded history frame, with per-bin times.
    history_store.survey(observations,map(keys(pending.scanners),f=>int(f)),pending.survey_id,pending.frequencies);
    let present=allclients(radios),missing=filter(keys(pending.scan_clients ?? {}),m=>!present[m]);
    if(length(missing)){
        pending.kind='scan-recovery';pending.started=now();
        state.status='Survey paused while the scanned radio clients reconnect';save();return;
    }
    advance_scan(radios);
}
function scan_recovery(radios) {
    if(pending?.kind!='scan-recovery')return false;
    let present=allclients(radios),missing=filter(keys(pending.scan_clients ?? {}),m=>!present[m]);
    lease(70,'Checking clients after a scan visit');
    if(length(missing)&&now()-pending.started<15)return true;
    if(length(missing)){
        state.radios[pending.scanner.name].scan_until=now()+60;
        history({event:'scan-client-unconfirmed',radio:pending.scanner.name,missing_count:length(missing)});
    }else history({event:'scan-client-recovered',radio:pending.scanner.name});
    advance_scan(radios);return true;
}

function tick(radios){if(!pending)return;let t=now();if(scan_recovery(radios))return;
    if(pending.kind=='scan-wait'&&t-pending.started>=12){
        let r=find_scanner(radios,pending.frequencies);
        if(!r&&cfg.scan_policy=='paced'){
            // Try another ready job instead of blocking other bands behind a busy AP.
            for(let i,job in pending.jobs){
                let other=find_scanner(radios,job.frequencies);if(!other)continue;
                pending.jobs[i]={frequencies:pending.frequencies};pending.frequencies=job.frequencies;pending.attempt=0;r=other;break;
            }
        }
        if(!r){
            if(cfg.scan_policy=='paced'&&t-pending.sweep_started<cfg.max_age){
                let resting=!!find_scanner(radios,pending.frequencies,true);
                if(!resting)pending.waited+=max(1,t-(pending.last_wait ?? t-1));
                pending.last_wait=t;
                if(resting||pending.waited<cfg.scan_wait){
                    state.status=resting?'Giving the radio serving time between scan visits':'Survey waiting for an eligible scanner; '+pending.waited+' of '+cfg.scan_wait+' wait seconds used';
                    lease(70,state.status);save();return;
                }
            }
            advance_scan(radios);return;
        }
        if(cfg.scan_policy=='paced'&&t-pending.sweep_started>=cfg.max_age){pending.jobs=[];advance_scan(radios);return;}
        pending.scanner=r;lease(70,'Scanning '+r.name);
        pending.scan_clients={...r.authorized};
        pending.kind='scan';pending.started=t;pending.clock_started=precise();
        // Broadcast probes only; never supply stored network names. Kernel/driver
        // still enforce scan restrictions; explicitly retain passive mode for NO-IR.
        let active=cfg.scan_type=='active'&&!length(filter(pending.frequencies,f=>r.caps[f]?.no_ir||r.caps[f]?.radar));
        // This ucode nl80211 binding encodes SSIDs as NUL-terminated strings;
        // [''] becomes a one-byte SSID, not a wildcard. Use iw's correct encoder.
        // Interface names and frequencies were validated/discovered above.
        let pipe=fs.popen('iw dev '+r.ifname+' scan trigger freq '+join(' ',pending.frequencies)+(active?'':' passive')+' 2>&1','r');
        if(!pipe)die('Cannot invoke iw scan trigger');
        let output=pipe.read('all'),result=pipe.close();
        if(result!=0)die('Scan trigger failed: '+output);
        state.status=(active?'Active':'Passive')+' scan in progress on '+r.name;save();
    }else if(pending.kind=='scan'&&t-pending.started>45){
        try{request(N.NL80211_CMD_ABORT_SCAN,0,{dev:pending.scanner.ifname});}catch(e){}
        die('Scan timeout; no channel change performed');

    }
}
function cancel(reason){
    if(pending?.kind=='scan')try{request(N.NL80211_CMD_ABORT_SCAN,0,{dev:pending.scanner.ifname});}catch(e){}
    pending=null;delete state.pending;release();state.status=reason;save();
}
return {start:scan,tick,event:finish_scan,cancel,busy:()=>pending!=null,phase:()=>pending?.kind};
};
