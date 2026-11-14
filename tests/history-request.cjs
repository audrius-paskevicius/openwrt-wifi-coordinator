'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
const source=fs.readFileSync(path.join(__dirname,'../channel-coordinator/files/wifi-coordinator.history.js'),'utf8');
let calls=[],fail=null,release=null,body={start:1,end:10,read_errors:[],periods:[]};
const fetch=async(url,options)=>{calls.push({url,options});if(release)await new Promise(r=>release=r);if(fail)throw fail;return {ok:true,json:async()=>body};};
const api=new Function('baseclass','L','fetch','URLSearchParams','AbortController','setTimeout','clearTimeout',source)(
 {extend:x=>x},{env:{sessionid:'test-session'}},fetch,URLSearchParams,AbortController,(fn,ms)=>ms===60000?0:setTimeout(fn,0),clearTimeout);
(async()=>{
 const options={hours:6,width:800};release=true;const a=api.read(options),b=api.read(options);assert.strictEqual(a,b);assert.equal(calls.length,1);release();release=null;
 const first=await a;assert.strictEqual(await b,first);assert.equal(new URLSearchParams(calls[0].options.body).get('width'),'800');assert.equal(calls[0].options.cache,'no-store');
 fail=Error('network');const cached=await api.read(options);assert(cached.refresh_warning);assert.equal(cached.end,10);assert.equal(calls.length,4,'two retries before stale data');
 await assert.rejects(api.read({hours:120,width:800}),/network/,'never reuse another time window');
 fail=Object.assign(Error('denied'),{status:403});await assert.rejects(api.read(options),/denied/);fail=Error('network');await assert.rejects(api.read(options),/network/,'permission failure clears cached view');
 fail=null;body={start:5,end:20,read_errors:[],periods:[]};assert.equal((await api.read(options)).end,20);
 const actions=await api.read({...options,kind:'actions',offset:100,end:20});assert.equal(new URLSearchParams(calls.at(-1).options.body).get('offset'),'100');
 console.log('PASS: viewport requests, coalescing, bounded retry/cache, distinct windows, permission failures and action paging');
})().catch(e=>{console.error(e);process.exitCode=1;});
