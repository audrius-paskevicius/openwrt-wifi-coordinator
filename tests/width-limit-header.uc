import {group,same,same_block,overlap,survey_covers,move_method,placements,frequency,permitted} from '../channel-coordinator/files/policy.uc';
import {assess,spatial_streams} from '../channel-coordinator/files/planner.uc';
let state={radios:{r:{width_limit:{actual:20,requested:40,until:1000}}}},T=100;
function now(){return T;}function dfs_mode(){return 'off';}
let evidence={},estimate_cache={},radar={records:()=>[]};
let cfg={max_age:900,cooldown:0,retry_delay:0,radar_half_life:21600,protected_clients:[]};
let scan_result={frequencies:[],observations:[],scanners:{}};
let r={name:'r',band:'2g',current:group(2412,20),clients:{},caps:{},csa:true,
 config:{managed:true,channels:[1,5,9,13],widths:[40,20],method:'idle_reconfigure',width_method:'idle_reconfigure'}};
for(let f=2412;f<=2472;f+=5){r.caps[f]={max_tx_power:2000};push(scan_result.frequencies,f);}
let rules=[{reg_rule_flags:0,freq_range_start:2400000,freq_range_end:2483500,freq_range_max_bw:40000,power_rule_max_eirp:2000}];
