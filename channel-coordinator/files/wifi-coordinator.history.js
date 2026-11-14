'use strict';
'require baseclass';
var pending=new Map(),cache=new Map(),tiles=new Map(),tileBytes=0,controllers=new Set(),epoch=0;
function tileInventory(){return Array.from(tiles.keys()).slice(-256).join(',');}
function assemble(h){
 if(h.protocol!==3)return h;
 var result=Object.assign({},h,{periods:[],clients:[],samples:[],surveys:[],events:[],radio_names:[],survey_cells:[],traffic_points:{},client_points:{}}),names=new Set(),latest={};
 function points(target,source,kind){Object.entries(source||{}).forEach(([radio,rows])=>{var out=target[radio]||(target[radio]=[]),last=out[out.length-1],first=rows[0];
  if(last&&first&&last.y!=null&&first.y!=null){var gap=kind==='clients'?(first.x>last.x||first.interval?.source!==last.interval?.source):(first.x>last.x+300||first.source!==last.source);if(gap)out.push({x:first.x,y:null});}
  out.push(...rows);
 });}
 for(const tile of h.tiles){
  if(tile.pending)continue;
  if(tile.data){var size=JSON.stringify(tile.data).length*2,old=tiles.get(tile.id);if(old)tileBytes-=old.size;tiles.delete(tile.id);tiles.set(tile.id,{data:tile.data,size});tileBytes+=size;}
  const entry=tiles.get(tile.id);if(!entry)throw Error('A required graph tile was evicted');const v=entry.data;
  (v.radio_names||[]).forEach(r=>names.add(r));result.periods.push(...(v.periods||[]));result.surveys.push(...(v.surveys||[]));result.events.push(...(v.events||[]));result.survey_cells.push(...(v.survey_cells||[]));
  for(const row of v.samples||[])if(!latest[row.radio]||row.end>latest[row.radio].end)latest[row.radio]=row;
  points(result.traffic_points,v.traffic_points,'traffic');points(result.client_points,v.client_points,'clients');
 }
 // Evict only after assembling this response, so a wide response can be consumed
 // even when not all its tiles fit the next request's bounded cache.
 while(tileBytes>8388608&&tiles.size){const [id,entry]=tiles.entries().next().value;tiles.delete(id);tileBytes-=entry.size;}
 result.radio_names=Array.from(names).sort();result.samples=Object.values(latest);
 result.periods.sort((a,b)=>a.radio.localeCompare(b.radio)||a.start-b.start);var merged=[];
 for(const p of result.periods){var old=merged[merged.length-1];if(old&&old.radio===p.radio&&old.end===p.start&&old.channel===p.channel&&old.center===p.center&&old.width===p.width&&old.role===p.role&&!old.aggregate&&!p.aggregate)old.end=p.end;else merged.push(Object.assign({},p));}result.periods=merged;
 delete result.tiles;return result;
}
function cancel(){epoch++;for(const c of controllers)c.abort();}
function cacheKey(options){return JSON.stringify([options.hours,options.width,options.kind||'graphs',options.offset||0,options.end||0]);}
async function query(options){
 var generation=epoch,params=new URLSearchParams(Object.assign({sessionid:L.env.sessionid,kind:'graphs'},options));if((options.kind||'graphs')==='graphs'&&tiles.size)params.set('have',tileInventory());
 for(var attempt=0;;attempt++){
  var controller=new AbortController();controllers.add(controller);var timer=setTimeout(()=>controller.abort(),60000);
  try{
   var response=await fetch('/cgi-bin/wifi-coordinator-history',{method:'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:params.toString(),signal:controller.signal});
   if(!response.ok){var e=Error('History request failed ('+response.status+')');e.status=response.status;throw e;}
   var h=await response.json();if(!h||!Array.isArray(h.read_errors)||!Number.isFinite(h.start)||!Number.isFinite(h.end))throw Error('Invalid history response');
   if(generation!==epoch)throw Object.assign(Error("Request superseded"),{cancelled:true});return assemble(h);
  }catch(e){if(generation!==epoch)e.cancelled=true;if(e.cancelled||attempt>=2||e.status&&e.status<500)throw e;await new Promise(resolve=>setTimeout(resolve,attempt?750:250));}
  finally{clearTimeout(timer);controllers.delete(controller);}
 }
}
function read(options){
 var key=cacheKey(options);if(pending.has(key))return pending.get(key);
 var promise=query(options).then(function(h){cache.delete(key);cache.set(key,h);while(cache.size>6)cache.delete(cache.keys().next().value);return h;}).catch(function(e){
  if(e.cancelled)throw e;
  if(e.status==401||e.status==403){cache.clear();tiles.clear();tileBytes=0;throw e;}
  var old=cache.get(key);if(!old)throw e;
  return Object.assign({},old,{refresh_warning:'History refresh failed; showing the previous response for this time window. Retrying automatically. '+e.message});
 }).finally(()=>pending.delete(key));
 pending.set(key,promise);return promise;
}
return baseclass.extend({read:read,cancel:cancel});
