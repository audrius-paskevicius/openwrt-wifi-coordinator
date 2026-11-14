import {history_view,reduce_points,survey_cells,coverage} from '../channel-coordinator/files/history-view.uc';
let checks=0;function check(ok,why){if(!ok)die('FAIL: '+why+'\n');checks++;}
let points=[];for(let i=0;i<1000;i++){if(i==500)push(points,{x:i,y:null});push(points,{x:i,y:i==123?1000:i==321?0:10});}
let reduced=reduce_points(points,0,1000,16,true);
check(length(reduced)<=16*4+5,'point budget scales with columns and known runs');
check(length(filter(reduced,p=>p.y==1000))==1&&length(filter(reduced,p=>p.y==0))==1,'extrema survive');
check(length(filter(reduced,p=>p.y==null))==1,'unknown gap survives');
check(length(reduce_points(points,0,1000,16,false))==length(points),'disabled reduction returns all points');
let peak_points=[];for(let i=0;i<20;i++)push(peak_points,{x:i,y:10,peak:i==7?900:10});
check(length(filter(reduce_points(peak_points,0,20,1,true),p=>p.peak==900))==1,'instantaneous traffic peak survives even when averages are flat');
for(let i=1;i<length(reduced);i++)check(reduced[i].x>=reduced[i-1].x,'extrema retain chronological order');
let cells=survey_cells({a:{low:2400,high:2405,points:{a:{time:0,level:100},b:{time:10,level:0}}}},[[0,100]],0,100,1,100,true);
check(length(cells)==1&&cells[0][5]==10&&cells[0][6]==0&&cells[0][7]==100,'heatmap uses time-weighted mean with full observed range');
check(cells[0][8]==2,'heatmap reports contributing observations');
cells=survey_cells({a:{low:2400,high:2405,points:{a:{time:0,level:1},b:{time:1,level:0}}}},[[0,10]],0,10,1,10,true);
check(length(cells)==1&&cells[0][5]==0.1,'fractional weighted averages are not integer-truncated');
cells=survey_cells({a:{low:2400,high:2405,points:{a:{time:0,level:1},b:{time:1,level:0},c:{time:2,level:1},d:{time:3,level:0}}}},[[0,7]],0,7,3,10,true);
let integral=0;for(let cell in cells)integral+=(cell[3]-cell[2])*cell[5];
check(max(integral-2,2-integral)<0.00001,'noninteger pixel widths conserve time-weighted data');
cells=survey_cells({a:{low:2400,high:2405,points:{a:{time:0,level:50},b:{time:80,level:20}}}},[[0,30],[60,100]],0,100,1,100,true);
check(length(cells)==2&&cells[0][3]<=30&&cells[1][2]>=60,'same-column missing coverage is never filled');
cells=survey_cells({a:{low:2400,high:2405,points:{a:{time:0,level:50}}}},[[0,100]],0,100,4,20,false);
check(length(cells)==1&&cells[0][3]==20,'stale survey shading stops even in full-detail mode');
check(length(coverage([{start:1,end:10},{start:5,end:12},{start:20,end:25}],0,30))==2,'overlapping radio observations merge without bridging a gap');
let h={periods:[],clients:[],samples:[],surveys:[],events:[]};
for(let i=0;i<500;i++){
 let t=1000+i*4;
 push(h.periods,{radio:'radio0',start:t,end:t+4,channel:i%2?36:40,center:5210,width:80,role:'serving'});
 push(h.clients,{radio:'radio0',start:t,end:t+4,count:i==50?0:i%3,source:'boot'});
 push(h.surveys,{time:t,cycle:''+i,bands:[{start:5170,step:20,levels:[i%100],offsets:[0]}]});
 push(h.events,{time:t,radio:'radio0',event:'client-departure',reason:'test',password:'do not transmit'});
}
push(h.periods,{radio:'radio0',start:4000,end:5000,channel:36,center:5210,width:80,role:'serving'});
push(h.clients,{radio:'radio0',start:4000,end:5000,count:1,source:'new-boot'});
for(let i=0;i<15;i++)push(h.samples,{radio:'radio0',time:1000+i*300,end:1000+i*300+290,n:10,traffic_sum:i==5?1000:10,traffic_peak:i==5?150:2,source:'boot'});
push(h.events,{event:'radio-unavailable',radio:'radio0',source:'boot',time:3100,start:3100,end:3200});
let flags={decimation:true,triangles:true,squares:true,crosses:true,popups:true};
let options={sources:['one','boundary'],start:1000,end:5000,width:16,max_age:300,display:flags};
let boundary={periods:[{...h.periods[0],end:1004}],clients:[],samples:[{...h.samples[0],n:20,traffic_sum:40}],surveys:[],events:[h.events[0]]};
let result=history_view(options,i=>i?boundary:h);
check(length(result.periods)<length(h.periods),'subpixel channel activity is reduced');
check(length(filter(result.periods,p=>p.start<3000&&p.end>3000))==0,'channel reduction preserves unknown interval');
check(length(filter(result.periods,p=>p.aggregate&&p.aggregate.placements==2))>0,'mixed channel activity is explicitly labelled');
check(result.traffic_points.radio0[0].y==2,'newer overlapping summary wins without double counting');
check(length(filter(result.traffic_points.radio0,p=>p.y==100))==1,'traffic average spike retained');
check(length(filter(result.client_points.radio0,p=>p.y==0))>0&&length(filter(result.client_points.radio0,p=>p.y==null))==1,'client zeroes and reboot gap retained');
check(!length(filter(result.client_points.radio0,p=>p.y!=null&&int(p.y)!=p.y)),'client counts remain integers');
check(length(result.actions)==100&&result.action_total==501,'action table is independently paginated and boundary event deduplicated');
check(result.actions[0].password==null,'private fields never reach graph action response');
check(length(filter(result.channel_evidence,e=>e.kind=='unknown'))==2,'confirmed unavailability subtracted from unknown gap');
check(length(filter(result.channel_evidence,e=>e.kind=='unavailable'))==1,'confirmed unavailability retained separately');
check(length(filter(result.channel_evidence,e=>e.count>1))>0,'crowded action markers grouped with counts');
for(let kind in ['triangles','squares','crosses']){
 let off={...flags};off[kind]=false;let r=history_view({...options,display:off},i=>i?boundary:h),hidden=kind=='triangles'?'action':kind=='squares'?'unknown':'unavailable';
 check(!length(filter(r.channel_evidence,e=>e.kind==hidden))&&!length(filter(r.client_evidence,e=>e.kind==hidden)),kind+' controls both graphs');
 check(r.action_total==501,'marker visibility never deletes log records');
}
let full=history_view({...options,display:{...flags,decimation:false}},i=>i?boundary:h);
check(length(full.periods)==length(h.periods),'full-detail mode retains channel intervals');
check(length(full.survey_cells)>length(result.survey_cells),'screen adaptation reduces transferred survey cells');
let next=history_view({...options,kind:'actions',offset:100},i=>i?boundary:h);
check(length(next.actions)==100&&next.actions[0].time<result.actions[99].time,'next action page is older and nonoverlapping');
check(!exists(next,'survey_cells'),'action requests do not return graph datasets');
let broken=history_view(options,i=>i?null:h);check(length(broken.read_errors)==1,'unreadable source is explicit');
print(sprintf('PASS: %d viewport reduction, gaps, markers, pagination and privacy checks\n',checks));
