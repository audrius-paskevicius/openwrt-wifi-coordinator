import { stream, iso, csv_cell } from '../channel-coordinator/files/history-export.uc';
let checks=0;
function check(ok,message){if(!ok)die(message);checks++;}
function empty(){return {periods:[],samples:[],events:[],surveys:[]};}
let a=empty(),b=empty(),ram=empty();
a.periods=[{radio:'radio0',start:90,end:110,channel:36,center:5210,width:80,role:'ap'}];
b.periods=[{...a.periods[0],end:150}];ram.periods=[{...a.periods[0],end:190}];
a.samples=[{radio:'radio0',time:100,end:110,channel:36,width:80,source:'test',n:1,traffic_sum:4,traffic_peak:4,busy_sum:20,busy_n:1}];
ram.samples=[{...a.samples[0],end:190,n:2,traffic_sum:10,traffic_peak:6,busy_sum:50,busy_n:2}];
a.surveys=[{time:70,bands:[{start:5170,step:20,levels:[10,20],offsets:[0,0]}]},
 {time:80,bands:[{start:5170,step:20,levels:[30,null],offsets:[0,0]}]}];
ram.surveys=[{time:150,cycle:1,bands:[{start:5170,step:20,levels:[40,50],offsets:[0,2]}]}];
a.events=[{time:120,event:'test',reason:'=1+1',password:'must not export',estimated_gain:12.5,movement_cost:9,affected_clients:3,departed_clients:2}];b.events=a.events;
ram.events=[{time:10,event:'old'},{time:201,event:'future'}];
a.clients=[{radio:'radio0',source:'boot',start:90,end:110,count:0,mac:'not-exported'}];
ram.clients=[{...a.clients[0],end:150},{radio:'radio0',source:'boot',start:150,end:190,count:2}];
let sources=[a,b,ram],opts={format:'json',now:200,start:100,retained:50,hours:1,sources:['batch-a','batch-b','RAM'],version:'test',
 radar:{half_life:3600,events:[{time:20,center:5250,width:80,weight:1}]},bands:['5g']};
let output='';
let result=stream(opts,i=>sources[i],s=>{output+=s;});
let data=json(output);
check(result.complete&&data.result.complete,'valid complete JSON');
check(length(data.datasets.clients)==2&&data.datasets.clients[0].end==150,'client intervals merge across archive/RAM and overlap window');
check(data.datasets.clients[0].count==0&&!exists(data.datasets.clients[0],'mac'),'zero clients retained and identities excluded');
check(data.datasets.clients[0].start_iso==iso(90),'client interval ISO timestamps');
check(data.datasets.periods[0].end==190&&length(data.datasets.periods)==1,'newest residence deduplicated');
check(length(data.datasets.traffic)==1&&data.datasets.traffic[0].traffic_avg_mbps==5,'traffic extends across batches');
check(data.datasets.traffic[0].busy_avg_percent==25,'measured airtime average');
check(length(data.datasets.surveys)==3,'independent pre-window bin context retained');
check(length(data.datasets.radar)==1,'older radar context retained');
check(length(data.datasets.actions)==1&&!exists(data.datasets.actions[0],'password'),'actions filtered, deduplicated and whitelisted');
check(data.datasets.actions[0].estimated_gain==12.5&&data.datasets.actions[0].movement_cost==9&&data.datasets.actions[0].affected_clients==3&&data.datasets.actions[0].departed_clients==2,'decision and observed outcome fields survive export');
check(data.datasets.actions[0].time_iso=='1970-01-01T00:02:00Z','UTC timestamp');
check(iso(0)=='1970-01-01T00:00:00Z','epoch ISO conversion');
check(csv_cell(-61)=='"-61"','negative numeric signal stays numeric');
check(csv_cell('  =1')=='"\'  =1"','formula injection neutralized');
check(csv_cell('a,"b"\nc')=='"a,""b""\nc"','CSV quotes/newlines preserved');
for(let k in ['periods','clients','traffic','surveys','radar','actions']){
 output='';stream({...opts,format:'csv',dataset:k},i=>sources[i],s=>{output+=s;});
 check(index(output,'record_type,')==0&&index(output,'"summary"')>=0,'CSV header and completion '+k);
 if(k=='actions')check(index(output,'estimated_gain')>=0&&index(output,'departed_clients')>=0,'CSV action details retain decision and outcome metrics');
 check(index(output,'"metadata"')>=0&&index(output,'"data"')>=0,'CSV metadata/data '+k);
}
output='';result=stream(opts,i=>i==1?null:sources[i],s=>{output+=s;});
check(!json(output).result.complete&&length(result.warnings)==1,'missing source is explicit and deduplicated warning');
let reads=0,failed=false;
try{stream(opts,i=>{reads++;return sources[i];},s=>{die('closed');});}catch(e){failed=true;}
check(failed&&reads==0,'cancelled output stops before archive reads');
// A batch disappears between indexing and emission: no invented success.
let visits={};output='';result=stream({...opts,format:'csv',dataset:'periods'},i=>{visits[i]=(visits[i]??0)+1;return i==1&&visits[i]>1?null:sources[i];},s=>{output+=s;});
check(!result.complete&&index(output,'"warning"')>=0,'mid-export loss produces warning and incomplete summary');
// Generate a large archive lazily. This catches buffering the full response;
// the production reader likewise retains only one bounded source at a time.
let names=map([0,1,2,3,4,5,6,7,8,9],i=>'batch-'+i),bytes=0,chunks=0,largest=0;
result=stream({...opts,format:'csv',dataset:'traffic',sources:names,now:100000,start:0,retained:0},i=>{
 let h=empty();for(let j=0;j<1000;j++)push(h.samples,{...a.samples[0],time:i*1000+j,end:i*1000+j+1});return h;
},s=>{bytes+=length(s);chunks++;largest=max(largest,length(s));});
check(result.counts.traffic==10000&&bytes>1000000&&chunks>50&&largest<20000,'large export uses bounded response chunks');
let diag=empty(),extended=empty();
diag.events=[{event:'planning-complete',time:150,kind:'comparison',elapsed:21,candidates_seconds:20,search_seconds:0.5,snapshot:'private'},
 {event:'observation-gap',time:150,start:100,end:150,missed_samples:9},
 {event:'radio-unavailable',radio:'r',source:'boot',time:90,start:90,end:110}];
