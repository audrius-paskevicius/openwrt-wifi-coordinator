import {next_step,begin_attempt,reserve_force,target_ok,transition_request} from '../channel-coordinator/files/handoff.uc';
import {create_preference} from '../radio-prefer/files/steering.uc';
let checks=0;function check(ok,label){if(!ok)die('FAIL: '+label+'\n');checks++;}
let cfg={escalation:'decisive',handoff_wait:90,ban_seconds:20,target_min:-67,source_min:-65,protected_clients:[],handoff_cooldown:300,handoff_attempts:3};
let ep={started:100};
check(next_step(ep,129,cfg)=='wait','gentle stage gets its full interval');
check(next_step(ep,130,cfg)=='strong','warning at one third');ep.strong_sent=true;
check(next_step(ep,160,cfg)=='force','force at two thirds');ep.force_sent=160;
check(next_step(ep,190,cfg)=='expired','episode is bounded');
check(next_step({started:100},170,{...cfg,escalation:'gentle'})=='wait','gentle never escalates');
check(next_step({started:100,strong_sent:true},170,{...cfg,escalation:'strong'})=='wait','strong never forces');
let shared={};
check(!begin_attempt(shared,'client','good',100,cfg,false),'first shared attempt admitted');
check(begin_attempt(shared,'client','good',200,cfg,false)=='cooldown','other path cannot bypass cooldown');
check(!begin_attempt(shared,'client','good',200,cfg,true),'bounded return opportunity can bypass cooldown');
check(!begin_attempt(shared,'client','good',500,cfg,false),'next attempt after cooldown');
check(begin_attempt(shared,'client','good',800,cfg,false)=='attempt-limit','shared attempt cap');
check(!begin_attempt(shared,'client','good',1401,cfg,false),'budget expires');
check(reserve_force(shared,'client',[],'target',-50,true,1500,cfg),'same-band source fallback');
check(!reserve_force(shared,'client',[],'target',-50,true,1600,cfg),'forced budget shared across paths');
check(!reserve_force(shared,'other',[],'target',-50,false,1600,cfg),'cross-band source-only inference prohibited');
check(!reserve_force(shared,'other',[{node:'target',age:0,rcpi:80,rssi:-80}],'target',-50,true,1600,cfg),'fresh weak target overrides source proximity');
check(!reserve_force(shared,'protected',[],'target',-50,true,1600,{...cfg,protected_clients:['protected']}),'protected clients cannot be forced');

