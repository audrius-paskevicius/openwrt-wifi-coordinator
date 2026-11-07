#!/usr/bin/env python3
"""Create an offline Chart.js fixture, with no router data or credentials."""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
files = root / 'channel-coordinator/files'
payload = {name: (files / filename).read_text(encoding='utf-8') for name, filename in [
    ('chart', 'wifi-coordinator.chart.js'), ('graph', 'wifi-coordinator.graphs.js')]}
script = r'''
const baseclass={extend:x=>x};
const chart=new Function('baseclass',payload.chart)(baseclass);
const graph=new Function('baseclass','chartlib',payload.graph)(baseclass,chart);
const start=1700000000,end=start+21600;
const periods=[
 {radio:'radio0',start,end:start+10800,channel:36,center:5250,width:160},
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
function assert(x,msg){if(!x)throw Error(msg);}
try{
 const full=graph.channelChart(document.getElementById('full'),periods,names,start,end,surveys,radar,['2g','5g']);
 const five=graph.channelChart(document.getElementById('five'),periods,names,start,end,surveys,radar,['5g']);
 [full,five].forEach(c=>c.update('none'));
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
 document.getElementById('legend').innerHTML=names.map((r,i)=>'<span style="color:'+graph.colour(r,i)+';margin-right:24px"><i style="display:inline-block;width:25px;height:12px;border:2px solid;'+graph.patternStyle(r,i)+'"></i> '+r+'</span>').join('');
 document.getElementById('result').textContent='PASS: actual Chart.js render, complete plans, band isolation, gap clipping, patterned legend and dense survey without dark seams';
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
<script>const payload=''' + json.dumps(payload) + ';\n' + script + '</script>'
Path(sys.argv[1]).write_text(html, encoding='utf-8')
print('Prepared offline Chart.js spectrum fixture: ' + sys.argv[1])
