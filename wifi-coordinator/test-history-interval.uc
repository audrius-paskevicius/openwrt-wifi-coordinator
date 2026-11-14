import * as fs from 'fs';
import {open_history,set_now} from './history-test-module.uc';
import {save_interval} from './history-storage-test.uc';
import {history as read_archive,archive as archive_info} from './history-assertions.uc';
import {fail_at} from './history-store-test.uc';
const PATH='/tmp/wifi-history-test.json';
let checks=0;
function check(ok,why){if(!ok)die('FAIL: '+why+'\n');checks++;}
function snapshot(){return json(fs.readfile(PATH));}
let start=int(time()/21600)*21600;
check(save_interval(null,120)==21600,'missing setting preserves six-hour default');
check(save_interval(1,120)==900&&save_interval(999,120)==21600,'storage bounds the interval');
check(save_interval(360,1)==3600,'short retention cannot expire unsaved records before the scheduled save');
for(let minutes in [15,30,60,180,360,45]){
 set_now(start);let h=open_history('interval-test',true,120,minutes);h.clear();h.event({event:'first'});
 check(snapshot().archive_interval==minutes*60&&snapshot().archive_next==start+minutes*60,'configured schedule is reported');
 set_now(start+minutes*60-1);h.flush(true);check(!length(archive_info().files),'no early scheduled flash write');
 set_now(start+minutes*60);h.flush(true);check(archive_info().revision==2&&read_archive().events[0].event=='first','record saved when selected interval becomes due');
 h.event({event:'second'});set_now(start+minutes*120);h.flush(true);
 check(archive_info().revision==3&&length(read_archive().events)==2,'successive checkpoints preserve boundary records exactly');
 h.clear();start+=50000;
}
set_now(start);let h=open_history('change-test',true,120,360);h.clear();h.event({event:'before-change'});
set_now(start+1800);h=open_history('change-test',true,120,15);h.flush(true);
check(archive_info().saved==start+1800,'shortening interval saves already overdue same-boot records');
h.event({event:'after-change'});h=open_history('change-test',true,120,180);h.flush(true);
check(archive_info().revision==2&&snapshot().archive_next==start+1800+10800,'lengthening interval preserves last attempt and pending records');
set_now(start+1801);check(h.shutdown()&&length(read_archive().events)==2,'shutdown saves pending history without waiting for selected interval');
h.clear();start+=50000;set_now(start);h=open_history('retention-test',true,1,360);h.clear();h.event({event:'short-retention'});
set_now(start+3600);h.flush(true);
check(snapshot().archive_interval==3600&&length(read_archive().events)==1,'one-hour retention checkpoints its boundary record');
h.clear();start+=50000;set_now(start);h=open_history('failure-test',true,120,15);h.clear();h.event({event:'unsaved'});
let collision='/tmp/wifi-history-test-archive/batch-'+(start+900)+'.json.new';fail_at('before-manifest');
set_now(start+900);h.flush(true);
check(snapshot().archive_error!=null&&index(snapshot().archive_error,'15 minutes')>=0&&length(snapshot().events)==1,'write failure reports selected retry interval and retains data');
set_now(start+901);h=open_history('failure-test',true,120,15);h.flush(true);
check(!length(archive_info().files)&&snapshot().archive_next==start+1800,'restart does not trigger rapid failed-write retries');
set_now(start+1800);h.flush(true);check(snapshot().archive_error==null&&length(read_archive().events)==1,'next scheduled retry recovers the unsaved record');
h.clear();
print(sprintf('PASS: %d configurable history interval checks\n',checks));
