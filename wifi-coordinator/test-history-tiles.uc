import * as fs from 'fs';
import {restore,clear_store,assign_ids,checkpoint,snapshot} from './history-store-test.uc';
import {graph_tiles,action_page,marker_events} from './history-reader-test.uc';
let checks=0;function check(v,m){if(!v)die('FAIL: '+m+'\n');checks++;}
let start=int(time()/3600)*3600-43200,end=start+43200;
clear_store('tiles',start,120);let h=restore('tiles',120,start);
h.periods=[{radio:'radio0',start,end,channel:36,width:80,center:5210,role:'serving'}];
h.clients=[{radio:'radio0',start,end,count:2,source:'tiles'}];
for(let t=start;t<=end;t+=300){
 push(h.samples,{radio:'radio0',time:t,end:t+1,n:1,traffic_sum:1,traffic_peak:t==start+900?99:1,channel:36,width:80,source:'tiles'});
 push(h.surveys,{time:t,updated:t,cycle:''+t,bands:[{start:5170,step:20,levels:[10,20,0],offsets:[0,0,0]}]});
 push(h.events,{time:t,event:t%600?'planning-complete':'client-departure',radio:'radio0'});
}
assign_ids(h);checkpoint(h,end+2,120,false);fs.writefile('/tmp/wifi-history-test.json',sprintf('%J',h));
let s=snapshot(),options={start,end:end+2,width:800,max_age:900,incremental:true};
let partial=graph_tiles(s,options);check(partial.preparing>0&&partial.cache_misses<=6,'cold preparation is bounded and reports pending tiles');
let full=graph_tiles(s,{...options,incremental:false}),warm=graph_tiles(s,{...options,incremental:false});
check(warm.cache_misses==0&&warm.source_reads==0,'warm graphs do not reread raw blocks');
let ids=map(full.tiles,t=>t.id),delta=graph_tiles(s,{...options,have:ids});
check(delta.preparing==0&&!length(filter(delta.tiles,t=>t.data))&&delta.source_reads==0,'browser inventory transfers no duplicate tile bodies');
let first=action_page(s,start,end+2,0),next=action_page(s,start,end+2,100);
check(first.action_total==145&&length(first.actions)==100&&length(next.actions)==45,'indexed action pagination preserves counts');
check(first.actions[99].time>next.actions[0].time,'action pages have stable chronological boundary');
check(length(filter(marker_events(s,start,end+2),e=>e.event=='client-departure'))==73,'marker-only block selection preserves all actions of interest');
s.release();h.periods[0].end=end+7;h.clients[0].end=end+7;fs.writefile('/tmp/wifi-history-test.json',sprintf('%J',h));s=snapshot();
let changed=graph_tiles(s,{...options,end:end+7,have:ids});check(length(filter(changed.tiles,t=>t.data))==1,'only the recent tile changes when ongoing intervals advance');
s.release();clear_store('tiles',end+10,120);fs.unlink('/tmp/wifi-history-test.json');
print(sprintf('PASS: %d indexed graph cache, progressive loading, delta transfer and pagination checks\n',checks));
