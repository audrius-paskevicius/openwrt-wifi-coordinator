'use strict';
(async()=>{
 const source=require('fs').readFileSync(require('path').join(__dirname,'../channel-coordinator/files/wifi-history.js'),'utf8');
 const prefix=source.slice(0,source.indexOf('return view.extend'));
 const dir='/etc/wifi-coordinator/',ram='/tmp/wifi-coordinator-history.json',state='/tmp/channel-coordinator-state.json';
 const batch=dir+'batch-100.json';
 let checks=0;function check(ok,label){if(!ok)throw Error(label);checks++;}
 const abort=()=>Error('XHR request aborted by browser');
 const missing=()=>Object.assign(Error('No such file'),{name:'NotFoundError'});
 function fixture(){
  const f={listing:[{name:'batch-100.json',type:'file'}],data:{
   [batch]:JSON.stringify({samples:[{time:10,end:20,radio:'radio1'}]}),
   [ram]:JSON.stringify({samples:[{time:30,end:40,radio:'radio1'}]}),
   [state]:JSON.stringify({declared_bands:['2g','5g'],radar:{half_life:3600,events:[{time:100,center:5250,width:160,weight:1}]}})
  },fail:{},calls:[],waits:[]};
  async function request(path){f.calls.push(path);if(f.fail[path])await f.fail[path]();return path===dir?f.listing:f.data[path];}
  f.read=new Function('fs','setTimeout','Date',prefix+';return readHistory;')(
   {list:()=>request(dir),read_direct:p=>request(p)},(fn,ms)=>{f.waits.push(ms);fn();},{now:()=>1000000});
  return f;
 }
 let f=fixture(),h=await f.read();
 check(h.samples.length===2,'baseline combines archived and recent history');
 let tries=0;f.fail[dir]=()=>{if(++tries===1)throw abort();};f.calls=[];
 h=await f.read();
 check(tries===2&&f.waits.join(',')==='250','temporary listing failure retries briefly');
 check(!h.refresh_warning&&!h.read_errors.length,'successful retry produces no warning');
 check(!f.calls.includes(batch),'successful retry reuses immutable batch');
 f.fail[dir]=()=>{throw abort();};f.calls=[];f.waits=[];
 h=await f.read();
 check(f.calls.filter(p=>p===dir).length===3&&f.waits.join(',')==='250,750','persistent interruption has bounded retries');
 check(h.samples.length===2&&h.archive_files===1&&h.archive_bytes>0,'listing failure preserves archive cache and accounting');
 check(h.refresh_warning.includes('previously loaded')&&!h.read_errors.length,'cached interruption is distinguished from unreadable history');
 delete f.fail[dir];f.calls=[];h=await f.read();
 check(!h.refresh_warning&&!f.calls.includes(batch),'recovery clears warning without redownloading archive');
 f.fail[ram]=()=>{throw Error('XHR request timed out');};h=await f.read();
 check(h.samples.some(s=>s.time===30&&s.end===40),'recent-history interruption preserves original data and timestamps');
 check(h.refresh_warning.includes('previously loaded'),'recent-history cache is visibly stale');
 delete f.fail[ram];f.data[ram]=JSON.stringify({samples:[{time:30,end:50,radio:'radio1'}]});h=await f.read();
 check(!h.refresh_warning&&h.samples.find(s=>s.time===30).end===50,'recent-history recovery replaces cached snapshot');
 f.fail[state]=()=>{throw Object.assign(Error('network down'),{name:'NetworkError'});};h=await f.read();
 check(h.declared_bands.length===2&&h.radar.events.length===1&&h.radar.half_life===3600,'controller interruption preserves bands and radar memory');
 check(!!h.refresh_warning,'controller fallback is disclosed');
 delete f.fail[state];h=await f.read();check(!h.refresh_warning,'controller recovery clears warning');
 f.fail[dir]=()=>{throw Object.assign(Error('Permission denied'),{name:'PermissionError'});};f.calls=[];f.waits=[];
 h=await f.read();
 check(f.calls.filter(p=>p===dir).length===1&&!f.waits.length,'permission failure is not retried as a network interruption');
 check(h.read_errors.length===1&&h.read_errors[0].includes('Permission denied')&&h.samples.length===2,'permission failure remains visible without dropping cached archives');
 delete f.fail[dir];f.data[ram]='invalid';f.calls=[];h=await f.read();
 check(f.calls.filter(p=>p===ram).length===1&&h.read_errors.some(e=>e.includes(ram)),'malformed JSON is reported, not repeatedly fetched');
 check(h.samples.find(s=>s.time===30).end===50,'malformed update cannot replace good recent data');
 f.data[ram]=JSON.stringify({samples:{bad:true}});h=await f.read();
 check(h.read_errors.some(e=>e.includes('Invalid history records'))&&h.samples.length===2,'malformed record arrays do not poison the cache');
 f.data[ram]='{}';f.listing=[];h=await f.read();
 check(!h.samples.length&&!h.archive_bytes&&!h.archive_files&&!h.read_errors.length,'successful clear removes cached history');
 f=fixture();await f.read();f.fail[ram]=()=>{throw missing();};h=await f.read();
 check(h.samples.length===1&&!h.read_errors.length,'confirmed missing RAM file clears its cached snapshot');
 f.fail[ram]=()=>{throw abort();};h=await f.read();
 check(h.samples.length===1,'later interruption cannot resurrect a deleted RAM snapshot');
 f.fail[dir]=()=>{throw missing();};delete f.fail[ram];f.data[ram]='{}';h=await f.read();
 check(!h.samples.length&&!h.archive_files,'confirmed missing archive directory clears cached batches');
 f=fixture();f.fail[dir]=f.fail[ram]=f.fail[state]=()=>{throw abort();};h=await f.read();
 check(!h.samples.length&&h.refresh_warning.includes('not fully loaded'),'initial outage does not claim that cached history exists');
 check(f.calls.length===9,'first-load outage remains bounded across all three sources');
 delete f.fail[dir];delete f.fail[ram];delete f.fail[state];h=await f.read();
 check(h.samples.length===2&&!h.refresh_warning,'first-load outage recovers on the next refresh');
 f=fixture();let release;f.fail[dir]=()=>new Promise(resolve=>{release=resolve;});
 const first=f.read(),second=f.read();
 check(first===second&&f.calls.length===1,'overlapping refreshes share one request sequence');
 release();await Promise.all([first,second]);delete f.fail[dir];f.calls=[];await f.read();
 check(f.calls.length===3&&!f.calls.includes(batch),'completed shared refresh releases the next refresh and keeps its archive');
 f=fixture();f.fail[batch]=()=>{throw abort();};h=await f.read();
 check(h.archive_bytes===0&&h.samples.length===1&&!!h.refresh_warning,'failed new archive is incomplete, not cached as empty');
 delete f.fail[batch];h=await f.read();
 check(h.samples.length===2&&!h.refresh_warning,'new archive is fetched after recovery');
 console.log('PASS: '+checks+' history interruption/recovery cases');
})().catch(e=>{console.error(e);process.exitCode=1;});
