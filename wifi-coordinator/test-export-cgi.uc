// Read-only integration check. Creates/destroys a short-lived ubus session;
// never prints tokens or real history. Optional argument: isolated CGI copy.
import * as fs from 'fs';
import * as ubus from 'ubus';
let path=ARGV[0] ?? '/www/cgi-bin/wifi-coordinator-export';
if(!match(path,/^\/[a-zA-Z0-9_./-]+$/))die('Invalid test CGI path');
let b=ubus.connect(),sid=b.call('session','create',{timeout:120})?.ubus_rpc_session,checks=0;
if(!match(sid ?? '',/^[a-f0-9]{32}$/))die('Cannot create test session');
function check(ok,message){if(!ok)die(message);checks++;}
function post(fields){
 // Only fixed test field literals and a validated hex session enter this shell.
 let body='sessionid='+sid+'&'+fields;
 let p=fs.popen("printf '%s' '"+body+"' | REQUEST_METHOD=POST CONTENT_TYPE=application/x-www-form-urlencoded CONTENT_LENGTH="+length(body)+' ucode '+path,'r');
 let response=p.read('all');p.close();return response;
}
try{
 check(index(post('format=json&hours=6'),'Status: 403')==0,'unprivileged session denied');
 b.call('session','grant',{ubus_rpc_session:sid,scope:'file',objects:[
  ['/etc/wifi-coordinator/','list'],['/tmp/wifi-coordinator-history.json','read'],['/tmp/channel-coordinator-state.json','read']
 ]});
 b.call('session','grant',{ubus_rpc_session:sid,scope:'uci',objects:[['channel_coordinator','read']]});
 let batches=filter(fs.lsdir('/etc/wifi-coordinator') ?? [],n=>match(n,/^batch-[0-9]+\.json$/));
 if(length(batches))check(index(post('format=json&hours=6'),'Status: 403')==0,'each archive needs permission');
 b.call('session','grant',{ubus_rpc_session:sid,scope:'file',objects:[['/etc/wifi-coordinator/batch-*.json','read']]});
 check(index(post('format=xml&hours=6'),'Status: 400')==0,'unknown format denied');
 check(index(post('format=csv&hours=201&dataset=actions'),'Status: 400')==0,'out of range window denied');
 check(index(post('format=json&hours=6&path=/etc/shadow'),'Status: 400')==0,'user paths denied');
 check(index(post('format=json&hours=6&hours=1'),'Status: 400')==0,'duplicate fields denied');
 let response=post('format=json&hours=0'),at=index(response,'\r\n\r\n');
 check(index(response,'Content-Disposition: attachment;')>=0&&index(response,'Cache-Control: no-store')>=0,'download and no-cache headers');
 let data=json(substr(response,at+4));
 check(data.format=='wifi-coordinator-history'&&data.version==1&&data.result.complete,'authorized JSON complete');
 check(length(keys(data.datasets))==6&&type(data.datasets.clients)=='array','all graph datasets, including client counts');
 for(let k in ['periods','clients','traffic','surveys','radar','actions']){
  response=post('format=csv&hours=6&dataset='+k);
  check(index(response,'Content-Type: text/csv')==0&&index(response,'"summary"')>=0,'authorized CSV '+k);
 }
}catch(e){b.call('session','destroy',{ubus_rpc_session:sid});die(e);}
b.call('session','destroy',{ubus_rpc_session:sid});
printf('PASS: %d CGI authorization/download checks\n',checks);
