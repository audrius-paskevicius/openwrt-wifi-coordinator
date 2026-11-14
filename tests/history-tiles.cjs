'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
const source=fs.readFileSync(path.join(__dirname,'../channel-coordinator/files/wifi-coordinator.history.js'),'utf8');
let bodies=[],response;
const api=new Function('baseclass','L','fetch','URLSearchParams','AbortController','setTimeout','clearTimeout',source)(
 {extend:x=>x},{env:{sessionid:'test'}},async(u,o)=>{bodies.push(new URLSearchParams(o.body));return {ok:true,json:async()=>response};},URLSearchParams,AbortController,setTimeout,clearTimeout);
function tile(id,start,end,source='boot'){return {id,start,end,data:{radio_names:['radio0'],periods:[{radio:'radio0',start,end,channel:36,center:5210,width:80,role:'serving'}],samples:[],surveys:[],events:[],survey_cells:[],client_points:{radio0:[{x:start,y:1,interval:{start,end,source}},{x:end,y:1,interval:{start,end,source}}]},traffic_points:{radio0:[{x:start,y:1,peak:10,end:start+295,source}]}}};}
(async()=>{
 const a=tile('a'.repeat(32),0,300),b=tile('b'.repeat(32),300,600);
 response={protocol:3,start:0,end:600,read_errors:[],display:{decimation:true},tiles:[a,b],channel_evidence:[],client_evidence:[]};
 response.tiles.push({id:'d'.repeat(32),pending:true});
 const first=await api.read({hours:1,width:800});assert.equal(first.periods.length,1);assert.equal(first.periods[0].end,600);assert.equal(a.data.periods[0].end,300,'assembly cannot mutate cached tile');
 response={...response,tiles:[{id:a.id},{id:b.id}]};const second=await api.read({hours:1,width:800});assert.deepEqual(second.periods,first.periods);assert(bodies.at(-1).get('have').includes(a.id),'refresh advertises existing immutable tiles');
 const c=tile('c'.repeat(32),900,1200,'next-boot');response={...response,end:1200,tiles:[{id:a.id},c]};const gap=await api.read({hours:1,width:800});assert(gap.client_points.radio0.some(p=>p.y===null));assert(gap.traffic_points.radio0.some(p=>p.y===null),'missing coverage and reboot boundaries remain gaps');
 response={start:0,end:1200,read_errors:[],periods:[],display:{decimation:false}};const raw=await api.read({hours:1,width:800});assert.equal(raw.display.decimation,false,'full detail remains independent of cached summaries');
 console.log('PASS: incremental tile transfer, immutable browser cache, interval joining, reboot/gap preservation and raw mode');
})().catch(e=>{console.error(e);process.exitCode=1;});
