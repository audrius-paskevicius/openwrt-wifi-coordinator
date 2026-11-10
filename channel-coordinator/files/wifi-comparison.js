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
     E('h4',{},a.radio+(a.hold?' — at comparison: '+a.hold:'')),
     E('p',{},_('Channel pool at comparison: ')+(a.channels||[]).join(' ')),
     E('p',{},_('Widths at comparison: ')+(a.widths||[]).join(' / ')+' MHz'),
     a.width_limit?E('p',{},'Width constraint at comparison: '+a.width_limit.reason+'; widths above '+a.width_limit.actual+' MHz temporarily deferred.'):'',
     ...((a.rejected||[]).length?[E('p',{},'Excluded at comparison: '+a.rejected.map(function(x){return (x.target.freq<3000?(x.target.freq-2407)/5:(x.target.freq-5000)/5)+' / '+x.target.width+' MHz — '+(x.reason||'Connectivity check failed');}).join('; ')+'.')]:[]),
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
