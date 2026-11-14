// Indexed snapshot reader. Immutable source blocks are parsed at most once per
// request within a bounded LRU; completed graph tiles are reusable RAM artifacts.
import * as fs from 'fs';
import {sha256} from 'digest';
import {LISTS,empty} from './history-codec.uc';
import {read_block} from './history-store.uc';
import {history_view} from './history-view.uc';
import {clean} from './history-export.uc';
const CACHE='/tmp/wifi-history-tiles',BUDGET=16777216,TILE=3600;
function endof(r){return r.updated ?? r.end ?? r.time;}
function clipped(h,a,b){
 let out=empty();for(let k in LISTS)out[k]=filter(h[k],r=>endof(r)>=a&&(r.start ?? r.time)<b);
 return out;
}
export function reader(snap){
 let cached={},order=[],bytes=0,reads=0;
 function block(d){
  if(cached[d.name])return cached[d.name];
  let h=read_block(d);reads++;
  while(length(order)&&bytes+d.size>4194304){let old=shift(order);bytes-=old.size;delete cached[old.name];}
  cached[d.name]=h;push(order,d);bytes+=d.size;return h;
 }
 function select(a,b,k){return filter(snap.manifest.blocks,d=>(!k||d.dataset==k)&&d.high>=a&&d.low<b);}
 function data(a,b,k,graphs){
  let out=empty();for(let d in select(a,b,k)){if(graphs&&d.dataset=='events'&&d.marker_count==0)continue;let h=block(d);for(let name in k?[k]:LISTS)for(let r in h[name])if(endof(r)>=a&&(r.start ?? r.time)<b)push(out[name],r);}
  for(let name in k?[k]:LISTS)for(let r in snap.active[name])if(endof(r)>=a&&(r.start ?? r.time)<b)push(out[name],r);
  return out;
 }
 return {select,data,block,reads:()=>reads};
};
function write_cache(path,value){
 if(!fs.stat(CACHE))fs.mkdir(CACHE,0700);
 let text=sprintf('%J',value);if(length(text)>2097152)return;
 let files=[],size=0;
 for(let name in fs.lsdir(CACHE) ?? []){
  let temporary=match(name,/^[a-f0-9]{32}\.json\.([0-9]+)\.new$/);
  if(temporary&&!fs.stat('/proc/'+temporary[1])){fs.unlink(CACHE+'/'+name);continue;}
  if(match(name,/^[a-f0-9]{32}\.json$/)){let s=fs.stat(CACHE+'/'+name);if(s){size+=s.size;push(files,{name,size:s.size,mtime:s.mtime});}}
 }
 files=sort(files,(a,b)=>a.mtime-b.mtime);
 while(length(files)&&size+length(text)>BUDGET){let f=shift(files);fs.unlink(CACHE+'/'+f.name);size-=f.size;}
 // Each worker has its own temporary name; readers see complete atomic files.
 let pid=split(fs.readfile('/proc/self/stat'),' ')[0],tmp=path+'.'+pid+'.new';
 let f=fs.open(tmp,'w',0600);if(f){let n=f.write(text);f.close();if(n==length(text))fs.rename(tmp,path);else fs.unlink(tmp);}
}
function signature(snap,read,a,b,step,max_age){
 let active=clipped(snap.active,a-max_age,b),parts=[];
 // Extending a live interval past a closed tile does not invalidate that tile.
 for(let k in LISTS)active[k]=map(active[k],r=>{let x={...r};if(x.end>b)x.end=b;if(x.updated>b)x.updated=b;return x;});
 for(let d in read.select(a-max_age,b))if(d.dataset!='events'||d.marker_count!=0)push(parts,[d.name,d.sha256]);
 return substr(sha256(sprintf('%J',[4,snap.manifest.epoch,a,b,step,max_age,parts,active])),0,32);
}
export function graph_tiles(snap,options){
 let read=reader(snap),step=1;while(step<(options.end-options.start)/options.width)step*=2;
 let tiles=[],have={};for(let id in options.have ?? [])have[id]=true;
 let hits=0,misses=0,pending=0,started=+split(fs.readfile('/proc/uptime'),' ')[0];
 // Recent data appears first; further bounded requests fill older uncached tiles.
 for(let a=int((options.end-1)/TILE)*TILE;a>=int(options.start/TILE)*TILE;a-=TILE){
  let b=min(a+TILE,options.end),id=signature(snap,read,a,b,step,options.max_age),path=CACHE+'/'+id+'.json',view=null;
  if(have[id]){push(tiles,{id,start:a,end:b});continue;}
  let s=fs.lstat(path);if(s?.type=='file'&&s.size<=2097152){try{view=json(fs.readfile(path));hits++;}catch(e){}}
  if(!view){
   if(options.incremental&&misses>0&&(misses>=6||+split(fs.readfile('/proc/uptime'),' ')[0]-started>=2)){
    push(tiles,{id,start:a,end:b,pending:true});pending++;continue;
   }
   let h=read.data(a-options.max_age,b,null,true);
   view=history_view({start:a,end:b,width:max(1,int((b-a)*1.0/step)),max_age:options.max_age,canonical:true,display:{decimation:true,triangles:true,squares:true,crosses:true,popups:true},sources:['indexed']},()=>h);
   view.periods=map(view.periods,p=>({...p,start:max(a,p.start),end:min(b,p.end)}));
   delete view.actions;delete view.action_total;delete view.read_errors;delete view.display;delete view.pixel_width;
   delete view.channel_evidence;delete view.client_evidence;
   write_cache(path,view);misses++;
  }
  push(tiles,{id,start:a,end:b,data:view});
 }
 return {tiles:reverse(tiles),step,preparing:pending,cache_hits:hits,cache_misses:misses,source_reads:read.reads()};
};
export function action_page(snap,start,end,offset){
 let read=reader(snap),blocks=read.select(start,end,'events'),total=0,rows=[],partial={};
 function selected(r){return endof(r)>=start&&r.time<=end;}
 for(let d in blocks){
  if(d.low>=start&&d.high<=end)total+=d.rows;
  else{let r=filter(read.block(d).events,selected);partial[d.name]=r;total+=length(r);}
 }
 let active=filter(snap.active.events,selected);total+=length(active);rows=[...active];
 blocks=sort(blocks,(a,b)=>(b.last_time ?? b.high)-(a.last_time ?? a.high));
 for(let d in blocks){
  rows=sort(rows,(a,b)=>b.time-a.time||(a._id<b._id?-1:1));
  if(length(rows)>=offset+100&&(d.last_time ?? d.high)<rows[offset+99].time)break;
  rows=[...rows,...(partial[d.name] ?? filter(read.block(d).events,selected))];
 }
 rows=sort(rows,(a,b)=>b.time-a.time||(a._id<b._id?-1:1));
 return {actions:map(slice(rows,offset,offset+100),e=>clean('actions',e,false)),action_total:total,offset};
};
export function marker_events(snap,start,end){
 let out=filter(snap.active.events,e=>endof(e)>=start&&e.time<=end);
 for(let d in snap.manifest.blocks)if(d.dataset=='events'&&d.marker_count!=0&&d.high>=start&&d.low<=end)out=[...out,...filter(read_block(d).events,e=>endof(e)>=start&&e.time<=end)];
 return out;
};
