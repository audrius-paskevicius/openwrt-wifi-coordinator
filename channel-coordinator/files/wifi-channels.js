'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require fs';
'require poll';

var service = rpc.declare({object:'service',method:'list',params:['name'],expect:{'':{}}});
var all5 = '36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161';
function radioName(r) { return r['.name']+' ('+(r.band=='2g'?'2.4':'5')+' GHz)'; }
function readState() { return fs.read('/tmp/channel-coordinator-state.json').then(JSON.parse).catch(function(){return {};}); }
function statusText(st, services) {
 var running=Object.values(((services||{})['channel-coordinator']||{}).instances||{}).some(function(i){return i.running;});
 return (running?'Running. ':'Stopped. ')+(st.halted?'Safety stop: '+st.halted:(st.status||'No evaluation yet.'));
}
return view.extend({
 load:function(){return Promise.all([uci.load('channel_coordinator'),uci.load('wireless'),readState(),service('channel-coordinator')]);},
 render:function(data){
  var state=data[2], radios=uci.sections('wireless','wifi-device');
  var status=E('p',{'class':'wc-status','data-level':state.halted?'warning':'normal'},statusText(state,data[3]));
  var details=E('div');
  var comparisonContent=E('div');
  var comparison=E('details',{},[
   E('summary',{},_('Why these channels? Compare all eligible placements')),comparisonContent
  ]);
  function refresh(st){
   var header=E('thead',{},E('tr',{},['Radio','Channel / width','Clients','Traffic','Minimum residence','Radar check'].map(function(x){return E('th',{'scope':'col'},_(x));}))),rows=[];
   Object.keys(st.radios||{}).forEach(function(name){var r=st.radios[name];rows.push(E('tr',{},[
    name,(r.channel||'?')+' / '+(r.width||'?')+' MHz',String(r.clients||0),Number(r.mbps||0).toFixed(3)+' Mbps',
    (r.cooldown_left||0)+' s',r.dfs?(r.dfs_ready?'Cleared DFS channel':'DFS clearance required'):'Not a DFS channel'
   ].map(function(v){return E('td',{},v);})));});
   var p=st.proposal, dfs=st.dfs;
   var items=[E('div',{'class':'wc-table-wrap'},E('table',{'class':'table wc-table'},[header,E('tbody',{},rows)]))],cards=[];
   if(st.scan_coverage)cards.push(E('div',{'class':'wc-summary'},[
    E('h4',{},_('Last survey coverage')),E('p',{},st.scan_coverage.completed+' of '+st.scan_coverage.requested+' frequencies measured ('+st.scan_coverage.policy+').'),
    E('p',{},'Completed at '+new Date(st.scan_coverage.at*1000).toLocaleTimeString()+'. Only radios with complete fresh coverage may move; missing coverage on another band does not block them.')
   ]));
   if(p)cards.push(E('div',{'class':'wc-summary'},[
    E('h4',{},_('Latest survey')),E('p',{},p.neighbors+' nearby networks.'),
    E('p',{},'Capacity-score improvement: '+Number(p.improvement||0).toFixed(1)+' points. Spectrum separation and the wider-channel preference take priority; this is not a speed prediction.'),
    (p.changes||[]).length?E('ul',{},p.changes.map(function(c){return E('li',{},'Target '+c.radio+': channel '+c.from+' to '+c.to+' ('+c.width+' MHz)');})):E('p',{},_('Current channel placement retained.')),
    p.separate?E('p',{},_('Separate spectrum takes priority. Each intermediate move must also avoid increasing overlap.')):null,
    p.decision?E('p',{},p.decision.reason+(p.decision.margin!=null?' (required benefit '+Number(p.decision.margin).toFixed(1)+' points; '+Object.keys(p.decision.comparisons||{}).map(function(name){return name+': '+p.decision.comparisons[name]+' supporting surveys';}).join(', ')+')':'')):null,
    p.steps?E('ol',{},p.steps.map(function(c){return E('li',{},c.radio+' to '+c.to+' / '+c.width+' MHz'+(c.staging?' (staging step)':''));})):null,   ]));
   if(dfs){var phase={listening:'Listening for radar',restoring:'Restoring the spare radio',ready:'Completed and shared',recovered:'Restored after an interrupted check',inactive:'Previous check ended','restored-after-error':'Restored after an error'};cards.push(E('div',{'class':'wc-summary'},[
    E('h4',{},_('Last radar preparation')),E('p',{},phase[dfs.phase]||dfs.phase),
    E('p',{},'Channel '+dfs.channel+' / '+dfs.width+' MHz'+(dfs.helper?' using '+dfs.helper:'')),
    dfs.elapsed!=null?E('p',{},'Preparation elapsed: '+dfs.elapsed+' seconds (includes radio setup).'):null
   ]));}
   if(cards.length)items.push(E('div',{'class':'wc-summaries'},cards));
   if(p&&p.alternatives)comparisonContent.replaceChildren.apply(comparisonContent,[
    E('p',{},_('The planner compares spectrum separation first, preferred width second, then cost. Estimated usable width combines channel width and congestion evidence; it is not Mbps. Grey history and planning share the same neighbour-pressure calculation. Fresh external busy counters can add evidence. Counters on channels carrying our clients are excluded because they include our own traffic. Missing airtime counters raise baseline uncertainty rather than inventing congestion. Variation between surveys and changes of scanner can raise uncertainty further, up to 15 points. A zero neighbour estimate does not prove zero interference.')),
    E('p',{},_('Every eligible alternative keeps its own count of consecutive completed surveys in which it beats the current channel cost, even when another alternative ranks first. Repeated support reduces the uncertainty margin. A changed current channel, contrary evidence, missing candidate or stale comparison resets that support. The latest survey selects the destination. Cost-only improvements must meet the evidence margin; improved separation or usable width can act without that cost margin.')),
    E('p',{},_('Sharing shows overlap with the other radios where they are now. The final plan can differ, but an immediate move cannot increase sharing when separation is enabled. The table sorts by current sharing, then cost; the joint plan also prioritizes usable width. Legal transmit power breaks otherwise equal choices. Unmeasured or prohibited channels are not candidates.')),
    E('div',{},p.alternatives.map(function(a){return E('div',{},[
     E('h4',{},a.radio+(a.hold?' — '+a.hold:'')),
     ...((a.rejected||[]).length?[E('p',{},'Temporarily excluded after failed connectivity checks: '+a.rejected.map(function(x){return ((x.target.freq-5000)/5>0?(x.target.freq-5000)/5:(x.target.freq-2407)/5)+' / '+x.target.width+' MHz';}).join(', ')+'. Each exclusion lasts six hours.')]:[]),
     E('div',{'class':'wc-table-wrap'},E('table',{'class':'table wc-table'},[
      E('thead',{},E('tr',{},['Channel / width','Cost','Estimated congestion','Estimated usable width','Sharing','Radar memory','Evidence uncertainty'].map(function(x){return E('th',{},x);}))),
      E('tbody',{},a.candidates.slice().sort(function(x,y){return (p.separate?x.shared-y.shared:0)||x.cost-y.cost;}).map(function(c){return E('tr',{},[
       c.channel+' / '+c.width+' MHz'+(c.current?' (current)':''),Number(c.cost).toFixed(1),Number(c.occupancy).toFixed(0)+' / 100',Number(c.capacity).toFixed(1)+' MHz',Number(c.shared*100).toFixed(0)+'%',Math.round((c.radar_risk||0)*100)+'%',Number(c.uncertainty||0).toFixed(1)
      ].map(function(x){return E('td',{},x);}));}))
     ]))
    ]);}))
   ]);
   else comparisonContent.replaceChildren(E('p',{},_('Waiting for the next channel comparison.')));
   items.push(comparison);
   if(st.updated)items.push(E('small',{'class':'wc-caption'},'Updates every 5 seconds. Traffic is measured between samples; it is not a speed-test result.'));
   details.replaceChildren.apply(details,items);
  }
  refresh(state);
  poll.add(function(){return Promise.all([readState(),service('channel-coordinator')]).then(function(x){status.textContent=statusText(x[0],x[1]);status.setAttribute('data-level',x[0].halted?'warning':'normal');refresh(x[0]);});},5);
  var intro=E('div',{},[
   E('h2',{},_('Wi-Fi Coordinator: channels')),
   E('p',{},_('Channel planning chooses where your radios transmit. Client steering chooses which radio each device uses. Both are managed by this package so they can take turns.')),
   E('ol',{},[
    E('li',{},_('Survey nearby networks and compare legal channel blocks. A lower congestion score is a useful estimate, not a promised speed.')),
    E('li',{},_('For a DFS channel, let an empty spare radio complete the radar check while the serving radio stays on its current channel.')),
    E('li',{},_('Use live CSA where supported. If a radio needs a restart, try a compatible handoff first, then allow brief reconnection if enabled.')),
    E('li',{},_('Verify the change, then let client steering recommend the preferred radio again. Clients make the final roaming decision.'))
   ]),status,details
  ]);
  var m=new form.Map('channel_coordinator',_('Channel settings'),_('Save & Apply restarts this coordinator. Fresh installations use an automatic preset inferred from the configured radios; existing settings are preserved. A radio can serve clients or listen on a different channel, but cannot do both simultaneously.'));
  var s=m.section(form.NamedSection,'main','coordinator');s.anonymous=true;
  s.tab('general',_('When to act'));s.tab('clients',_('Protect playback'));s.tab('dfs',_('Radar preparation'));s.tab('scan',_('Survey'));s.tab('score',_('Planning details'));
  function val(tab,name,title,def,type,desc){var o=s.taboption(tab,form.Value,name,_(title),_(desc||''));o.default=String(def);o.datatype=type;o.rmempty=false;return o;}
  function flag(tab,name,title,def,desc){var o=s.taboption(tab,form.Flag,name,_(title),_(desc||''));o.default=def;o.rmempty=false;return o;}
  var o=flag('general','enabled','Enable channel coordination','1','Turning this off keeps the current channels. Client steering has its own enable switch on the Clients page.');
  o=s.taboption('general',form.ListValue,'mode',_('Operating mode'),_('Observe shows proposed changes. Automatic applies better separation or usable width, and cost improvements that meet the evidence margin. Close comparisons request more measurements.'));
  o.value('observe',_('Observe: recommend only'));o.value('automatic',_('Automatic: prepare and apply'));o.default='automatic';o.rmempty=false;
  val('general','interval','Wait between completed surveys (seconds)',60,'range(30,86400)','Broad surveys maintain coverage. Close comparisons can request an earlier repeat. Longer intervals reduce scan overhead.');
  val('general','improvement','Required improvement (score points)',3,'range(1,200)','The minimum estimated gain needed to change channel; no extra switching penalty is subtracted. Higher values resist small fluctuations. Points are neither Mbps nor a percentage. Widening into sufficiently clear spectrum follows the width preference. Uncertain comparisons collect more evidence; clear gains can act after one complete survey.');
  val('general','min_dwell','Minimum residence after a verified move (seconds)',180,'range(30,86400)','A short anti-hopping period after a completed change. Deferred preparation attempts use the separate short retry delay.');
  val('general','retry_delay','Retry delay after a deferred operation (seconds)',30,'range(10,3600)','A deferred attempt does not impose a full channel residence period. Failed placements are tracked separately.');
  val('dfs','radar_half_life','Radar-memory half-life (seconds)',21600,'range(900,604800)','21600 is six hours. Remembered interruption risk halves over this time; repeated detections strengthen it. This never shortens the kernel radar prohibition or replaces required clearance. Amber history bands use this same decay.');
  flag('general','persist','Remember verified channels after restart','1','Verified placements are checkpointed at most every six hours. Power loss may return to the last saved working placement.');
  flag('general','clear_stop','Clear the safety stop when applying settings','0','First check that the radios and clients work normally. The switch clears itself after restarting the coordinator.');
  val('clients','max_mbps','Quiet-traffic threshold for channel changes (Mbps)',0.05,'range(0.01,1000)','Applies to quiet-only channel changes and sustained-quiet scanning. Automatic live CSA and paced scanning do not require traffic silence.');
  val('clients','quiet_seconds','Continuous quiet period (seconds)',60,'range(10,600)','For quiet-only channel changes and sustained-quiet scanning, traffic must remain below the threshold for this period. A single quiet sample is insufficient.');
  val('clients','handoff_wait','Time allowed for client handoff (seconds)',90,'range(60,300)','The first third allows a gentle request; the second can use a stronger request; the final third allows the decisive step if selected below. Live CSA does not need a handoff. Without a compatible destination, skip this wait and use brief reconnection if enabled below.');
  o=s.taboption('clients',form.ListValue,'handoff_escalation',_('How to handle clients that stay'),_('One uniform policy applies to every radio. A healthy AP on the same network and a compatible band must be available. Decisive mode can briefly interrupt the selected client; it verifies reconnection elsewhere before using the emptied radio.'));
  o.value('gentle',_('Gentle requests only'));o.value('strong',_('Gentle, then stronger requests'));o.value('decisive',_('Escalate to one bounded disconnect'));o.default='decisive';o.rmempty=false;
  val('clients','ban_seconds','Prevent immediate return to the old radio (seconds)',20,'range(5,30)','Used only after a decisive disconnect. This short restriction expires automatically. If the client does not reconnect elsewhere, access is restored; the brief-reconnect fallback below can then proceed. Forced handoff retries are limited to one per client every five minutes.');
  o=s.taboption('clients',form.Flag,'allow_reconnect',_('Change channel even if handoff cannot finish'),_('Shared Automatic policy for every radio: first try a compatible handoff, then restart only the changing radio if clients remain. With no compatible AP, skip the impossible handoff. Clients briefly disconnect and reconnect to the same Wi-Fi network. Allow a 60-second grace period for missing clients. Verify recovery using available probes, traffic and associations; persistent failure restores the previous channel. Protected clients and explicit quiet-only or empty-only policies still apply.'));o.default='1';o.rmempty=false;
  o=s.taboption('clients',form.DynamicList,'protected_clients',_('Clients protected from automatic handoff'),_('These clients are not automatically asked to roam or forcibly disconnected by channel coordination. An AP needing a restart stays put while they are attached. Useful for a PC doing important work; remove its entry when that protection is no longer needed.'));o.datatype='macaddr';o.rmempty=true;
  val('clients','verify_unprobed','Observe unprobeable clients after a move (seconds)',180,'range(150,600)','Before a switch, up to eight clients with private DHCP addresses are checked for reachability. Previously responsive clients must respond afterwards. Clients without a usable probe need this longer association watch because drivers may retain stale associations. A sustained service failure starts bounded recovery on the affected radio. Fresh bidirectional traffic can establish service even when ICMP is filtered.');
  val('clients','handoff_target_min','Minimum measured destination signal (dBm)',-72,'range(-90,-30)','A fresh client measurement below this threshold prevents a forced move. Less negative means stronger.');
  val('clients','handoff_source_min','Required current signal when destination is unmeasured (dBm)',-65,'range(-90,-30)','Some clients cannot measure another radio. A strong current signal is then used as a proximity estimate for these co-located radios. This estimate does not guarantee the destination signal.');
  val('clients','csa_count','Advance channel-switch announcements (beacons)',15,'range(5,100)','CSA means Channel Switch Announcement. More announcements give clients more notice, but cannot fix a driver or client that handles channel changes poorly.');
  o=s.taboption('dfs',form.ListValue,'dfs_mode',_('Use radar-shared channels'),_('DFS means Dynamic Frequency Selection. The kernel and hostapd enforce radar listening and channel evacuation. This implementation requires matching European ETSI DFS regions. A country conflict blocks DFS; it is never worked around by skipping the radar check.'));
  o.value('off',_('Exclude DFS candidates'));o.value('available',_('Use channels already cleared by the kernel'));o.value('prepare',_('Prepare channels with an empty spare radio'));o.default='prepare';o.rmempty=false;
  o=s.taboption('dfs',form.ListValue,'dfs_helper',_('Radio used for radar listening'),_('Only an empty, compatible 5 GHz radio can listen. With handoff enabled, the coordinator first asks its clients to move elsewhere. The spare temporarily stops offering its regular network during the radar check, then restores it before the main radio moves. If clients stay, preparation waits.'));
  o.value('',_('Choose a compatible empty radio'));radios.filter(function(r){return r.band!='2g';}).forEach(function(r){o.value(r['.name'],radioName(r));});o.rmempty=false;
  val('dfs','cac_timeout','Maximum radar preparation time (seconds)',720,'range(120,1200)','CAC means Channel Availability Check. It usually takes about one minute; weather-radar blocks can require ten minutes. This timeout never shortens the mandatory listening period.');
  o=s.taboption('scan',form.ListValue,'scan_policy',_('Which radios may scan?'),_('Scanning briefly takes a radio away from its serving channel. Empty-radio scanning offers the least disruption. Radar preparation always requires an empty radio regardless of this setting.'));
  o.value('paced',_('Paced scans while serving clients'));o.value('idle',_('Only radios with no clients'));o.value('low_traffic',_('Also radios with sustained quiet traffic'));o.default='paced';o.rmempty=false;
  val('scan','scan_duty','Maximum scan duty on a serving radio (%)',10,'range(1,30)','Each measured off-channel visit is followed by enough serving time to respect this budget. Empty radios are preferred. Steady traffic does not permanently block coverage.');
  val('scan','scan_gap','Serving time between scan visits (seconds)',3,'range(1,30)','Paced scans visit one frequency at a time. A radio with clients gets at least this much time back on its serving channel before another visit; another radio can scan meanwhile.');
  val('scan','scan_wait','Extra scanner-wait budget per survey (seconds)',60,'range(5,300)','Wait for temporarily unavailable scanners within this shared budget. Normal serving gaps do not consume it. Completed measurements are retained; missing parts remain unknown.');
  o=s.taboption('scan',form.ListValue,'scanner',_('Survey radio'),_('Automatic selection prefers empty radios, then estimates the client capacity interrupted by each scan. It waits for the least-cost scanner during its serving gap; another ready band may be scanned meanwhile.'));
  o.value('',_('Choose automatically'));radios.forEach(function(r){o.value(r['.name'],radioName(r));});o.rmempty=false;
  o=s.taboption('scan',form.ListValue,'scan_type',_('Survey method'),_('Active scans send broadcast probes only where permitted. DFS and other restricted frequencies are always scanned passively.'));
  o.value('passive',_('Passive listening'));o.value('active',_('Active where permitted'));o.default='active';o.rmempty=false;
  val('scan','scan_batch','Frequencies per scan batch in non-paced modes',5,'range(1,16)','Paced mode always uses one frequency per visit. This limit applies to empty-only and sustained-quiet modes. Each radio needs complete coverage of its candidate spectrum; an incomplete other band can wait independently.');
  val('scan','max_age','Oldest usable survey (seconds)',900,'range(60,7200)','Stale observations are discarded. An unmeasured channel is unknown, not assumed empty.');
  flag('score','separate_radios','Prefer separate spectrum before comparing scores','1','Choose the least overlapping legal arrangement, then prefer usable width, then compare estimated capacity cost. Includes fixed radios and radios within their minimum residence period. If separation is impossible, minimise overlap; do not create more overlap during a move.');
  val('score','overlap_penalty','Additional cost of overlap between our radios',25,'range(0,500)','With separation enabled, a lower overlap wins regardless of this score. If disabled, overlap competes with other score terms.');
  val('score','wide_threshold','Congestion score that permits narrowing',70,'range(10,100)','Prefer the widest channel with a non-overlapping placement below this score. Heavy congestion, radar memory of 50% or more, or lack of separate spectrum can favor a narrower placement; it must still offer sufficient estimated capacity gain. This is a model score, not measured airtime. Higher values keep wider channels more strongly.');
  radios.forEach(function(r){
   var name=r['.name'],two=r.band=='2g';if(!uci.get('channel_coordinator',name))uci.add('channel_coordinator','radio',name);
   var q=m.section(form.NamedSection,name,'radio',radioName(r));q.anonymous=true;
   var v=q.option(form.Flag,'managed',_('Include this radio'),_('Excluded radios keep their current placement and are not used for radar preparation. This switch does not turn the radio off.'));v.default='1';v.rmempty=false;
   v=q.option(form.ListValue,'occupied_policy',_('When clients are connected'),_('Automatic uses live CSA with clients where supported, otherwise tries a compatible handoff and then the shared brief-reconnect fallback under Protect playback. Quiet-only and empty-only remain explicit restrictions.'));
   v.value('handoff',_('Automatic: live CSA or coordinated handoff'));v.value('quiet',_('Wait for quiet traffic, then announce the switch'));v.value('empty',_('Wait until the radio is empty'));v.default='handoff';v.rmempty=false;
   v=q.option(form.ListValue,'method',_('How this radio changes channels'),_('Use CSA when the driver supports it. Reconfiguration restarts only the selected radio, first trying to move its clients elsewhere. The shared brief-reconnect fallback also permits it with attached clients.'));
   v.value('csa',_('Announce a channel switch (CSA)'));v.value('idle_reconfigure',_('Restart this radio'));v.default='csa';v.rmempty=false;
   v=q.option(form.ListValue,'width_method',_('When channel width also changes'),_('Some drivers announce frequency changes correctly but fail to change width. Reconfiguration normally requires clients to leave first; the brief-reconnect option permits the fallback with clients attached. Frequency-only moves can still use CSA.'));
   v.value('',_('Use the channel-change method'));v.value('csa',_('Announce a channel switch (CSA)'));v.value('idle_reconfigure',_('Restart this radio'));v.optional=true;
   v=q.option(form.Value,'channels',_('Candidate primary channels'),_('Space-separated 20 MHz channel numbers. Every member of a wider block must be included. The kernel capabilities, regulatory limits and selected DFS mode further restrict this list. More numbers do not create sliding 80 MHz centre positions.'));
   v.default=two?'1 2 3 4 5 6 7 8 9 10 11 12 13':all5;v.validate=function(section,x){return /^(\d+\s*)+$/.test(x)?true:_('Enter channel numbers separated by spaces.');};v.rmempty=false;
   v=q.option(form.Value,'widths',_('Candidate widths (MHz)'),_('80 gives more peak capacity; 40 or 20 may avoid congestion. Enter several widths to compare them. The score favours wider channels but does not directly measure client throughput.'));
   v.default=two?'20':'80 40 20';v.validate=function(section,x){return (two?/^20$/:/^(20|40|80)(\s+(20|40|80))*$/).test(x)?true:_('Use 20 on 2.4 GHz; 20, 40 or 80 on 5 GHz.');};v.rmempty=false;
  });
  return m.render().then(function(formNode){return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),intro,formNode]);});
 }
});
