'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
const source=fs.readFileSync(path.join(__dirname,'../channel-coordinator/files/wifi-coordinator.history.js'),'utf8');
let calls=0,created=0,terminated=0,hold=false,held=[],blockError=null,denied=false;
class FakeWorker{
 constructor(){created++;}
 postMessage(m){if(m.cancel)return;const deliver=()=>{
  this.onmessage({data:{id:m.id,progress:{stage:'loading',loaded:1,total:1}}});
  if(blockError){const status=blockError;blockError=null;this.onmessage({data:{id:m.id,error:'fixture error',status}});}
  else this.onmessage({data:{id:m.id,result:{start:m.metadata.start,end:m.metadata.end,read_errors:[],pixel_width:m.width}}});
 };if(hold)held.push(deliver);else queueMicrotask(deliver);}
 terminate(){terminated++;}
}
const api=new Function('baseclass','L','Worker','fetch','URLSearchParams','AbortController','setTimeout','clearTimeout',source)(
 {extend:x=>x},{env:{sessionid:'fixture',resource_version:'test'},resource:x=>'/'+x},FakeWorker,
 async()=>{calls++;return denied?{ok:false,status:403}:{ok:true,json:async()=>({protocol:4,start:1,end:100,read_errors:[],blocks:[],active:{}})};},
 URLSearchParams,AbortController,(fn,ms)=>ms===60000?0:setTimeout(fn,0),clearTimeout);
(async()=>{
 const progress=[];assert.equal((await api.read({hours:6,width:800},p=>progress.push(p))).pixel_width,800);
 assert.equal(progress.length,1);assert.equal(calls,1);
 await api.read({hours:6,width:360});await api.read({hours:6,width:800});assert.equal(calls,1,'resizing both directions uses browser data');
 await api.read({hours:6,width:800});assert.equal(calls,2,'regular refresh gets a current snapshot');
 blockError=409;await api.read({hours:12,width:800});assert.equal(calls,4,'expired block triggers fresh index before retry');
 hold=true;const pending=api.read({hours:24,width:800});await new Promise(r=>setTimeout(r,0));api.cancel();await assert.rejects(pending,e=>e.cancelled);hold=false;for(const fn of held)fn();
 denied=true;await assert.rejects(api.read({hours:24,width:800}),e=>e.status===403);assert.equal(terminated,1,'permission failure terminates cached worker');
 denied=false;await api.read({hours:24,width:800});assert.equal(created,2,'new permission-checked worker after failure');
 console.log('PASS: worker adapter, resize reuse, polling refresh, progress, expired snapshot retry, cancellation and permission cache clearing');
})().catch(e=>{console.error(e.message);process.exitCode=1;});
