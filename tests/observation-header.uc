import {observed_placement} from '../channel-coordinator/files/observation.uc';
import {declared_bands,traffic_sample} from '../channel-coordinator/files/policy.uc';
let checks=0;function check(v,s){if(!v)die('FAIL: '+s+'\n');checks++;}
let caps={};for(let f in [2412,2432,2452,2472,2484,5500,5520,5540,5560,5580,5600,5620,5640])caps[f]={freq:f};
let live={ifname:'phy0-ap0',wiphy:0,wiphy_freq:5620,channel_width:5,center_freq1:5570};
let fixture=live,client_reads=0,state={radios:{radio0:{}}},unavailable_rows=[],regulatory=null;
let N={NL80211_CMD_GET_REG:1,NL80211_CMD_GET_INTERFACE:2,NL80211_CMD_GET_WIPHY:3,NL80211_CMD_CHANNEL_SWITCH:4,NL80211_CMD_GET_STATION:5,NLM_F_DUMP:1};
let traffic={},rates={},quiet_since={},cfg={max_mbps:0.5};
let cancellations=0,planning={cancel:()=>cancellations++,take:()=>die('Incomplete observation reached planner')},scan_result=null,estimate_cache={};
function planning_key(){die('Incomplete observation reached planning key');}
function measured(){}
function calculation(){}
function now(){return 100;}
function rcfg(){return {};}
function config_fingerprint(){return 'test';}
function call(object,method){
 if(object=='network.wireless')return {radio0:{up:true,config:{htmode:'VHT160'},interfaces:[{ifname:'phy0-ap0',config:{mode:'ap'}}]}};
 if(method=='get_status')return {status:'ENABLED'};
 if(method=='get_clients'){client_reads++;return {clients:{}};}
 die('Unexpected ubus call');
}
function request(command){
 if(command==N.NL80211_CMD_GET_REG)return {dfs_region:2};
 if(command==N.NL80211_CMD_GET_INTERFACE)return fixture?[fixture]:[];
 if(command==N.NL80211_CMD_GET_WIPHY)return [{wiphy:0,wiphy_bands:[{freqs:values(caps)}]}];
 if(command==N.NL80211_CMD_GET_STATION)return [];
 die('Unexpected netlink call');
}
