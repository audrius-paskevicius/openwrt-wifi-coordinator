#!/usr/bin/ucode
// Fill missing choices and remove retired internal tuning options.
import * as uci from 'uci';
import * as fs from 'fs';
let c=uci.cursor(getenv('WIFI_COORDINATOR_CONFIG_DIR') ?? '/etc/config');
for(let key in ['retry_delay','scan_wait','scan_batch','cac_timeout','csa_count','ban_seconds'])
    c.delete('channel_coordinator','main',key);
let board=trim(fs.readfile('/tmp/sysinfo/board_name') ?? '');
let wrt=index(['linksys,wrt3200acm','linksys,wrt32x'],board)>=0;
let radios=[];c.foreach('wireless','wifi-device',r=>push(radios,r));
let preferred=filter(radios,r=>r.band=='5g')[0] ?? radios[0];
if(wrt)preferred=filter(radios,r=>r['.name']=='radio0')[0] ?? preferred;
if(!c.get('radio_prefer','main','preferred_radio')&&preferred)c.set('radio_prefer','main','preferred_radio',preferred['.name']);
for(let r in radios){
    let name=r['.name'];
    if(!c.get_all('channel_coordinator',name))c.set('channel_coordinator',name,'radio');
    let defaults={managed:'1',occupied_policy:'handoff',method:'auto',width_method:'auto',
        channels:'auto',
        widths:'auto'};
    for(let key,value in defaults)if(c.get('channel_coordinator',name,key)==null)c.set('channel_coordinator',name,key,value);
}
if(ARGV[0]=='--apply'){
    for(let config in ['channel_coordinator','radio_prefer'])
        if(length(c.changes(config) ?? {})&&!c.commit(config))die('Could not save inferred radio roles\n');
    print('Missing radio roles filled; existing settings preserved\n');
}else print(sprintf('%J\n',c.changes()));
