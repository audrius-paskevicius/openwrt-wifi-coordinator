import * as nl from 'nl80211';
import {create_survey} from '../channel-coordinator/files/survey.uc';
let checks=0,T=100,commands=[],events=[],reserved=[],rows=[],result=null;
function check(ok,why){if(!ok)die('FAIL: '+why+'\n');checks++;}
let cfg={scan_policy:'paced',scan_duty:10,scan_gap:3,scan_wait:60,scan_batch:5,max_age:900,scanner:'',scan_type:'active',quiet_seconds:60,max_mbps:0.05};
let caps={};for(let ch=1;ch<=13;ch++)caps[2407+5*ch]={max_tx_power:2000};
let base={band:'2g',unsafe:false,clients:{},authorized:{},mbps:0,own_bssids:[],config:{managed:true,channels:[1],widths:[20]},caps};
let a={...base,name:'a',ifname:'a0',phy:0},z={...base,name:'z',ifname:'z0',phy:1},radios=[z];
let state={radios:{a:{},z:{}}};
let rules=[{reg_rule_flags:0,freq_range_start:2400000,freq_range_end:2484000,freq_range_max_bw:40000,power_rule_max_eirp:2000}];
let survey=create_survey({cfg,state,now:()=>int(T),precise:()=>T,save:()=>{},lease:()=>{},release:()=>{},history:e=>push(events,e),coordination_ready:()=>{},
 reserved:()=>reserved,dfs_mode:()=>'off',allclients:()=>({}),inventory:()=>radios,rates:{},quiet_since:{},history_store:{survey:()=>{}},
 fs:{popen:cmd=>{push(commands,cmd);return {read:()=>'',close:()=>0};}},
 request:cmd=>cmd==nl.const.NL80211_CMD_GET_REG?{reg_rules:rules}:rows,complete:r=>result=r});
function done(aborted){T+=0.25;survey.event({cmd:aborted?nl.const.NL80211_CMD_SCAN_ABORTED:nl.const.NL80211_CMD_NEW_SCAN_RESULTS,msg:{wiphy:survey.pending().scanner.phy}});}
function restart(){survey.cancel('test boundary');T+=10;survey.start(radios);survey.tick(radios);}
survey.start(radios);survey.tick(radios);done(false);radios=[a,z];survey.tick(radios);
check(survey.pending().scanner.name=='z','equal-cost newly available radio does not replace successful scanner');
done(false);radios=[z,a];survey.tick(radios);
check(survey.pending().scanner.name=='z','enumeration changes do not change tied scanner');
done(false);z.clients={client:true};z.client_capacity=100;survey.tick(radios);
check(survey.pending().scanner.name=='a','cheaper empty radio beats remembered occupied scanner');
done(false);z.clients={};reserved=['a'];survey.tick(radios);
check(survey.pending().scanner.name=='z','reservation overrides continuity');
done(false);reserved=[];cfg.scanner='a';survey.tick(radios);
check(survey.pending().scanner.name=='a','explicit scanner overrides remembered scanner');
done(false);cfg.scanner='';a.unsafe=true;survey.tick(radios);
check(survey.pending().scanner.name=='z','unsafe scanner is never retained');
done(false);a.unsafe=false;
// Finish ordinary sweep without introducing any extra visits.
for(let i=0;i<30&&survey.busy();i++){T+=5;survey.tick(radios);if(survey.phase()=='scan')done(false);}
let summary=events[-1];
check(result&&length(result.frequencies)==13&&length(commands)==13,'quality collection adds no scan visits');
check(summary.event=='scan-complete'&&length(summary.scan_quality)==2,'one per-radio summary per completed sweep');
check(summary.scan_quality[0].visits+summary.scan_quality[1].visits==13,'summary accounts for all completed visits');
check(summary.scan_quality[0].active_visits+summary.scan_quality[1].active_visits==13,'active mode accounted for');
// Abort retries retain the existing two-retry budget and release to next job.
restart();let before=length(commands);done(true);T+=3;survey.tick(radios);done(true);T+=3;survey.tick(radios);done(true);
check(length(commands)==before+2,'exactly two retries, no additional scan budget');
let retries=filter(events,e=>e.event=='scan-retry');
check(length(retries)==2&&retries[0].attempt==1&&retries[1].attempt==2,'retry numbers retained');
check(retries[0].radio=='z'&&retries[0].frequencies[0]==2412&&retries[0].elapsed==0.25&&retries[0].mode=='active','retry identifies radio, frequency, elapsed and mode');
check(events[-1].event=='scan-aborted','third abort does not claim coverage');
survey.cancel('radar invalidated survey');summary=events[-1];
check(summary.event=='scan-partial'&&summary.scanned_frequencies==0,'interrupted failed sweep stays incomplete');
check(summary.scan_quality[0].visits==3&&summary.scan_quality[0].retries==2&&summary.scan_quality[0].aborts==3,'all aborted visits and retries counted');
// Only successful visits update continuity; successful fresh detections are counts.
cfg.scanner='a';restart();done(true);survey.cancel('test boundary');cfg.scanner='';restart();
check(survey.pending().scanner.name=='z','failed scan cannot replace last successful scanner');
rows=[{bss:{bssid:'02:00:00:00:00:01',seen_ms_ago:0,signal_mbm:-4500,frequency:2412}},{bss:{bssid:'02:00:00:00:00:01',seen_ms_ago:0,signal_mbm:-4600,frequency:2412}},{bss:{bssid:'02:00:00:00:00:02',seen_ms_ago:999999,signal_mbm:-4500,frequency:2412}}];
done(false);survey.cancel('test boundary');summary=events[-1];
check(summary.scan_quality[0].detections==1,'fresh detections deduplicate per visit and exclude stale entries');
check(index(sprintf('%J',summary),'02:00:00')<0,'quality summary contains no BSSID inventory');
// Existing serving gap still applies even when another equal-cost radio is ready.
a.clients={c:true};z.clients={c:true};a.client_capacity=100;z.client_capacity=100;state.radios.a.scan_duration=0.25;state.radios.z.scan_duration=0.25;rows=[];
restart();done(false);before=length(commands);survey.tick(radios);
check(length(commands)==before,'continuity does not bypass serving gap or borrow tied radio during it');
T+=3;survey.tick(radios);check(length(commands)==before+1,'serving gap ends normally');survey.cancel('finished');
printf('PASS: %d scanner continuity and quality cases\n',checks);
