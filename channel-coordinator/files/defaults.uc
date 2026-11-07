#!/usr/bin/ucode
// Fill only missing choices. Existing administrator settings always win.
import * as uci from 'uci';
import * as fs from 'fs';
let c=uci.cursor(getenv('WIFI_COORDINATOR_CONFIG_DIR') ?? '/etc/config');
let board=trim(fs.readfile('/tmp/sysinfo/board_name') ?? '');
let wrt=index(['linksys,wrt3200acm','linksys,wrt32x'],board)>=0;
let radios=[];c.foreach('wireless','wifi-device',r=>push(radios,r));
let preferred=filter(radios,r=>r.band=='5g')[0] ?? radios[0];
if(wrt)preferred=filter(radios,r=>r['.name']=='radio0')[0] ?? preferred;
if(!c.get('radio_prefer','main','preferred_radio')&&preferred)c.set('radio_prefer','main','preferred_radio',preferred['.name']);
for(let r in radios){
    let name=r['.name'],two=r.band=='2g';
    if(!c.get_all('channel_coordinator',name))c.set('channel_coordinator',name,'radio');
    let defaults={managed:'1',occupied_policy:'handoff',method:wrt&&name=='radio2'?'idle_reconfigure':'csa',
        channels:two?'1 2 3 4 5 6 7 8 9 10 11 12 13':'36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161',
        widths:two?'20':'80 40 20'};
    if(wrt&&!two)defaults.width_method='idle_reconfigure';
    for(let key,value in defaults)if(c.get('channel_coordinator',name,key)==null)c.set('channel_coordinator',name,key,value);
}
if(ARGV[0]=='--apply'){
    for(let config in ['channel_coordinator','radio_prefer'])
        if(length(c.changes(config) ?? {})&&!c.commit(config))die('Could not save inferred radio roles\n');
    print('Missing radio roles filled; existing settings preserved\n');
}else print(sprintf('%J\n',c.changes()));
