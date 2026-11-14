'use strict';
'require baseclass';
'require wifi-coordinator.chart as chartlib';
'require wifi-coordinator.time as timefmt';

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
function dated(t){return timefmt.stamp(t);}
function frequency(ch){return ch<=14?(ch==14?2484:2407+5*ch):5000+5*ch;}
// Fixed WLAN channel plans. PHY band declarations select whole plans, never
// individual frequencies. See docs/ARCHITECTURE.md for the plan references.
const plans={
 '2g':{label:'2.4G',ranges:[[2401,2495]],ticks:[1,6,11,14],frequency:c=>c==14?2484:2407+5*c},
 '5g':{label:'5G',ranges:[[5160,5330],[5490,5895]],ticks:[36,52,64,100,116,132,144,149,165,177],frequency:c=>5000+5*c},
 '6g':{label:'6G',ranges:[[5925,7125]],ticks:[1,33,65,97,129,161,193,233],frequency:c=>5950+5*c}
};
function spectrumAxis(bands){
 var sections=[],breaks=[],ticks=[],top=0;
 ['2g','5g','6g'].filter(b=>(bands||[]).includes(b)).forEach(function(b){
  var plan=plans[b];
  plan.ranges.forEach(function(range){
   if(sections.length){breaks.push({value:top+8,low:sections[sections.length-1].high,high:range[0]});top+=16;}
   sections.push({band:b,low:range[0],high:range[1],offset:top});top+=range[1]-range[0];
  });
 });
 function position(f){var s=sections.find(s=>f>=s.low&&f<=s.high);return s?s.offset+f-s.low:null;}
 function spans(low,high){return sections.map(function(s){var a=Math.max(low,s.low),b=Math.min(high,s.high);return b>a?{low:a,high:b,yLow:s.offset+a-s.low,yHigh:s.offset+b-s.low}:null;}).filter(Boolean);}
 ['2g','5g','6g'].filter(b=>(bands||[]).includes(b)).forEach(function(b){
  plans[b].ticks.forEach(c=>ticks.push({value:position(plans[b].frequency(c)),label:plans[b].label+' \u00b7 '+c}));
 });
 breaks.forEach(g=>ticks.push({value:g.value,label:'//',gap:true}));ticks.sort((a,b)=>a.value-b.value);
 return {position:position,spans:spans,sections:sections,breaks:breaks,ticks:ticks,max:top};
}
const defaultAxis=spectrumAxis(['2g','5g','6g']);
function centre(p){
 if(Number.isFinite(p.center))return p.center;
 var f=frequency(p.channel);if(p.width==20)return f;
 var starts=p.width==160?[5180,5500,5745]:p.width==80?[5180,5260,5500,5580,5660,5745,5825]:p.width==40?[5180,5220,5260,5300,5500,5540,5580,5620,5660,5700,5745,5785,5825,5865]:[];
 var start=starts.find(function(s){return f>=s&&f<s+p.width&&(f-s)%20==0;});
 return start==null?null:start+p.width/2-10;
}
function geometry(p,axis){var c=centre(p),a=axis||defaultAxis;return c==null?null:{center:c,low:a.position(c-p.width/2),high:a.position(c+p.width/2)};}
function baseOptions(start,end){return {
 responsive:true,maintainAspectRatio:false,animation:false,normalized:false,
 parsing:false,spanGaps:false,events:['mousemove','mouseout','click','touchstart','touchmove'],
 elements:{point:{radius:0,hitRadius:5},line:{borderWidth:2.5,tension:0,fill:false}},
 interaction:{mode:'nearest',intersect:false},
 plugins:{legend:{display:false},tooltip:{displayColors:true}},
 scales:{x:{type:'linear',min:start,max:end,grid:{color:'#e5e5e5'},border:{color:'#999'},
  afterBuildTicks:function(s){s.ticks=timefmt.ticks(start,end,s.chart.width-100).map(v=>({value:v}));},
  ticks:{color:'#444',autoSkip:false,maxRotation:0,callback:function(v,i,ticks){return timefmt.label(v,start,end,ticks.map(t=>t.value));}},
  title:{display:false}},
 y:{type:'linear',grid:{color:'#e5e5e5'},border:{color:'#999'},ticks:{color:'#444'},afterFit:function(s){s.width=80;}}}
};}
function displayOptions(options,view){
 if(view&&view.display&&view.display.popups===false){options.plugins.tooltip.enabled=false;options.events=[];options.elements.point.hitRadius=0;}
 return options;
}
function aggregateLabel(raw){var a=raw&&raw.aggregate;return a?'Screen summary: '+a.count+' records, '+dated(a.start)+' \u2013 '+dated(a.end)+(a.min!=null?'; observed range '+a.min+'\u2013'+a.max:'; '+a.placements+' placements'):null;}
function line(label,data,color,extra){return Object.assign({label:label,data:data,borderColor:color,backgroundColor:color,fill:false,pointRadius:0,pointHoverRadius:3,borderWidth:2.5,tension:0,spanGaps:false},extra||{});}
function channelData(periods,names,start,end,axis){
 axis=axis||defaultAxis;
 var sets=[];
 names.forEach(function(r,i){
  ['serving','radar preparation'].forEach(function(role){
   var outline=[];
   periods.filter(function(p){return p.radio==r&&(p.role||'serving')==role;}).forEach(function(p){
    var g=geometry(p,axis),a=Math.max(start,p.start),b=Math.min(end,p.end);if(!g||b<=a)return;
    function point(x,y){return {x:x,y:y,period:p,center:g.center};}
    axis.spans(g.center-p.width/2,g.center+p.width/2).forEach(function(s){
     outline.push(point(a,s.yLow),point(b,s.yLow),point(b,s.yHigh),point(a,s.yHigh),point(a,s.yLow),{x:b,y:null});
    });
   });
   if(outline.length){
    // Transparent pattern tiles combine into coloured cross-hatching at overlaps.
    // Outlines return backwards in time to close each rectangle. Let Chart.js
    // detect that order; parsing:false incorrectly assumes sorted X values.
    sets.push(line(r,outline,colour(r,i),{radio:r,parsing:true,fill:'shape',backgroundColor:hatch(r,i).pattern,borderWidth:0,order:6,wcRole:role,wcFill:true,pointHoverRadius:0}));
    sets.push(line(r,outline,'#ffffff',{radio:r,parsing:true,borderWidth:3.8,order:4,wcRole:role,wcHalo:true,pointHoverRadius:0}));
    sets.push(line(r,outline,colour(r,i),{radio:r,parsing:true,borderWidth:2.5,borderDash:role=='radar preparation'?[6,4]:[],order:2-i/100,wcRole:role}));
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
function clientData(intervals,names,start,end){
 return names.map(function(r,i){
  var points=[],previous=null;
  intervals.filter(function(p){return p.radio==r&&Number.isInteger(p.count)&&p.count>=0&&Number.isFinite(p.start)&&Number.isFinite(p.end)&&p.end>=p.start&&p.end>=start&&p.start<=end;})
   .sort(function(a,b){return a.start-b.start;}).forEach(function(p){
    var a=Math.max(start,p.start),b=Math.min(end,p.end);
    if(previous&&(a>previous.end||p.source!=previous.source))points.push({x:a,y:null});
    points.push({x:a,y:p.count,interval:p},{x:b,y:p.count,interval:p});previous={end:b,source:p.source};
   });
  return line(r,points,colour(r,i),{radio:r,borderDash:dash(r,i),pointRadius:function(c){var p=c.raw;return p&&p.interval&&p.interval.start==p.interval.end?2:0;}});
 });
}
function surveyData(surveys,start,end,axis){
 axis=axis||defaultAxis;
 var bins={},frames=surveys.slice().sort(function(a,b){return a.time-b.time;});
 frames.forEach(function(s){
  (s.bands||[]).forEach(function(band){(band.levels||[]).forEach(function(v,j){
   if(v==null)return;
   var lo=band.start+j*band.step;
   axis.spans(lo,lo+band.step).forEach(function(span){
    var key=span.low+':'+span.high;
    if(!bins[key])bins[key]={low:span.low,high:span.high,points:[]};
    bins[key].points.push({y:(span.yLow+span.yHigh)/2,level:Math.max(0,Math.min(100,v)),observed:s.time+((band.offsets||[])[j]||0),low:span.low,high:span.high});
   });
  });});
 });
 return Object.keys(bins).map(function(key){var bin=bins[key];bin.points.sort(function(a,b){return a.observed-b.observed;});var points=bin.points.map(function(p,i){return Object.assign({},p,{x:[Math.max(start,p.observed),Math.min(end,bin.points[i+1]?bin.points[i+1].observed:end)]});}).filter(function(p){return p.x[1]>p.x[0];});return {
  type:'bar',indexAxis:'y',label:'Spectrum survey '+bin.low+'\u2013'+bin.high+' MHz',wcSurvey:true,
  data:points,parsing:true,grouped:false,order:10,borderWidth:0,borderSkipped:false,inflateAmount:0,
  backgroundColor:function(c){return 'rgba(30,30,30,'+(0.02+0.60*Math.sqrt((c.raw?c.raw.level:0)/100))+')';},
  barThickness:function(c){var y=c.chart.scales.y;return Math.abs(y.getPixelForValue(axis.position(bin.high))-y.getPixelForValue(axis.position(bin.low)));}
 };});
}
function radarColour(level){return 'rgba(140,90,0,'+(0.90*Math.max(0,Math.min(1,level)))+')';}
function radarGradient(){return 'linear-gradient(to right,'+radarColour(1)+','+radarColour(0)+'), #fff';}
function radarData(records,start,end,halfLife,axis,view){
 axis=axis||defaultAxis;
 var bins={},half=Math.max(60,halfLife||3600),step=Math.max(60,(end-start)/160,half/12);
 if(view)step=view.display&&view.display.decimation?Math.max(1,(end-start)/Math.max(1,view.pixel_width)):Math.max(1,half/12);
 (records||[]).forEach(function(e){if(!(e.width>0)||!Number.isFinite(e.center)||e.time>end)return;
  for(var f=e.center-e.width/2;f<e.center+e.width/2;f+=20){
   axis.spans(f,Math.min(f+20,e.center+e.width/2)).forEach(function(span){
    var key=span.low+':'+span.high;if(!bins[key])bins[key]={span:span,events:[]};bins[key].events.push(e);
   });
  }
 });
 return Object.keys(bins).map(function(key){
  var span=bins[key].span,events=bins[key].events,times=[start,end];
  events.forEach(function(e){if(e.time>start&&e.time<end)times.push(e.time);});
  for(var t=start+step;t<end;t+=step)times.push(t);
  times=Array.from(new Set(times)).sort(function(a,b){return a-b;});
  function level(t){return Math.min(1,events.reduce(function(n,e){return n+(t>=e.time?(e.weight||1)*Math.pow(2,-(t-e.time)/half):0);},0));}
  var points=[];
  for(var i=0;i<times.length-1;i++){
   var a=times[i],b=times[i+1],v=level(a);if(v<0.001)continue;
   var seen=events.filter(function(e){return e.time<=a;}).map(function(e){return e.time;});
   points.push({x:[a,b],y:(span.yLow+span.yHigh)/2,low:span.low,high:span.high,radar:true,level:v,endLevel:level(b-0.001),observed:Math.max.apply(null,seen)});
  }
  return {type:'bar',indexAxis:'y',label:'Radar history',wcRadar:true,data:points,parsing:true,grouped:false,
   order:8,borderWidth:0,borderSkipped:false,inflateAmount:0,
   backgroundColor:function(c){var p=c.raw,x=c.chart.scales.x;if(!p||!x)return 'transparent';
    var a=x.getPixelForValue(p.x[0]),b=x.getPixelForValue(p.x[1]);
    if(!Number.isFinite(a)||!Number.isFinite(b)||a==b)return radarColour(p.level);
    var gradient=c.chart.ctx.createLinearGradient(a,0,b,0);
    gradient.addColorStop(0,radarColour(p.level));gradient.addColorStop(1,radarColour(p.endLevel));return gradient;},
   barThickness:function(c){var y=c.chart.scales.y;return Math.abs(y.getPixelForValue(span.yHigh)-y.getPixelForValue(span.yLow));}
  };
 });
}
// Mark evidence without filling missing observations or inventing continuity.
function evidenceData(rows,names,start,end,events,axis){
 var sets=[],labels={unknown:'Unknown observation gap',unavailable:'Confirmed unavailable',action:'Recorded action'};
 names.forEach(function(r){
  var ordered=rows.filter(p=>p.radio==r).slice().sort((a,b)=>a.start-b.start),marks={unknown:[],unavailable:[],action:[]};
  function anchor(t){var previous=ordered.filter(p=>p.start<=t).slice(-1)[0];return previous||ordered[0];}
  function mark(kind,a,b,detail){
   if(b<start||a>end)return;
   var p=anchor(a),y=p?(axis?axis.position(centre(p)):p.count):null;
   if(y==null)return;
   marks[kind].push({x:Math.max(start,Math.min(end,(a+b)/2)),y:y,evidence:{radio:r,start:a,end:b,detail:detail,kind:kind}});
  }
  for(var i=1;i<ordered.length;i++){
   var a=ordered[i-1].end,b=ordered[i].start;
   if(b-a>15){
    var unknown=[[a,b]];
    (events||[]).filter(e=>e.radio==r&&e.event=='radio-unavailable').forEach(function(e){
     unknown=unknown.flatMap(function(span){
      if(e.end<=span[0]||e.start>=span[1])return [span];
      return [[span[0],Math.min(span[1],e.start)],[Math.max(span[0],e.end),span[1]]].filter(p=>p[1]>p[0]);
     });
    });
    unknown.forEach(p=>mark('unknown',p[0],p[1],'No observations for '+Math.round(p[1]-p[0])+' s; service continuity unknown'));
   }
  }
  (events||[]).forEach(function(e){
   if(e.radio!=r)return;
   if(e.event=='radio-unavailable')mark('unavailable',e.start,e.end,'Hostapd reported no enabled access point');
   else if(['placement-observed','radio-reconnect','radar-evacuation','client-departure'].includes(e.event)||e.event=='operation-complete'&&e.disconnect_events>0)
    mark('action',e.time,e.time,(e.reason||e.event)+(e.disconnect_events?' ('+e.disconnect_events+' station departures)':''));
  });
  Object.keys(marks).forEach(function(kind){if(marks[kind].length)sets.push(line(r+' \u00b7 '+labels[kind],marks[kind],kind=='unavailable'?'#b83b35':kind=='unknown'?'#777':colour(r,0),
   {wcEvidence:true,showLine:false,pointStyle:kind=='unavailable'?'crossRot':kind=='unknown'?'rect':'triangle',pointRadius:4,pointHoverRadius:6,pointBorderWidth:2,order:-1}));});
 });return sets;
}
function evidenceTitle(raw){return dated(raw.evidence.start)+(raw.evidence.end!=raw.evidence.start?' \u2013 '+dated(raw.evidence.end):'');}
function evidenceLabel(raw){return raw.evidence.radio+': '+raw.evidence.detail;}
function readyEvidence(rows,axis){
 var sets=new Map();(rows||[]).forEach(function(e){var key=e.radio+':'+e.kind;if(!sets.has(key))sets.set(key,{radio:e.radio,kind:e.kind,points:[]});var y=axis?axis.position(e.anchor):e.anchor;if(y==null)return;
  sets.get(key).points.push({x:(e.start+e.end)/2,y:y,evidence:Object.assign({},e,{detail:e.detail+(e.count>1?' ('+e.count+' records)':'')})});});
 return Array.from(sets.values()).map(function(s){return line(s.radio+' \u00b7 '+s.kind,s.points,s.kind=='unavailable'?'#b83b35':s.kind=='unknown'?'#777':colour(s.radio,0),{wcEvidence:true,showLine:false,pointStyle:s.kind=='unavailable'?'crossRot':s.kind=='unknown'?'rect':'triangle',pointRadius:4,pointHoverRadius:6,pointBorderWidth:2,order:-1});});
}
function surveyCells(cells,axis){
 var bins=new Map();(cells||[]).forEach(function(c){axis.spans(c[0],c[1]).forEach(function(span){var key=span.low+':'+span.high;if(!bins.has(key))bins.set(key,{span:span,points:[]});
  bins.get(key).points.push({x:[c[2],c[3]],y:(span.yLow+span.yHigh)/2,observed:c[4],level:c[5],minimum:c[6],maximum:c[7],observations:c[8],low:span.low,high:span.high});});});
 return Array.from(bins.values()).map(function(b){return {type:'bar',indexAxis:'y',label:'Spectrum survey',wcSurvey:true,data:b.points,parsing:true,grouped:false,order:10,borderWidth:0,borderSkipped:false,inflateAmount:0,
  backgroundColor:c=>'rgba(30,30,30,'+(0.02+0.60*Math.sqrt((c.raw?c.raw.level:0)/100))+')',
  barThickness:c=>Math.abs(c.chart.scales.y.getPixelForValue(b.span.yHigh)-c.chart.scales.y.getPixelForValue(b.span.yLow))};});
}
function updateChart(canvas,config,existing){
 if(!existing)return new chartlib.Chart(canvas,config);
 existing.data=config.data;existing.options=config.options;existing.resize();existing.update('none');return existing;
}
function channelChart(canvas,periods,names,start,end,surveys,radar,bands,events,view,existing){
 var options=displayOptions(baseOptions(start,end),view),axis=spectrumAxis(bands),ticks=axis.ticks;
 options.scales.y.min=-6;options.scales.y.max=Math.max(1,axis.max)+6;
 options.scales.y.afterBuildTicks=function(s){s.ticks=ticks.map(function(t){return {value:t.value};});};
 options.scales.y.ticks={autoSkip:false,color:'#444',font:{size:11},callback:function(v){return (ticks.find(function(t){return t.value==v;})||{}).label||'';}};
 options.scales.y.grid={color:function(c){return axis.breaks.some(g=>c.tick&&g.value==c.tick.value)?'#999':'#e5e5e5';}};
 options.scales.y.title={display:true,text:'Band / channel',color:'#444'};
 options.plugins.tooltip.filter=function(item,index,items){
  if(item.dataset.wcHalo||item.dataset.wcFill||item.dataset.wcSurvey&&item.raw.level===0)return false;
  // Closing a ribbon repeats its first corner. Show its interval only once,
  // even when several outline vertices are equally close to the pointer.
  var period=item.raw.period;
  return !period||!items.slice(0,index).some(other=>!other.dataset.wcHalo&&!other.dataset.wcFill&&other.raw.period===period);
 };
 options.plugins.tooltip.callbacks={
  title:function(items){var raw=items[0]&&items[0].raw,p=raw&&raw.period;return raw?.evidence?evidenceTitle(raw):p?dated(p.start)+' \u2013 '+dated(p.end):raw?(raw.radar?'Last radar detection: ':'Survey measured at ')+dated(raw.observed):'';},
  label:function(c){var p=c.raw.period;return c.raw.evidence?evidenceLabel(c.raw):p?[p.radio+': primary channel '+p.channel+' / '+p.width+' MHz','Centre '+c.raw.center+' MHz \u00b7 '+(p.role||'serving'),aggregateLabel(p)].filter(Boolean):c.raw.radar?[c.raw.low+'\u2013'+c.raw.high+' MHz','Radar avoidance strength: '+Math.round(c.raw.level*100)+'% (not a probability)']:[c.raw.low+'\u2013'+c.raw.high+' MHz','Congestion estimate: '+Number(c.raw.level).toFixed(1)+' / 100',c.raw.observations>1?'Time-weighted display column; range '+c.raw.minimum+'\u2013'+c.raw.maximum+' from '+c.raw.observations+' observations':null].filter(Boolean);}
 };
 return updateChart(canvas,{type:'line',data:{datasets:channelData(periods,names,start,end,axis).concat(view&&view.survey_cells?surveyCells(view.survey_cells,axis):surveyData(surveys||[],start,end,axis),radarData(radar&&radar.events,start,end,radar&&radar.half_life,axis,view),view&&view.channel_evidence?readyEvidence(view.channel_evidence,axis):evidenceData(periods,names,start,end,events,axis))},options:options},existing);
}
function trafficChart(canvas,samples,names,start,end,view,existing){
 var options=displayOptions(baseOptions(start,end),view);options.scales.y.min=0;options.scales.y.suggestedMax=0.1;
 options.scales.y.ticks.maxTicksLimit=5;options.scales.y.title={display:true,text:'Traffic (Mbit/s)',color:'#444'};
 options.plugins.tooltip.callbacks={title:function(items){return items.length?dated(items[0].raw.x)+' \u2013 '+dated(items[0].raw.end):'';},
  label:function(c){return [c.dataset.label+': '+c.raw.y.toFixed(3)+' Mbit/s average; '+c.raw.peak.toFixed(3)+' peak (5-minute summary)',aggregateLabel(c.raw)].filter(Boolean);}};
 return updateChart(canvas,{type:'line',data:{datasets:view&&view.traffic_points?names.map((r,i)=>{var points=view.traffic_points[r]||[];return line(r,points,colour(r,i),{radio:r,pointRadius:points.filter(p=>p.y!=null).length==1?2:0});}):trafficData(samples,names)},options:options},existing);
}
function clientChart(canvas,intervals,names,start,end,events,view,existing){
 var options=displayOptions(baseOptions(start,end),view);options.scales.y.min=0;options.scales.y.suggestedMax=1;
 options.scales.y.ticks.maxTicksLimit=5;options.scales.y.ticks.precision=0;
 options.scales.y.title={display:true,text:'Clients',color:'#444'};
 options.plugins.tooltip.callbacks={title:function(items){var raw=items[0]&&items[0].raw,p=raw&&raw.interval;return raw?.evidence?evidenceTitle(raw):p?dated(p.start)+' \u2013 '+dated(p.end):'';},
  label:function(c){return c.raw.evidence?evidenceLabel(c.raw):[c.dataset.label+': '+c.raw.y+' client'+(c.raw.y==1?'':'s'),aggregateLabel(c.raw)].filter(Boolean);}};
 options.layout={padding:{top:10}};
 var data=view&&view.client_points?names.map((r,i)=>line(r,view.client_points[r]||[],colour(r,i),{radio:r,stepped:'after',pointRadius:c=>c.raw&&c.raw.interval&&c.raw.interval.start==c.raw.interval.end?2:0})):clientData(intervals,names,start,end);
 return updateChart(canvas,{type:'line',data:{datasets:data.concat(view&&view.client_evidence?readyEvidence(view.client_evidence):evidenceData(intervals,names,start,end,events))},options:options,plugins:[clientFinPlugin]},existing);
}
function finSlant(r,i){return [-8,0,8][radioIndex(r,i)%3];}
function clientFinStyle(r,i){
 var dx=finSlant(r,i),c=colour(r,i);
 var svg='<svg xmlns="http://www.w3.org/2000/svg" width="28" height="14" viewBox="0 0 28 14"><path d="M0 12H28 M8 12L'+(8+dx)+' 4 M20 12L'+(20+dx)+' 4" fill="none" stroke="'+c+'" stroke-width="1.7"/></svg>';
 return 'display:inline-block;width:28px;height:14px;margin-right:7px;vertical-align:baseline;background:no-repeat center url("data:image/svg+xml,'+encodeURIComponent(svg)+'")';
}
function clientFinMarks(chart){
 var marks=[],area=chart.chartArea,spacing=12,total=chart.data.datasets.filter(d=>!d.wcEvidence).length;
 chart.data.datasets.forEach(function(d,i){
  if(!chart.isDatasetVisible(i))return;
  for(var j=0;j+1<d.data.length;j++){
   var p=d.data[j],q=d.data[j+1];
   if(!p.interval||!q.interval||p.interval.source!==q.interval.source||p.interval.end<q.interval.start||p.y==null||p.y!==q.y)continue;
   var a=Math.max(area.left,chart.scales.x.getPixelForValue(p.x)),b=Math.min(area.right,chart.scales.x.getPixelForValue(q.x)),y=chart.scales.y.getPixelForValue(p.y);
   if(b-a<2||y<area.top||y>area.bottom)continue;
   var phase=area.left+spacing*(i+0.5)/Math.max(1,total),first=phase+Math.ceil((a-phase)/spacing)*spacing;
   // Even a short newly recorded interval gets a fin for each radio.
   if(first>b)first=a+(b-a)*(i+1)/(total+1);
   for(var x=first;x<=b;x+=spacing)marks.push({x:x,y:y,dx:finSlant(d.radio,i),color:d.borderColor});
  }
 });return marks;
}
var clientFinPlugin={id:'wcClientFins',afterDatasetsDraw:function(chart){
 var ctx=chart.ctx,a=chart.chartArea;
 ctx.save();ctx.beginPath();ctx.rect(a.left,a.top-9,a.right-a.left,a.bottom-a.top+9);ctx.clip();ctx.lineWidth=1.7;
 clientFinMarks(chart).forEach(function(m){ctx.strokeStyle=m.color;ctx.beginPath();ctx.moveTo(m.x,m.y);ctx.lineTo(m.x+m.dx,m.y-8);ctx.stroke();});
 ctx.restore();
}};
return baseclass.extend({evidenceData:evidenceData,spectrumAxis:spectrumAxis,channelChart:channelChart,clientChart:clientChart,trafficChart:trafficChart,colour:colour,keyStyle:keyStyle,patternStyle:patternStyle,patternName:patternName,geometry:geometry,channelData:channelData,clientData:clientData,clientFinStyle:clientFinStyle,clientFinMarks:clientFinMarks,trafficData:trafficData,surveyData:surveyData,radarData:radarData,radarColour:radarColour,radarGradient:radarGradient});
