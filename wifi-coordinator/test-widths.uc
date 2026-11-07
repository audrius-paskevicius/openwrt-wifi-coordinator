import {hardware_widths,configured_widths,group,placements,permitted,reconfigure_text,live_width,move_method,same} from '../channel-coordinator/files/policy.uc';
import {create_executor} from '../channel-coordinator/files/executor.uc';
import * as nl from 'nl80211';
let checks=0;function check(ok,label){if(!ok)die('FAIL: '+label+'\n');checks++;}
check(join(' ',hardware_widths('5g',{ht_capa:6255,vht_capa:865827190}))=='160 80 40 20','radio0 advertised widths');
check(join(' ',hardware_widths('2g',{ht_capa:6255,vht_capa:865827190}))=='40 20','2.4GHz ignores misleading VHT width flags');
check(join(' ',hardware_widths('5g',{ht_capa:383,vht_capa:868249904}))=='80 40 20','radio2 advertises no 160');
check(join(' ',hardware_widths('5g',{}))=='20','no capabilities invent no wide modes');
check(join(' ',hardware_widths('5g',{ht_capa:2,vht_capa:8}))=='160 80 40 20','80+80-capable PHY also supports contiguous 160');
check(join(' ',configured_widths('auto','2g',[40,20]))=='40 20','Auto follows HT40 hardware');
check(join(' ',configured_widths('160 40','5g',[80,40,20]))=='160 40','manual intent preserved for reported capability filtering');
check(live_width(5)==160&&live_width(4)==null,'160 inventory decoded; 80+80 not misread as contiguous');
check(length(placements(2432,40))==2,'both secondary directions considered');
check(length(placements(2412,40))==1&&group(2412,40).sec==1,'lower edge HT40 plus');
check(length(placements(2472,40))==1&&group(2472,40).sec==-1,'upper edge HT40 minus');
check(length(placements(2484,40))==0,'channel14 cannot form HT40');
check(group(2432,40,2422).members[0]==2412,'live secondary-below geometry preserved');
check(group(5180,160).center==5250&&length(group(5180,160).members)==8,'lower 160 block geometry');
check(group(5640,160).center==5570&&group(5640,160).sec==-1,'upper primary in DFS160 block');
check(group(5660,160)==null,'no invented sliding 160 center');
check(move_method({method:'csa',width_method:'idle_reconfigure'},group(2412,40),group(2437,40))=='idle_reconfigure','HT40 frequency moves use coexistence-capable width method');
let caps={},rule={reg_rule_flags:16,freq_range_start:5470000,freq_range_end:5725000,freq_range_max_bw:160000,power_rule_max_eirp:2600};
let target=group(5500,160);
for(let f in target.members)caps[f]={radar:true,no_ir:true,dfs_state:2,max_tx_power:2000};
check(permitted(target,caps,[rule],[100],'available'),'160 allowed with legal complete cleared block');
caps[5580].no_160mhz=true;check(!permitted(target,caps,[rule],[100],'available'),'single member width prohibition blocks whole160');delete caps[5580].no_160mhz;
caps[5580].dfs_state=0;check(!permitted(target,caps,[rule],[100],'available'),'uncleared160 member blocks available mode');
check(permitted(target,caps,[rule],[100],'prepare'),'uncleared member eligible for preparation');
caps[5580].dfs_state=1;check(!permitted(target,caps,[rule],[100],'prepare'),'radar prohibition cannot be prepared around');caps[5580].dfs_state=2;
let low=group(5180,160),lowcaps={};for(let f in low.members)lowcaps[f]={max_tx_power:f<5250?2300:2000,radar:f>5250,dfs_state:2};
let rules=[{reg_rule_flags:2048,freq_range_start:5150000,freq_range_end:5250000,freq_range_max_bw:80000,power_rule_max_eirp:2300},
 {reg_rule_flags:2064,freq_range_start:5250000,freq_range_end:5350000,freq_range_max_bw:80000,power_rule_max_eirp:2000}];
check(permitted(low,lowcaps,rules,[36],'available'),'AUTO_BW joins contiguous rules with per-member power checks');
rules[1].freq_range_start+=1000;check(!permitted(low,lowcaps,rules,[36],'available'),'AUTO_BW cannot bridge regulatory gap');rules[1].freq_range_start-=1000;
rules[1].reg_rule_flags=16;check(!permitted(low,lowcaps,rules,[36],'available'),'both spans require AUTO_BW');rules[1].reg_rule_flags=2064;
lowcaps[5260].max_tx_power=2300;check(!permitted(low,lowcaps,rules,[36],'available'),'AUTO_BW retains mismatch guard');
let two={};for(let f=2412;f<=2472;f+=5)two[f]={max_tx_power:2000};
let twoRule={reg_rule_flags:0,freq_range_start:2400000,freq_range_end:2483500,freq_range_max_bw:40000,power_rule_max_eirp:2000};
check(permitted(group(2432,40,2422),two,[twoRule],[5]),'HT40 manual primary need not list secondary');
two[2432].no_ht40_minus=true;check(!permitted(group(2432,40,2422),two,[twoRule],[5]),'HT40 direction restriction');
check(permitted(group(2432,40,2442),two,[twoRule],[5]),'other HT40 direction remains eligible');
let text='channel=36\nht_capab=[HT40+]\nvht_capab=[SHORT-GI-80]\nvht_oper_chwidth=1\nvht_oper_centr_freq_seg0_idx=42\nnoscan=0\n';
let wide=reconfigure_text(text,target,'5g',{vht_capa:68});
check(index(wide,'vht_oper_chwidth=2')>=0&&index(wide,'seg0_idx=114')>=0,'hostapd160 width and center');
check(index(wide,'[VHT160][SHORT-GI-160]')>=0,'advertised160 and shortGI enabled');
let narrow=reconfigure_text(wide,group(5500,80),'5g');check(index(narrow,'[VHT160]')<0&&index(narrow,'[SHORT-GI-160]')<0,'narrowing removes160-only capability configuration');
check(reconfigure_text('channel=36\nht_capab=[HT40+]\n',target,'5g')==null,'incomplete VHT template rejected');
let ht40=reconfigure_text('channel=6\nht_capab=[LDPC]\nnoscan=1\n',group(2432,40,2422),'2g');
check(index(ht40,'[HT40-]')>=0&&index(ht40,'noscan=0')>=0&&index(ht40,'obss_interval=300')>=0,'HT40 executes hostapd coexistence instead of forcing width');

