import * as fs from 'fs';
import {open_history,set_now} from './history-test-module.uc';
import {history,archive} from './history-assertions.uc';
import {manifest,fail_at} from './history-store-test.uc';
import {prune} from './history-storage-test.uc';
let checks=0;function check(ok,msg){if(!ok)die('FAIL: '+msg+'\n');checks++;}
const PATH='/tmp/wifi-history-test.json';
let start=int(time()/21600)*21600;
function row(n){return {radio:'radio'+n,channel:n==1?6:36,center:n==1?2437:5210,width:n==1?20:80,role:'serving',traffic:n+1,clients:1,busy:20,signal:-60};}
set_now(start);let h=open_history('simulation',true,120,360);h.clear();
let fingerprints={},max_ram=0;
for(let i=0;i<=1512;i++){
 set_now(start+i*300);h.record([row(0),row(1),row(2)]);
 h.survey([{center:2412,width:20,signal:-55,load:null},{center:5210,width:80,signal:-50,load:10}],[2412,2437,2462,5180,5200,5220,5240],'cycle-'+i);
 h.event({event:'test-action',radio:'radio0',reason:'Observation '+i});
 if(i%72==0){
  for(let d in manifest().blocks){if(fingerprints[d.name])check(fingerprints[d.name]==d.sha256,'completed block identity never changes');fingerprints[d.name]=d.sha256;}
  max_ram=max(max_ram,fs.stat(PATH).size);
 }
}
let out=history(),cutoff=start+1512*300-120*3600;prune(out,cutoff);let ram=json(fs.readfile(PATH));
check(length(out.samples)==4323,'all 120-hour traffic summaries preserved');
check(length(out.surveys)==1441,'all 120-hour surveys preserved');
check(length(filter(out.events,e=>e.event=='test-action'))==1441,'all actions preserved');
check(!length(filter(out.samples,s=>s.traffic_sum/s.n!=int(substr(s.radio,5))+1)),'recorded traffic values unchanged');
check(max_ram<=1048576&&!ram.dropped_records,'bounded RAM without dropped records');
check(length(ram.samples)<=3,'completed traffic leaves RAM after save');
let ids={};for(let k in ['periods','samples','clients','events','surveys'])for(let r in out[k]){check(!ids[r._id],'one authoritative occurrence per record');ids[r._id]=true;}
let before=manifest().revision;h.flush(true);check(manifest().revision==before,'ordinary RAM flush does not rewrite archive');
set_now(start+1512*300+5);h.event({event:'shutdown-test'});check(h.shutdown(),'orderly shutdown commits pending data');
fs.unlink(PATH);set_now(start+1512*300+30);h=open_history('new-boot',true,120,360);h.flush(true);
check(length(filter(history().events,e=>e.event=='shutdown-test'))==1,'cold reboot retains committed event once');
h.record([row(0)]);h.flush(true);let sample=json(fs.readfile(PATH)).samples[0];check(sample.source=='new-boot','cold reboot starts a distinct measurement session');
// Inject a scheduled write failure, then recover without discarding pending data.
set_now(start+1512*300+21630);fail_at('before-manifest');h.event({event:'retry-test'});h.flush(true);
check(json(fs.readfile(PATH)).archive_error!=null,'write failure is visible');
set_now(start+1512*300+43230);h.flush(true);
check(json(fs.readfile(PATH)).archive_error==null&&length(filter(history().events,e=>e.event=='retry-test'))==1,'scheduled retry commits once');
h.clear();check(!length(history().samples)&&!length(history().events),'explicit clear empties both tiers');
print(sprintf('PASS: %d canonical retention, immutable-block, exact-once, bounded-RAM and recovery checks\n',checks));
