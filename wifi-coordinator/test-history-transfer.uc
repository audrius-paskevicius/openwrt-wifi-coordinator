import * as fs from 'fs';
import {restore,clear_store,assign_ids,checkpoint,snapshot,DIRECTORY} from './history-store-test.uc';
import {graph_blocks,block_batch} from './history-transfer-test.uc';
let checks=0;function check(v,m){if(!v)die('FAIL: '+m+'\n');checks++;}
function fails(fn,m){let failed=false;try{fn();}catch(e){failed=true;}check(failed,m);}
let t=time()-10000;clear_store('transfer',t,120);let h=restore('transfer',120,t);
h.periods=[{radio:'radio0',start:t,end:t+10,channel:36,center:5210,width:80}];
h.clients=[{radio:'radio0',start:t,end:t+10,count:0,source:'transfer'}];
h.samples=[{radio:'radio0',time:t,end:t+10,n:1,traffic_sum:1,traffic_peak:1}];
h.surveys=[{time:t,updated:t,bands:[{start:5170,step:20,levels:[0],offsets:[0]}]}];
h.events=[{time:t,event:'planning-complete'},{time:t,event:'client-departure',radio:'radio0'}];
assign_ids(h);checkpoint(h,t+100,120,true);fs.writefile('/tmp/wifi-history-test.json',sprintf('%J',h));
let s=snapshot(),descriptors=graph_blocks(s,t,t+100,900,true),ids=map(descriptors,d=>d.sha256);
check(length(descriptors)==5,'graph blocks include all four streams and marker events only');
let batch=block_batch(s.manifest.epoch,ids);
check(length(batch)==length(ids),'all requested encoded blocks returned');
for(let i=0;i<length(batch);i++)check(batch[i].id==ids[i]&&batch[i].text==fs.readfile(DIRECTORY+'/'+descriptors[i].name),'stored bytes preserved');
check(length(graph_blocks(s,t+5000,t+6000,900,true))==2,'retained intervals supply boundary evidence without old survey data');
fails(()=>block_batch('0000000000000000',ids),'old epoch refused');
fails(()=>block_batch(s.manifest.epoch,['ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff']),'unknown identifier refused');
let d=descriptors[0],path=DIRECTORY+'/'+d.name,original=fs.readfile(path);
fs.writefile(path,replace(original,'radio0','radio9'));
fails(()=>block_batch(s.manifest.epoch,[d.sha256]),'same-size corruption refused');
fs.writefile(path,original);s.release();clear_store('transfer',time(),120);fs.unlink('/tmp/wifi-history-test.json');
print(sprintf('PASS: %d encoded block selection, identity, integrity and epoch checks\n',checks));
