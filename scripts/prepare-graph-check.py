#!/usr/bin/env python3
"""Create an offline Chart.js fixture, with no router data or credentials."""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
files = root / 'channel-coordinator/files'
payload = {name: (files / filename).read_text(encoding='utf-8') for name, filename in [
    ('chart', 'wifi-coordinator.chart.js'), ('graph', 'wifi-coordinator.graphs.js'), ('time', 'wifi-coordinator.time.js')]}
script = r'''
const baseclass={extend:x=>x};
const chart=new Function('baseclass',payload.chart)(baseclass);
const timefmt=new Function('baseclass',payload.time)(baseclass);
const graph=new Function('baseclass','chartlib','timefmt',payload.graph)(baseclass,chart,timefmt);
const start=1700000000,end=start+21600;
const periods=[
 {radio:'radio0',start,end:start+10000,channel:36,center:5250,width:160},
 {radio:'radio0',start:start+10800,end,channel:100,center:5570,width:160},
 {radio:'radio1',start,end,channel:6,center:2437,width:20},
 {radio:'radio2',start,end,channel:149,center:5775,width:80}
];
const surveys=[{time:start,bands:[
 {start:2400,step:5,levels:Array.from({length:19},(_,i)=>i<9?70:15)},
 {start:5170,step:20,levels:Array.from({length:34},(_,i)=>i<8?50:i<16?90:25)}
]}];
const radar={half_life:21600,events:[{time:start,center:5610,width:80}]};
const names=['radio0','radio1','radio2'];
const evidence=[{radio:'radio0',event:'radio-unavailable',start:start+10200,end:start+10600},
 {radio:'radio0',event:'placement-observed',time:start+10800}];
function assert(x,msg){if(!x)throw Error(msg);}
try{
 const full=graph.channelChart(document.getElementById('full'),periods,names,start,end,surveys,radar,['2g','5g'],evidence);
 const five=graph.channelChart(document.getElementById('five'),periods,names,start,end,surveys,radar,['5g']);
 [full,five].forEach(c=>c.update('none'));
 const outlineIndex=full.data.datasets.findIndex(d=>d.radio==='radio0'&&!d.wcFill&&!d.wcHalo);
 const otherIndex=full.data.datasets.findIndex(d=>d.radio==='radio1'&&!d.wcFill&&!d.wcHalo);
 const corner=full.getDatasetMeta(outlineIndex).data[0];
 const closedCorners=full.data.datasets.flatMap((d,i)=>d.radio==='radio0'&&d.wcRole==='serving'?[{datasetIndex:i,index:0},{datasetIndex:i,index:4}]:[]);
 full.tooltip.setActiveElements(closedCorners,{x:corner.x,y:corner.y});
 assert(full.tooltip.dataPoints.length===1,'closed ribbon corner must produce one tooltip entry');
 full.tooltip.setActiveElements([{datasetIndex:outlineIndex,index:0},{datasetIndex:outlineIndex,index:4},{datasetIndex:outlineIndex,index:6},{datasetIndex:otherIndex,index:0}],{x:corner.x,y:corner.y});
 assert(full.tooltip.dataPoints.length===3,'distinct intervals and radios remain in the tooltip');
 full.tooltip.setActiveElements([],{x:0,y:0});full.update('none');
 const markers=full.data.datasets.filter(d=>d.wcEvidence);
 assert(markers.length===3,'unknown, unavailable and action evidence shown independently');
 markers.forEach(d=>{
  const raw=d.data[0];
  assert(full.options.plugins.tooltip.callbacks.title([{raw}]).length>0,'evidence tooltip timestamp');
  const label=full.options.plugins.tooltip.callbacks.label({raw});
  assert(typeof label==='string'&&label.includes(raw.evidence.detail)&&!label.includes('Marker height'),'evidence tooltip keeps only the event description');
 });
 assert(full.scales.y.ticks.filter(t=>t.label==='//').length===2,'two standard breaks');
 assert(five.scales.y.ticks.filter(t=>t.label==='//').length===1,'5 GHz-only has one break');
 assert(five.scales.y.ticks.every(t=>!t.label.startsWith('2.4G')),'history cannot introduce undeclared band');
 assert(!five.data.datasets.some(d=>d.radio==='radio1'),'undeclared-band radio history is not plotted');
 assert(full.scales.y.ticks.some(t=>t.label==='5G · 177'),'complete upper 5 GHz plan');
 const axis=graph.spectrumAxis(['2g','5g']);
 const x=full.scales.x.getPixelForValue(start+5000),y=full.scales.y.getPixelForValue(axis.breaks[1].value+3);
 const pixel=full.ctx.getImageData(Math.round(x),Math.round(y),1,1).data;
 assert(pixel[3]===0||pixel[0]>210&&pixel[1]>210&&pixel[2]>210,'survey and radar cannot paint through omitted gap');
 const upper=full.scales.y.getPixelForValue(axis.position(5815));
 const edge=full.ctx.getImageData(Math.round(x)-1,Math.round(upper)-1,3,3).data;
 assert(Array.from({length:9},(_,i)=>i*4).some(i=>edge[i]<60&&edge[i+2]>180),'radio outline retains its complete upper edge');
 // Dense constant readings must not acquire dark seams from overlapping
 // translucent Chart.js rectangles at measurement or frequency boundaries.
 const dense=Array.from({length:360},(_,i)=>({time:start+i*60,bands:[{start:5490,step:20,levels:[64,64,64,64]}]}));
 const smooth=graph.channelChart(document.getElementById('smooth'),[],[],start,end,dense,{events:[]},['5g']);
 smooth.options.scales.x.grid.display=false;smooth.options.scales.y.grid.display=false;smooth.update('none');
 const row=Math.round(smooth.scales.y.getPixelForValue(graph.spectrumAxis(['5g']).position(5520)));
 const left=Math.ceil(smooth.chartArea.left)+2,right=Math.floor(smooth.chartArea.right)-2;
 const pixels=smooth.ctx.getImageData(left,row,right-left,1).data;
 const alphas=Array.from({length:right-left},(_,i)=>pixels[i*4+3]);
 assert(Math.max(...alphas)<=130,'dense survey boundaries cannot accumulate darker opacity');
 assert(Math.min(...alphas)>=90,'dense survey remains visible between readings');
 assert(smooth.data.datasets.filter(d=>d.wcSurvey).every(d=>d.inflateAmount===0),'survey cells have no inflated edges');
 assert(full.data.datasets.filter(d=>d.wcRadar).every(d=>d.inflateAmount===0),'radar cells have no inflated edges');
 const traffic=graph.trafficChart(document.getElementById('traffic'),[],names,start,end);
 const clients=graph.clientChart(document.getElementById('clients'),[
  {radio:'radio0',source:'one',start,end:start+7200,count:0},
  {radio:'radio0',source:'one',start:start+7200,end,count:2},
  {radio:'radio1',source:'one',start,end:start+7200,count:2},
  {radio:'radio1',source:'one',start:start+7200,end,count:0},
  {radio:'radio2',source:'one',start,end:start+10800,count:1},
  {radio:'radio2',source:'two',start:start+14400,end,count:1}
 ],names,start,end);
 clients.update('none');
 assert(clients.scales.y.ticks.every(t=>Number.isInteger(t.value)),'client axis has whole numbers');
 assert(clients.data.datasets.every(d=>d.borderWidth===traffic.data.datasets[0].borderWidth),'client and traffic line styles match');
 const cx=clients.scales.x.getPixelForValue(start+9000),cy=clients.scales.y.getPixelForValue(2);
 const cp=clients.ctx.getImageData(Math.round(cx)-2,Math.round(cy)-2,5,5).data;
 assert(Array.from({length:25},(_,i)=>i*4).some(i=>cp[i]>150&&cp[i+1]<80&&cp[i+2]>100),'actual client-count line painted');
 const localStart=new Date(2026,10,7,9,0).getTime()/1000;
 [300,950].forEach(width=>[ [localStart,localStart+21600], [localStart,localStart+120*3600], [localStart+14*3600,localStart+16*3600] ].forEach(([a,b])=>{
  const c=graph.channelChart(document.getElementById('dates'),[],[],a,b,[],{},['2g','5g']);
  const t=graph.trafficChart(document.getElementById('times'),[],names,a,b);
  [c,t].forEach(g=>g.resize(width,400));
  const tickData=g=>g.scales.x.ticks.map(t=>({value:t.value,label:t.label}));
  assert(JSON.stringify(tickData(c))===JSON.stringify(tickData(t)),'both graphs share time ticks');
  assert(c.scales.x.ticks.length<=7,'bounded tick count');
  assert(c.options.scales.x.title.text!=='Time','no redundant Time label');
  assert(!c.options.scales.x.title.display,'no caption beneath time axis');
  assert(c.scales.x.ticks.every(t=>timefmt.showDate(a,b)?Array.isArray(t.label)&&/^\d{4}-\d{2}-\d{2}$/.test(t.label[0]):typeof t.label==='string'),'dates only for 24-hour or longer views crossing midnight');
  c.destroy();t.destroy();
 }));
 document.getElementById('legend').innerHTML=names.map((r,i)=>'<span style="color:'+graph.colour(r,i)+';margin-right:24px"><i style="display:inline-block;width:25px;height:12px;border:2px solid;'+graph.patternStyle(r,i)+'"></i> '+r+'</span>').join('');
 document.getElementById('result').textContent='PASS: actual Chart.js render, spectrum geometry, dense surveys, shared ISO ticks at narrow/wide sizes, same-day, midnight and 120-hour views';
 document.getElementById('result').dataset.status='pass';
}catch(e){document.getElementById('result').textContent='FAIL: '+e.stack;document.getElementById('result').dataset.status='fail';}
'''
html = '''<!doctype html><meta charset="utf-8"><title>Standard spectrum axis check</title>
<style>body{font:14px Arial;margin:20px;color:#333}section{height:600px;border:1px solid #aaa;padding:12px}#result{white-space:pre-wrap}i{vertical-align:middle}</style>
<pre id="result">RUNNING</pre><h2>Channel placement over time</h2>
<p>Full standard plans for declared bands. // marks compressed gaps; MHz spacing remains proportional inside each block.</p>
<section><canvas id="full"></canvas></section><p id="legend"></p>
<h2>5 GHz declaration only (same history)</h2><section><canvas id="five"></canvas></section>
<h2>Dense survey boundaries</h2><section><canvas id="smooth"></canvas></section>
<h2>Traffic</h2><section><canvas id="traffic"></canvas></section>
<h2>Clients</h2><section><canvas id="clients"></canvas></section>
<section><canvas id="dates"></canvas></section><section><canvas id="times"></canvas></section>
<script>const payload=''' + json.dumps(payload) + ';\n' + script + '</script>'
Path(sys.argv[1]).write_text(html, encoding='utf-8')
print('Prepared offline Chart.js spectrum fixture: ' + sys.argv[1])
