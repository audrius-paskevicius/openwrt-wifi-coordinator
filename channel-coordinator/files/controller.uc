// Shared decision policy. No hardware calls, configuration writes or timers.
import {same, same_block, move_method} from './policy.uc';

export function reservations(pending) {
    if (!pending) return [];
    let names = [pending.radio, pending.helper?.name, pending.spare, pending.handoff_target,pending.handoff_source,pending.rescue?.target];
    return uniq(filter(names, n => type(n) == 'string' && length(n)));
};

export function movement_effect(model, target, cfg) {
    if(same(model.current,target)||!model.config)return {cost:0,clients:0,helper_clients:0};
    let base=cfg.improvement ?? 3,n=max(0,model.clients ?? 0),prep=target.preparation;
    let restart=move_method(model.config,model.current,target)!='csa'||prep&&prep.radio==model.name;
    let fraction=max(0,min(1,model.disruption?.fraction ?? 0));
    let gentle=0.5+0.5*n,hard=1+2*n;
    let cost=base*(n?(restart?hard:gentle+(hard-gentle)*fraction):0.25);
    if(same_block(model.current,target))cost*=2;
    let helpers=prep&&prep.radio!=model.name?max(0,prep.clients ?? 0):0;
    if(prep&&prep.radio!=model.name)cost+=base*(helpers?1+2*helpers:0.25);
    return {cost,clients:n,helper_clients:helpers,helper:prep?.radio,method:restart?'restart':'csa',observed_disconnect_fraction:fraction};
};
export function movement_cost(model,target,cfg){return movement_effect(model,target,cfg).cost;};
export function learning_scope(r){
    // Execution temporarily resolves the method for a particular width. Only
    // administrator intent and hardware changes should reset the memory.
    return sprintf('%J',[r.phy,r.band,r.config.hardware_widths,r.config.widths,r.config.requested_method ?? r.config.method,r.config.requested_width_method ?? r.config.width_method,r.dfs_region]);
};
export function refresh_learning(s,r,t){
    let scope=learning_scope(r);
    for(let key in ['width_limit','disruption']){
        let m=s[key];if(!m)continue;
        if(m.scope!=null&&m.scope!=scope||t-(m.at ?? m.until ?? t)>=86400)delete s[key];
        else m.scope=scope;
    }
};
export function learn_disruption(previous,clients,departed,t,scope){
    let fresh=previous&&previous.scope==scope&&t-previous.at<86400;
    let ratio=min(1,max(0,departed)/(1.0*max(1,clients)));
    return {at:t,scope,samples:min(8,(fresh?previous.samples:0)+1),
        fraction:fresh?(previous.fraction*3+ratio)/4:ratio};
};

export function action_valid(action, radio, t, max_age) {
    if (!radio || radio.fingerprint != action.fingerprint) return false;
    if (action.evidence_at != null && t - action.evidence_at > max_age) return false;
    return same(radio.current, action.source);
};

export function width_retry(previous,t,base) {
    let attempts=previous&&t-(previous.at ?? 0)<86400?min(6,(previous.attempts ?? 1)+1):1;
    return {at:t,attempts,until:t+min(21600,base*(1 << (attempts-1)))};
};

export function return_summary(before, radios, preferred) {
    let on = {}, elsewhere = {}, present = {};
    for (let r in radios) for (let mac in keys(r.authorized ?? {})) {
        present[mac] = true;
        if (r.name == preferred) on[mac] = true; else elsewhere[mac] = true;
    }
    let returned=0, other=0, absent=0;
    for (let mac in keys(before)) {
        if (on[mac]) returned++;
        else if (present[mac]) other++;
        else absent++;
    }
    return {returned, elsewhere:other, absent, total:length(before)};
};

export function create_returns(io) {
    let pending = [];
    function add(action, preferred) {
        action={...action,before:action.return_before ?? action.before};
        if (!preferred || action.radio != preferred || !length(action.before ?? {})) return;
        // A newer placement supersedes the old follow-up on that radio.
        pending = filter(pending, x => x.radio != action.radio);
        push(pending, {...action, preferred, since:io.now(), until:io.now()+120, last:null});
    }
    function tick(radios, states) {
        let next=[];
        for (let p in pending) {
            let result=return_summary(p.before,radios,p.preferred), rejected=0;
            for (let mac in keys(p.before)) if ((states?.[mac]?.response ?? 0)>0 && states[mac].last_btm>=p.since) rejected++;
            result.declined=rejected;
            let signature=sprintf('%J',result);
            if(signature!=p.last || io.now()>=p.until) {
                io.history({event:'client-return',operation:p.id,radio:p.radio,...result,
                    reason:result.returned==result.total?'All tracked clients returned':
                        io.now()>=p.until?'Return observation ended; normal preference continues':'Observing client return'});
                p.last=signature;
            }
            if(result.returned<result.total && io.now()<p.until)push(next,p);
        }
        pending=next;
    }
    return {add,tick,busy:()=>length(pending)>0,radios:()=>map(pending,p=>p.radio)};
};
