// Read-only, viewport-specific history. Stored records and export precision are unchanged.
import {clean} from './history-export.uc';
function identity(k,x){
 if(k=='periods')return sprintf('%J',[x.radio,x.start,x.channel,x.center,x.width,x.role]);
 if(k=='clients')return sprintf('%J',[x.radio,x.source,x.start,x.count]);
 if(k=='samples')return sprintf('%J',[x.radio,x.time,x.channel,x.width,x.role,x.source]);
 if(x.event=='radio-unavailable')return sprintf('%J',[x.event,x.radio,x.source,x.start]);
 return sprintf('%J',x);
}
function ordered(rows){return sort(rows,(a,b)=>(a.start ?? a.time)-(b.start ?? b.time));}
function clip(a,b,start,end){return [max(a,start),min(b,end)];}
export function coverage(periods,start,end){
 let out=[];
 for(let p in ordered(periods)){
  let a=max(start,p.start),b=min(end,p.end),last=out[length(out)-1];if(b<=a)continue;
  if(last&&a<=last[1])last[1]=max(last[1],b);else push(out,[a,b]);
 }
 return out;
};
// First/minimum/maximum/last in chronological order, separately within every known run.
export function reduce_points(points,start,end,width,enabled){
 if(!enabled)return points;
 let out=[],bucket=[],column=null,step=(end-start)*1.0/width;
 function flush(){
  if(!length(bucket))return;
  if(length(bucket)<=4){for(let p in bucket)push(out,p);bucket=[];return;}
  let lo=0,hi=0,peak=0;for(let i=1;i<length(bucket);i++){if(bucket[i].y<bucket[lo].y)lo=i;if(bucket[i].y>bucket[hi].y)hi=i;if((bucket[i].peak ?? -1)>(bucket[peak].peak ?? -1))peak=i;}
  let indexes=sort([0,lo,hi,peak,length(bucket)-1],(a,b)=>a-b),last=-1;
  for(let i in indexes)if(i!=last){
   let p={...bucket[i]};
   if(length(bucket)>4)p.aggregate={start:bucket[0].x,end:bucket[length(bucket)-1].x,count:length(bucket),min:bucket[lo].y,max:bucket[hi].y};
   push(out,p);last=i;
  }
  bucket=[];
 }
 for(let p in points){
  if(p.y==null){flush();if(length(out)&&out[length(out)-1].y!=null)push(out,p);column=null;continue;}
  let c=int((p.x-start)/step);if(column!=null&&c!=column)flush();column=c;push(bucket,p);
 }
 flush();return out;
};
function reduced_periods(rows,start,end,width,enabled){
 if(!enabled)return rows;
 let out=[],short=[],last=null,run=0,lastkey=null,step=(end-start)*1.0/width;
 function flush(){
  let geometries={};for(let p in short){let key=sprintf('%J',[p.channel,p.center,p.width,p.role]),old=geometries[key];
   if(old){old.start=min(old.start,p.start);old.end=max(old.end,p.end);}else geometries[key]={...p};}
  for(let p in values(geometries)){
   if(length(short)>1)p.aggregate={start:short[0].start,end:short[length(short)-1].end,count:length(short),placements:length(geometries)};
   push(out,p);
  }
  short=[];
 }
 for(let p in ordered(rows)){
  if(last&&p.start>last.end){flush();run++;}
  let a=int((max(start,p.start)-start)/step),b=int((min(end,p.end)-start)/step),key=''+run+':'+a;
  if(a!=b){flush();push(out,p);lastkey=null;}
  else {if(lastkey!=key)flush();push(short,p);lastkey=key;}
  last=p;
 }
 flush();return ordered(out);
}
export function evidence(rows,events,start,end,width,enabled,flags,channel){
 let out=[],step=(end-start)*1.0/width;
 let names={};for(let p in rows)names[p.radio]=true;
 for(let radio in keys(names)){
  let periods=ordered(filter(rows,p=>p.radio==radio));
  let radio_events=filter(events,e=>e.radio==radio),unavailable=filter(radio_events,e=>e.event=='radio-unavailable');
  function mark(kind,a,b,detail){
   if(b<start||a>end||flags[kind]==false)return;
   let lo=0,hi=length(periods);while(lo<hi){let mid=int((lo+hi)/2);if(periods[mid].start<=a)lo=mid+1;else hi=mid;}
   let p=periods[max(0,lo-1)];
   if(!p)return;
   push(out,{radio,kind,start:max(start,a),end:min(end,b),detail,anchor:channel?p.center:p.count,count:1});
  }
  for(let i=1;i<length(periods);i++){
   let a=periods[i-1].end,b=periods[i].start;
   if(b-a<=15)continue;
   let unknown=[[a,b]];
   for(let e in unavailable){
    let next=[];for(let span in unknown){
     if(e.end<=span[0]||e.start>=span[1])push(next,span);
     else {if(e.start>span[0])push(next,[span[0],e.start]);if(e.end<span[1])push(next,[e.end,span[1]]);}
    }unknown=next;
   }
   for(let span in unknown)mark('unknown',span[0],span[1],'No observations; service continuity unknown');
  }
  for(let e in radio_events){
   if(e.event=='radio-unavailable')mark('unavailable',e.start,e.end,'Hostapd reported no enabled access point');
   else if(index(['placement-observed','radio-reconnect','radar-evacuation','client-departure'],e.event)>=0||e.event=='operation-complete'&&e.disconnect_events>0)
    mark('action',e.time,e.time,e.reason ?? e.event);
  }
 }
 if(!enabled)return out;
 let groups={};for(let e in out){let id=sprintf('%J',[e.radio,e.kind,int(((e.start+e.end)/2-start)/step)]),old=groups[id];
  if(old){old.start=min(old.start,e.start);old.end=max(old.end,e.end);old.count++;old.detail='Multiple '+e.kind+' records in this display column';}else groups[id]=e;
 }
 return values(groups);
};
// Time-weighted heatmap columns. Neither missing coverage nor expired observations are filled.
export function survey_cells(bins,known,start,end,width,max_age,enabled){
 let out=[],step=(end-start)*1.0/width;
 for(let bin in values(bins)){
  let observations=sort(values(bin.points),(a,b)=>a.time-b.time),rows=[],groups={},last_end=null,run=0,ci=0;
  // Equal readings are constant spans, not thousands of independently drawn bars.
  // Keep actual measurement times so popups never invent a fresher observation.
  for(let p in observations){let last=rows[length(rows)-1];
   if(enabled&&last&&last.level==p.level&&p.time-last.last<=max_age){last.last=p.time;push(last.times,p.time);}
   else push(rows,{time:p.time,last:p.time,level:p.level,times:[p.time]});
  }
  let columns=enabled&&length(observations)>width;
  function preceding(times,t){let lo=0,hi=length(times);while(lo<hi){let mid=int((lo+hi)/2);if(times[mid]<=t)lo=mid+1;else hi=mid;}return max(0,lo-1);}
  for(let i=0;i<length(rows);i++){
   let p=rows[i],a=max(start,p.time),b=min(end,p.last+max_age,i+1<length(rows)?rows[i+1].time:end);
   if(b<=a)continue;
   while(ci<length(known)&&known[ci][1]<=a)ci++;
   for(let ki=ci;ki<length(known)&&known[ki][0]<b;ki++){
    let lo=max(a,known[ki][0]),hi=min(b,known[ki][1]);if(hi<=lo)continue;
    if(last_end==null||lo>last_end)run++;last_end=hi;
    if(!columns){let first=preceding(p.times,lo),final=preceding(p.times,hi-0.0001);push(out,[bin.low,bin.high,lo,hi,p.times[final],p.level,p.level,p.level,final-first+1]);continue;}
    let column_start=(lo-start)/step,column_end=(hi-start)/step;
    let edges=[[lo,hi]],inside_start=start+(int(column_start)+(column_start>int(column_start)?1:0))*step,inside_end=start+int(column_end)*step;
    if(inside_end-inside_start>=step){
     let first=preceding(p.times,inside_start),final=preceding(p.times,inside_end-0.0001);
     push(out,[bin.low,bin.high,inside_start,inside_end,p.times[final],p.level,p.level,p.level,final-first+1]);
     edges=[[lo,inside_start],[inside_end,hi]];
    }
    for(let edge in edges)for(let pos=edge[0];pos<edge[1];){
     let col=min(width-1,max(0,int((pos-start)/step))),stop=min(edge[1],start+(col+1)*step);
     if(stop<=pos)break;
     let id=''+run+':'+col,g=groups[id],duration=stop-pos;
     if(!g)g=groups[id]={start:pos,end:stop,sum:0,duration:0,min:p.level,max:p.level,observed:p.time,count:0};
     let first=preceding(p.times,pos),final=preceding(p.times,stop-0.0001);
     g.end=stop;g.sum+=p.level*duration;g.duration+=duration;g.min=min(g.min,p.level);g.max=max(g.max,p.level);g.observed=max(g.observed,p.times[final]);g.count+=final-first+1;
     pos=stop;
    }
   }
  }
  for(let g in values(groups))push(out,[bin.low,bin.high,g.start,g.end,g.observed,g.sum*1.0/g.duration,g.min,g.max,g.count]);
 }
 return sort(out,(a,b)=>a[0]-b[0]||a[2]-b[2]);
};
export function history_view(options,read_source){
 let start=options.start,end=options.end,width=options.width,enabled=options.display.decimation;
 let maps={periods:{},clients:{},samples:{},events:{}},direct={periods:[],clients:[],samples:[],events:[]},bins={},warnings=[],radar=[];
 for(let si=0;si<length(options.sources);si++){
  let h=read_source(si);if(!h){push(warnings,'Cannot read history source '+options.sources[si]);continue;}
  for(let k in options.kind=='actions'?['events']:keys(maps)){
   if(h[k]==null&&k=='clients')continue;
   if(type(h[k])!='array'){push(warnings,'Invalid '+k+' in '+options.sources[si]);continue;}
   for(let row in h[k]){
    if(type(row)!='object')continue;
    let at=row.end ?? row.time,begin=row.start ?? row.time;
    if(at<start||begin>end)continue;
    if(options.canonical){push(direct[k],row);continue;}
    let x=row,key=identity(k,x),old=maps[k][key];
    if(!old||(x.end ?? x.time)>=(old.end ?? old.time))maps[k][key]=x;
   }
  }
  if(options.kind=='actions')continue;
  for(let frame in h.surveys ?? [])for(let band in frame.bands ?? [])for(let j=0;j<length(band.levels ?? []);j++){
   let level=band.levels[j],t=frame.time+(band.offsets?.[j] ?? 0);
   if(level==null||t<start-options.max_age||t>end)continue;
   let low=band.start+j*band.step,key=''+low+':'+band.step;
   if(!bins[key])bins[key]={low,high:low+band.step,points:{}};
   bins[key].points[''+t]={time:t,level};
  }
 }
 let periods=ordered(options.canonical?direct.periods:values(maps.periods)),clients=ordered(options.canonical?direct.clients:values(maps.clients)),samples=ordered(options.canonical?direct.samples:values(maps.samples)),events=ordered(options.canonical?direct.events:values(maps.events));
 maps=null;
 let actions=sort([...events],function(a,b){if(a.time!=b.time)return b.time-a.time;let ak=identity('events',a),bk=identity('events',b);return ak<bk?-1:ak>bk?1:0;}),offset=options.offset ?? 0;
 if(options.kind=='actions')return {actions:map(slice(actions,offset,offset+100),e=>clean('actions',e,false)),action_total:length(actions),offset,start,end,read_errors:warnings};
 let names={},latest={},traffic_points={},client_points={},reduced=[];
 for(let p in [...periods,...clients,...samples])names[p.radio]=true;
 for(let radio in sort(keys(names))){
  let rperiods=filter(periods,p=>p.radio==radio),rclients=filter(clients,p=>p.radio==radio),rsamples=filter(samples,p=>p.radio==radio),buckets={};
  for(let s in rsamples){
   if(!latest[radio]||s.end>=latest[radio].end)latest[radio]=s;
   if(!(s.n>0))continue;
   let b=buckets[''+s.time];if(!b)b=buckets[''+s.time]={x:s.time,end:s.end,n:0,sum:0,peak:0,source:s.source};
   b.end=max(b.end,s.end);b.n+=s.n;b.sum+=s.traffic_sum;b.peak=max(b.peak,s.traffic_peak);
  }
  let points=[],last=null;
  for(let b in sort(values(buckets),(a,b)=>a.x-b.x)){
   if(last&&(b.x>last.x+300||b.source!=last.source))push(points,{x:b.x,y:null});
   push(points,{x:b.x,y:b.sum*1.0/b.n,end:b.end,peak:b.peak,source:b.source});last=b;
  }
  traffic_points[radio]=reduce_points(points,start,end,width,enabled);
  points=[];last=null;
  for(let p in rclients){
   let a=max(start,p.start),b=min(end,p.end);
   if(last&&(a>last.end||p.source!=last.source))push(points,{x:a,y:null});
   push(points,{x:a,y:p.count,interval:p},{x:b,y:p.count,interval:p});last=p;
  }
  client_points[radio]=map(reduce_points(points,start,end,width,enabled),p=>p.interval?{...p,interval:clean('clients',p.interval,false)}:p);
  for(let p in reduced_periods(rperiods,start,end,width,enabled))push(reduced,p);
 }
 let flags={action:options.display.triangles,unknown:options.display.squares,unavailable:options.display.crosses};
 let summary=[];
 for(let b in values(bins)){
  let rows=sort(values(b.points),(a,b)=>a.time-b.time),p=rows[length(rows)-1];
  if(p&&end-p.time<=options.max_age)push(summary,{time:p.time,bands:[{start:b.low,step:b.high-b.low,levels:[p.level],offsets:[0]}]});
 }
 return {start,end,display:options.display,pixel_width:width,periods:map(reduced,p=>p.aggregate?{...clean('periods',p,false),aggregate:p.aggregate}:clean('periods',p,false)),clients:[],samples:map(values(latest),p=>clean('traffic',p,false)),surveys:summary,
  radio_names:sort(keys(names)),traffic_points,client_points,
  survey_cells:survey_cells(bins,coverage(periods,start,end),start,end,width,options.max_age,enabled),
  channel_evidence:evidence(periods,events,start,end,width,enabled,flags,true),
  client_evidence:evidence(clients,events,start,end,width,enabled,flags,false),
  events:map(filter(events,e=>e.event=='radar-state'),e=>clean('actions',e,false)),actions:map(slice(actions,0,100),e=>clean('actions',e,false)),action_total:length(actions),read_errors:warnings};
};
