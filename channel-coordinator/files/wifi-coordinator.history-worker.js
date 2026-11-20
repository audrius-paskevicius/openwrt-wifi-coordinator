'use strict';
importScripts('history-core.js'+self.location.search);
const core=self.WifiHistoryCore,LISTS=['periods','samples','clients','events','surveys'];
const blocks=new Map(),CACHE_BYTES=16*1024*1024;
let bytes=0,storeEpoch=null,job=null;
// Yield for cancellation messages without timers that browsers throttle in
// background tabs (one timer per hour would otherwise make long views stall).
const taskChannel=new MessageChannel(),resumes=[];
taskChannel.port1.onmessage=()=>resumes.shift()?.();
function yieldTask(){return new Promise(resolve=>{resumes.push(resolve);taskChannel.port2.postMessage(0);});}
function remember(id,data){
 const text=JSON.stringify(data),size=text.length*2,old=blocks.get(id);
 if(old)bytes-=old.size;blocks.delete(id);
 if(size<=CACHE_BYTES){blocks.set(id,{text,size});bytes+=size;}
 while(bytes>CACHE_BYTES){const [key,value]=blocks.entries().next().value;blocks.delete(key);bytes-=value.size;}
}
function cached(id){
 const entry=blocks.get(id);if(!entry)return null;
 blocks.delete(id);blocks.set(id,entry);return JSON.parse(entry.text);
}
function check(current){if(job!==current||current.cancelled)throw Object.assign(Error('Request superseded'),{cancelled:true});}
function progress(current,stage,loaded,total){check(current);postMessage({id:current.id,progress:{stage,loaded,total}});}
async function batch(current,meta,ids,sessionid){
 const controller=new AbortController();current.controllers.add(controller);
 const timer=setTimeout(()=>controller.abort(),30000);
 try{
  const response=await fetch('/cgi-bin/wifi-coordinator-history',{method:'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/x-www-form-urlencoded'},
   body:new URLSearchParams({sessionid,kind:'blocks',epoch:meta.epoch,ids:ids.join(',')}).toString(),signal:controller.signal});
  if(!response.ok)throw Object.assign(Error('History block request failed ('+response.status+')'),{status:response.status});
  const result=await response.json();check(current);
  if(result.epoch!==meta.epoch||!Array.isArray(result.blocks)||result.blocks.length!==ids.length)throw Error('Invalid history block response');
  return result.blocks.map((b,i)=>{if(b.id!==ids[i]||!b.data||typeof b.data!=='object')throw Error('Unexpected history block');return b;});
 }finally{clearTimeout(timer);current.controllers.delete(controller);}
}
function merge(views){
 const result={periods:[],clients:[],samples:[],surveys:[],events:[],radio_names:[],survey_cells:[],traffic_points:{},client_points:{}},names=new Set(),latest={};
 function points(target,source,kind){
  for(const [radio,rows] of Object.entries(source||{})){
   const out=target[radio]||(target[radio]=[]),last=out[out.length-1],first=rows[0];
   if(last&&first&&last.y!=null&&first.y!=null){
    const gap=kind==='clients'?(first.x>last.x||first.interval?.source!==last.interval?.source):(first.x>last.x+300||first.source!==last.source);
    if(gap)out.push({x:first.x,y:null});
   }
   for(const row of rows)out.push(row);
  }
 }
 for(const view of views){
  for(const r of view.radio_names)names.add(r);
  for(const k of ['periods','surveys','events','survey_cells'])for(const row of view[k])result[k].push(row);
  for(const row of view.samples)if(!latest[row.radio]||row.end>latest[row.radio].end)latest[row.radio]=row;
  points(result.traffic_points,view.traffic_points,'traffic');points(result.client_points,view.client_points,'clients');
 }
 result.radio_names=Array.from(names).sort();result.samples=Object.values(latest);
 result.periods.sort((a,b)=>a.radio.localeCompare(b.radio)||a.start-b.start);
 const merged=[];
 for(const p of result.periods){
  const old=merged[merged.length-1];
  if(old&&old.radio===p.radio&&old.end===p.start&&old.channel===p.channel&&old.center===p.center&&old.width===p.width&&old.role===p.role&&!old.aggregate&&!p.aggregate)old.end=p.end;
  else merged.push({...p});
 }
 result.periods=merged;return result;
}
async function prepare(current,meta,sessionid,width){
 if(meta.protocol!==4||!Array.isArray(meta.blocks)||!meta.active)throw Error('Invalid history index');
 if(storeEpoch!==meta.epoch){blocks.clear();bytes=0;storeEpoch=meta.epoch;}
 const decoded=new Map(),missing=[];let loaded=0;
 for(const d of meta.blocks){
  const data=cached(d.id);
  if(data){decoded.set(d.id,core.unpack(data));loaded++;}else missing.push(d);
 }
 progress(current,'loading',loaded,meta.blocks.length);
 for(let at=0;at<missing.length;){
  const ids=[];let size=0;
  while(at<missing.length&&ids.length<64){
   const d=missing[at];if(ids.length&&size+d.size>1048576)break;
   ids.push(d.id);size+=d.size;at++;
  }
  for(const b of await batch(current,meta,ids,sessionid)){remember(b.id,b.data);decoded.set(b.id,core.unpack(b.data));loaded++;}
  progress(current,'loading',loaded,meta.blocks.length);
 }
 const h=Object.fromEntries(LISTS.map(k=>[k,[]]));
 function append(data){for(const k of LISTS)for(const row of data[k]||[])h[k].push(row);}
 for(const d of meta.blocks)append(decoded.get(d.id));append(meta.active);decoded.clear();
 const options={start:meta.start,end:meta.end,width,max_age:meta.max_age,canonical:true,display:meta.display,sources:['indexed']};
 function read(a,b){return Object.fromEntries(LISTS.map(k=>[k,h[k].filter(r=>(r.updated??r.end??r.time)>=a&&(r.start??r.time)<b)]));}
 let result;
 if(!options.display.decimation){
  progress(current,'preparing',0,1);
  result=core.history_view(options,()=>read(options.start-options.max_age,options.end));
 }else{
  let step=1;while(step<(options.end-options.start)/width)step*=2;
  const views=[],first=Math.trunc(options.start/3600)*3600,last=Math.trunc((options.end-1)/3600)*3600,total=(last-first)/3600+1;
  for(let a=last;a>=first;a-=3600){
   check(current);const b=Math.min(a+3600,options.end),rows=read(a-options.max_age,b);
   // Preserve the original hour boundaries, reduction widths and marker rules.
   const v=core.history_view({...options,start:a,end:b,width:Math.max(1,Math.trunc((b-a)/step))},()=>rows);
   v.periods=v.periods.map(p=>({...p,start:Math.max(a,p.start),end:Math.min(b,p.end)}));
   views.push(v);progress(current,'preparing',views.length,total);
   await yieldTask();
  }
  result=merge(views.reverse());
  const flags={action:meta.display.triangles,unknown:meta.display.squares,unavailable:meta.display.crosses};
  const events=h.events.filter(e=>(e.updated??e.end??e.time)>=options.start&&e.time<=options.end);
  result.channel_evidence=core.evidence(h.periods,events,options.start,options.end,width,true,flags,true);
  result.client_evidence=core.evidence(h.clients,events,options.start,options.end,width,true,flags,false);
 }
 check(current);
 const {blocks:descriptors,active,...status}=meta;
 return {...status,...result,actions:meta.actions,action_total:meta.action_total,start:meta.start,end:meta.end,pixel_width:width,display:meta.display,read_errors:[],preparing:0};
}
function cancel(){if(job){job.cancelled=true;for(const c of job.controllers)c.abort();}}
self.onmessage=async({data})=>{
 if(data.cancel){cancel();return;}
 cancel();const current={id:data.id,controllers:new Set(),cancelled:false};job=current;
 try{const result=await prepare(current,data.metadata,data.sessionid,data.width);check(current);postMessage({id:current.id,result});}
 catch(e){if(!e.cancelled&&!current.cancelled)postMessage({id:current.id,error:e.message,status:e.status});}
 finally{if(job===current)job=null;}
};
