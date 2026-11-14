#!/usr/bin/ucode
// Called after the daemon exits, only by the orderly system-shutdown hook.
import * as fs from 'fs';
import * as uci from 'uci';
import {open_history} from './history.uc';
import {open_memory} from './radar.uc';
let c=uci.cursor(),boot=trim(fs.readfile('/proc/sys/kernel/random/boot_id'));
let h=open_history(boot,c.get('channel_coordinator','main','history_enabled')!='0',int(c.get('channel_coordinator','main','history_hours') ?? 24),int(c.get('channel_coordinator','main','history_save_minutes') ?? 360));
if(!h.shutdown())die('Could not save all recent Wi-Fi history at shutdown; check free flash space\n');
let state={};try{state=json(fs.readfile('/tmp/channel-coordinator-state.json'));}catch(e){}
let radar=open_memory('/etc/wifi-coordinator/radar-memory.json',int(c.get('channel_coordinator','main','radar_half_life') ?? 3600),time,
    ()=>int(split(fs.readfile('/proc/uptime'),' ')[0]),state.boot==boot?state.radar?.events:[]);
if(!radar.flush(true))die('Could not save recent radar memory at shutdown\n');
if(system('sync')!=0)die('Could not synchronize history checkpoint\n');
print('Recent Wi-Fi history checkpoint complete\n');
