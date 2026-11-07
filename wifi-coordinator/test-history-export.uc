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
a.events=[{time:120,event:'test',reason:'=1+1',password:'must not export'}];b.events=a.events;
ram.events=[{time:10,event:'old'},{time:201,event:'future'}];
let sources=[a,b,ram],opts={format:'json',now:200,start:100,retained:50,hours:1,sources:['batch-a','batch-b','RAM'],version:'test',
 radar:{half_life:3600,events:[{time:20,center:5250,width:80,weight:1}]},bands:['5g']};
let output='';
let result=stream(opts,i=>sources[i],s=>{output+=s;});
let data=json(output);
check(result.complete&&data.result.complete,'valid complete JSON');
check(data.datasets.periods[0].end==190&&length(data.datasets.periods)==1,'newest residence deduplicated');
check(length(data.datasets.traffic)==1&&data.datasets.traffic[0].traffic_avg_mbps==5,'traffic extends across batches');
check(data.datasets.traffic[0].busy_avg_percent==25,'measured airtime average');
check(length(data.datasets.surveys)==3,'independent pre-window bin context retained');
check(length(data.datasets.radar)==1,'older radar context retained');
check(length(data.datasets.actions)==1&&!exists(data.datasets.actions[0],'password'),'actions filtered, deduplicated and whitelisted');
check(data.datasets.actions[0].time_iso=='1970-01-01T00:02:00Z','UTC timestamp');
check(iso(0)=='1970-01-01T00:00:00Z','epoch ISO conversion');
check(csv_cell(-61)=='"-61"','negative numeric signal stays numeric');
check(csv_cell('  =1')=='"\'  =1"','formula injection neutralized');
check(csv_cell('a,"b"\nc')=='"a,""b""\nc"','CSV quotes/newlines preserved');
for(let k in ['periods','traffic','surveys','radar','actions']){
 output='';stream({...opts,format:'csv',dataset:k},i=>sources[i],s=>{output+=s;});
 check(index(output,'record_type,')==0&&index(output,'"summary"')>=0,'CSV header and completion '+k);
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
printf('PASS: %d streaming export checks\n',checks);
