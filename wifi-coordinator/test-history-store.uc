import * as fs from 'fs';
import {initialize,restore,manifest,read_block,checkpoint,snapshot,clear_store,assign_ids,cleanup,fail_at,repack_store} from './history-store-test.uc';
import {empty,pack,unpack,LISTS} from '../channel-coordinator/files/history-codec.uc';
import {clean} from '../channel-coordinator/files/history-export.uc';
const DIR='/tmp/wifi-history-test-archive',RAM='/tmp/wifi-history-test.json';
let checks=0,T=1800000000;
function check(ok,msg){if(!ok)die('FAIL: '+msg+'\n');checks++;}
function reset(){fs.unlink(RAM);if(!fs.stat(DIR))fs.mkdir(DIR,0700);for(let n in fs.lsdir(DIR))if(match(n,/^(block-|tail-|batch-|history-index|history-migration)/))fs.unlink(DIR+'/'+n);}
function all(){let s=snapshot(),out=empty();for(let d in s.manifest.blocks){let h=read_block(d);for(let k in LISTS)out[k]=[...out[k],...h[k]];}for(let k in LISTS)out[k]=[...out[k],...s.active[k]];s.release();return out;}
function publish(h){fs.writefile(RAM,sprintf('%J',h));}
reset();
let original=empty();original.surveys=[];
for(let i=0;i<40;i++)push(original.surveys,{time:T+i*19,updated:T+i*19+8,cycle:'boot:'+i,bands:[{start:2400,step:5,levels:[0,0,i%3,null,20],offsets:[0,4,8,null,2]}]});
let encoded=pack(original);check(sprintf('%J',unpack(encoded))==sprintf('%J',original),'lossless survey values, nulls, offsets, frame identities');
check(length(sprintf('%J',encoded))<length(sprintf('%J',original)),'column encoding reduces repeated survey storage');
original.events=[{time:T,event:'a'},{time:T,event:'a'}];original.periods=[{radio:'radio0',start:T,end:T+10,channel:36,width:80,center:5210}];
fs.writefile(DIR+'/batch-'+T+'.json',sprintf('%J',original));
let newer=empty();newer.periods=[{...original.periods[0],end:T+30}];newer.events=[{time:T+1,event:'b'}];publish(newer);
let m=initialize('boot',120,T+1000),rows=all();
check(length(rows.events)==2&&length(rows.periods)==1&&rows.periods[0].end==T+30,'one-time normalization matches legacy latest-revision semantics');
check(length(rows.surveys)==40,'migration retains every survey frame');
check(fs.stat(DIR+'/batch-'+T+'.json')!=null,'migration originals remain available');
check(initialize('boot',120,T+1001).revision==m.revision,'initialization is idempotent');
let h=restore('boot',120,T+1001);push(h.events,{time:T+1002,event:'new'});push(h.periods,{radio:'radio0',start:T+1001,end:T+1002,channel:40,width:20,center:5200});assign_ids(h);publish(h);
check(length(all().events)==3,'snapshot includes unsaved records');
checkpoint(h,T+1003,120,false);publish(h);let first=manifest();
check(length(h.events)==0&&length(h.periods)==1,'completed records released only after commit; active interval retained');
check(length(all().events)==3&&length(all().periods)==2,'committed data appears once');
let immutable=map(first.blocks,d=>[d.name,d.sha256]);
h.periods[0].end=T+1008;publish(h);check(all().periods[1].end==T+1008,'RAM advances the committed active checkpoint');
checkpoint(h,T+1009,120,false);publish(h);
for(let d in immutable)check(length(filter(manifest().blocks,b=>b.name==d[0]&&b.sha256==d[1])),'closed blocks never rewritten');
h.periods[0].end=T+1010;checkpoint(h,T+1011,120,false);
h=restore('boot',120,T+1012);check(h.periods[0].end==T+1010,'durable active checkpoint wins over stale RAM after interrupted publication');publish(h);
fs.unlink(RAM);let reboot=restore('next-boot',120,T+1013);check(reboot.periods[0].end==T+1010,'cold reboot restores durable active checkpoint');
checkpoint(reboot,T+1014,120,false);publish(reboot);check(length(reboot.periods)==0&&length(all().periods)==2,'prior-boot active interval is finalized without continuity invention');
for(let stage in ['blocks-written','before-manifest','after-manifest']){
 let current=restore('next-boot',120,T+1020);push(current.events,{time:T+1021,event:stage});assign_ids(current);publish(current);let before=length(all().events);
 fail_at(stage);let failed=false;try{checkpoint(current,T+1022,120,false);}catch(e){failed=true;}
 check(failed,'fault injection '+stage);
 let recovered=restore('next-boot',120,T+1023);publish(recovered);checkpoint(recovered,T+1024,120,false);publish(recovered);
 check(length(all().events)==before,'retry/recovery never duplicates or loses committed records: '+stage);
 checkpoint(recovered,T+1025,120,false);publish(recovered);check(length(all().events)==before,'repeated recovery remains idempotent');
}
// A pinned reader can finish even while retention removes its generation.
let pin=snapshot(),old=pin.manifest.blocks[0];let current=restore('next-boot',120,T+2000);
checkpoint(current,T+600000,1,false);publish(current);
check(fs.stat(DIR+'/'+old.name)!=null&&read_block(old)!=null,'retention respects active export lease');
pin.release();cleanup(manifest());check(fs.stat(DIR+'/'+old.name)==null,'expired block released after reader finishes');
current=restore('next-boot',120,T+600001);push(current.events,{time:T+600002,event:'integrity'});assign_ids(current);checkpoint(current,T+600003,120,false);publish(current);
let d=manifest().blocks[0],path=DIR+'/'+d.name,text=fs.readfile(path);fs.writefile(path,substr(text,0,length(text)-3));let corrupt=false;try{read_block(d);}catch(e){corrupt=true;}check(corrupt,'truncated committed block fails visibly');fs.writefile(path,text);
let before_repack=all();repack_store();let after_repack=all();check(length(after_repack.events)==length(before_repack.events)&&after_repack.events[0]._id==before_repack.events[0]._id,'lossless repack preserves identities and counts');
let epoch=manifest().epoch;clear_store('next-boot',T+600004,120);check(manifest().epoch!=epoch&&length(all().events)==0,'clear changes epoch and excludes stale RAM');
reset();print(sprintf('PASS: %d canonical storage, codec, migration, interruption, integrity and snapshot checks\n',checks));
