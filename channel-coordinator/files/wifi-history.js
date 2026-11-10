'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';
'require uci';
'require fs';
'require poll';
'require wifi-coordinator.graphs as graphs';
'require wifi-coordinator.time as timefmt';
'require wifi-coordinator.help as help';
function historyKey(k,x){
 if(k=='clients')return JSON.stringify([x.radio,x.source,x.start,x.count]);
 if(k=='periods')return JSON.stringify([x.radio,x.start,x.channel,x.center,x.width,x.role]);
 if(k=='samples')return JSON.stringify([x.radio,x.time,x.channel,x.width,x.role,x.source]);
 if(k=='surveys')return String(x.cycle==null?x.time:x.cycle);
 return JSON.stringify(x);
}
var archiveCache=new Map(),recentCache=new Map(),archiveFiles=null,historyRead=null;
function missingHistory(e){return e.name=='NotFoundError'||/No such file/i.test(e.message||'');}
function interruptedHistory(e){return /^(AbortError|NetworkError|TimeoutError)$/.test(e.name||'')||/XHR request (aborted|timed out)|network request failed|failed to fetch/i.test(e.message||'');}
async function historyRequest(request){
 for(var attempt=0;;attempt++){
  try{return await request();}
  catch(e){if(!interruptedHistory(e)||attempt>=2)throw e;await new Promise(function(resolve){setTimeout(resolve,attempt?750:250);});}
 }
}
function radarHistory(events,periods,memory){
 // Planner memory is bounded and checkpointed separately from graph history.
 // Reconstruct detections from all retained batches, never from CAC/NOP events.
 var rows=(memory||[]).map(function(e){return Object.assign({},e,{phys:(e.phys||[]).slice()});});
 (events||[]).forEach(function(e){
  if(e.event!='radar-state'||e.radar_event!==0)return;
  var center=e.center,width=e.width,region=e.region==null?null:e.region;
  if(!Number.isFinite(center)||!(width>0)){
   var matches=(memory||[]).filter(function(p){return Math.abs(p.time-e.time)<=5&&(e.region==null||e.region==p.region)&&Number.isFinite(p.center)&&p.width>0&&e.freq>=p.center-p.width/2&&e.freq<p.center+p.width/2;});
   if(!matches.length)matches=(periods||[]).filter(function(p){return p.start<=e.time&&p.end+5>=e.time&&Number.isFinite(p.center)&&p.width>0&&e.freq>=p.center-p.width/2&&e.freq<p.center+p.width/2;});
   // Legacy records lack geometry. Use a unique contemporaneous block; if
   // ambiguous, show only the reported primary instead of inventing a width.
   var blocks=new Map(matches.map(function(p){return [p.center+':'+p.width,p];}));
   var p=blocks.size==1?Array.from(blocks.values())[0]:null;
   center=p?p.center:e.freq;width=p?p.width:20;if(region==null&&p&&p.region!=null)region=p.region;
  }
  rows.push({time:e.time,center:center,width:width,region:region,phys:e.phy==null?[]:[e.phy],weight:1});
 });
 var result=[],blocks=new Map();
 rows.sort(function(a,b){return a.time-b.time;}).forEach(function(e){
  if(!Number.isFinite(e.time)||!(e.time>0)||!Number.isFinite(e.center)||e.center<5000||e.center>=5925||!(e.width>0&&e.width<=160))return;
  var key=[e.region,e.center,e.width].join(':'),old=blocks.get(key);
  if(old&&e.time-old.time<=5){e.phys.forEach(function(phy){if(old.phys.indexOf(phy)<0)old.phys.push(phy);});return;}
  blocks.set(key,e);result.push(e);
 });
 return result;
}
function readHistory(){
 // A slow refresh and another caller must not race to replace or prune caches.
 if(!historyRead)historyRead=loadHistory().finally(function(){historyRead=null;});
 return historyRead;
}
async function loadHistory(){
 var errors=[],directory='/etc/wifi-coordinator/',interrupted=false,usedCache=false;
 // History can exceed the ubus file-read limit before its six-hour offload.
 // LuCI's streaming reader uses the same session and file ACLs without that cap.
 async function read(path,recent){
  try{
   var raw=await historyRequest(function(){return fs.read_direct(path,'text');}),h=JSON.parse(raw);
   if(!h||typeof h!='object'||Array.isArray(h))throw Error('Invalid history data');
   if(['periods','samples','clients','events','surveys'].some(function(k){return h[k]!=null&&!Array.isArray(h[k]);}))throw Error('Invalid history records');
   h.file_bytes=new TextEncoder().encode(raw).length;if(recent)recentCache.set(path,h);return h;
  }catch(e){
   if(missingHistory(e)){if(recent)recentCache.delete(path);return {};}
   var cached=recent&&recentCache.get(path);
   if(interruptedHistory(e))interrupted=true;
   else errors.push('Cannot read '+path+': '+(e.message||e)+(cached?'. Showing previously loaded data.':''));
   if(cached)usedCache=true;return cached||{};
  }
 }
 var files,listed=false;
 try{
  files=await historyRequest(function(){return fs.list(directory);});
  files=files.filter(function(f){return f.type=='file'&&/^batch-[0-9]+\.json$/.test(f.name);}).sort(function(a,b){return a.name.localeCompare(b.name);});
  listed=true;
 }catch(e){
  if(missingHistory(e)){files=[];listed=true;}
  else{
   if(interruptedHistory(e))interrupted=true;else errors.push('Cannot list history: '+(e.message||e));
   files=archiveFiles||[];if(archiveCache.size)usedCache=true;
  }
 }
 // Only a successful listing (including a confirmed missing directory) can
 // establish deletion. A failed request must never empty the archive cache.
 if(listed){archiveFiles=files;var names=new Set(files.map(function(f){return f.name;}));archiveCache.forEach(function(v,k){if(!names.has(k))archiveCache.delete(k);});}
 var parts=[];
 // Closed batches are immutable: fetch once, then reuse them on minute refreshes.
 for(var i=0;i<files.length;i+=4){await Promise.all(files.slice(i,i+4).map(async function(f){if(!archiveCache.has(f.name)){var h=await read(directory+f.name);if(h.file_bytes)archiveCache.set(f.name,h);}}));}
 files.forEach(function(f){if(archiveCache.has(f.name))parts.push(archiveCache.get(f.name));});
 var ram=await read('/tmp/wifi-coordinator-history.json',true),out=Object.assign({},ram),archiveBytes=parts.reduce(function(n,h){return n+(h.file_bytes||0);},0),saved=parts.reduce(function(n,h){return Math.max(n,h.saved||0);},0);
 parts.push(ram);
 ['periods','samples','clients','events','surveys'].forEach(function(k){var records=new Map();
  parts.forEach(function(part){(part[k]||[]).forEach(function(x){var id=historyKey(k,x),old=records.get(id),at=function(s){return s.updated||s.end||s.time;};if(!old||at(x)>=at(old))records.set(id,x);});});
  out[k]=Array.from(records.values()).sort(function(a,b){return (a.start||a.time)-(b.start||b.time);});
 });
 out.ram_bytes=ram.file_bytes||0;out.archive_bytes=archiveBytes;out.archive_files=files.length;out.read_errors=errors;
 var controller=await read('/tmp/channel-coordinator-state.json',true);out.radar=Object.assign({},controller.radar,{events:radarHistory(out.events,out.periods,controller.radar&&controller.radar.events)});out.declared_bands=controller.declared_bands||[];
 out.refresh_warning=interrupted?(usedCache?'Refresh interrupted; showing previously loaded history where available. Retrying automatically.':'Refresh interrupted; history is not fully loaded. Retrying automatically.'):null;
 out.archive_saved=ram.archive_saved||saved;return out;
}
function stamp(t){return timefmt.stamp(t);}
function surveyPressure(sample,surveys){
 var g=graphs.geometry(sample),bins={};
 if(!g||!Number.isFinite(g.center)||!(sample.width>0))return null;
 var low=g.center-sample.width/2,high=g.center+sample.width/2;
 surveys.forEach(function(frame){(frame.bands||[]).forEach(function(b){(b.levels||[]).forEach(function(level,i){
  if(level==null||!Number.isFinite(level))return;
  var lo=b.start+i*b.step,hi=lo+b.step,span=Math.max(0,Math.min(high,hi)-Math.max(low,lo));
  var observed=frame.time+((b.offsets||[])[i]||0),key=lo+':'+hi;
  if(!span||observed>sample.end)return;
  if(!bins[key]||observed>=bins[key].observed)bins[key]={span:span,level:level,observed:observed};
 });});});
 var rows=Object.values(bins),covered=rows.reduce(function(n,b){return n+b.span;},0);
 return covered?{level:rows.reduce(function(n,b){return n+b.span*b.level;},0)/covered,
  coverage:Math.min(100,100*covered/sample.width),oldest:Math.min.apply(null,rows.map(function(b){return b.observed;})),
  newest:Math.max.apply(null,rows.map(function(b){return b.observed;}))}:null;
}
function congestionCell(sample,surveys){
 var estimate=surveyPressure(sample,surveys),lines=[];
 if(sample.busy_n)lines.push(E('span',{},(sample.busy_sum/sample.busy_n).toFixed(0)+'% measured airtime'));
 if(estimate){
  lines.push(E('span',{'style':'display:block'},'Survey estimate '+estimate.level.toFixed(0)+' / 100'+(estimate.coverage<99.9?' ('+estimate.coverage.toFixed(0)+'% coverage)':'')));
 }
 if(!lines.length)lines.push(E('span',{},'Awaiting spectrum survey'));
 var detail='Measured airtime comes from driver counters. Survey estimates average the grey neighbour-pressure dataset across this channel width; they are not airtime percentages.';
 if(estimate)detail+=' Survey observed: '+stamp(estimate.oldest)+(estimate.oldest!=estimate.newest?' – '+stamp(estimate.newest):'')+'. Coverage: '+estimate.coverage.toFixed(0)+'%.';
 return E('div',{'title':detail},lines);
}
var retentionChoices=[1,3,6,12,24,48,72,96,120,168,200];
var actionNames={
 'radio-recovered':'Radio service recovered automatically','restart-retry':'Automatic restart-recovery check','switch-request-failed':'Channel switch request failed',
 'client-recovery-start':'Targeted client recovery started','client-recovery-request':'Targeted roaming request',
 'client-recovery-verified':'Alternate client service verified','client-recovery-unresolved':'Alternate client service unconfirmed',
 'move-evidence':'Placement recovery assessment',
 'recovery-client-unconfirmed':'Radio restored; client return unconfirmed',
 'cac-start':'Radar check started','cac-shared':'Radar clearance shared','radar-state':'Radar state changed',
 'handoff-request':'Gentle roaming request','handoff-strong':'Stronger roaming request','handoff-disconnect':'Decisive handoff',
 'switch-verified':'Channel change verified','switch-safety-stop':'Channel change failed verification','switch-ignored':'Driver kept previous channel','scan-client-recovered':'Client reconnected after scan',
 'rollback-verified':'Previous channel restored','rollback-failed':'Channel recovery needs attention',
 'plan-start':'Joint plan started','radio-repair':'Radio data service recovery','radar-evacuation':'Driver radar evacuation',
 'external-recovery-verified':'External channel change verified','external-recovery-unresolved':'External recovery needs attention',
 'switch-recovery':'Channel change needs recovery','radio-reconnect':'Brief restart for client reconnection','scan-client-unconfirmed':'Scan paused for client recheck',
 'scan-retry':'Survey batch retried','scan-complete':'Survey completed','scan-partial':'Partial survey saved','scan-client-loss':'Client disappeared during survey','scan-aborted':'Survey batch aborted','error':'Operation deferred or failed',
 'width-constrained':'20 MHz retained during HT40 setup',
 'operation-complete':'Radio operation finished','client-return':'Preferred-radio return',
 'switch-unconfirmed':'Radio ready; client stability unconfirmed',
 'steering-request':'Preferred-radio recommendation','steering-response':'Client response',
 'method-unavailable':'Unsupported switching method learned'
};
return view.extend({
 load:function(){return Promise.all([uci.load('channel_coordinator'),readHistory()]);},
 render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));},
 renderPage:function(data){
  var instances=[],frame=null;
  var history=data[1],retain=Math.max(1,Math.min(200,Number(uci.get('channel_coordinator','main','history_hours'))||24)),hours=Math.min(6,retain),display=E('div'),selector=E('select',{'class':'cbi-input-select'});
  function setRetention(value){retain=Math.max(1,Math.min(200,Number(value)||24));hours=Math.min(hours,retain);
   var choices=retentionChoices.filter(function(h){return h<=retain;});if(choices.indexOf(retain)<0)choices.push(retain);
   selector.replaceChildren.apply(selector,choices.map(function(h){return E('option',{value:h},'Last '+h+' hour'+(h==1?'':'s'));}));
   if(choices.indexOf(hours)<0)hours=choices[choices.length-1];selector.value=String(hours);
  }
  setRetention(retain);
  function redraw(h){
   if(frame!=null)cancelAnimationFrame(frame);
   instances.forEach(function(c){c.destroy();});instances=[];frame=null;
   var now=Math.floor(Date.now()/1000),cutoff=now-hours*3600;
   var periods=(h.periods||[]).filter(function(p){return p.end>=cutoff;});
   var clients=(h.clients||[]).filter(function(s){return s.end>=cutoff;});
   var samples=(h.samples||[]).filter(function(s){return s.end>=cutoff;});
   var surveys=(h.surveys||[]).slice().sort(function(a,b){return a.time-b.time;});
   var radioNames=Array.from(new Set(periods.map(function(p){return p.radio;}).concat(samples.map(function(s){return s.radio;}),clients.map(function(s){return s.radio;})))).sort();
   var warnings=(h.read_errors||[]).map(function(e){return E('p',{'class':'alert-message warning'},'History is incomplete. '+e);});
   if(h.refresh_warning)warnings.unshift(E('p',{'class':'alert-message warning'},h.refresh_warning));
   if(!radioNames.length){display.replaceChildren.apply(display,warnings.concat([E('p',{'class':'wc-status'},'History is collecting, or has been disabled. Recent history is in RAM; archived history survives reboot.')]));return;}
   var start=Math.min(now-1,Math.max(cutoff,Math.min.apply(null,periods.map(function(p){return p.start;}).concat(clients.map(function(s){return s.start;}),samples.map(function(s){return s.time;}),surveys.map(function(s){return s.time;})))));
   var channelCanvas=E('canvas',{'role':'img','aria-label':'Channel and width of each radio over time'});
   var clientCanvas=E('canvas',{'role':'img','aria-label':'Clients on each radio over time'});
   function heading(title,detail){return E('h3',{},E('span',{'class':'wc-setting-help','role':'button','tabindex':'0','data-tooltip':detail,'data-tooltip-style':'wc-help-tooltip','aria-label':title+'. '+detail},title));}
   var trafficCanvas=E('canvas',{'role':'img','aria-label':'Observed radio traffic over time'});
   function legend(patterns,fins){return E('p',{'class':'wc-legend'},radioNames.map(function(r,i){return E('span',{'style':'color:'+graphs.colour(r,i)+';margin-right:22px;font-weight:600;'},[E('span',{'class':fins?'wc-fin-key':patterns?'wc-pattern-key':'wc-line-key','style':fins?graphs.clientFinStyle(r,i):patterns?graphs.patternStyle(r,i):'border-color:'+graphs.colour(r,i),'title':patterns?graphs.patternName(r,i):r}),r]);}));}
   var radarHalf=Number(h.radar&&h.radar.half_life)||3600;
   function elapsedLabel(seconds){return seconds>=3600?+(seconds/3600).toFixed(1)+' h':+(seconds/60).toFixed(1)+' min';}
   var radarKey=E('div',{'class':'wc-radar-key','title':'Amber marks radar detections. Detection: 100%; after '+elapsedLabel(radarHalf)+': 50%; after '+elapsedLabel(2*radarHalf)+': 25%; after '+elapsedLabel(3*radarHalf)+': 12.5%. White represents zero remembered strength. Percentages describe avoidance strength, not probability. Radar clearance rules still apply.'},[
    E('span',{},_('Radar memory')),
    E('div',{'class':'wc-radar-ramp'},[
     E('div',{'class':'wc-amber-scale','aria-hidden':'true','style':'background:'+graphs.radarGradient()}),
     E('div',{'class':'wc-radar-ticks'},[100,75,50,25,0].map(function(n){return E('span',{},n+'%');}))
    ])
   ]);
   var nodes=[heading(_('Where each radio spent its time'),_('Ribbons show each radio’s channel and width. // marks gaps in spectrum. Hover or tap for details. Each declared band shows its standard channel plan; displayed channels may not be permitted locally or supported by your radio. Dashed outlines indicate radar listening.')+(surveys.length?'':' '+_('Survey background appears after the next scan.'))),
    E('div',{'class':'wc-chart wc-spectrum-chart'},channelCanvas),legend(true),
    E('div',{'class':'wc-spectrum-keys'},[E('div',{'class':'wc-survey-key','title':'Estimated congestion ranges from 0 (lowest) to 100 (highest estimated congestion). Darker grey means more or stronger overlapping networks, adjusted for advertised load. This is an estimate, not measured airtime or a percentage. Hover over the graph for measurement times.'},[E('span',{},_('Estimated congestion')),E('div',{'class':'wc-survey-ramp'},[E('div',{'class':'wc-grey-scale','aria-hidden':'true'}),E('div',{'class':'wc-scale-ticks'},[0,25,50,75,100].map(function(n){return E('span',{},String(n));}))])]),radarKey]),
    heading(_('Clients on each radio over time'),_('Associated clients, sampled every five seconds. Whole-number steps show count changes. Gaps mean no observations; older history contains no client-count intervals. Hover or tap for details.')),
    E('div',{'class':'wc-chart wc-traffic-chart'},clientCanvas),legend(false,true),
    heading(_('Observed traffic over time'),_('Upload + download, averaged over five minutes. This shows usage, not a speed test. Hover or tap for details.')),
    E('div',{'class':'wc-chart wc-traffic-chart'},trafficCanvas),legend()];
   var latest=radioNames.map(function(r){return samples.filter(function(s){return s.radio==r;}).slice(-1)[0];}).filter(Boolean);
   var head=['Radio','Channel / width','Traffic avg / peak','Clients peak','Congestion evidence','Weakest signal'];
   nodes.push(E('h3',{},_('Latest summaries')));
   nodes.push(E('div',{'class':'wc-table-wrap'},E('table',{'class':'table wc-table'},[
    E('thead',{},E('tr',{},head.map(function(x){return E('th',{'scope':'col'},_(x));}))),
    E('tbody',{},latest.map(function(s){return E('tr',{},[
     s.radio,s.channel+' / '+s.width+' MHz',(s.traffic_sum/Math.max(1,s.n)).toFixed(2)+' / '+s.traffic_peak.toFixed(2)+' Mbps',String(s.clients_peak),congestionCell(s,surveys),s.signal_min!=null?s.signal_min+' dBm':s.clients_peak===0?'No clients':'No signal data'
    ].map(function(x){return E('td',{},x);}));}))
   ])));
   var events=(h.events||[]).filter(function(e){return e.time>=cutoff;}).slice().reverse();
   nodes.push(heading(_('Recent actions'),_('Newest first, within the selected time window.')));
   nodes.push(E('div',{'class':'wc-table-wrap wc-log-wrap'},E('table',{'class':'table wc-table'},[
    E('thead',{},E('tr',{},['Time','Action','Details'].map(function(x){return E('th',{'scope':'col'},_(x));}))),
    E('tbody',{},events.map(function(e){var detail=e.reason||[
     e.operation?'operation '+e.operation:'',e.returned!=null?e.returned+' returned / '+e.elsewhere+' elsewhere / '+e.absent+' absent':'',e.declined?e.declined+' declined':'',e.response!=null?'response '+e.response:'',e.forced_disconnects!=null?e.forced_disconnects+' forced disconnects':'',e.radio,e.kind?'assessment: '+e.kind:'',e.affected!=null?e.affected+' affected clients':'',e.retry_seconds?Math.round(e.retry_seconds/60)+'-minute deferral':'',e.preflight?'before channel change':'',e.stage!=null?['gentle','strong','decisive'][e.stage]:'',e.helper?'helper '+e.helper:'',e.from!=null?'from '+e.from:'',e.to!=null?'to '+e.to:'',e.channel!=null?'channel '+e.channel:'',e.width?e.width+' MHz':'',e.clients!=null?e.clients+' clients':'',e.elapsed!=null?e.elapsed+' seconds':'',e.ban_seconds?e.ban_seconds+'-second return restriction':'',e.disconnect_events!=null?e.disconnect_events+' disconnect events':'',e.neighbors!=null?e.neighbors+' networks observed':'',e.missing_count!=null?e.missing_count+' clients missing':'',e.scanned_frequencies!=null?e.scanned_frequencies+' frequencies measured':'',e.missing_frequencies!=null?e.missing_frequencies+' deferred':''
    ].filter(Boolean).join('; ');return E('tr',{},[stamp(e.time),actionNames[e.event]||e.event,detail].map(function(x){return E('td',{},x);}));}))
   ])));
   if(h.archive_error)nodes.push(E('p',{'class':'alert-message warning'},h.archive_error));
   if(h.dropped_records)nodes.push(E('p',{'class':'alert-message warning'},h.dropped_records+' records were dropped because the recent RAM buffer filled before a successful offload.'));
   nodes=warnings.concat(nodes);
   display.replaceChildren.apply(display,nodes);
   var attempts=0;
   function draw(){
    if(!display.isConnected){if(++attempts<60)frame=requestAnimationFrame(draw);return;}
    frame=null;
    instances=[graphs.channelChart(channelCanvas,periods,radioNames,start,now,surveys,h.radar,h.declared_bands),graphs.clientChart(clientCanvas,clients,radioNames,start,now),graphs.trafficChart(trafficCanvas,samples,radioNames,start,now)];
   }
   frame=requestAnimationFrame(draw);
  }
  selector.addEventListener('change',function(){hours=Number(selector.value);redraw(history);});
  poll.add(function(){return readHistory().then(function(h){history=h;redraw(h);});},60);
  redraw(history);
  return Promise.resolve(E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),E('h2',{},_('Wi-Fi Coordinator: history')),E('p',{},[_('Show: '),selector]),display
  ]));
 },
 handleSave:null,
 handleSaveApply:null,
 handleReset:null
});
