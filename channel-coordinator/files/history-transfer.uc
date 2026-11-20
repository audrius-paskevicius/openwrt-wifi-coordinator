// Transfer immutable encoded blocks. Graph calculations belong to the browser.
import * as fs from 'fs';
import {sha256} from 'digest';
import {DIRECTORY,manifest} from './history-store.uc';
export function graph_blocks(snap,start,end,max_age,adapt){
 let first=adapt?int(start/3600)*3600:start;
 return filter(snap.manifest.blocks,d=>{
  // Whole retained interval streams preserve evidence anchors at window edges.
  if(d.dataset=='periods'||d.dataset=='clients')return true;
  return d.high>=first-max_age&&d.low<end&&(d.dataset!='events'||d.marker_count!=0);
 });
};
export function block_batch(epoch,ids){
 let m=manifest();if(!m||m.epoch!=epoch)die('History changed; reload its index');
 let by_id={};for(let d in m.blocks)by_id[d.sha256]=d;
 let size=0,selected=[];
 for(let id in ids){let d=by_id[id];if(!d)die('History block expired; reload its index');size+=d.size;push(selected,d);}
 if(size>2097152)die('History batch exceeds 2 MiB');
 let result=[];
 for(let d in selected){
  let path=DIRECTORY+'/'+d.name,s=fs.lstat(path);
  if(s?.type!='file'||s.size!=d.size)die('History block unavailable; reload its index');
  let f=fs.open(path,'r');if(!f)die('Cannot read history block');
  let text=f.read(d.size+1);f.close();
  if(length(text)!=d.size||sha256(text)!=d.sha256)die('History block failed integrity check');
  push(result,{id:d.sha256,text});
 }
 // Nothing is emitted before every requested block has passed validation.
 return result;
};