let T,preference,clients,radios,calls,events,common,shared_state,locks,source_place,target_place,raw_state;
let network={mode:'ap',ssid:'test-network',encryption:'psk2',key:'synthetic-fixture',network:['lan']};
let nr='020000000001ef1900008024090603022a00';
function setup(mode){
    T=1000;calls=[];events=[];locks=[];raw_state=null;shared_state={};common={...cfg,escalation:mode ?? 'decisive'};
    clients={'hostapd.src':{client:{connected:60000,'bss-transition-management':true,'beacon-measurement-modes':['ACTIVE'],measurements:[]}},'hostapd.dst':{}};
    source_place={ifname:'src',wiphy_freq:5745,center_freq1:5775,channel_width:3};
    target_place={ifname:'dst',wiphy_freq:5500,center_freq1:5530,channel_width:3};
    radios=[{name:'broad',ifname:'src',authorized:{client:true},signals:{client:-45}},{name:'good',ifname:'dst',authorized:{},signals:{}}];
    let bus={error:()=>null,list:()=>[{bss_transition_request:true,rrm_beacon_req:true}],call:(node,method,args)=>{
        push(calls,{node,method,args});
        if(method=='get_config'||node=='service')return {};
        if(node=='network.wireless')return {broad:{interfaces:[{ifname:'src',config:network}]},good:{interfaces:[{ifname:'dst',config:network}]}};
        if(method=='local_info')return {'hostapd.src':{ssid:'test-network',load:0,n_assoc:1,rrm_nr:[null,null,nr]},'hostapd.dst':{ssid:'test-network',load:0,n_assoc:0,rrm_nr:[null,null,nr]}};
        if(method=='connected_clients')return clients;
        if(method=='get_status')return {status:'ENABLED',freq:node=='hostapd.dst'?target_place.wiphy_freq:source_place.wiphy_freq,channel:node=='hostapd.dst'?100:149};
        if(method=='get_clients')return {clients:clients[node]};
        return {};
    }};
    preference=create_preference({bus,shared:shared_state,handoff_cfg:common,now:()=>T,radios:()=>radios,interfaces:()=>[source_place,target_place],save:()=>{},history:e=>push(events,e),
        cursor:{get_all:(name)=>name=='radio_prefer'?{enabled:'1',preferred_radio:'good',cooldown:'300',settle_time:'30',max_attempts:'3'}:{}},
        fs:{readfile:path=>index(path,'boot_id')>=0?'test':null,writefile:(path,data)=>{raw_state=json(data);return true;}}});
    preference.tick(locks);T+=31;preference.tick(locks);
}
function tick(seconds){T+=seconds;preference.tick(locks);}
function requests(){return filter(calls,c=>c.method=='bss_transition_request');}
function disconnects(){return filter(calls,c=>c.method=='del_client'&&c.args.deauth);}
setup('strong');
check(length(requests())==1&&!requests()[0].args.disassociation_imminent,'preference begins gently without waiting for measurement');
tick(31);check(length(requests())==2&&requests()[1].args.disassociation_imminent,'unmeasured client receives strong warning');
tick(31);check(!length(disconnects()),'Strong preference never forces');
tick(30);check(!preference.state.clients.client.episode&&length(requests())==2,'expiry does not restart the episode immediately');
setup('gentle');tick(31);tick(31);tick(30);
check(length(requests())==1&&!length(disconnects()),'Gentle preference stays gentle throughout');
setup();tick(31);tick(31);
check(length(disconnects())==1&&disconnects()[0].args.ban_time==20000,'Decisive preference uses bounded shared disconnect');
check(length(preference.reserved())==2,'reconnection reserves source and target briefly');
delete clients['hostapd.src'].client;radios[0].authorized={};
tick(10);check(preference.state.clients.client.episode!=null,'absent client is still observed');
tick(11);check(!preference.state.clients.client.episode&&!length(preference.reserved()),'failed return releases reservation and episode');
check(length(filter(calls,c=>c.method=='del_client'&&c.args.ban_time==0))==1,'failed return clears temporary restriction');
setup();tick(31);tick(31);
clients['hostapd.dst'].client=clients['hostapd.src'].client;delete clients['hostapd.src'].client;
radios[0].authorized={};radios[1].authorized={client:true};tick(1);
check(!preference.state.clients.client.episode&&preference.state.clients.client.decision=='on-preferred-radio','target association completes preference goal');
check(length(filter(events,e=>e.event=='steering-complete'&&e.reason=='on-preferred-radio'))==1,'completion recorded once');
setup();shared_state.forced={client:T-1};tick(31);tick(31);
check(!length(disconnects()),'a prior channel-operation force blocks preference force');
setup();common.protected_clients=['client'];tick(31);
check(!preference.state.clients.client.episode&&length(requests())==1&&!length(disconnects()),'protection added mid-episode cancels escalation');
setup();target_place.wiphy_freq=5580;tick(31);
check(length(requests())==1&&!length(disconnects()),'changed placement cancels stale episode');
setup();clients['hostapd.src'].client.measurements=[{node:'hostapd.dst',age:0,rcpi:60,rssi:-80}];tick(31);
check(length(requests())==1&&!length(disconnects()),'fresh weak target stops escalation');
setup();source_place.wiphy_freq=2412;tick(1);tick(300);tick(31);tick(31);
check(!length(disconnects()),'cross-band missing measurement never forces');
setup();locks=['good'];tick(100);
check(!preference.state.clients.client.episode,'reservations cannot prolong an episode indefinitely');
setup();tick(31);tick(31);delete clients['hostapd.src'].client;radios[0].authorized={};preference.stop();
check(!preference.state.clients.client.episode&&!length(preference.reserved()),'shutdown releases episode and temporary restriction');
printf('PASS: %d shared handoff and actual preference integration checks\n',checks);
