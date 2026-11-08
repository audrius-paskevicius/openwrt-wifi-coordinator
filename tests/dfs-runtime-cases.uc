let checks=0;
function check(v,s){if(!v)die('FAIL: '+s+'\n');checks++;}
check(dfs_mode(r)=='prepare'&&state.radios.r.dfs_constraint==null,'actual runtime allows kernel-authorized DFS without private-driver gating');
for(let value in [1,2,3]){
    region=value;r.dfs_region=value;
    check(dfs_mode(r)=='prepare','current country DFS region is accepted');
}
region=1;r.dfs_region=2;
check(dfs_mode(r)=='off','country-region conflict still blocks DFS');
region=0;r.dfs_region=0;
check(dfs_mode(r)=='off','unknown kernel region still blocks DFS');
region=2;r.dfs_region=2;
let g=group(5500,160),caps={},channels=[100];
let rules=[{reg_rule_flags:16,freq_range_start:5490000,freq_range_end:5730000,freq_range_max_bw:160000,power_rule_max_eirp:2700}];
for(let f in g.members)caps[f]={radar:true,dfs_state:0,max_tx_power:2600};
check(permitted(g,caps,rules,channels,dfs_mode(r))&&!dfs_ready(g,caps),'quiet usable 160 MHz DFS block enters preparation, not immediate transmission');
cfg.dfs_mode='available';
check(!permitted(g,caps,rules,channels,dfs_mode(r)),'available-only mode cannot skip CAC');
for(let f in g.members)caps[f].dfs_state=2;
check(permitted(g,caps,rules,channels,dfs_mode(r))&&dfs_ready(g,caps),'completed clearance makes the wide DFS block usable');
cfg.dfs_mode='prepare';caps[5580].dfs_state=1;
check(!permitted(g,caps,rules,channels,dfs_mode(r))&&!dfs_ready(g,caps),'one radar-blocked member excludes the entire 160 MHz block');
caps[5580].dfs_state=0;
check(permitted(g,caps,rules,channels,dfs_mode(r))&&!dfs_ready(g,caps),'kernel expiry restores preparation eligibility without an extra permanent ban');
caps[5580].dfs_state=2;
check(permitted(g,caps,rules,channels,dfs_mode(r))&&dfs_ready(g,caps),'renewed clearance permits reuse after radar');
let snapshot={observations:[],scanners:{},busy:{}},W=100000;
let recent=[{time:W,center:g.center,width:g.width,region:2,weight:1}];
let fresh=assess(g,snapshot,160,recent,W,3600,2,null,1);
let faded=assess(g,snapshot,160,recent,W+6*3600,3600,2,null,1);
let narrow=assess(group(5180,80),snapshot,160,[],W,3600,2,null,1);
check(faded.service>fresh.service&&faded.service>narrow.service,'radar memory fades and quiet wide spectrum can outrank a non-DFS fallback again');
caps[5500].disabled=true;
check(!permitted(g,caps,rules,channels,dfs_mode(r)),'country/driver-disabled frequencies remain forbidden');
r.band='2g';let before=reads;
check(dfs_mode(r)=='off'&&state.radios.r.dfs_constraint==null&&reads==before,'2.4 GHz does not need a DFS check');
printf('PASS: %d actual DFS-runtime and opportunistic reuse cases\n',checks);
