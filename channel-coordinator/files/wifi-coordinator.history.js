'use strict';
'require baseclass';
var pending=new Map(),cache=new Map(),controllers=new Set(),epoch=0,worker=null,jobs=new Map(),nextJob=0,metadata=null,cacheBytes=0;
function stopWorker(){
 if(worker)worker.terminate();worker=null;
 for(const job of jobs.values())job.reject(Object.assign(Error('Request superseded'),{cancelled:true}));jobs.clear();
}
function prepare(h,options,generation,onProgress){
 if(typeof Worker==='undefined')return Promise.reject(Error('This browser does not support history workers'));
 if(!worker){
  worker=new Worker(L.resource('wifi-coordinator/history-worker.js')+(L.env.resource_version?'?v='+encodeURIComponent(L.env.resource_version):''));
  worker.onmessage=function(event){
   var m=event.data,job=jobs.get(m.id);if(!job)return;
   if(m.progress){if(job.generation===epoch&&job.onProgress)job.onProgress(m.progress);return;}
   jobs.delete(m.id);if(job.generation!==epoch){job.reject(Object.assign(Error('Request superseded'),{cancelled:true}));return;}
   m.error?job.reject(Object.assign(Error(m.error),{status:m.status})):job.resolve(m.result);
  };
  worker.onerror=function(){var failed=Array.from(jobs.values());jobs.clear();worker.terminate();worker=null;for(const job of failed)job.reject(Error('History worker failed'));};
 }
 return new Promise((resolve,reject)=>{var id=++nextJob;jobs.set(id,{resolve,reject,generation,onProgress});worker.postMessage({id,metadata:h,width:options.width,sessionid:L.env.sessionid});});
}
function cancel(){
 epoch++;for(const c of controllers)c.abort();if(worker)worker.postMessage({cancel:true});
 for(const job of jobs.values())job.reject(Object.assign(Error('Request superseded'),{cancelled:true}));jobs.clear();
}
function cacheKey(options){return JSON.stringify([options.hours,options.width,options.kind||'graphs',options.offset||0,options.end||0]);}
async function query(options,onProgress){
 var generation=epoch,isGraph=(options.kind||'graphs')==='graphs',key=JSON.stringify([options.hours,options.end||0]);
 for(var attempt=0;;attempt++){
  var controller=new AbortController();controllers.add(controller);var timer=setTimeout(()=>controller.abort(),60000);
  try{
   var h;
   // A resize needs new browser calculations, not another router snapshot.
   if(isGraph&&metadata&&metadata.key===key&&metadata.width!==options.width&&Date.now()-metadata.at<60000){h=metadata.value;metadata.width=options.width;}
   else{
    var params=new URLSearchParams(Object.assign({sessionid:L.env.sessionid,kind:'graphs'},options));
    var response=await fetch('/cgi-bin/wifi-coordinator-history',{method:'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:params.toString(),signal:controller.signal});
    if(!response.ok){var e=Error('History request failed ('+response.status+')');e.status=response.status;throw e;}
    h=await response.json();
    if(!h||!Array.isArray(h.read_errors)||!Number.isFinite(h.start)||!Number.isFinite(h.end))throw Error('Invalid history response');
    if(isGraph&&h.protocol===4)metadata={key,width:options.width,at:Date.now(),value:h};
   }
   if(generation!==epoch)throw Object.assign(Error('Request superseded'),{cancelled:true});
   if(isGraph&&h.protocol===4)return await prepare(h,options,generation,onProgress);
   return h;
  }catch(e){
   if(generation!==epoch)e.cancelled=true;
   if(e.status===409)metadata=null;
   if(e.cancelled||attempt>=2||e.status&&e.status<500&&e.status!==409)throw e;
   await new Promise(resolve=>setTimeout(resolve,attempt?750:250));
  }finally{clearTimeout(timer);controllers.delete(controller);}
 }
}
function read(options,onProgress){
 var key=cacheKey(options);if(pending.has(key))return pending.get(key);
 var promise=query(options,onProgress).then(function(h){
  var old=cache.get(key);if(old)cacheBytes-=old.size;cache.delete(key);
  var size=JSON.stringify(h).length*2;cache.set(key,{data:h,size});cacheBytes+=size;
  while(cache.size>1&&(cache.size>6||cacheBytes>16777216)){var entry=cache.entries().next().value;cache.delete(entry[0]);cacheBytes-=entry[1].size;}
  return h;
 }).catch(function(e){
  if(e.cancelled)throw e;
  if(e.status==401||e.status==403){cache.clear();cacheBytes=0;metadata=null;stopWorker();throw e;}
  var old=cache.get(key);if(!old)throw e;
  return Object.assign({},old.data,{refresh_warning:'History refresh failed; showing the previous response for this time window. Retrying automatically. '+e.message});
 }).finally(()=>pending.delete(key));
 pending.set(key,promise);return promise;
}
return baseclass.extend({read:read,cancel:cancel});