// Exercise actual executor: an 80MHz helper clears both halves of a 160MHz move.
let T=100,events=[],files={},journal=null,restores=0;
for(let f in target.members)caps[f].dfs_state=0;
let state={radios:{main:{},spare:{}}};
let cfg={allow_reconnect:false,separate:false,dfs_helper:'',escalation:'gentle',protected_clients:[],cac_timeout:720,quiet_seconds:60,csa_count:15,verify_unprobed:180};
function radio(name,phy,width,radar_widths){return {name,phy,ifname:name,band:'5g',current:group(5745,width),caps:json(sprintf('%J',caps)),clients:{},authorized:{},unsafe:false,radar_widths,fingerprint:'stable',
 config:{managed:true,occupied:'handoff',method:'idle_reconfigure',width_method:'idle_reconfigure',widths:width==160?[160,80,40,20]:[80,40,20],channels:[100,104,108,112,116,120,124,128,149,153,157,161]},aps:[{status:{},config:{}}]};}
let main=radio('main',0,160,47),spare=radio('spare',2,80,15);main.current=group(5745,80);main.clients={client:true};main.authorized={client:true};
main.caps[5745]={max_tx_power:2000};spare.caps[5745]={max_tx_power:2000};
files['/var/run/hostapd-phy0.conf']=text+'ieee80211h=1\ninterface=main\n';files['/var/run/hostapd-phy2.conf']=text+'ieee80211h=1\ninterface=spare\n';
let io={cfg,state,boot:'test',now:()=>T,save:()=>{},lease:()=>{},release:()=>{},log:()=>{},history:e=>push(events,e),config_fingerprint:()=>'stable',coordination_ready:()=>{},dfs_mode:()=>'prepare',empty_interface:()=>true,
 request:()=>({reg_rules:[rule]}),phy_caps:phy=>phy==2?spare.caps:main.caps,allclients:()=>({client:true}),private_json:(p,j)=>{journal=j;},
 fs:{readfile:p=>files[p] ?? '',writefile:(p,s)=>{files[p]=s;return true;},stat:()=>journal,unlink:()=>{}},
 apply_empty_config:()=>{},restore_preparation:()=>{spare.current=journal.source;journal=null;restores++;},call:()=>({status:'ENABLED',freq:spare.current.freq}),completed:()=>{},quiet_since:{}};
let ex=create_executor(io);ex.start(main,target,[main,spare]);T+=15;ex.tick([main,spare]);
check(ex.pending().kind=='cac'&&ex.pending().helper.name=='spare'&&ex.pending().cac_target.width==80,'80MHz spare chosen without emptying occupied160 radio');
let first=ex.pending().cac_target;
spare.current=first;for(let f in first.members){spare.caps[f].dfs_state=2;main.caps[f].dfs_state=2;}
ex.event({cmd:nl.const.NL80211_CMD_RADAR_DETECT,msg:{wiphy:2,wiphy_freq:first.freq,radar_event:1}},[main,spare]);T+=65;ex.tick([main,spare]);
check(ex.pending().kind=='restore'&&restores==1,'first piece verified on both PHYs and helper restored');
T+=5;ex.tick([main,spare]);T+=15;ex.tick([main,spare]);
check(ex.pending().kind=='cac'&&!same(ex.pending().cac_target,first),'second uncleared half selected');
let second=ex.pending().cac_target;spare.current=second;for(let f in second.members)spare.caps[f].dfs_state=2;
ex.event({cmd:nl.const.NL80211_CMD_RADAR_DETECT,msg:{wiphy:2,wiphy_freq:second.freq,radar_event:1}},[main,spare]);T+=65;ex.tick([main,spare]);
check(ex.pending().kind=='cac','helper-only clearance never authorizes the serving radio');
for(let f in second.members)main.caps[f].dfs_state=2;
ex.tick([main,spare]);T+=5;ex.tick([main,spare]);
check(ex.pending().kind=='move-wait'&&ex.pending().target.width==160&&restores==2,'original160 intent retained after both preparations');
check(length(filter(events,e=>e.event=='cac-shared'))==2,'both shared checks recorded separately');
printf('PASS: %d hardware width, HT40, VHT160, regulatory and segmented DFS checks\n',checks);
