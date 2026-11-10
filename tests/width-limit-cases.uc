let checks=0;function check(ok,label){if(!ok)die('FAIL: '+label+'\n');checks++;}
let list=candidates(r,[r],rules);
check(length(list)>1&&!length(filter(list,g=>g.width>20)),'observed width limit still allows narrower channel optimization');
r.current=group(2452,20);list=candidates(r,[r],rules);
check(!length(filter(list,g=>g.width>20)),'changing primary cannot bypass observed width limit');
T=1001;list=candidates(r,[r],rules);
check(length(filter(list,g=>g.width==40))>0,'expiry restores hardware width candidates');
check(join(' ',r.config.widths)=='40 20','runtime evidence does not rewrite configured width intent');
state.radios.r.recheck_until=T+900;list=candidates(r,[r],rules);
check(length(list)>1&&index(state.radios.r.planning_hold,'client evidence')>=0,'restored-service hold retains visible alternatives');
T+=901;list=candidates(r,[r],rules);
check(length(list)>1&&!state.radios.r.planning_hold,'restored-service recheck expires without manual acknowledgement');
state.radios.r.rejected=[{target:group(2412,40),until:T+21600}];
list=candidates(r,[r],rules);
check(!length(filter(list,g=>g.width==40&&g.center==2422)),'another primary cannot evade a failed-footprint exclusion');
// Reproduce ch13 HT40 narrowing, client failure at 20 MHz, and later retry.
r.current=group(2442,20);
state.radios.r.width_limit={actual:20,requested:40,until:T+900};
state.radios.r.rejected=[
 {target:group(2472,40),until:T+900,reason:'HT40 setup retained 20 MHz'},
 {target:group(2472,20),kind:'client',until:T+21600}];
T+=901;list=candidates(r,[r],rules);
check(!length(filter(list,g=>g.width==40&&index(g.members,2472)>=0)),
 'expired width pause cannot retry a still-failed20 fallback, including reversed primary');
check(!length(filter(list,g=>g.freq==2472&&g.width==20)),'failed20 placement remains excluded');
check(length(filter(list,g=>g.width==40))>0,'unrelated HT40 blocks remain eligible');
check(length(filter(list,g=>g.freq==2452&&g.width==20))>0,'healthy20 member stays eligible');
check(length(filter(list,g=>same(g,r.current)))==1,'current serving placement is retained');
T+=20700;list=candidates(r,[r],rules);
check(length(filter(list,g=>g.freq==2472&&g.width==40))>0,'failure expiry restores HT40 candidate');
check(length(filter(list,g=>g.freq==2472&&g.width==20))>0,'failure expiry restores20 candidate');
state.radios.r.rejected=[{target:group(2472,40),until:T+900}];
list=candidates(r,[r],rules);
check(length(filter(list,g=>g.freq==2472&&g.width==20))>0,'width refusal alone does not exclude20 service');
state.radios.r.last_attempt=T;cfg.retry_delay=30;
check(length(candidates(r,[r],rules))>1&&state.radios.r.planning_hold,'retry delay retains alternatives with an explicit hold');
check(length(candidates(r,[r],rules,true))>1,'prepared action does not cancel itself through its own retry gate');
r.unsafe=true;check(length(candidates(r,[r],rules,true))==1,'revalidation cannot bypass unsupported configuration');
printf('PASS: %d actual width-limit candidate cases\n',checks);
