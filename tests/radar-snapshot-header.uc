import * as fs from 'fs';
import {open_memory} from '../channel-coordinator/files/radar.uc';
let path='/tmp/wifi-radar-snapshot-test.json',T=0,W=100000;
fs.unlink(path);fs.unlink(path+'.new');
let radar=open_memory(path,3600,()=>W,()=>T),state={},cfg={mode:'observe',radar_half_life:3600};
let next_eval=0,persist_queue={},next_persist=0,STATE='mock',written;
function now(){return T;}
function atomic(path,value){written=json(sprintf('%J',value));}
