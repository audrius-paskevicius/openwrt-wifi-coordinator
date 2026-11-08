let checks=0;
function check(v,s){if(!v)die('FAIL: '+s+'\n');checks++;}
check(dfs_mode(r)=='off'&&index(state.radios.r.dfs_constraint,'mwlwifi')>=0,'actual runtime blocks the observed driver mismatch');
directory=false;report=null;
check(dfs_mode(r)=='off','known driver with unavailable debugfs does not silently pass');
driver='../../drivers/mwifiex_sdio';
check(dfs_mode(r)=='prepare'&&state.radios.r.dfs_constraint==null,'auxiliary driver retains matching-region DFS');
for(let value in [1,2,3]){
    region=value;r.dfs_region=value;
    check(dfs_mode(r)=='prepare','current country DFS region is accepted without ETSI-only assumption');
}
region=1;r.dfs_region=2;
check(dfs_mode(r)=='off','country-region conflict blocks new DFS use');
driver='../../drivers/mwlwifi';region=2;r.dfs_region=2;report='dfs_region: 2\n';
check(dfs_mode(r)=='prepare','corrected driver can follow current kernel region');
r.band='2g';let before=reads;
check(dfs_mode(r)=='off'&&state.radios.r.dfs_constraint==null&&reads==before,'2.4 GHz has no misleading DFS mismatch warning');
printf('PASS: %d actual DFS-runtime cases\n',checks);
