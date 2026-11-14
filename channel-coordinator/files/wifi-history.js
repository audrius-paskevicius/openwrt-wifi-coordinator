'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';
'require uci';
'require wifi-coordinator.history as historyapi';
'require poll';
'require wifi-coordinator.graphs as graphs';
'require wifi-coordinator.time as timefmt';
'require wifi-coordinator.help as help';
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
 if(estimate)detail+=' Survey observed: '+stamp(estimate.oldest)+(estimate.oldest!=estimate.newest?' \u2013 '+stamp(estimate.newest):'')+'. Coverage: '+estimate.coverage.toFixed(0)+'%.';
 return E('div',{'title':detail},lines);
}
var retentionChoices=[1,3,6,12,24,48,72,96,120];
var actionNames={
 'planning-complete':'Planning calculation completed','planning-discarded':'Planning calculation discarded','planning-failed':'Planning calculation failed','slow-stage':'Slow controller stage','observation-gap':'Missed observations','radio-unavailable':'Confirmed radio unavailability','placement-observed':'Channel placement changed','client-departure':'Station departed',
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
 'steering-disconnect':'Bounded preference disconnect','steering-complete':'Preference attempt completed',
 'method-unavailable':'Unsupported switching method learned'
};
function graphWidth(element){return Math.max(160,Math.min(2048,Math.ceil((((element&&element.clientWidth)||document.documentElement.clientWidth)-100)/32)*32));}
function emptyHistory(error,hours){var end=Math.floor(Date.now()/1000);return {start:end-hours*3600,end:end,periods:[],samples:[],clients:[],surveys:[],events:[],read_errors:[error.message||String(error)]};}
return view.extend({
 load:async function(){await uci.load('channel_coordinator');var hours=Math.min(6,Number(uci.get('channel_coordinator','main','history_hours'))||24);return [null,await historyapi.read({hours:hours,width:graphWidth(document.getElementById('view'))}).catch(e=>emptyHistory(e,hours))];},
 render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));},
 renderPage:function(data){
  var instances=[],frame=null,generation=0,resizeTimer=null,preparationTimer=null,requestedWidth=0,lastRendered=null,activeRequest=null,queuedRefresh=false;
  var history=data[1],retain=Math.max(1,Math.min(120,Number(uci.get('channel_coordinator','main','history_hours'))||24)),hours=Math.min(6,retain),display=E('div'),selector=E('select',{'class':'cbi-input-select'});
  function setRetention(value){retain=Math.max(1,Math.min(120,Number(value)||24));hours=Math.min(hours,retain);
   var choices=retentionChoices.filter(function(h){return h<=retain;});if(choices.indexOf(retain)<0)choices.push(retain);
   selector.replaceChildren.apply(selector,choices.map(function(h){return E('option',{value:h},'Last '+h+' hour'+(h==1?'':'s'));}));
   if(choices.indexOf(hours)<0)hours=choices[choices.length-1];selector.value=String(hours);
  }
  setRetention(retain);
  var channelCanvas=E('canvas',{'role':'img','aria-label':'Channel and width of each radio over time'}),clientCanvas=E('canvas',{'role':'img','aria-label':'Clients on each radio over time'}),trafficCanvas=E('canvas',{'role':'img','aria-label':'Observed radio traffic over time'});
  function redraw(h){
   if(frame!=null)cancelAnimationFrame(frame);
   frame=null;
   var now=h.end||Math.floor(Date.now()/1000),cutoff=h.start||now-hours*3600,popups=!h.display||h.display.popups!==false;
   h.radar=Object.assign({},h.radar,{events:radarHistory(h.events,h.periods,h.radar&&h.radar.events)});lastRendered=h;
   var periods=(h.periods||[]).filter(function(p){return p.end>=cutoff;});
   var clients=(h.clients||[]).filter(function(s){return s.end>=cutoff;});
   var samples=(h.samples||[]).filter(function(s){return s.end>=cutoff;});
   var surveys=(h.surveys||[]).slice().sort(function(a,b){return a.time-b.time;});
   var radioNames=h.radio_names||Array.from(new Set(periods.map(function(p){return p.radio;}).concat(samples.map(function(s){return s.radio;}),clients.map(function(s){return s.radio;})))).sort();
   var warnings=(h.read_errors||[]).map(function(e){return E('p',{'class':'alert-message warning'},'History is incomplete. '+e);});
   if(h.preparing)warnings.unshift(E('p',{'class':'wc-caption','aria-live':'polite'},'Preparing older history: '+h.preparing+' sections remaining. Unloaded areas are temporarily blank.'));
   if(h.refresh_warning)warnings.unshift(E('p',{'class':'alert-message warning'},h.refresh_warning));
   if(!radioNames.length){
    instances.forEach(c=>c.destroy());instances=[];
    var recording=h.enabled==null?uci.get('channel_coordinator','main','history_enabled')!='0':h.enabled;
    var message=warnings.length?'No history available to display.':recording?'No observations in the selected period. History recording is enabled.':'No observations in the selected period. History recording is disabled.';
    display.replaceChildren.apply(display,warnings.concat([E('p',{'class':'wc-status'},_(message))]));clearTimeout(preparationTimer);if(h.preparing)preparationTimer=setTimeout(()=>refresh(),150);return;
   }
   var start=h.start||Math.min(now-1,Math.max(cutoff,Math.min.apply(null,periods.map(function(p){return p.start;}).concat(clients.map(function(s){return s.start;}),samples.map(function(s){return s.time;}),surveys.map(function(s){return s.time;})))));


   function heading(title,detail){if(!popups)return E('h3',{},title);return E('h3',{},E('span',{'class':'wc-setting-help','role':'button','tabindex':'0','data-tooltip':detail,'data-tooltip-style':'wc-help-tooltip','aria-label':title+'. '+detail},title));}

   function legend(patterns,fins){return E('p',{'class':'wc-legend'},radioNames.map(function(r,i){return E('span',{'style':'color:'+graphs.colour(r,i)+';margin-right:22px;font-weight:600;'},[E('span',{'class':fins?'wc-fin-key':patterns?'wc-pattern-key':'wc-line-key','style':fins?graphs.clientFinStyle(r,i):patterns?graphs.patternStyle(r,i):'border-color:'+graphs.colour(r,i),'title':popups?(patterns?graphs.patternName(r,i):r):null}),r]);}));}
   var radarHalf=Number(h.radar&&h.radar.half_life)||3600;
   function elapsedLabel(seconds){return seconds>=3600?+(seconds/3600).toFixed(1)+' h':+(seconds/60).toFixed(1)+' min';}
   var radarKey=E('div',{'class':'wc-radar-key','title':popups?'Amber shows remembered radar activity, fading by half every '+elapsedLabel(radarHalf)+'. The scale shows avoidance strength, not the probability of radar. Radar clearance is still required.':null},[
    E('span',{},_('Radar memory')),
    E('div',{'class':'wc-radar-ramp'},[
     E('div',{'class':'wc-amber-scale','aria-hidden':'true','style':'background:'+graphs.radarGradient()}),
     E('div',{'class':'wc-radar-ticks'},[100,75,50,25,0].map(function(n){return E('span',{},n+'%');}))
    ])
   ]);
   var nodes=[E('p',{'class':'wc-caption'},h.display&&h.display.decimation?'Graph detail adapted to screen width; peaks, changes and unknown gaps are preserved.':'Showing available stored graph detail.'),heading(_('Where each radio spent its time'),_('Ribbons show channel and width; dashed outlines show radar listening. // marks breaks in the spectrum axis. Squares mark missing observations, crosses mark unavailability, and triangles mark actions. Hover or tap for details.')),
    E('div',{'class':'wc-chart wc-spectrum-chart'},channelCanvas),legend(true),
    E('div',{'class':'wc-spectrum-keys'},[E('div',{'class':'wc-survey-key','title':popups?'Estimated congestion ranges from 0 (lowest) to 100 (highest estimated congestion). Darker grey means more or stronger overlapping networks, adjusted for advertised load. This is an estimate, not measured airtime or a percentage. Hover over the graph for measurement times.':null},[E('span',{},_('Estimated congestion')),E('div',{'class':'wc-survey-ramp'},[E('div',{'class':'wc-grey-scale','aria-hidden':'true'}),E('div',{'class':'wc-scale-ticks'},[0,25,50,75,100].map(function(n){return E('span',{},String(n));}))])]),radarKey]),
    heading(_('Clients on each radio over time'),_('Number of connected clients on each radio. Gaps mean observations are missing. Hover or tap for counts and events.')),
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
   nodes.push(heading(_('Recent actions'),_('Newest first, within the selected time window. Stored actions are paged without aggregation.')));
   function actionsTable(events){
    return E('div',{'class':'wc-table-wrap wc-log-wrap'},E('table',{'class':'table wc-table'},[
    E('thead',{},E('tr',{},['Time','Action','Details'].map(function(x){return E('th',{'scope':'col'},_(x));}))),
    E('tbody',{},events.map(function(e){var detail=e.reason||[
     e.operation?'operation '+e.operation:'',e.returned!=null?e.returned+' returned / '+e.elsewhere+' elsewhere / '+e.absent+' absent':'',e.declined?e.declined+' declined':'',e.response!=null?'response '+e.response:'',e.forced_disconnects!=null?e.forced_disconnects+' forced disconnects':'',e.radio,e.kind?'assessment: '+e.kind:'',e.affected!=null?e.affected+' affected clients':'',e.retry_seconds?Math.round(e.retry_seconds/60)+'-minute deferral':'',e.preflight?'before channel change':'',e.stage!=null?['gentle','strong','decisive'][e.stage]:'',e.helper?'helper '+e.helper:'',e.from!=null?'from '+e.from:'',e.to!=null?'to '+e.to:'',e.channel!=null?'channel '+e.channel:'',e.width?e.width+' MHz':'',e.clients!=null?e.clients+' clients':'',e.elapsed!=null?timefmt.seconds(e.elapsed)+' seconds':'',e.ban_seconds?e.ban_seconds+'-second return restriction':'',e.disconnect_events!=null?e.disconnect_events+' disconnect events':'',e.neighbors!=null?e.neighbors+' networks observed':'',e.missing_count!=null?e.missing_count+' clients missing':'',e.scanned_frequencies!=null?e.scanned_frequencies+' frequencies measured':'',e.missing_frequencies!=null?e.missing_frequencies+' deferred':''
    ].filter(Boolean).join('; ');
    var metrics=[e.scan_quality?(e.scan_quality||[]).map(q=>q.radio+': '+q.visits+' scan visits, '+Number(q.scan_seconds||0).toFixed(1)+' s scanning, '+q.retries+' retries').join('; '):'',e.frequencies?'frequencies '+e.frequencies.join(', ')+' MHz':'',e.attempt!=null?'retry '+e.attempt+' of 2':'',e.start!=null&&e.end!=null?'observed interval '+stamp(e.start)+' \u2013 '+stamp(e.end):'',e.candidates_seconds!=null?'candidate calculation '+Number(e.candidates_seconds).toFixed(2)+' s':'',e.search_seconds!=null?'layout search '+Number(e.search_seconds).toFixed(2)+' s':'',e.missed_samples!=null?e.missed_samples+' missed samples':'',e.estimated_gain!=null?'net benefit '+Number(e.estimated_gain).toFixed(1)+' points':'',e.movement_cost!=null?'move cost '+Number(e.movement_cost).toFixed(1):'',e.required_gain!=null?'required '+Number(e.required_gain).toFixed(1):'',e.affected_clients!=null?e.affected_clients+' clients on affected radios':'',e.client_moves!=null?e.client_moves+' estimated client moves':'',e.scan_age!=null?'survey age '+timefmt.seconds(e.scan_age)+' seconds':'',e.observed_clients!=null?e.observed_clients+' tracked clients':'',e.departed_clients!=null?e.departed_clients+' clients observed leaving':'',e.operation_seconds!=null?'operation '+timefmt.seconds(e.operation_seconds)+' seconds':'',e.reason&&e.disconnect_events!=null?e.disconnect_events+' disconnect events':''].filter(Boolean);
    detail=[detail].concat(metrics).filter(Boolean).join('; ');return E('tr',{},[stamp(e.time),actionNames[e.event]||e.event,detail].map(function(x){return E('td',{},x);}));}))
   ]));
   }
   var actionHost=E('div'),pageOffset=0,total=h.action_total==null?(h.actions||h.events||[]).length:h.action_total;
   var previous=E('button',{type:'button','class':'cbi-button'},_('Newer actions'));
   var next=E('button',{type:'button','class':'cbi-button'},_('Older actions'));
   var pageStatus=E('span',{'class':'wc-caption'});
   function showActions(rows,count){total=count;actionHost.replaceChildren(actionsTable(rows));previous.disabled=pageOffset===0;next.disabled=pageOffset+rows.length>=total;pageStatus.textContent=total?' '+(pageOffset+1)+'\u2013'+(pageOffset+rows.length)+' of '+total+' actions ':' No actions ';}
   async function actionPage(offset){
    previous.disabled=true;next.disabled=true;
    try{var page=await historyapi.read({hours:hours,width:requestedWidth||graphWidth(display),kind:'actions',offset:offset,end:now});if(lastRendered!==h)return;
     if(page.refresh_warning||(page.read_errors||[]).length)throw Error(page.refresh_warning||(page.read_errors||[]).join('; '));
     pageOffset=offset;showActions(page.actions,page.action_total);
    }catch(e){pageStatus.textContent=' Cannot load actions: '+e.message;previous.disabled=pageOffset===0;next.disabled=pageOffset+100>=total;}
   }
   previous.addEventListener('click',()=>actionPage(Math.max(0,pageOffset-100)));next.addEventListener('click',()=>actionPage(pageOffset+100));
   showActions(h.actions||(h.events||[]).filter(e=>(e.end==null?e.time:e.end)>=cutoff).slice().reverse().slice(0,100),total);
   nodes.push(actionHost,E('p',{},[previous,pageStatus,next]));
   if(h.archive_error)nodes.push(E('p',{'class':'alert-message warning'},h.archive_error));
   if(h.dropped_records)nodes.push(E('p',{'class':'alert-message warning'},h.dropped_records+' records were dropped because the recent RAM buffer filled before a successful offload.'));
   nodes=warnings.concat(nodes);
   display.replaceChildren.apply(display,nodes);
   var attempts=0;
   function draw(){
    if(!display.isConnected){if(++attempts<60)frame=requestAnimationFrame(draw);return;}
    frame=null;
    instances=[graphs.channelChart(channelCanvas,periods,radioNames,start,now,surveys,h.radar,h.declared_bands,h.events,h,instances[0]),graphs.clientChart(clientCanvas,clients,radioNames,start,now,h.events,h,instances[1]),graphs.trafficChart(trafficCanvas,samples,radioNames,start,now,h,instances[2])];
   }
   frame=requestAnimationFrame(draw);
   clearTimeout(preparationTimer);if(h.preparing)preparationTimer=setTimeout(()=>refresh(),150);
  }
  function refresh(urgent){
   clearTimeout(preparationTimer);
   if(activeRequest){if(urgent){queuedRefresh=true;generation++;historyapi.cancel();}return activeRequest;}
   var id=++generation,chosen=hours,width=graphWidth(display);requestedWidth=width;
   activeRequest=historyapi.read({hours:chosen,width:width}).then(function(h){if(id!==generation)return;history=h;redraw(h);})
    .catch(function(e){if(id===generation)redraw(lastRendered?Object.assign({},lastRendered,{refresh_warning:"Refresh failed; displaying the previous view. "+e.message}):emptyHistory(e,chosen));})
    .finally(function(){activeRequest=null;if(queuedRefresh&&display.isConnected){queuedRefresh=false;refresh();}});
   return activeRequest;
  }
  selector.addEventListener('change',function(){hours=Number(selector.value);refresh(true);});
  poll.add(function(){if(display.isConnected)return refresh();},60);
  var observer=typeof ResizeObserver!='undefined'?new ResizeObserver(function(){if(!display.isConnected)return;var width=graphWidth(display);if(width===requestedWidth)return;if(history.display&&history.display.decimation===false){requestedWidth=width;return;}clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>refresh(true),200);}):null;
  if(observer)observer.observe(display);
  window.addEventListener('pagehide',function(){generation++;historyapi.cancel();clearTimeout(resizeTimer);clearTimeout(preparationTimer);if(observer)observer.disconnect();instances.forEach(c=>c.destroy());},{once:true});
  requestedWidth=history.pixel_width||0;redraw(history);
  return Promise.resolve(E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),
   E('div',{'class':'wc-history-header'},[
    E('h2',{},_('Wi-Fi Coordinator: history')),
    E('label',{'class':'wc-history-period'},[E('span',{},_('Show:')),selector])
   ]),display
  ]));
 },
 handleSave:null,
 handleSaveApply:null,
 handleReset:null
});
