import {dfs_policy,group,permitted,dfs_ready} from '../channel-coordinator/files/policy.uc';
import {assess} from '../channel-coordinator/files/planner.uc';
let region=2,reads=0;
let cfg={dfs_mode:'prepare'},state={radios:{r:{}}},N={NL80211_CMD_GET_REG:1};
// Any attempted private-driver inspection fails the actual runtime test.
let fs={readfile:()=>die('Unexpected debugfs dependency'),readlink:()=>die('Unexpected sysfs dependency'),stat:()=>die('Unexpected private-driver dependency')};
function request(){reads++;return {dfs_region:region};}
let r={name:'r',phy:0,band:'5g',dfs_region:2};
