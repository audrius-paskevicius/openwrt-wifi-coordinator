'use strict';
'require baseclass';
'require wifi-coordinator.chart as chartlib';

const palette=['#d900b5','#f05a00','#005dff','#008f9c'];
function colour(r,i){var n=/^radio(\d+)$/.exec(r);return palette[(n?Number(n[1]):i)%palette.length];}
function radioIndex(r,i){var n=/^radio(\d+)$/.exec(r);return n?Number(n[1]):i;}
function dash(r,i){return [];}
function keyStyle(r,i){return 'solid';}
var hatchCache=new Map();
function hatch(r,i){
 var index=radioIndex(r,i)%4,key=index+':'+colour(r,i);if(hatchCache.has(key))return hatchCache.get(key);
 var tile=document.createElement('canvas');tile.width=12;tile.height=12;
 var ctx=tile.getContext('2d');ctx.strokeStyle=colour(r,i);ctx.globalAlpha=0.85;ctx.lineWidth=1.6;ctx.beginPath();
 if(index==1){ctx.moveTo(6,0);ctx.lineTo(6,12);}
 else for(var n=-1;n<=1;n++){
  if(index==0||index==3){ctx.moveTo(n*12,0);ctx.lineTo(n*12+12,12);}
  if(index==2||index==3){ctx.moveTo(n*12,12);ctx.lineTo(n*12+12,0);}
 }
 ctx.stroke();var result={pattern:ctx.createPattern(tile,'repeat'),url:tile.toDataURL()};hatchCache.set(key,result);return result;
}
function patternStyle(r,i){return 'border-color:'+colour(r,i)+';background-image:url("'+hatch(r,i).url+'")';}
function patternName(r,i){return ['left-leaning lines','vertical lines','right-leaning lines','crossed lines'][radioIndex(r,i)%4];}
function clock(t){return new Date(t*1000).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'});}
function dated(t){return new Date(t*1000).toLocaleString([],{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'});}
function frequency(ch){return ch<=14?(ch==14?2484:2407+5*ch):5000+5*ch;}
// Keep MHz spacing inside each band; collapse only the gap between bands.
function position(f){return f<3000?f-2400:120+f-5170;}
function centre(p){
 if(Number.isFinite(p.center))return p.center;
 var f=frequency(p.channel);if(p.width==20)return f;
 var starts=p.width==80?[5180,5260,5500,5580,5660,5745]:p.width==40?[5180,5220,5260,5300,5500,5540,5580,5620,5660,5700,5745,5785]:[];
 var start=starts.find(function(s){return f>=s&&f<s+p.width&&(f-s)%20==0;});
 return start==null?null:start+p.width/2-10;
}
function geometry(p){var c=centre(p);return c==null?null:{center:c,low:position(c-p.width/2),high:position(c+p.width/2)};}
function baseOptions(start,end){return {
 responsive:true,maintainAspectRatio:false,animation:false,normalized:false,
 parsing:false,spanGaps:false,events:['mousemove','mouseout','click','touchstart','touchmove'],
 elements:{point:{radius:0,hitRadius:5},line:{borderWidth:2.5,tension:0,fill:false}},
 interaction:{mode:'nearest',intersect:false},
 plugins:{legend:{display:false},tooltip:{displayColors:true}},
 scales:{x:{type:'linear',min:start,max:end,grid:{color:'#e5e5e5'},border:{color:'#999'},
  ticks:{color:'#444',maxTicksLimit:7,maxRotation:0,callback:end-start>=86400?dated:clock},title:{display:true,text:'Time',color:'#444'}},
 y:{type:'linear',grid:{color:'#e5e5e5'},border:{color:'#999'},ticks:{color:'#444'},afterFit:function(s){s.width=100;}}}
};}
function line(label,data,color,extra){return Object.assign({label:label,data:data,borderColor:color,backgroundColor:color,fill:false,pointRadius:0,pointHoverRadius:3,borderWidth:2.5,tension:0,spanGaps:false},extra||{});}
function channelData(periods,names,start,end){
 var sets=[];
 names.forEach(function(r,i){
  ['serving','radar preparation'].forEach(function(role){
   var outline=[];
   periods.filter(function(p){return p.radio==r&&(p.role||'serving')==role;}).forEach(function(p){
    var g=geometry(p),a=Math.max(start,p.start),b=Math.min(end,p.end);if(!g||b<=a)return;
    function point(x,y){return {x:x,y:y,period:p,center:g.center};}
    outline.push(point(a,g.low),point(b,g.low),point(b,g.high),point(a,g.high),point(a,g.low),{x:b,y:null});
   });
   if(outline.length){
    // Transparent pattern tiles combine into coloured cross-hatching at overlaps.
    sets.push(line(r,outline,colour(r,i),{radio:r,fill:'shape',backgroundColor:hatch(r,i).pattern,borderWidth:0,order:6,wcRole:role,wcFill:true,pointHoverRadius:0}));
    sets.push(line(r,outline,'#ffffff',{radio:r,borderWidth:3.8,order:4,wcRole:role,wcHalo:true,pointHoverRadius:0}));
    sets.push(line(r,outline,colour(r,i),{radio:r,borderWidth:2.5,borderDash:role=='radar preparation'?[6,4]:[],order:2-i/100,wcRole:role}));
   }
  });
 });return sets;
}
function trafficData(samples,names){
 return names.map(function(r,i){
  // One weighted value per five-minute bucket, even if the radio changed channel.
  var buckets={};samples.filter(function(s){return s.radio==r&&s.n>0;}).forEach(function(s){
   var b=buckets[s.time]||(buckets[s.time]={time:s.time,end:s.end,n:0,sum:0,peak:0});
   b.end=Math.max(b.end,s.end);b.n+=s.n;b.sum+=s.traffic_sum;b.peak=Math.max(b.peak,s.traffic_peak);
  });
  var points=[],previous=null;
  Object.keys(buckets).map(Number).sort(function(a,b){return a-b;}).forEach(function(t){
   var b=buckets[t];if(previous!=null&&t>previous)points.push({x:t-1,y:null});
   points.push({x:t,y:b.sum/b.n,peak:b.peak,end:b.end});previous=t+300;
  });return line(r,points,colour(r,i),{radio:r,borderDash:dash(r,i),pointRadius:points.filter(function(p){return p.y!=null;}).length==1?2:0});
 });
}
function surveyData(surveys,start,end){
 var bins={},frames=surveys.slice().sort(function(a,b){return a.time-b.time;});
 frames.forEach(function(s){
  (s.bands||[]).forEach(function(band){(band.levels||[]).forEach(function(v,j){
   if(v==null)return;
   var lo=band.start+j*band.step,key=lo+':'+band.step;
   if(!bins[key])bins[key]={low:lo,high:lo+band.step,points:[]};
   bins[key].points.push({y:position(lo+band.step/2),level:Math.max(0,Math.min(100,v)),observed:s.time+((band.offsets||[])[j]||0),low:lo,high:lo+band.step});
  });});
 });
 return Object.keys(bins).map(function(key){var bin=bins[key];bin.points.sort(function(a,b){return a.observed-b.observed;});var points=bin.points.map(function(p,i){return Object.assign({},p,{x:[Math.max(start,p.observed),Math.min(end,bin.points[i+1]?bin.points[i+1].observed:end)]});}).filter(function(p){return p.x[1]>p.x[0];});return {
  type:'bar',indexAxis:'y',label:'Spectrum survey '+bin.low+'–'+bin.high+' MHz',wcSurvey:true,
  data:points,parsing:true,grouped:false,order:10,borderWidth:0,borderSkipped:false,
  backgroundColor:function(c){return 'rgba(30,30,30,'+(0.02+0.60*Math.sqrt((c.raw?c.raw.level:0)/100))+')';},
  barThickness:function(c){var y=c.chart.scales.y;return Math.abs(y.getPixelForValue(position(bin.high))-y.getPixelForValue(position(bin.low)));}
 };});
}
function radarData(records,start,end,halfLife){
 var bins={},half=Math.max(60,halfLife||21600),step=Math.max(60,(end-start)/160,half/12);
 (records||[]).forEach(function(e){if(!(e.width>0)||!Number.isFinite(e.center)||e.time>end)return;
  for(var f=e.center-e.width/2+10;f<e.center+e.width/2;f+=20){if(!bins[f])bins[f]=[];bins[f].push(e);}
 });
 return Object.keys(bins).map(function(key){
  var f=Number(key),events=bins[key],times=[start,end];
  events.forEach(function(e){if(e.time>start&&e.time<end)times.push(e.time);});
  for(var t=start+step;t<end;t+=step)times.push(t);
  times=Array.from(new Set(times)).sort(function(a,b){return a-b;});
  function level(t){return Math.min(1,events.reduce(function(n,e){return n+(t>=e.time?(e.weight||1)*Math.pow(2,-(t-e.time)/half):0);},0));}
  var points=[];
  for(var i=0;i<times.length-1;i++){
   var a=times[i],b=times[i+1],v=level(a);if(v<0.001)continue;
   var seen=events.filter(function(e){return e.time<=a;}).map(function(e){return e.time;});
   points.push({x:[a,b],y:position(f),low:f-10,high:f+10,radar:true,level:v,endLevel:level(b-0.001),observed:Math.max.apply(null,seen)});
  }
  return {type:'bar',indexAxis:'y',label:'Radar history',wcRadar:true,data:points,parsing:true,grouped:false,
   order:8,borderWidth:0,borderSkipped:false,
   backgroundColor:function(c){var p=c.raw,x=c.chart.scales.x;if(!p||!x)return 'transparent';
    var a=x.getPixelForValue(p.x[0]),b=x.getPixelForValue(p.x[1]);
    if(!Number.isFinite(a)||!Number.isFinite(b)||a==b)return 'rgba(185,125,0,'+(0.22*p.level)+')';
    var gradient=c.chart.ctx.createLinearGradient(a,0,b,0);
    gradient.addColorStop(0,'rgba(185,125,0,'+(0.22*p.level)+')');gradient.addColorStop(1,'rgba(185,125,0,'+(0.22*p.endLevel)+')');return gradient;},
   barThickness:function(c){var y=c.chart.scales.y;return Math.abs(y.getPixelForValue(position(f+10))-y.getPixelForValue(position(f-10)));}
  };
 });
}
function channelChart(canvas,periods,names,start,end,surveys,radar){
 var options=baseOptions(start,end),ticks=[1,6,11,14,36,52,64,100,116,132,149,161,165].map(function(c){return {value:position(frequency(c)),label:(c<=14?'2.4G · ':'5G · ')+c};});
 ticks.push({value:105,label:'//'});ticks.sort(function(a,b){return a.value-b.value;});
 options.scales.y.min=0;options.scales.y.max=795;
 options.scales.y.afterBuildTicks=function(s){s.ticks=ticks.map(function(t){return {value:t.value};});};
 options.scales.y.ticks={autoSkip:false,color:'#444',font:{size:11},callback:function(v){return (ticks.find(function(t){return t.value==v;})||{}).label||'';}};
 options.scales.y.grid={color:function(c){return c.tick&&c.tick.value==105?'#999':'#e5e5e5';}};
 options.scales.y.title={display:true,text:'Channel / band',color:'#444'};
 options.plugins.tooltip.filter=function(item){return !item.dataset.wcHalo&&!item.dataset.wcFill;};
 options.plugins.tooltip.callbacks={
  title:function(items){var raw=items[0]&&items[0].raw,p=raw&&raw.period;return p?dated(p.start)+' – '+dated(p.end):raw?(raw.radar?'Last radar detection: ':'Survey measured at ')+dated(raw.observed):'';},
  label:function(c){var p=c.raw.period;return p?[p.radio+': primary channel '+p.channel+' / '+p.width+' MHz','Centre '+c.raw.center+' MHz · '+(p.role||'serving')]:c.raw.radar?[c.raw.low+'–'+c.raw.high+' MHz','Radar avoidance strength: '+Math.round(c.raw.level*100)+'% (not a probability)']:[c.raw.low+'–'+c.raw.high+' MHz','Congestion estimate: '+c.raw.level+' / 100'];}
 };
 return new chartlib.Chart(canvas,{type:'line',data:{datasets:channelData(periods,names,start,end).concat(surveyData(surveys||[],start,end),radarData(radar&&radar.events,start,end,radar&&radar.half_life))},options:options});
}
function trafficChart(canvas,samples,names,start,end){
 var options=baseOptions(start,end);options.scales.y.min=0;options.scales.y.suggestedMax=0.1;
 options.scales.y.ticks.maxTicksLimit=5;options.scales.y.title={display:true,text:'Traffic (Mbit/s)',color:'#444'};
 options.plugins.tooltip.callbacks={title:function(items){return items.length?dated(items[0].raw.x)+' – '+dated(items[0].raw.end):'';},
  label:function(c){return c.dataset.label+': '+c.raw.y.toFixed(3)+' Mbit/s average; '+c.raw.peak.toFixed(3)+' peak (5-minute summary)';}};
 return new chartlib.Chart(canvas,{type:'line',data:{datasets:trafficData(samples,names)},options:options});
}
return baseclass.extend({channelChart:channelChart,trafficChart:trafficChart,colour:colour,keyStyle:keyStyle,patternStyle:patternStyle,patternName:patternName,geometry:geometry,channelData:channelData,trafficData:trafficData,surveyData:surveyData,radarData:radarData});
