'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
process.env.HISTORY_TEST_IMPORT='1';
const {harness,fixture}=require('./history-worker.cjs');
function compare(a,b,p='result'){
 if(typeof a==='number'&&typeof b==='number'){
  if(a===b)return;
  if(!Number.isFinite(a)||!Number.isFinite(b)||Math.abs(a-b)>Math.max(1,Math.abs(b))*1e-12)throw Error('Numeric mismatch at '+p);return;
 }
 if(a&&b&&typeof a==='object'&&typeof b==='object'){
  assert.deepEqual(Object.keys(a).sort(),Object.keys(b).sort(),'Keys differ at '+p);
  for(const k of Object.keys(b))compare(a[k],b[k],p+'.'+k);return;
 }
 if(a!==b)throw Error('Mismatch at '+p);
}
(async()=>{
 const references=JSON.parse(fs.readFileSync(process.argv[2],'utf8')),t=harness(),{h,end}=fixture(),id='a'.repeat(64);
 t.source.set(id,h);let checked=0;
 for(const reference of references){
  const {hours,width,adapt}=reference,meta={protocol:4,epoch:'a'.repeat(16),blocks:[{id,size:10000}],active:{},start:end-hours*3600,end,max_age:900,actions:[],action_total:10,read_errors:[],display:{decimation:adapt,triangles:true,squares:true,crosses:true,popups:true}};
  const actual=await t.run(meta,width),r=reference.result;
  const expected=r.full||{...t.context.merge(r.views),channel_evidence:r.channel_evidence,client_evidence:r.client_evidence};
  for(const k of ['periods','clients','samples','surveys','events','radio_names','traffic_points','client_points','survey_cells','channel_evidence','client_evidence'])compare(actual[k],JSON.parse(JSON.stringify(expected[k])),hours+'h/'+width+'/'+adapt+'/'+k);
  checked++;
 }
 assert.equal(checked,36);console.log('PASS: all 36 worker outputs match ucode reference across nine spans, both widths and detail modes (numeric serialization tolerance only)');
})().catch(e=>{console.error(e.message);process.exitCode=1;});
