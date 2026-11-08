import {dfs_policy} from '../channel-coordinator/files/policy.uc';
let region=2,report='dfs_region: 0\n',driver='../../drivers/mwlwifi',directory=true,reads=0;
let cfg={dfs_mode:'prepare'},state={radios:{r:{}}},N={NL80211_CMD_GET_REG:1};
let fs={readfile:path=>{reads++;return report;},readlink:path=>driver,stat:path=>directory};
function request(){return {dfs_region:region};}
let r={name:'r',phy:0,band:'5g',dfs_region:2};
