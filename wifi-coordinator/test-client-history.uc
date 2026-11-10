import * as fs from 'fs';
import {open_history,set_now} from './history-test-module.uc';
import {read_archive,merge_history,prune,bounded} from './history-storage-test.uc';
let checks=0;function check(v,msg){if(!v)die(msg);checks++;}
let t=1000000,path='/tmp/wifi-history-test.json';
function read(){return json(fs.readfile(path));}
function row(count){return {radio:'radio0',channel:36,center:5210,width:80,role:'serving',clients:count,traffic:0};}
set_now(t);let h=open_history('counts',true,24);h.clear();
h.record([row(0)]);set_now(t+5);h.record([row(0)]);h.flush(true);
check(length(read().clients)==1&&read().clients[0].count==0&&read().clients[0].end==t+5,'zero is recorded and unchanged counts compact');
set_now(t+10);h.record([row(2)]);h.flush(true);
check(length(read().clients)==2&&read().clients[0].end==t+10&&read().clients[1].start==t+10,'change closes old interval at new observation');
set_now(t+15);h=open_history('counts',true,24);h.record([row(2)]);h.flush(true);
check(length(read().clients)==2&&read().clients[1].end==t+15,'same-boot restart extends count');
check(h.shutdown(),'client history checkpoint succeeds');
set_now(t+20);h.record([row(2)]);h.flush(true);
let merged=merge_history(read_archive(),read());
check(length(merged.clients)==2&&merged.clients[1].end==t+20,'RAM/archive extension deduplicated');
set_now(t+40);h.record([row(2)]);h.flush(true);
check(length(read().clients)==3&&read().clients[1].end==t+20,'missing observations leave a gap');
set_now(t+45);h=open_history('counts',false,24);h.record([row(4)]);h.flush(true);
check(length(read().clients)==3,'disabled recording adds no counts');
set_now(t+50);h=open_history('reboot',true,24);h.record([row(1)]);h.flush(true);
check(length(read().clients)==1&&read().clients[0].source=='reboot','new boot resets RAM');
check(length(read_archive().clients)==2,'reboot retains archived counts');
let old=read();delete old.clients;fs.writefile(path,sprintf('%J',old));
set_now(t+55);h=open_history('reboot',true,24);h.record([row(3)]);h.flush(true);
check(length(read().clients)==1&&length(read().samples)>0,'older RAM gains counts without losing existing summaries');
let small={clients:[{radio:'radio0',start:1,end:2,count:0},{radio:'radio0',start:3,end:4,count:1}]};
prune(small,3);check(length(small.clients)==1&&small.clients[0].count==1,'client interval retention uses last observation');
small.clients[0].padding=join('',map([1,2,3,4,5],x=>'abcdefghijklmnopqrstuvwxyz'));
check(length(bounded(small,100))<=100&&!length(small.clients),'counts share bounded RAM eviction');
h.clear();check(!length(read().clients)&&!length(read_archive().clients),'clear removes both tiers');
printf('PASS: %d client-count recording, continuity, migration and storage checks\n',checks);
