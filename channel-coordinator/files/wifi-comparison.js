'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';
'require uci';
'require fs';
'require poll';
'require wifi-coordinator.time as timefmt';

function readState(){return fs.read_direct('/tmp/channel-coordinator-state.json','text').then(function(raw){var s=JSON.parse(raw);if(!s||typeof s!='object'||Array.isArray(s))throw Error('Invalid coordinator state');return s;});}
function operationText(st) {
 return st.restart_check?(st.status||'Checking radios after interruption'):
  st.halted?'Coordination paused: '+st.halted+(st.recovery_retry_at>st.updated?' — automatic retry in '+Math.ceil(st.recovery_retry_at-st.updated)+' seconds.':' — automatic reassessment pending.'):(st.status||'No evaluation yet.');
}
function comparisonTime(p,st) {
 if(!p.evaluated_at)return _('Last completed comparison.');
 var age=Math.max(0,Date.now()/1000-p.evaluated_at);
 return _('Last comparison: ')+timefmt.stamp(p.evaluated_at)+
  (Number.isFinite(age)?' ('+(age<60?Math.floor(age)+' seconds':Math.floor(age/60)+' minutes')+' ago).':'.');
}
function rejectionDescription(reason){
 var messages={
  'Radio serves other clients; affected clients lack verified alternate service':['Client service not verified','The controller had not confirmed that affected clients could continue working through another radio.'],
  'Known client-placement conflict; alternate service did not verify':['Client service not verified','Some clients had trouble on this placement, and a working connection through another radio had not been confirmed.'],
  'Known client-placement conflict; no permitted compatible fallback':['No suitable alternative connection','Some clients had trouble on this placement, and no permitted alternative radio could serve them.'],
  'Client service recovered on previous placement; six-hour compatibility cooldown':['Clients recovered on the previous channel','Client service returned after restoring the previous placement. This placement was paused before another attempt.'],
  'Radio did not establish the requested placement':['Channel change did not succeed','The radio did not establish service on the requested channel and width. Another attempt was temporarily deferred.'],
  'Driver left the original channel/width unchanged':['Channel change was not applied','The driver kept the previous channel and width. Another attempt was temporarily deferred.'],
  'Client check inconclusive; short retry deferral pending recovery evidence':['Client check inconclusive','The check could not establish whether client service was working. A short pause allows time for further recovery checks.']
 },width=/^(\d+) MHz retained during (\d+) MHz setup: coexistence or driver constraint$/.exec(reason||'');
 if(width)return {title:'Requested width not applied',text:'The radio stayed at '+width[1]+' MHz when '+width[2]+' MHz was requested.',actual:Number(width[1]),requested:Number(width[2])};
 var m=messages[reason];return m?{title:m[0],text:m[1]}:{title:'Previous attempt did not pass verification',text:reason||'The connection check did not confirm working service.'};
}
function restrictionTime(until,p){
 if(!Number.isFinite(until)||!Number.isFinite(p.evaluated_at)||!Number.isFinite(p.evaluated_uptime))return null;
 var t=p.evaluated_at+until-p.evaluated_uptime;
 return timefmt.sameDay(t,p.evaluated_at)?timefmt.clock(t,true):timefmt.stamp(t);
}
function channelList(channels){
 var values=Array.from(new Set(channels)).sort((a,b)=>a-b).map(String);
 return values.length<2?values[0]:values.slice(0,-1).join(', ')+' and '+values[values.length-1];
}
function comparisonNotes(a,p){
 var notes=[],groups=new Map(),limit=a.width_limit;
 if(limit){
  notes.push({title:'Channel width limited to '+limit.actual+' MHz',
   text:'The radio stayed at '+limit.actual+' MHz when '+limit.requested+' MHz was requested. Wider widths were temporarily paused before another attempt.',
   expiry:restrictionTime(limit.until,p)});
 }
 (a.rejected||[]).forEach(function(x){
  if(!x.target)return;
  var d=rejectionDescription(x.reason);
  // A radio-wide width pause already explains these narrower per-channel holds.
  if(limit&&d.actual===limit.actual&&d.requested===limit.requested&&x.until<=limit.until)return;
  var key=JSON.stringify([x.target.width,d.title,d.text]),g=groups.get(key),f=x.target.freq,ch=f===2484?14:f<3000?(f-2407)/5:(f-5000)/5;
  if(!g){g={width:x.target.width,description:d,channels:[],ends:new Map()};groups.set(key,g);}
  g.channels.push(ch);
  var end=restrictionTime(x.until,p);
  if(!g.ends.has(end))g.ends.set(end,[]);g.ends.get(end).push(ch);
 });
 groups.forEach(function(g){
  var channels=channelList(g.channels),plural=new Set(g.channels).size>1;
  var expiry=g.ends.size===1?Array.from(g.ends.keys())[0]:Array.from(g.ends).map(([end,chs])=>(chs.length>1?'Channels ':'Channel ')+channelList(chs)+': '+(end||'time not recorded')).join('; ');
  notes.push({title:(plural?'Channels ':'Channel ')+channels+' ('+g.width+' MHz) deferred — '+g.description.title.toLowerCase(),text:g.description.text,expiry});
 });
 return notes;
}
return view.extend({
 load:function(){return Promise.all([uci.load('channel_coordinator'),readState().then(function(state){return {state:state};},function(e){return {error:e.message||String(e)};})]);},
 render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));},
 renderPage:function(data){
  var content=E('div'),status=E('p',{'class':'wc-status'}),warning=E('p',{'class':'alert-message warning','hidden':true}),last=null,previous=null;
  function refresh(st){
   if(st.proposal&&Array.isArray(st.proposal.alternatives))last=st.proposal;
   var p=last;
   status.textContent=(p?comparisonTime(p,st)+' ':'')+'Now: '+operationText(st)+(p&&p.placements_changed?' Radio placements have changed; these results describe the previous comparison.':'')+(p&&Date.now()/1000-p.evaluated_at>Number(uci.get('channel_coordinator','main','max_age')||900)?' This comparison is older than the configured survey freshness limit.':'');
   status.setAttribute('data-level',st.halted&&!st.restart_check?'warning':'normal');
   if(!p){content.replaceChildren(E('p',{},_('No completed comparison yet. Results will appear here after evaluation.')));return;}
   // Keep the table DOM, selection and scroll position while only live status changes.
   var key=JSON.stringify(p);if(key===previous)return;previous=key;
   var nodes=[];
   nodes.push(E('div',{'class':'wc-summary'},[
    E('h4',{},_('Last completed comparison')),E('p',{},p.neighbors+' nearby networks.'),
    E('p',{},'Estimated benefit after movement cost: '+Number(p.improvement||0).toFixed(1)+' points. Spectrum separation takes priority when enabled; this is a capacity estimate, not a speed measurement.'),
    p.movement_cost!=null?E('p',{},'Movement cost: '+Number(p.movement_cost).toFixed(1)+' points; '+p.affected_clients+' currently associated clients on affected radios; '+p.client_moves+' estimated client moves including helpers and staging.'):'',
    (p.changes||[]).length?E('ul',{},p.changes.map(function(c){return E('li',{},'Compared target '+c.radio+': channel '+c.from+' to '+c.to+' ('+c.width+' MHz)');})):E('p',{},_('Placement at comparison retained.')),
    p.placements_changed?E('p',{},_('Radio placements have changed since this comparison.')):'',
    p.separate?E('p',{},_('Separate spectrum takes priority. Each intermediate move must also avoid increasing overlap.')):'',
    p.decision?E('p',{},p.decision.reason+(p.decision.margin!=null?' (required benefit '+Number(p.decision.margin).toFixed(1)+' points; '+Object.keys(p.decision.comparisons||{}).map(function(name){return name+': '+p.decision.comparisons[name]+' supporting surveys';}).join(', ')+')':'')):'',
    p.steps?E('ol',{},p.steps.map(function(c){return E('li',{},c.radio+' to '+c.to+' / '+c.width+' MHz'+(c.staging?' (staging step)':''));})):'',   ]));
   nodes.push(
    E('p',{},_('The planner jointly maximizes estimated service after applying your spectrum-separation policy. Higher service is better: usable bandwidth is weighted by advertised radio spatial streams. The primary channel matters to narrow clients and to fallback transmissions. Wide channels earn their extra capacity only where the secondary spectrum is usable. This is hardware headroom for present and future clients, not predicted Mbps or a score fitted to currently connected devices.')),
    E('p',{},_('Grey history shows average neighbour pressure. Planning also accounts for the primary channel, bonded subchannels, fresh external busy counters and radar memory. A neighbour spanning a wide channel is counted once per bonded block. Our own traffic is excluded from busy-airtime evidence. Unknown airtime raises uncertainty; a white background does not prove zero interference.')),
    E('p',{},_('A move must repay its disruption cost and meet the evidence margin. Cost grows with the number of affected clients, includes helpers and staging, and rises when recent channel announcements were accompanied by client departures. Small primary-channel changes face an additional cost. These are score points, not outage seconds. Temporary residence and retry holds keep alternatives visible but prevent their execution. Repeated scans alone do not erase uncertainty. Each step is checked again before execution. Only improved spectrum separation can bypass the service margin. Sharing below refers to peers at comparison time; a joint plan can move those peers too.')),
    E('div',{},p.alternatives.map(function(a){return E('div',{},[
     E('h4',{},a.radio),
     E('p',{'class':'wc-comparison-context'},_('At the last comparison')),
     a.hold?E('p',{},_('Channel changes paused: ')+a.hold):'',
     E('p',{},_('Channel pool: ')+(a.channels||[]).join(' ')),
     E('p',{},_('Widths: ')+(a.widths||[]).join(' / ')+' MHz'),
     E('div',{'class':'wc-comparison-notes'},comparisonNotes(a,p).map(function(note){return E('div',{'class':'wc-comparison-note'},[
      E('strong',{},note.title),E('p',{},note.text),note.expiry?E('p',{'class':'wc-restriction-end'},'Retry restriction end: '+note.expiry):''
     ]);})),
     E('div',{'class':'wc-table-wrap'},E('table',{'class':'table wc-table'},[
      E('thead',{},E('tr',{},['Channel / width','Service index','Congestion: primary / block','Estimated usable width','Sharing','Radar memory','Evidence uncertainty','Move cost'].map(function(x){return E('th',{},x);}))),
      E('tbody',{},a.candidates.slice().sort(function(x,y){return (p.separate?x.shared-y.shared:0)||x.cost-y.cost;}).map(function(c){return E('tr',{},[
       c.channel+' / '+c.width+' MHz'+(c.current?' (used then)':''),c.service!=null?Number(c.service).toFixed(1):'--',Number(c.primary_occupancy!=null?c.primary_occupancy:c.occupancy).toFixed(0)+' / '+Number(c.occupancy).toFixed(0),Number(c.capacity).toFixed(1)+' MHz',Number(c.shared*100).toFixed(0)+'%',Math.round((c.radar_risk||0)*100)+'%',Number(c.uncertainty||0).toFixed(1),c.movement?Number(c.movement.cost).toFixed(1):'--'
      ].map(function(x){return E('td',{},x);}));}))
     ]))
    ]);}))
   );
   content.replaceChildren.apply(content,nodes);
  }
  function failed(e){warning.hidden=false;warning.textContent='Could not refresh the comparison. '+(last?'Showing the last completed results. ':'')+(e.message||String(e));}
  if(data[1].state)refresh(data[1].state);else {refresh({});failed(Error(data[1].error));}
  poll.add(function(){return readState().then(function(st){warning.hidden=true;refresh(st);},failed);},5);
  return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),
   E('h2',{},_('Wi-Fi Coordinator: comparison')),status,warning,content
  ]);
 },handleSave:null,handleSaveApply:null,handleReset:null
});
