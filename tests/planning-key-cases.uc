let T=100,state={radios:{radio0:{last_move:0,rejected:[]}}};
let files={a:'original'},fs={readfile:p=>files.a},scan_result={stamps:{'5g':50}};
let steering={reserved:()=>[]},returns={radios:()=>[]},radars=[];
let radar={records:()=>radars},regulatory={};
function now(){return T;}
let radios=[{name:'radio0',current:{freq:5180,width:80,center:5210},config:{managed:true},fingerprint:'a',
 clients:{one:true},authorized:{one:true},caps:{'5180':{dfs_state:2,dfs_time:1}},mbps:1}];
let n=0;function check(v,s){if(!v)die('FAIL: '+s);n++;}
let first=planning_key(radios,null);
radios[0].mbps=20;radios[0].caps[5180].dfs_time=100;radios[0].config.csa_recovery_left=20;
check(planning_key(radios,null)==first,'changing counters do not starve calculation');
function changed(fn,undo,label){fn();check(planning_key(radios,null)!=first,label);undo();check(planning_key(radios,null)==first,'fixture restored');}
changed(()=>radios[0].clients.two=true,()=>delete radios[0].clients.two,'new client invalidates');
changed(()=>radios[0].caps[5180].dfs_state=0,()=>radios[0].caps[5180].dfs_state=2,'DFS permission invalidates');
changed(()=>radios[0].current.freq=5500,()=>radios[0].current.freq=5180,'placement change invalidates');
changed(()=>files.a='changed',()=>files.a='original','configuration change invalidates');
changed(()=>scan_result.stamps['5g']=60,()=>scan_result.stamps['5g']=50,'survey change invalidates');
changed(()=>push(radars,{time:100}),()=>pop(radars),'radar invalidates');
changed(()=>state.radios.radio0.failed=true,()=>delete state.radios.radio0.failed,'recovery gate invalidates');
printf('PASS: %d planning snapshot validity checks\n',n);
