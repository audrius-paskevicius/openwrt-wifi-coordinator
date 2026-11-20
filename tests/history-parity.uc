// Generate reference output on OpenWrt from a synthetic, canonical input fixture.
import * as fs from 'fs';
import {history_view,evidence} from '../channel-coordinator/files/history-view.uc';
let input=json(fs.readfile(ARGV[0])),h=input.h,end=input.end,results=[];
function read(a,b){let out={};for(let k in ['periods','clients','samples','events','surveys'])out[k]=filter(h[k],r=>(r.updated ?? r.end ?? r.time)>=a&&(r.start ?? r.time)<b);return out;}
for(let hours in [1,3,6,12,24,48,72,96,120])for(let width in [360,1100])for(let adapt in [true,false]){
 let start=end-hours*3600,display={decimation:adapt,triangles:true,squares:true,crosses:true,popups:true},options={start,end,width,max_age:900,canonical:true,display,sources:['indexed']},result;
 if(!adapt)result={full:history_view(options,()=>read(start-900,end))};
 else{
  let step=1;while(step<(end-start)/width)step*=2;
  let views=[];
  for(let a=int((end-1)/3600)*3600;a>=int(start/3600)*3600;a-=3600){
   let b=min(a+3600,end),rows=read(a-900,b),view=history_view({...options,start:a,end:b,width:max(1,int((b-a)*1.0/step))},()=>rows);
   view.periods=map(view.periods,p=>({...p,start:max(a,p.start),end:min(b,p.end)}));push(views,view);
  }
  let events=filter(h.events,e=>(e.updated ?? e.end ?? e.time)>=start&&e.time<=end),flags={action:true,unknown:true,unavailable:true};
  result={views:reverse(views),channel_evidence:evidence(h.periods,events,start,end,width,true,flags,true),client_evidence:evidence(h.clients,events,start,end,width,true,flags,false)};
 }
 push(results,{hours,width,adapt,result});
}
fs.writefile(ARGV[1],sprintf('%J',results));print(sprintf('Prepared %d ucode reference cases\n',length(results)));
