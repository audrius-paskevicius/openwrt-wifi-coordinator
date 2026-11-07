import {same,group,live_width} from '../channel-coordinator/files/policy.uc';
let checks=0,j,content,live,applies,occupied=true;
const JOURNAL='/test',boot='boot',N={NL80211_CMD_GET_INTERFACE:1,NLM_F_DUMP:2};
function check(v,s){if(!v)die('FAIL: '+s+'\n');checks++;}
function readjson(){return j;}
function request(){return live?[live]:[];}
function apply_radio_config(phy,path,ifname,allow){if(occupied&&!allow)die('not empty');push(applies,{phy,allow});}
let fs={readfile:()=>content,writefile:(p,s)=>{content=s;return true;},unlink:()=>{j=null;}};
function setup(kind){j={kind,boot,path:'/var/run/hostapd-phy1.conf',phy:'phy1',ifname:'phy1-ap0',original:'old',temporary:'new',source:group(2412,20)};content='new';live=null;applies=[];}
