// Restart recovery observes existing APs; it never moves or restarts a radio.
const CHECKING='Checking radios after interrupted operation';
export function schedule_recovery(state,t) {
    state.recovery_attempts=min(4,(state.recovery_attempts ?? 0)+1);
    state.recovery_retry_at=t+[0,60,120,240,300][state.recovery_attempts];
};
export function begin_restart_check(state,t,retry) {
    // A genuine recovery error must never be cleared by another service restart.
    if(state.halted&&state.halted!=CHECKING&&!retry)return false;
    state.restart_check={started:t,radios:keys(state.radios ?? {})};
    state.halted=CHECKING;state.status=CHECKING;
    return true;
};
export function check_restart(state,radios,enabled,t,journal,timeout) {
    let check=state.restart_check;
    if(!check)return null;
    if(state.halted!=CHECKING){delete state.restart_check;return null;}
    let expected=filter(check.radios,n=>index(enabled,n)>=0),problems=[];
    if(journal)push(problems,'temporary configuration still needs restoration');
    for(let name in expected){
        let r=filter(radios,r=>r.name==name)[0];
        if(!r||r.unsafe||!length(r.aps)||length(filter(r.aps,a=>a.status?.status!='ENABLED'||a.status?.dfs?.cac_active)))
            push(problems,name+' is not ready');
        else if(state.radios[name]?.failed)push(problems,name+' has unresolved recovery');
        else if(!r.current?.freq||!r.current?.width||!r.current?.center||
            length(filter(r.aps,a=>a.status.freq&&a.status.freq!=r.current.freq)))
            push(problems,name+' has inconsistent channel state');
    }
    let signature=join('|',map(sort(expected),name=>{
        let r=filter(radios,r=>r.name==name)[0];
        return name+':'+sprintf('%J',r?.current);
    }));
    if(length(problems)){delete check.stable_since;delete check.signature;}
    else if(check.signature!=signature){check.signature=signature;check.stable_since=t;}
    if(!length(problems)&&t-check.stable_since>=30){
        for(let name in expected)delete state.radios[name].unavailable;
        delete state.halted;delete state.restart_check;
        delete state.recovery_retry_at;delete state.recovery_attempts;
        state.status='Radio state verified after restart; coordination resumed';
        return 'resumed';
    }
    if(t-check.started>=timeout){
        state.halted='Restart recovery needs attention: '+(length(problems)?join('; ',problems):'radio state did not settle');
        state.status=state.halted;delete state.restart_check;
        schedule_recovery(state,t);
        return 'failed';
    }
    state.status=length(problems)?'Waiting for restart recovery: '+join('; ',problems):'Radios are ready; checking stability before resuming';
    return 'waiting';
};
