'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert'),vm=require('vm');
const root=path.join(__dirname,'../channel-coordinator/files');
function harness(){
 const messages=[],requests=[],source=new Map();let error=null;
 const context={console,URLSearchParams,AbortController,setTimeout,clearTimeout,Map,Set,Date,JSON,Math,Object,Array,Promise,Error,Number,String,encodeURIComponent,
  MessageChannel:class {constructor(){this.port1={};this.port2={postMessage:()=>setImmediate(()=>this.port1.onmessage())};}},
  location:{search:''},postMessage:m=>messages.push(m),fetch:async(url,options)=>{
   const args=new URLSearchParams(options.body),ids=args.get('ids').split(',');requests.push(ids);
   if(error)return {ok:false,status:error};
   return {ok:true,json:async()=>({epoch:args.get('epoch'),blocks:ids.map(id=>({id,data:source.get(id)}))})};
 }};
 context.self=context;context.importScripts=()=>vm.runInContext(fs.readFileSync(path.join(root,'wifi-coordinator.history-core.js'),'utf8'),context);
 vm.createContext(context);vm.runInContext(fs.readFileSync(path.join(root,'wifi-coordinator.history-worker.js'),'utf8'),context);
 let next=0;
 return {context,source,requests,messages,setError:e=>error=e,async run(metadata,width=800){
  const id=++next;await context.onmessage({data:{id,metadata,width,sessionid:'fixture'}});
  const reply=messages.find(m=>m.id===id&&(m.result||m.error));if(!reply)throw Error('No worker reply');if(reply.error)throw Object.assign(Error(reply.error),{status:reply.status});
  return JSON.parse(JSON.stringify(reply.result));
 }};
}
function fixture(){
 const end=1700500100,start=end-120*3600,h={periods:[],clients:[],samples:[],surveys:[],events:[]};
 for(const [i,radio] of ['radio0','radio1','radio2'].entries()){
  for(const [a,b,source] of [[start,end-2500,'boot-a'],[end-2000,end,'boot-b']]){
   h.periods.push({radio,start:a,end:b,channel:i===1?13:36,center:i===1?2472:5210,width:i===1?20:80,role:i===2?'radar preparation':'serving'});
   h.clients.push({radio,start:a,end:b,count:i,source});
  }
 }
 for(let t=start;t<end;t+=300){
  h.samples.push({radio:'radio0',time:t,end:t+290,channel:36,width:80,role:'serving',n:3,traffic_sum:t===end-600?90:3,traffic_peak:t===end-900?300:2,clients_peak:2,busy_sum:30,busy_n:3,source:t<end-2500?'boot-a':'boot-b'});
  h.surveys.push({time:t,updated:t+3,cycle:''+t,bands:[{start:5170,step:20,levels:[t%13,null,0,40],offsets:[0,1,2,3]}]});
 }
 h.events.push({radio:'radio0',event:'radio-unavailable',time:end-2400,start:end-2400,end:end-2300},{radio:'radio0',event:'client-departure',time:end-2000,reason:'fixture'},{event:'radar-state',time:end-1800,radio:'radio0',center:5250,width:80});
 return {h,end};
}
module.exports={harness,fixture};
if(require.main===module||!process.env.HISTORY_TEST_IMPORT){(async()=>{
 const t=harness(),{h,end}=fixture(),empty={periods:[],clients:[],samples:[],surveys:[],events:[]},id='a'.repeat(64);
 t.source.set(id,h);
 const meta={protocol:4,epoch:'a'.repeat(16),blocks:[{id,size:10000}],active:empty,start:end-3600,end,max_age:900,actions:[],action_total:10,read_errors:[],display:{decimation:true,triangles:true,squares:true,crosses:true,popups:true}};
 for(const hours of [1,3,6,12,24,48,72,96,120])for(const width of [360,1100])for(const decimation of [true,false]){
  const v=await t.run({...meta,start:end-hours*3600,display:{...meta.display,decimation}},width);
  assert.equal(v.start,end-hours*3600);assert.equal(v.end,end);assert.equal(v.preparing,0);assert.equal(v.action_total,10);
  assert(v.client_points.radio0.some(p=>p.y===0));assert(v.client_points.radio0.some(p=>p.y===null));
  assert(v.channel_evidence.some(p=>p.kind==='unknown'));assert(v.channel_evidence.some(p=>p.kind==='unavailable'));
  assert(v.traffic_points.radio0.some(p=>p.peak===300));assert(v.survey_cells.every(c=>Number.isFinite(c[5])));
 }
 assert.equal(t.requests.length,1,'all spans, widths and detail modes reuse immutable blocks');
 const hidden=await t.run({...meta,display:{...meta.display,triangles:false,squares:false,crosses:false}});
 assert.equal(hidden.channel_evidence.length,0);assert.equal(hidden.client_evidence.length,0);
 await t.run({...meta,epoch:'b'.repeat(16)});assert.equal(t.requests.length,2,'clearing history invalidates block cache');
 const bad='b'.repeat(64);t.setError(409);await assert.rejects(t.run({...meta,blocks:[{id:bad,size:1}]}),e=>e.status===409);
 t.setError(403);await assert.rejects(t.run({...meta,blocks:[{id:bad,size:1}]}),e=>e.status===403);
 t.setError(null);const many=Array.from({length:70},(_,i)=>({id:(i+1).toString(16).padStart(64,'0'),size:100}));
 for(const d of many)t.source.set(d.id,empty);
 const before=t.requests.length;await t.run({...meta,epoch:'c'.repeat(16),blocks:many,active:h});
 assert.equal(t.requests.length-before,2);assert.equal(t.requests[before].length,64,'small blocks share a bounded batch');
 const large=many.slice(0,3).map(d=>({...d,size:600000})),start=t.requests.length;
 await t.run({...meta,epoch:'d'.repeat(16),blocks:large,active:h});
 assert.equal(t.requests.length-start,3,'normal batches stay within the byte budget');
 const progress=t.messages.filter(m=>m.progress);assert(progress.every(m=>m.progress.loaded<=m.progress.total));
 console.log('PASS: browser worker, all nine spans, phone/desktop widths, full/reduced detail, zeroes/gaps/peaks/markers, immutable reuse, epoch invalidation and failures');
})().catch(e=>{console.error(e.message);process.exitCode=1;});}
