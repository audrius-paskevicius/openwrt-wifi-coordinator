// Shared decision policy. No hardware calls, configuration writes or timers.
import {same, same_block, move_method} from './policy.uc';

export function reservations(pending) {
    if (!pending) return [];
    let names = [pending.radio, pending.helper?.name, pending.spare, pending.handoff_target,pending.handoff_source,pending.rescue?.target];
    return uniq(filter(names, n => type(n) == 'string' && length(n)));
};

export function movement_cost(model, target, cfg) {
    if (same(model.current, target)) return 0;
    if (!model.config) return 0; // callers without execution facts cannot price a move
    // Cost has the same units as the configured admission margin, not Mbps.
    // It is a conservative decision preference, not a predicted outage length.
    let base = cfg.improvement ?? 3;
    let occupied = (model.clients ?? 0) > 0;
    let restart = model.config && move_method(model.config, model.current, target) != 'csa';
    let primary = same_block(model.current, target);
    return base * (occupied ? (restart ? 3 : 1) : 0.25) * (primary ? 2 : 1);
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
