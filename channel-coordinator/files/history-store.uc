// A manifest rename commits immutable blocks and one replaceable active checkpoint.
// Derived graph data never participates in recovery. Only this module writes history.
import * as fs from 'fs';
import {sha256} from 'digest';
import {LISTS,empty,key,pack,unpack} from './history-codec.uc';
export const DIRECTORY='/etc/wifi-coordinator';
export const RAM_PATH='/tmp/wifi-coordinator-history.json';
const INDEX=DIRECTORY+'/history-index.json',LEASES='/tmp/wifi-history-readers';
const MAX_FILE=2097152;
function pid(){return int(split(fs.readfile('/proc/self/stat'),' ')[0]);}
const WRITER='/tmp/wifi-history-writer';
function locked(fn){
 if(!fs.mkdir(WRITER,0700)){
  let owner=int(fs.readfile(WRITER+'/pid') ?? 0),st=fs.stat(WRITER);
  if(owner&&!fs.stat('/proc/'+owner)||!owner&&st&&time()-st.mtime>30){fs.unlink(WRITER+'/pid');fs.rmdir(WRITER);}
  if(!fs.mkdir(WRITER,0700))die('History writer is busy');
 }
 fs.writefile(WRITER+'/pid',''+pid());
 let result;try{result=fn();}catch(e){fs.unlink(WRITER+'/pid');fs.rmdir(WRITER);die(e);}
 fs.unlink(WRITER+'/pid');fs.rmdir(WRITER);return result;
}
function raw(path,limit){let s=fs.lstat(path);if(s?.type!='file'||s.size>limit)return null;let f=fs.open(path,'r');if(!f)return null;let x=f.read(limit+1);f.close();return x!=null&&length(x)<=limit?x:null;}
export function manifest(){
 let text=raw(INDEX,2097152);if(text==null){if(fs.stat(INDEX))die('Cannot read history index');return null;}
 let m=json(text);if(m.format!=3||type(m.blocks)!='array'||!match(m.epoch ?? '',/^[a-f0-9]{16}$/))die('Invalid history index');
 for(let d in [...m.blocks,...(m.tail?[m.tail]:[])])if(!match(d.name ?? '',/^(block|tail)-[a-f0-9]{16}-[0-9A-Za-z-]+\.json$/)||!match(d.sha256 ?? '',/^[a-f0-9]{64}$/))die('Invalid indexed history file');
 return m;
};
export function read_block(d){
 let text=raw(DIRECTORY+'/'+d.name,MAX_FILE);if(text==null||length(text)!=d.size||sha256(text)!=d.sha256)die('History block failed integrity check: '+d.name);
 let h=unpack(json(text));for(let k in LISTS)if(type(h[k])!='array')die('Invalid dataset in '+d.name);return h;
};
function atomic(path,text,durable){
 let f=fs.open(path+'.new','w',0600);if(!f)die('Cannot create history file');
 let n=f.write(text),flushed=f.flush(),closed=f.close();if(n!=length(text)||!flushed||!closed)die('Incomplete history write');
 if(durable&&system('sync')!=0)die('History synchronization failed');
 if(!fs.rename(path+'.new',path))die('History rename failed');
 if(durable&&system('sync')!=0)die('History commit synchronization failed');
}
function free_bytes(){let p=fs.popen("df -Pk '"+DIRECTORY+"'",'r');if(!p)return 0;let lines=split(trim(p.read('all')),/\n/);p.close();let f=split(trim(lines[length(lines)-1]),/\s+/);return int(f[3])*1024;}
function marker(r){return index(['radio-unavailable','placement-observed','radio-reconnect','radar-evacuation','client-departure','radar-state'],r.event)>=0||r.event=='operation-complete'&&r.disconnect_events>0;}
function descriptor(name,h,k){
 let rows=k?h[k]:[...h.periods,...h.clients,...h.samples,...h.events,...h.surveys];
 let low=null,high=null;for(let r in rows){let a=r.start ?? r.time,b=r.updated ?? r.end ?? r.time;low=low==null?a:min(low,a);high=high==null?b:max(high,b);}
 let text=sprintf('%J',pack(h));if(length(text)>MAX_FILE)die('History block exceeds bounded file size');
 atomic(DIRECTORY+'/'+name,text,false);
 let d={name,dataset:k,low:low ?? 0,high:high ?? 0,rows:length(rows),size:length(text),sha256:sha256(text)};
 if(k=='events'){
  d.first_time=null;d.last_time=null;d.marker_count=0;
  for(let r in rows){d.first_time=d.first_time==null?r.time:min(d.first_time,r.time);d.last_time=d.last_time==null?r.time:max(d.last_time,r.time);
   if(marker(r))d.marker_count++;
  }
 }
 return d;
}
// Leases pin the manifest's files. A reader validates the revision after publishing
// its lease; cleanup happens only after publication of the next manifest.
export function snapshot(){
 if(!fs.stat(LEASES))fs.mkdir(LEASES,0700);
 let path=LEASES+'/'+pid()+'.json';
 for(let attempt=0;attempt<8;attempt++){
  let m=manifest();if(!m)die('History store has not been initialized');
  atomic(path,sprintf('%J',{pid:pid(),files:map([...m.blocks,...(m.tail?[m.tail]:[])],d=>d.name)}),false);
  let next=manifest();if(next?.epoch!=m.epoch||next?.revision!=m.revision)continue;
  try{
   let tail=m.tail?read_block(m.tail):empty(),ram=null;
   try{ram=json(raw(RAM_PATH,1048576));}catch(e){}
   let active=empty();
   for(let k in LISTS){
    let rows={};for(let r in tail[k])rows[r._id]=r;
    if(ram?.epoch==m.epoch)for(let r in ram[k] ?? []){
     if(!r._id)continue;
     let old=rows[r._id];
     if(old?(r.updated ?? r.end ?? r.time)>=(old.updated ?? old.end ?? old.time):r._seq>(m.watermarks[r._session] ?? 0))rows[r._id]=r;
    }
    active[k]=sort(values(rows),(a,b)=>(a.start ?? a.time)-(b.start ?? b.time));
   }
   return {manifest:m,active,status:ram ?? {},release:()=>fs.unlink(path)};
  }catch(e){fs.unlink(path);die(e);}
 }
 fs.unlink(path);die('History changed repeatedly during snapshot');
};
export function cleanup(m){
 let keep={};for(let d in [...m.blocks,...(m.tail?[m.tail]:[])])keep[d.name]=true;
 for(let name in fs.lsdir(LEASES) ?? []){
  if(!match(name,/^[0-9]+\.json$/))continue;
  let p=LEASES+'/'+name,r;try{r=json(fs.readfile(p));}catch(e){continue;}
  if(!fs.stat('/proc/'+r.pid)){fs.unlink(p);continue;}
  for(let file in r.files ?? [])keep[file]=true;
 }
 for(let name in fs.lsdir(DIRECTORY) ?? [])if(match(name,/^(block|tail)-[a-f0-9]{16}-[0-9A-Za-z-]+\.json(\.new)?$/)&&!keep[name])fs.unlink(DIRECTORY+'/'+name);
};
function commit(m,closed,active,t,hours,watermarks){
 if(!fs.stat(DIRECTORY)&&!fs.mkdir(DIRECTORY,0700))die('Cannot create history directory');
 // Reserve space before writing; failed attempts never evict retained history.
 let required=length(sprintf('%J',closed))+length(sprintf('%J',active))+length(sprintf('%J',m))+65536;
 if(free_bytes()<required+4194304)die('Less than 4 MiB would remain free');
 let rev=m.revision+1,prefix=m.epoch+'-'+rev,blocks=filter(m.blocks,d=>d.high>=t-hours*3600);
 for(let k in LISTS){
  let groups={};for(let r in closed[k]){let bucket=''+int((r.start ?? r.time)/3600)+(k=='events'?(marker(r)?'-m':'-a'):'');if(!groups[bucket])groups[bucket]=[];push(groups[bucket],r);}
  for(let bucket,rows in groups){
   rows=sort(rows,(a,b)=>(a.start ?? a.time)-(b.start ?? b.time));
   // Keep every allocation and export read bounded even for very busy logs.
   for(let i=0;i<length(rows);i+=400){let h=empty();h[k]=slice(rows,i,i+400);push(blocks,descriptor('block-'+prefix+'-'+k+'-'+bucket+'-'+int(i/400)+'.json',h,k));}
  }
 }
 let tail=descriptor('tail-'+prefix+'.json',active,null);
 let next={format:3,epoch:m.epoch,revision:rev,saved:t,retention_hours:hours,blocks,tail,watermarks};
 // All referenced data must be durable before the manifest becomes visible.
 if(system('sync')!=0)die('Cannot synchronize history blocks');
 let index_text=sprintf('%J',next);if(length(index_text)>2097152)die('History index exceeds its safe size');
 atomic(INDEX,index_text,true);
 cleanup(next);return next;
}
export function assign_ids(h){
 h.next_seq=h.next_seq ?? 0;
 for(let k in LISTS)for(let r in h[k] ?? [])if(!r._id){r._session=h.session ?? h.boot;r._seq=++h.next_seq;r._id=r._session+':'+r._seq;}
};
function checkpoint_locked(h,t,hours,shutdown){
 let m=manifest();if(!m)die('History index is unavailable');
 cleanup(m); // Reclaim interrupted, unpublished writes before reserving space.
 if(h.epoch==null&&h.session){let tail=m.tail?read_block(m.tail):empty();for(let k in LISTS)h[k]=[...tail[k],...h[k]];h.epoch=m.epoch;}
 if(m.epoch!=h.epoch)die('History epoch changed');
 if(m.revision>(h.archive_revision ?? 0)){
  let tail=m.tail?read_block(m.tail):empty(),ids={};for(let k in LISTS)for(let r in tail[k])ids[r._id]=true;
  for(let k in LISTS)h[k]=filter(h[k],r=>ids[r._id]||r._seq>(m.watermarks[r._session] ?? 0));
 }
 assign_ids(h);let active=empty(),closed=empty(),keep={};
 if(!shutdown){
  for(let k in ['periods','clients','events']){
   let last={};for(let r in h[k])if(k!='events'||r.event=='radio-unavailable')last[r.radio]=r;
   for(let r in values(last))if(r._session==(h.session ?? h.boot)&&r.end>=t-15)keep[r._id]=true;
  }
  for(let r in h.samples)if(r._session==(h.session ?? h.boot)&&r.time>=int(t/300)*300)keep[r._id]=true;
  let survey=h.surveys[length(h.surveys)-1];if(survey&&survey._session==(h.session ?? h.boot)&&survey.updated>=t-300)keep[survey._id]=true;
 }
 let marks={...m.watermarks};
 for(let k in LISTS)for(let r in h[k]){
  marks[r._session]=max(marks[r._session] ?? 0,r._seq);
  if((r.updated ?? r.end ?? r.time)<t-hours*3600)continue;
  push(keep[r._id]?active[k]:closed[k],r);
 }
 let next=commit(m,closed,active,t,hours,marks);
 for(let k in LISTS)h[k]=active[k];
 h.archive_revision=next.revision;return true;
};
function initialize_locked(boot,hours,t){
 let m=manifest();if(m)return m;
 if(!fs.stat(DIRECTORY))fs.mkdir(DIRECTORY,0700);
 let epoch=substr(sha256(''+t+':'+pid()+':'+boot),0,16);
 m={format:3,epoch,revision:0,blocks:[],watermarks:{}};
 let names=sort(filter(fs.lsdir(DIRECTORY) ?? [],n=>match(n,/^batch-[0-9]+\.json$/))),maps={};for(let k in LISTS)maps[k]={};
 // Legacy normalization runs once, before publishing the first new manifest.
 // Original files remain untouched for rollback and export comparison.
 for(let name in [...names,'RAM']){
  let path=name=='RAM'?RAM_PATH:DIRECTORY+'/'+name,text=raw(path,MAX_FILE);if(text==null){if(name=='RAM'&&!fs.stat(path))continue;die('Cannot migrate '+name);}
  let h=json(text);for(let k in LISTS)for(let r in h[k] ?? []){
   if((r.updated ?? r.end ?? r.time)<t-hours*3600)continue;
   let id=key(k,r),old=maps[k][id];if(!old||(r.updated ?? r.end ?? r.time)>=(old.updated ?? old.end ?? old.time))maps[k][id]=r;
  }
 }
 let closed=empty(),seq=0,session='legacy-'+epoch;
 for(let k in LISTS){closed[k]=sort(values(maps[k]),(a,b)=>(a.start ?? a.time)-(b.start ?? b.time));for(let r in closed[k]){r._session=session;r._seq=++seq;r._id=session+':'+seq;}}
 let marks={};marks[session]=seq;
 let next=commit(m,closed,empty(),t,hours,marks);
 // Record the source inventory; migration leaves its inputs available for audit.
 atomic(DIRECTORY+'/history-migration.json',sprintf('%J',{epoch,at:t,sources:names,records:seq}),true);
 return next;
};
export function restore(boot,hours,t){
 let m=manifest() ?? locked(()=>initialize_locked(boot,hours,t)),h=null;
 try{let old=json(raw(RAM_PATH,1048576));if(old.boot==boot&&old.epoch==m.epoch)h=old;}catch(e){}
 if(!h){h={...empty(),boot,started:t,next_seq:m.watermarks[boot] ?? 0,epoch:m.epoch};let tail=m.tail?read_block(m.tail):empty();for(let k in LISTS)h[k]=tail[k];}
 // A crash after manifest commit but before RAM publication must not replay
 // already committed completed records. Active checkpoint IDs may advance.
 let tail=m.tail?read_block(m.tail):empty(),ids={};for(let k in LISTS)for(let r in tail[k])ids[r._id]=true;
 for(let k in LISTS){
  let rows={};for(let r in tail[k])rows[r._id]=r;
  for(let r in h[k] ?? []){
   let old=rows[r._id];
   if(old?(r.updated ?? r.end ?? r.time)>=(old.updated ?? old.end ?? old.time):r._seq>(m.watermarks[r._session] ?? 0))rows[r._id]=r;
  }
  h[k]=sort(values(rows),(a,b)=>(a.start ?? a.time)-(b.start ?? b.time));
 }
 h.archive_saved=m.saved;h.archive_revision=m.revision;h.next_seq=max(h.next_seq ?? 0,m.watermarks[h.session ?? boot] ?? 0);return h;
};
function clear_locked(boot,t,hours){
 let epoch=substr(sha256('clear:'+t+':'+pid()+':'+(manifest()?.epoch ?? '')),0,16);
 let m=commit({epoch,revision:0,blocks:[],watermarks:{}},empty(),empty(),t,hours,{});
 // Explicit Clear also removes retained migration inputs, never radar memory.
 for(let name in fs.lsdir(DIRECTORY) ?? [])if(match(name,/^batch-[0-9]+\.json(\.new)?$/))fs.unlink(DIRECTORY+'/'+name);
 fs.unlink(DIRECTORY+'/history-migration.json');return m;
};

export function checkpoint(h,t,hours,shutdown){return locked(()=>checkpoint_locked(h,t,hours,shutdown));};
export function initialize(boot,hours,t){return manifest() ?? locked(()=>initialize_locked(boot,hours,t));};
export function clear_store(boot,t,hours){return locked(()=>clear_locked(boot,t,hours));};
// Optional, explicit lossless repack; the old manifest remains authoritative
// until all replacement blocks are durable. Reader leases protect the old files.
export function repack_store(){return locked(()=>{
 let m=manifest();if(!m)die('No history index');let closed=empty();
 for(let d in m.blocks){let h=read_block(d);for(let k in LISTS)closed[k]=[...closed[k],...h[k]];}
 let tail=m.tail?read_block(m.tail):empty();
 return commit({...m,blocks:[]},closed,tail,m.saved,m.retention_hours,m.watermarks);
});};
