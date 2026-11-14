'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
const source=fs.readFileSync(path.join(__dirname,'../channel-coordinator/files/wifi-coordinator.graphs.js'),'utf8');
const graph=new Function('baseclass','chartlib','timefmt',source)({extend:x=>x},{Chart:function(c,x){return x;}},{stamp:String});
const view={display:{decimation:true,popups:false},pixel_width:200,traffic_points:{radio0:[{x:1,y:2,peak:5,end:2}]},client_points:{radio0:[{x:1,y:0,interval:{start:1,end:2,source:'a'}},{x:2,y:0,interval:{start:1,end:2,source:'a'}}]},channel_evidence:[],client_evidence:[],survey_cells:[[5170,5190,1,2,1,30,10,50,2]]};
const charts=[graph.channelChart(null,[],['radio0'],0,10,[],{},['5g'],[],view),graph.clientChart(null,[],['radio0'],0,10,[],view),graph.trafficChart(null,[],['radio0'],0,10,view)];
for(const c of charts){assert.equal(c.options.plugins.tooltip.enabled,false);assert.deepEqual(c.options.events,[]);}
assert.equal(charts[0].data.datasets.filter(d=>d.wcEvidence).length,0);assert.equal(charts[0].data.datasets.find(d=>d.wcSurvey).data[0].maximum,50);
assert.equal(charts[1].data.datasets[0].data[0].y,0);assert.equal(charts[1].data.datasets[0].stepped,'after');
assert.equal(charts[2].data.datasets[0].data[0].peak,5);
const evidence={...view,display:{...view.display,popups:true},channel_evidence:[{radio:'radio0',kind:'unavailable',start:2,end:3,anchor:5210,count:2,detail:'Unavailable'}]};
const marked=graph.channelChart(null,[],['radio0'],0,10,[],{},['5g'],[],evidence);assert.notEqual(marked.options.plugins.tooltip.enabled,false);assert.equal(marked.data.datasets.find(d=>d.wcEvidence).pointStyle,'crossRot');
assert(marked.options.plugins.tooltip.callbacks.label({raw:marked.data.datasets.find(d=>d.wcEvidence).data[0]}).includes('2 records'));
const radar=[{time:0,center:5250,width:20}];assert(graph.radarData(radar,0,10000,3600,graph.spectrumAxis(['5g']),{display:{decimation:true},pixel_width:20})[0].data.length<=21);
const historySource=fs.readFileSync(path.join(__dirname,'../channel-coordinator/files/wifi-history.js'),'utf8');
const radarHistory=new Function(historySource.slice(0,historySource.indexOf('function stamp('))+'return radarHistory;')();
const detection={event:'radar-state',radar_event:0,time:100,freq:5180,center:5250,width:160,phy:0};
const restored=radarHistory([detection,{...detection,phy:2},{...detection,radar_event:1}],[],[]);assert.equal(restored.length,1);assert.deepEqual(restored[0].phys,[0,2]);
console.log('PASS: all graph popups, prepared cells/points, cross markers, aggregate details, radar resolution and detection deduplication');

let updates=0;const existing={resize(){},update(mode){assert.equal(mode,'none');updates++;}};assert.strictEqual(graph.trafficChart(null,[],['radio0'],0,10,view,existing),existing);assert.equal(updates,1);
