import {begin_restart_check,check_restart} from '../channel-coordinator/files/recovery.uc';
let checks=0;function check(v,s){if(!v)die('FAIL: '+s+'\n');checks++;}
let state,radio;
function setup(){
    state={radios:{a:{unavailable:true}}};
    radio={name:'a',current:{freq:5500,center:5530,width:80},aps:[{status:{status:'ENABLED',freq:5500}}]};
    begin_restart_check(state,100);
}
function tick(t,radios,journal){return check_restart(state,radios ?? [radio],['a'],t,!!journal,780);}
setup();check(tick(100)=='waiting'&&state.halted,'restart pauses planning while observation begins');
check(tick(129)=='waiting','one healthy sample does not bypass stability observation');
check(tick(130)=='resumed'&&!state.halted&&!state.restart_check&&!state.radios.a.unavailable,'stable AP resumes automatically and clears stale unavailable flag');
setup();tick(100);radio.current={freq:5745,center:5775,width:80};radio.aps[0].status.freq=5745;
check(tick(129)=='waiting'&&tick(130)=='waiting'&&tick(159)=='resumed','channel change restarts the stability interval');
setup();tick(100);check(tick(120,[])=='waiting','absent AP interrupts stability observation');
check(tick(130)=='waiting'&&tick(160)=='resumed','returning AP receives a new full observation');
setup();check(tick(100,[radio],true)=='waiting'&&tick(880,[radio],true)=='failed'&&state.halted,'unrestored journal cannot auto-clear');
check(!begin_restart_check(state,900)&&state.halted,'another restart cannot erase a genuine recovery failure');
setup();radio.aps[0].status.status='DFS';check(tick(100)=='waiting'&&tick(880)=='failed','unfinished radar check cannot pass as a healthy AP');
setup();radio.aps[0].status.freq=5580;check(tick(880)=='failed','hostapd and kernel frequency mismatch remains stopped');
setup();radio.unsafe=true;check(tick(880)=='failed','unsupported radio state remains stopped');
setup();state.radios.a.failed=true;check(tick(880)=='failed'&&state.radios.a.failed,'existing per-radio recovery failure is not erased');
setup();state.radios.a.rejected=[{until:9999}];tick(100);tick(130);
check(length(state.radios.a.rejected)==1,'automatic resume preserves timed destination exclusions');
setup();check_restart(state,[],[],100,false,780);
check(check_restart(state,[],[],130,false,780)=='resumed','administrator-disabled AP does not block recovery');
setup();state.halted='Spare-radio restoration failed';check(tick(130)==null&&state.halted=='Spare-radio restoration failed','new recovery fault cannot be cleared by an older check');
setup();tick(100);check(begin_restart_check(state,110)&&tick(110)=='waiting'&&tick(140)=='resumed','another interrupted operation starts a fresh observation');
setup();check(tick(800,[])=='waiting','startup permits long DFS listening period');
check(tick(801)=='waiting'&&tick(831)=='resumed','long radar preparation can finish without manual acknowledgement');
print('PASS: '+checks+' restart recovery checks\n');
