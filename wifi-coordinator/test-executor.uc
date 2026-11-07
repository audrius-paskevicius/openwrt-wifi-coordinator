import {create_executor,data_flow} from '../channel-coordinator/files/executor.uc';
import {group} from '../channel-coordinator/files/policy.uc';
import * as nl from 'nl80211';
let checks=0;function check(v,s){if(!v)die('FAIL: '+s+'\n');checks++;}
let T,st,radio,ex,calls,events,ignore=false,repairs=0,content,journal,restores=0;
check(!data_flow({rx:0,tx:0},{rx:500,tx:500}),'handshake-sized counters do not prove service');
check(!data_flow({rx:0,tx:0},{rx:100000,tx:0}),'one-way counters do not prove bidirectional service');
check(data_flow({rx:1000000,tx:1000000},{rx:10000,tx:10000}),'counter reset after restart can still establish fresh data flow');
function setup(method,occupied){
 T=100;calls=[];events=[];ignore=false;repairs=0;journal=null;restores=0;
 content='channel=100\nht_capab=[HT40+]\nvht_oper_chwidth=1\nvht_oper_centr_freq_seg0_idx=106\n';
 let cfg={allow_reconnect:false,persist:false,csa_count:15,quiet_seconds:60,handoff_wait:90,escalation:'decisive',protected_clients:[],ban_seconds:20,
 target_min:-72,source_min:-65,verify_unprobed:180,cac_timeout:720,interval:60,cooldown:180,separate:true};
 st={radios:{r:{}},last_move:0};
 let caps={};for(let f in [5180,5200,5220,5240,5500,5520,5540,5560,5580,5600,5620,5640,5745,5765,5785,5805])caps[f]={max_tx_power:2000,dfs_state:2};
 radio={name:'r',phy:0,ifname:'test0',current:group(5500,80),caps,csa:true,unsafe:false,band:'5g',
 clients:{client:true},authorized:{client:true},client_data:{client:{rx:10000,tx:10000}},signals:{client:-50},fingerprint:'stable',
 config:{method:method??'csa',width_method:'idle_reconfigure',occupied:occupied??'handoff',channels:[36,40,44,48,100,104,108,112,116,120,124,128,149,153,157,161]},aps:[]};
 function call(obj,method,args){push(calls,{obj,method,args});
  if(method=='switch_chan'){if(!ignore)radio.current=group(args.freq,args.bandwidth);return {};}
  if(method=='get_clients')return {clients:radio.clients};
  if(method=='connected_clients')return {'hostapd.test0':{client:{'bss-transition-management':true}}};
  if(method=='rrm_nr_get_own')return {value:[null,null,'020000000001ef19000080240900']};
  return {};
 }
 let io={cfg,state:st,boot:'test',now:()=>T,save:()=>{},lease:()=>{},release:()=>{},call,
 request:()=>({reg_rules:[{reg_rule_flags:0,freq_range_start:5150000,freq_range_end:5875000,freq_range_max_bw:80000,power_rule_max_eirp:2000}]}),
 config_fingerprint:()=>'stable',phy_caps:()=>caps,allclients:(rs)=>{let c={};for(let r in rs)for(let m in keys(r.authorized))c[m]=true;return c;},
 empty_interface:()=>!length(radio.clients),apply_empty_config:()=>{repairs++;let ch=int(match(content,/channel=([0-9]+)/)[1]),w=int(match(content,/vht_oper_chwidth=([0-9]+)/)?.[1] ?? 0);radio.current=group((radio.band=='2g'?2407:5000)+5*ch,radio.band=='2g'?20:w==2?160:w?80:20);},
 apply_radio_config:()=>{repairs++;if(!ignore){let ch=int(match(content,/channel=([0-9]+)/)[1]),w=int(match(content,/vht_oper_chwidth=([0-9]+)/)[1]);radio.current=group(5000+5*ch,w?80:20);}},
 restore_preparation:()=>{if(!journal)return false;restores++;content=journal.original;radio.current=journal.source;journal=null;return true;},private_json:(p,j)=>{journal=j;},coordination_ready:()=>{},
 dfs_mode:()=>'prepare',history:e=>push(events,e),log:()=>{},quiet_since:{},remember:()=>{},completed:()=>{},
 fs:{stat:p=>index(p,'-cac.json')>=0&&journal?{}:null,readfile:p=>index(p,'hostapd-phy')>=0?content:'',writefile:(p,s)=>{if(match(p,/\.conf$/))content=s;return 1;},chmod:()=>true,unlink:()=>{journal=null;return true;}}};
 ex=create_executor(io);return io;
}
setup();ex.start(radio,group(5580,80),[radio]);T+=15;ex.tick([radio]);
check(length(filter(calls,c=>c.method=='switch_chan'))==1,'live CSA proceeds with active clients and no quiet history');
check(!length(filter(calls,c=>c.method=='del_client'||c.method=='bss_transition_request')),'live CSA does not unnecessarily herd clients');
T+=181;ex.tick([radio]);check(!ex.busy()&&events[-1].event=='switch-verified','successful move completes verification');
setup('csa','quiet');ex.start(radio,group(5580,80),[radio]);T+=15;let denied=false;
try{ex.tick([radio]);}catch(e){denied=true;ex.abort(e);}
check(denied&&!length(filter(calls,c=>c.method=='switch_chan')),'explicit quiet-only restriction is respected');
check(!st.halted,'a deferred operation does not globally halt radios');
setup('idle_reconfigure','empty');ex.start(radio,group(5580,80),[radio]);T+=15;denied=false;
try{ex.tick([radio]);}catch(e){denied=true;ex.abort(e);}
check(denied&&repairs==0,'occupied AP cannot be restarted');
setup();ex.start(radio,group(5580,80),[radio]);T+=15;ex.tick([radio]);
ex.event({cmd:nl.const.NL80211_CMD_RADAR_DETECT,msg:{wiphy:0,wiphy_freq:5580,radar_event:0}},[radio]);
check(ex.pending().kind=='reconcile'&&!st.halted,'radar during verification enters external reconciliation');
radio.current=group(5745,80);T+=70;ex.tick([radio]);
check(ex.pending().kind=='verify'&&ex.pending().target.freq==5745,'driver-selected legal placement becomes the verification target');
T+=181;ex.tick([radio]);check(!ex.busy()&&!st.halted&&events[-1].event=='external-recovery-verified','radar evacuation does not become a generic channel failure');
check(length(filter(calls,c=>c.method=='switch_chan'))==1,'reconciliation does not fight the driver by issuing another CSA');
setup();ex.start(radio,group(5580,80),[radio]);T+=15;ignore=true;ex.tick([radio]);T+=181;ex.tick([radio]);
check(!ex.busy()&&!st.halted&&events[-1].event=='switch-ignored','driver no-op is scoped to target rather than global stop');
check(length(st.radios.r.rejected)==1,'ignored destination receives a bounded exclusion');
setup();ex.start(radio,group(5580,80),[radio]);T+=15;ex.tick([radio]);radio.current=group(5745,80);T+=10;ex.tick([radio]);
check(ex.pending().kind=='reconcile','unannounced external channel change also reconciles');
setup();ex.event({cmd:nl.const.NL80211_CMD_RADAR_DETECT,msg:{wiphy:0,wiphy_freq:5500,radar_event:0}},[radio]);
check(ex.busy()&&ex.pending().kind=='reconcile','radar while idle is handled by the operation owner');
T+=721;ex.tick([]);check(!ex.busy()&&st.radios.r.unavailable&&!st.halted,'unreturned radio is isolated without stopping healthy peers');
setup();radio.clients={};radio.authorized={};ex.start(radio,group(5580,20),[radio]);T+=15;ex.tick([radio]);
check(repairs==1&&!length(filter(calls,c=>c.method=='switch_chan')),'width-specific restart method survives inventory refresh');
setup();ex.start(radio,group(5580,80),[radio]);T+=15;ex.tick([radio]);
radio.clients={};radio.authorized={};T+=181;ex.tick([radio]);T+=20;ex.tick([radio]);
check(ex.pending()?.repair_attempted&&st.radios.r.failed&&!st.halted,'sustained missing client starts one scoped repair');
T+=15;ex.tick([radio]);check(repairs==1&&radio.current.freq==5500,'empty-radio repair can run when the lost client is absent');
radio.clients={client:true};radio.authorized={client:true};radio.client_data.client={rx:30000,tx:30000};T+=181;ex.tick([radio]);
check(!ex.busy()&&!st.radios.r.failed&&!st.halted,'client data recovery clears affected-radio failure');
check(st.radios.r.csa_failed_until>T&&length(st.radios.r.rejected)==1,'failed method and target remain temporarily quarantined');
// A single compatible AP can change channel by briefly reconnecting its clients.
let opt=setup('idle_reconfigure');opt.cfg.allow_reconnect=true;radio.aps=[{}];
ex.start(radio,group(5580,80),[radio]);T+=15;ex.tick([radio]);
check(repairs==1&&ex.pending().kind=='verify'&&radio.current.freq==5580,'opted-in occupied radio restarts without impossible handoff wait');
check(journal?.kind=='reconnect'&&events[-1].event=='radio-reconnect','reconnect saves recovery journal and an anonymous action');
check(!length(filter(calls,c=>c.method=='bss_transition_request'||c.method=='del_client')),'no incompatible roaming requests or client bans');
radio.clients={};radio.authorized={};T+=20;ex.tick([radio]);
check(ex.pending().kind=='verify'&&restores==0,'expected disconnect receives a reconnection grace period');
radio.clients={client:true};radio.authorized={client:true};radio.client_data.client={rx:30000,tx:30000};T+=45;ex.tick([radio]);
check(!ex.busy()&&!journal&&events[-1].event=='switch-verified','reconnected client data verifies success and clears journal');
opt=setup('idle_reconfigure');opt.cfg.allow_reconnect=true;radio.aps=[{}];
ex.start(radio,group(5580,80),[radio]);T+=15;ex.tick([radio]);radio.clients={};radio.authorized={};
T+=61;ex.tick([radio]);T+=20;ex.tick([radio]);
check(ex.pending().kind=='rollback'&&restores==1&&radio.current.freq==5500,'persistent reconnect failure restores previous channel once');
radio.clients={client:true};radio.authorized={client:true};T+=31;ex.tick([radio]);
check(!ex.busy()&&!st.radios.r.failed&&events[-1].event=='rollback-verified','rollback confirms clients returned');
check(length(st.radios.r.rejected)==1,'failed restart destination is excluded from immediate retries');
opt=setup('idle_reconfigure');opt.cfg.allow_reconnect=true;radio.aps=[{}];opt.cfg.protected_clients=['client'];
ex.start(radio,group(5580,80),[radio]);T+=15;denied=false;try{ex.tick([radio]);}catch(e){denied=true;ex.abort(e);}
check(denied&&!repairs&&!journal,'protected client prevents occupied restart');
opt=setup('idle_reconfigure','empty');opt.cfg.allow_reconnect=true;radio.aps=[{}];
ex.start(radio,group(5580,80),[radio]);T+=15;denied=false;try{ex.tick([radio]);}catch(e){denied=true;ex.abort(e);}
check(denied&&!repairs,'empty-only policy still overrides reconnect permission');
setup('idle_reconfigure');radio.aps=[{}];ex.start(radio,group(5580,80),[radio]);T+=15;denied=false;
try{ex.tick([radio]);}catch(e){denied=index(''+e,'No compatible handoff AP')>=0;ex.abort(e);}
check(denied&&!repairs&&!ex.busy(),'without opt-in report missing compatible AP immediately');
opt=setup('idle_reconfigure');opt.cfg.allow_reconnect=true;radio.aps=[{}];
opt.apply_radio_config=()=>{die('simulated AP start failure');};
ex.start(radio,group(5580,80),[radio]);T+=15;try{ex.tick([radio]);}catch(e){ex.abort(e);}
check(restores==1&&!journal&&radio.current.freq==5500,'exception after journal creation restores original configuration');
// Same fallback after a real compatible handoff attempt has failed.
opt=setup('idle_reconfigure');opt.cfg.allow_reconnect=true;
let net={ssid:'test-network',encryption:'none',network:'lan'};
radio.aps=[{config:net}];
let peer={...radio,name:'peer',phy:2,ifname:'peer0',current:group(5180,80),clients:{other:true},authorized:{other:true},aps:[{config:net,status:{}}]};
let pair=[radio,peer];ex.start(radio,group(5580,80),pair);T+=15;ex.tick(pair);
check(ex.pending().kind=='handoff'&&!repairs&&length(filter(calls,c=>c.method=='bss_transition_request'))==1,'compatible AP receives gentle handoff before restart');
T+=31;ex.tick(pair);check(length(filter(calls,c=>c.method=='bss_transition_request'&&c.args.disassociation_imminent))==1,'handoff escalates to strong request first');
T+=30;ex.tick(pair);radio.clients={};radio.authorized={};
T+=21;ex.tick(pair);check(ex.pending().kind=='move-wait','failed decisive handoff proceeds instead of aborting the channel change');
T+=1;ex.tick(pair);check(repairs==1&&ex.pending().kind=='verify','stranded disconnected client can reconnect after the channel change');
radio.clients={client:true};radio.authorized={client:true};radio.client_data.client={rx:30000,tx:30000};T+=70;ex.tick(pair);
check(!ex.busy()&&events[-1].event=='switch-verified'&&peer.current.freq==5180&&peer.clients.other,'fallback verifies same-AP reconnection without changing the peer radio');
opt=setup();radio.clients={};radio.authorized={};radio.aps=[{}];content+='vht_capab=[SHORT-GI-80]\n';
opt.request=()=>({reg_rules:[{reg_rule_flags:0,freq_range_start:5150000,freq_range_end:5875000,freq_range_max_bw:160000,power_rule_max_eirp:2000}]});
// The executor captures request at creation; widen its existing synthetic rule through a fresh instance.
ex=create_executor(opt);ex.start(radio,group(5500,160),[radio]);T+=15;ex.tick([radio]);
check(repairs==1&&radio.current.width==160&&index(content,'vht_oper_chwidth=2')>=0,'160 restart reaches requested width with actual hostapd configuration');
T+=46;ex.tick([radio]);check(!ex.busy()&&events[-1].event=='switch-verified','160 restart completes verification');
opt=setup();radio.band='2g';radio.current=group(2412,20);radio.clients={};radio.authorized={};radio.aps=[{}];radio.caps={};
for(let ch=1;ch<=13;ch++)radio.caps[2407+5*ch]={max_tx_power:2000};
radio.config.channels=[1,5,9,13];content='channel=1\nht_capab=[LDPC]\nnoscan=0\n';
opt.request=()=>({reg_rules:[{reg_rule_flags:0,freq_range_start:2400000,freq_range_end:2483500,freq_range_max_bw:40000,power_rule_max_eirp:2000}]});
ex=create_executor(opt);ex.start(radio,group(2432,40),[radio]);T+=15;ex.tick([radio]);
check(index(content,'[HT40+]')>=0&&index(content,'noscan=0')>=0,'HT40 requests coexistence-checked setup');
radio.current=group(2432,20);T+=5;ex.tick([radio]);
check(ex.pending().kind=='verify'&&ex.pending().target.width==40&&!ex.pending().external,'early20 fallback on a new primary does not become unrelated external recovery');
T+=41;ex.tick([radio]);
check(!ex.busy()&&!st.radios.r.failed&&events[-1].event=='switch-verified','hostapd20 fallback verifies service without false connectivity failure');
check(st.radios.r.rejected[0].target.width==40&&st.radios.r.rejected[0].until==T+900,'coexistence refusal remembered only for evidence freshness period');
check(st.radios.r.width_limit.actual==20&&st.radios.r.width_limit.requested==40&&st.radios.r.width_limit.until==T+900,'observed width limit defers repeated widening across primary channels');
radio.config.width_method='csa';ex.start(radio,group(2412,40),[radio]);T+=15;denied=false;
try{ex.tick([radio]);}catch(e){denied=index(''+e,'coexistence')>=0;ex.abort(e);}
check(denied,'explicit CSA cannot bypass HT40 coexistence');
print('PASS: '+checks+' executor integration and failure cases\n');
