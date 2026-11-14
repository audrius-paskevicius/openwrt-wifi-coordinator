import * as fs from 'fs';
import * as uloop from 'uloop';
import {create_job} from './planning-job-test.uc';
const PREFIX='/tmp/wifi-coordinator-plan-test.';
function clock(){return +split(fs.readfile('/proc/uptime'),' ')[0];}
let checks=0;function check(v,s){if(!v)die('FAIL: '+s+'\n');checks++;}
let data=[];for(let i=0;i<3000;i++)push(data,{index:i,channel:124,width:160,members:[5500,5520,5540,5560,5580,5600,5620,5640],service:286.08,note:'large result with Unicode \u2013 and nested fields'});
let expected=sprintf('%J',data),reports=[],offset=0,phase=0,round=0,tick,start=clock(),ticks=0;
uloop.init();
let job=create_job({now:()=>clock()+offset,report:(...args)=>push(reports,args)});
function paths(){return fs.glob(PREFIX+'*');}
check(!length(paths()),'no leftover test jobs');
let orphan=fs.mkdtemp(PREFIX+'XXXXXX');fs.writefile(orphan+'/owner','{"pid":99999999,"start":"0"}');fs.writefile(orphan+'/pending','partial');
job=create_job({now:()=>clock()+offset,report:(...args)=>push(reports,args)});
check(!fs.stat(orphan),'restart reaps dead owner and partial result');
job.start('comparison','large',()=>data);
let live_dir=paths()[0];create_job({now:clock,report:()=>{}});
check(!!fs.stat(live_dir),'another manager preserves a live owner');
tick=uloop.timer(5,()=>{
 ticks++;if(clock()-start>45)die('Transfer test timed out');
 if(phase==0){
  let result=job.take('comparison','large');if(!result){tick.set(5);return;}
  check(!result.error&&sprintf('%J',result.value)==expected,'large result is complete and lossless');
  check(!length(paths()),'successful result cleaned');
  if(++round<80){job.start('comparison','large',()=>data);tick.set(5);return;}
  job.start('comparison','oversize',()=>join('',map([1,2,3,4,5,6,7,8,9,10],()=>expected)));phase=1;
 }else if(phase==1){
  let result=job.take('comparison','oversize');if(!result){tick.set(5);return;}
  check(index(result.error,'size limit')>=0&&!length(paths()),'oversized result rejected and cleaned');
  job.start('comparison','corrupt',()=>{let until=clock()+0.2;while(clock()<until){};return data;});
  fs.writefile(paths()[0]+'/result','{"id":');
  check(!!job.take('comparison','corrupt').error&&!length(paths()),'truncated result rejected and worker cancelled');
  phase=2;
 }else if(phase==2){
  check(!length(paths()),'cancelled worker cannot recreate deleted result');
  job.start('comparison','wrong',()=>{let until=clock()+0.2;while(clock()<until){};return data;});
  fs.writefile(paths()[0]+'/result','{"id":-1,"value":true}');
  check(!!job.take('comparison','wrong').error&&!length(paths()),'wrong job identity rejected');
  job.start('comparison','gone',()=>exit(0));phase=3;
 }else if(phase==3){
  let result=job.take('comparison','gone');if(!result){tick.set(5);return;}
  check(!!result.error&&!length(paths()),'worker exit without publication fails explicitly');
  check(ticks>=80,'event loop kept running throughout transfers');
  printf('PASS: %d large-result, integrity, cleanup and restart checks; 80 transfers of %d bytes in %.2f seconds\n',checks,length(expected),clock()-start);
  uloop.end();return;
 }
 tick.set(10);
});
uloop.run();
