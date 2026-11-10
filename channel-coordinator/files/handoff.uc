// Shared client-move policy for channel work and preferred-radio steering.
import {force_signal_ok} from './policy.uc';
export function protected_client(mac,list){
    return index(map(type(list)=='array'?list:split(list ?? '',/\s+/),x=>lc(x)),lc(mac))>=0;
};
export function target_ok(measurements,node,minimum){
    let fresh=filter(measurements ?? [],m=>m.node==node&&m.age>=0&&m.age<=30000&&m.rcpi>0&&m.rcpi<=220);
    if(!length(fresh))return true;
    let r=fresh[0].rssi;if(r>2147483647)r-=4294967296;
    return r<0&&r>=minimum;
};
export function next_step(s,t,cfg){
    let elapsed=t-s.started,wait=cfg.handoff_wait ?? 90;
    if(elapsed>=wait)return 'expired';
    if(elapsed>=int(wait/3)&&!s.strong_sent&&cfg.escalation!='gentle')return 'strong';
    if(elapsed>=int(wait*2/3)&&s.force_sent==null&&cfg.escalation=='decisive')return 'force';
    return 'wait';
};
export function begin_attempt(shared,mac,target,t,cfg,extra){
    let cooldown=cfg.handoff_cooldown ?? 300,limit=cfg.handoff_attempts ?? 3;
    let memory=shared.handoff_attempts ?? {};shared.handoff_attempts=memory;
    for(let k,v in memory)if(t-v.at>=cooldown*limit)delete memory[k];
    let key=lc(mac)+'|'+target,old=memory[key];
    if(!extra&&old){
        if(old.count>=limit)return 'attempt-limit';
        if(t-old.at<cooldown)return 'cooldown';
    }
    if(!old&&length(memory)>=256)return 'attempt-limit';
    memory[key]={at:t,count:min(limit+1,(old?.count ?? 0)+1)};
    return null;
};
export function reserve_force(shared,mac,measurements,target,source_signal,same_band,t,cfg){
    if(protected_client(mac,cfg.protected_clients))return false;
    let forced=shared.forced ?? {};shared.forced=forced;
    if(t-(forced[mac] ?? -100000)<300||forced[mac]==null&&length(forced)>=256)return false;
    // A source-only proximity estimate applies only within the same band.
    if(!force_signal_ok(measurements,target,same_band?source_signal:null,cfg.target_min ?? -72,cfg.source_min ?? -65))return false;
    forced[mac]=t;return true;
};
export function transition_request(mac,nr,token,strong){
    if(type(nr)!='string'||length(nr)<26||length(nr)%2||!match(nr,/^[a-fA-F0-9]+$/))die('Invalid neighbor report');
    let report=substr(nr,0,26);
    for(let p=26;p<length(nr);){
        if(p+4>length(nr))die('Truncated neighbor subelement');
        let size=hex(substr(nr,p+2,2))*2+4;
        if(p+size>length(nr))die('Truncated neighbor subelement');
        if(lc(substr(nr,p,2))!='03')report+=substr(nr,p,size);
        p+=size;
    }
    return {addr:mac,disassociation_imminent:!!strong,disassociation_timer:0,
        validity_period:100,neighbors:[report+'0301ff'],abridged:true,dialog_token:token,
        mbo_reason:0,cell_pref:0,reassoc_delay:0};
};