extended.events=[{...diag.events[2],end:160}];
output='';stream({...opts,sources:['one','two']},i=>[diag,extended][i],s=>output+=s);
let diagnostics=json(output).datasets.actions;
check(length(diagnostics)==3&&!exists(diagnostics[0],'snapshot'),'diagnostics export allowlist and interval deduplication');
check(diagnostics[0].candidates_seconds==20&&diagnostics[0].search_seconds==0.5,'candidate/search timings exported');
check(diagnostics[1].missed_samples==9&&diagnostics[1].start_iso==iso(100),'gap count and ISO boundaries exported');
check(diagnostics[2].start==90&&diagnostics[2].end==160,'confirmed interval overlapping window retained');
output='';stream({...opts,format:'csv',dataset:'actions',sources:['one']},i=>diag,s=>output+=s);
check(index(output,'candidates_seconds')>=0&&index(output,'missed_samples')>=0&&index(output,'private')<0,'CSV diagnostics included without private snapshot');
let quality=empty();quality.events=[{event:'scan-complete',time:150,survey_cycle:'123:456',scan_quality:[{radio:'radio2',frequencies:[2412,2437,'private'],visits:2,scan_seconds:0.75,retries:1,aborts:1,detections:4,active_visits:2,passive_visits:0,password:'PRIVATE-QUALITY',bssid:'aa:bb:cc:dd:ee:ff'}]},
 {event:'scan-retry',time:151,radio:'radio2',frequencies:[2412],attempt:2,elapsed:0.25,mode:'active',survey_cycle:'123:456'}];
output='';stream({...opts,sources:['one']},i=>quality,s=>output+=s);
let q=json(output).datasets.actions;
check(q[0].scan_quality[0].scan_seconds==0.75&&length(q[0].scan_quality[0].frequencies)==2&&q[0].survey_cycle=='123:456','scan summary exported with valid frequencies and sweep identity');
check(index(output,'PRIVATE-QUALITY')<0&&index(output,'aa:bb:cc')<0,'nested quality export rejects private fields');
check(q[1].attempt==2&&q[1].frequencies[0]==2412&&q[1].mode=='active','retry diagnostic export retains context');
output='';stream({...opts,format:'csv',dataset:'actions',sources:['one']},i=>quality,s=>output+=s);
check(index(output,'scan_quality')>=0&&index(output,'scan_seconds')>=0&&index(output,'survey_cycle')>=0&&index(output,'PRIVATE-QUALITY')<0,'Actions CSV includes quality without new columns or private fields');
printf('PASS: %d streaming export checks\n',checks);
