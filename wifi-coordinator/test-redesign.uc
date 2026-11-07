import {group,same} from '../channel-coordinator/files/policy.uc';
import {assess,layout,better,transition,choose,decide,worthwhile_narrowing} from '../channel-coordinator/files/planner.uc';
import {remember,strength,risk} from '../channel-coordinator/files/radar.uc';
import {create_survey,scan_cost} from '../channel-coordinator/files/survey.uc';
import {create_executor} from '../channel-coordinator/files/executor.uc';
import * as nl from 'nl80211';
let count=0;function check(v,s){if(!v)die('FAIL: '+s+'\n');count++;}
let cfg={separate:true,wide_threshold:70,overlap_penalty:10,improvement:3};
function g(f,w,c,occ){return {...group(f,w),cost:c,occupancy:occ??c,radar_risk:0,uncertainty:3,max_width:80,power:20};}
function model(name,c,choices){return {name,current:c,candidates:choices};}
let old=g(5500,80,5.88),clean=g(5580,80,0),m=[model('main',old,[old,clean])];
let plan=choose(m,cfg),d=decide(plan,m,null,1,cfg,null);
check(d.action=='move'&&d.next.target.freq==5580,'clear win acts after one completed sweep');
let tied=[model('main',clean,[clean,g(5745,80,0)])];
check(!length(choose(tied,cfg).path),'equal evidence does not manufacture a move');
let reverse=[model('main',clean,[clean,old])];check(!length(choose(reverse,cfg).path),'winner does not bounce back');
let uncertain={...clean,uncertainty:8},um=[model('main',old,[old,uncertain])],up=choose(um,cfg);
let first=decide(up,um,null,1,cfg,null);check(first.action=='measure','uncertain comparison requests more evidence');
check(decide(up,um,first,1,cfg,null).count==1,'same sweep cannot confirm itself');
check(decide(up,um,first,2,cfg,null).action=='move','repeat evidence can resolve comparison');
// Reproduce rotating 2.4 GHz winners without losing the non-winning evidence.
let incumbent={...g(2412,20,10),uncertainty:12.3};
let altA={...g(2432,20,1.7),uncertainty:15},altB={...g(2427,20,1.9),uncertainty:15};
function comparison(current,choices,prior,stamp,name){
 let ms=[model(name??'radio1',current,[current,...choices])];
 return decide(choose(ms,cfg),ms,prior,stamp,cfg,null);
}
let support=null;
for(let round=1;round<=4;round++){
 let choices=round%2?[altA,altB]:[{...altA,cost:1.9},{...altB,cost:1.7}];
 support=comparison(incumbent,choices,support,round);
 check(support.count==round,'alternating winner retains its own comparison history '+round);
 check(support.action==(round<4?'measure':'move'),'8.3-point gain clears 15-point uncertainty after four surveys '+round);
}
check(support.next.target.freq==2427,'latest evidence selects the current winner');
check(comparison(incumbent,[altA,altB],support,4).count==4,'same survey with a new winner cannot add support');
let contrary=comparison(incumbent,[{...altA,cost:11},altB],support,5);
check(contrary.count==5,'contrary evidence for one alternative does not erase another');
let reappeared=comparison(incumbent,[altA,altB],contrary,6);
check(reappeared.count==1&&reappeared.action=='measure','an alternative that stopped beating the incumbent must earn support again');
let absent=comparison(incumbent,[altB],support,5);
check(comparison(incumbent,[altA,altB],absent,6).count==1,'missing or ineligible candidate cannot retain support');
check(comparison(incumbent,[altA,altB],support,905).count==1,'stale comparison cannot lend confidence');
check(comparison(incumbent,[altA,altB],support,3).count==1,'backward survey timestamp resets support');
check(comparison({...incumbent,freq:2417,center:2417},[altA,altB],support,5).count==1,'changed incumbent resets comparison');
check(comparison(incumbent,[altA,altB],support,5,'other').count==1,'a different radio cannot borrow support');
check(comparison(incumbent,[{...altA,width:40},altB],support,5).count==1,'a different target width cannot borrow support');
let newTarget={...g(2462,20,0),uncertainty:15};
let newlyBest=comparison(incumbent,[altA,altB,newTarget],support,5);
check(newlyBest.count==1&&newlyBest.action=='measure','new destination does not inherit confidence from older winners');
let secondCurrent={...g(5180,80,10),uncertainty:15};
let changedOther=[model('radio1',incumbent,[incumbent,altA,altB]),model('radio2',secondCurrent,[secondCurrent,g(5500,80,9)])];
let independent=decide(choose(changedOther,cfg),changedOther,support,5,cfg,null);
check(independent.comparisons.radio1==5&&independent.comparisons.radio2==1,'unrelated radio changes preserve only relevant support');
let tiny=comparison(incumbent,[{...altA,cost:9,uncertainty:1}],null,1);
for(let round=2;round<=70;round++)tiny=comparison(incumbent,[{...altA,cost:9,uncertainty:1}],tiny,round);
check(tiny.count==64&&tiny.required>=cfg.improvement&&tiny.action=='measure','bounded evidence never bypasses minimum benefit');
let narrow=g(5580,40,50,0),wide=g(5500,80,55,55);
check(choose([model('main',narrow,[narrow,wide])],cfg).choices[0].width==80,'usable wide spectrum preferred despite cleaner narrow block');
let blockedWide={...wide,cost:95,occupancy:95};
check(choose([model('main',blockedWide,[blockedWide,narrow])],cfg).choices[0].width==40,'severely crowded wide block can lose to clear narrow block');
let marginalWide=g(5500,80,70,70),worseNarrow=g(5580,40,80,60);
check(choose([model('main',marginalWide,[marginalWide,worseNarrow])],cfg).choices[0].width==80,'narrowing cannot reduce estimated service merely by crossing a congestion threshold');
// Existing locations cannot prevent a better JOINT width arrangement.
let x=g(5180,40,50,0),y=g(5220,40,50,0),a=g(5180,80,0,0),b=g(5500,80,0,0);
let joint=[model('a',x,[x,a]),model('b',y,[y,b])],jp=choose(joint,cfg);
check(jp.choices[0].width==80&&jp.choices[1].width==80,'joint widths are evaluated against final placements');
check(jp.path[0].index==1,'occupying radio leaves before broadening into its old block');
// A neutral staging move can unlock a profitable swap without colliding.
let ac=g(5180,80,50,50),bc=g(5500,80,50,50),at=g(5500,80,0,0),bt=g(5180,80,0,0),stage=g(5580,80,50,50);
let swap=[model('a',ac,[ac,at,stage]),model('b',bc,[bc,bt])],sp=choose(swap,cfg);
check(sp.cost==0&&length(sp.path)==3&&sp.path[0].staging,'joint swap gets a bounded neutral staging route');
let positions=[ac,bc];for(let step in sp.path){positions[step.index]=step.target;check(layout(positions,cfg).overlap==0,'every intermediate step remains separated');}
check(decide(sp,swap,null,1,cfg,null).action=='move','staging is admitted by final-plan benefit');
// Independent exhaustive reference for small complete models.
for(let k=0;k<40;k++){
 let ms=[];for(let i=0;i<3;i++){let cs=[];for(let j=0;j<3;j++)push(cs,g([5180,5500,5580][j],j==0?40:80,(k*13+i*19+j*31)%100));push(ms,model('r'+i,cs[i],cs));}
 let got=choose(ms,cfg),ref={...layout(map(ms,z=>z.current),cfg)};
 for(let c0 in ms[0].candidates)for(let c1 in ms[1].candidates)for(let c2 in ms[2].candidates){
  let cs=[c0,c1,c2],l=layout(cs,cfg),current=map(ms,z=>z.current);
  if(worthwhile_narrowing(current,cs,layout(current,cfg),l,cfg)&&better(l,ref,cfg)&&transition(ms,cs,cfg))ref=l;
 }
 check(!got.truncated&&got.cost==ref.cost&&got.width==ref.width&&got.overlap==ref.overlap,'joint plan matches exhaustive feasible reference '+k);
}
let e={time:100,center:5610,width:80,region:2,phy:0,radar_event:0},events=remember([],e);
events=remember(events,{...e,phy:2});check(length(events)==1&&length(events[0].phys)==2,'shared PHY reports count once');
check(length(remember(events,{...e,radar_event:1,time:300}))==1,'CAC completion is not a detection');
check(strength(events[0],100,3600)==1&&strength(events[0],3700,3600)==0.5,'risk halves at configured half life');
check(risk(events,group(5580,80),3700,3600,2)==0.5,'planner uses the same decay');
check(risk(events,group(5620,40),100,3600,2)==1,'changing primary or width cannot evade affected spectrum');
check(risk(events,group(5500,80),100,3600,2)==0,'unrelated block remains unaffected');
check(risk(events,group(5580,80),100,3600,1)==0,'different regulatory-region history is not silently combined');
check(strength(events[0],50,3600)==1,'clock reversal cannot create negative-age decay');
events=remember(events,{...e,time:3700});check(risk(events,group(5580,80),7300,3600,2)==0.75,'repeated independent incidents strengthen memory');
let snap={observations:[],busy:{},scanners:{'5580':'r','5600':'r','5620':'r','5640':'r'}};
let q=assess(group(5580,80),snap,80,[],100,3600,2,null);
check(q.cost==0&&q.airtime==null&&q.uncertainty>0,'missing airtime is uncertainty rather than invented congestion');
let qr=assess(group(5580,80),snap,80,remember([],e),100,3600,2,null);
check(qr.cost>q.cost&&qr.radar_risk==1,'empty Wi-Fi survey cannot erase radar risk');
// Exercise the actual survey module under continuous high traffic.
let T=100,commands=[],state={radios:{r:{}}},result=null;
let scfg={scan_policy:'paced',scan_duty:10,scan_gap:3,scan_wait:60,scan_batch:5,max_age:900,interval:60,scanner:'',scan_type:'active',quiet_seconds:60,max_mbps:0.05};
let rr={name:'r',ifname:'test',band:'2g',phy:0,unsafe:false,clients:{c:true},authorized:{c:true},mbps:500,config:{managed:true,channels:[1],widths:[20]},caps:{}};
for(let ch=1;ch<=13;ch++)rr.caps[2407+5*ch]={max_tx_power:2000};
let rules=[{reg_rule_flags:0,freq_range_start:2400000,freq_range_end:2484000,freq_range_max_bw:40000,power_rule_max_eirp:2000}];
let survey=create_survey({cfg:scfg,state,now:()=>int(T),precise:()=>T,save:()=>{},lease:()=>{},release:()=>{},history:()=>{},coordination_ready:()=>{},
 dfs_mode:()=>'off',allclients:()=>({c:true}),inventory:()=>[rr],rates:{r:500},quiet_since:{},history_store:{survey:()=>{}},
 fs:{popen:(cmd)=>{push(commands,cmd);return {read:()=>'',close:()=>0};}},
 request:(cmd)=>cmd==nl.const.NL80211_CMD_GET_REG?{reg_rules:rules}:[],complete:r=>{result=r;}});
survey.start([rr]);survey.tick([rr]);check(length(commands)==1,'steady traffic cannot starve paced scanning');
T+=0.2;survey.event({cmd:nl.const.NL80211_CMD_NEW_SCAN_RESULTS,msg:{wiphy:0}});survey.tick([rr]);check(length(commands)==1,'serving gap follows off-channel visit');
T+=3;survey.tick([rr]);check(length(commands)==2,'next visit resumes within duty budget');
survey.cancel('test complete');check(!survey.busy(),'scan can yield ownership for external events');
check(scan_cost({...rr,clients:{}},1)==0,'empty scanner has no displaced-client cost');
let fast={...rr,name:'fast',ifname:'fast0',phy:0,mbps:0,client_capacity:866},slow={...rr,name:'slow',ifname:'slow0',phy:2,mbps:0,client_capacity:58};
check(scan_cost(fast,0.3)>scan_cost(slow,0.3),'uniform scan cost protects higher-capacity client links');
T=200;commands=[];let radios=[fast,slow];state={radios:{fast:{},slow:{}}};
let coordinated=create_survey({cfg:scfg,state,now:()=>int(T),precise:()=>T,save:()=>{},lease:()=>{},release:()=>{},history:()=>{},coordination_ready:()=>{},
 dfs_mode:()=>'off',allclients:()=>({c:true}),inventory:()=>radios,rates:{},quiet_since:{},history_store:{survey:()=>{}},
 fs:{popen:cmd=>{push(commands,cmd);return {read:()=>'',close:()=>0};}},
 request:cmd=>cmd==nl.const.NL80211_CMD_GET_REG?{reg_rules:rules}:[],complete:()=>{}});
coordinated.start(radios);coordinated.tick(radios);check(index(commands[0],'slow0')>=0,'lower displaced capacity chooses scanner regardless of name');
T+=0.2;coordinated.event({cmd:nl.const.NL80211_CMD_NEW_SCAN_RESULTS,msg:{wiphy:2}});coordinated.tick(radios);
check(length(commands)==1,'serving gap does not borrow the costlier radio');
T+=3;coordinated.tick(radios);check(length(commands)==2&&index(commands[1],'slow0')>=0,'preferred scanner resumes after its bounded serving gap');
coordinated.cancel('test complete');
print('PASS: '+count+' redesigned planner, radar and survey cases\n');
