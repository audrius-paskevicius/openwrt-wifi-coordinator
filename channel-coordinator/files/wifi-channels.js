'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';
'require form';
'require uci';
'require rpc';
'require fs';
'require poll';
'require wifi-coordinator.help as help';
'require wifi-coordinator.time as timefmt';

var service = rpc.declare({object:'service',method:'list',params:['name'],expect:{'':{}}});
function radioName(r) { return r['.name']+' ('+(r.band=='2g'?'2.4':'5')+' GHz)'; }
function readState() { return fs.read('/tmp/channel-coordinator-state.json').then(JSON.parse).catch(function(){return {};}); }
function operationText(st) {
 return st.restart_check?(st.status||'Checking radios after interruption'):
  st.halted?'Coordination paused: '+st.halted+(st.recovery_retry_at>st.updated?' — automatic retry in '+Math.ceil(st.recovery_retry_at-st.updated)+' seconds.':' — automatic reassessment pending.'):(st.status||'No evaluation yet.');
}
function statusText(st, services) {
 var running=Object.values(((services||{})['channel-coordinator']||{}).instances||{}).some(function(i){return i.running;});
 return (running?'Running. ':'Stopped. ')+operationText(st);
}
function comparisonTime(p,st) {
 if(!p.evaluated_at)return _('Last completed comparison.');
 var age=Math.max(0,(st.updated||p.evaluated_uptime)-p.evaluated_uptime);
 return _('Last comparison: ')+timefmt.stamp(p.evaluated_at)+
  (Number.isFinite(age)?' ('+(age<60?Math.floor(age)+' seconds':Math.floor(age/60)+' minutes')+' ago).':'.');
}
return view.extend({
 load:function(){return Promise.all([uci.load('channel_coordinator'),uci.load('wireless'),readState(),service('channel-coordinator')]);},
 render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));},
 renderPage:function(data){
  var state=data[2], radios=uci.sections('wireless','wifi-device'),methodStatus={};
  var status=E('p',{'class':'wc-status','data-level':state.halted&&!state.restart_check?'warning':'normal'},statusText(state,data[3]));
  var details=E('div');
  var comparisonContent=E('div');
  var comparison=E('details',{},[
   E('summary',{},_('Why these channels? Compare all eligible placements')),comparisonContent
  ]);
  function refresh(st){
   var methods={auto:'Auto',inherit:'Follow channel method',csa:'CSA',idle_reconfigure:'Restart'};
   Object.keys(methodStatus).forEach(function(name){
    var r=(st.radios||{})[name],node=methodStatus[name];
    if(!r){node.replaceChildren(E('p',{},_('No live status for this radio.')));return;}
    var rows=[E('p',{},'Applied channel method: '+(methods[r.requested_method]||'?')+' → '+(methods[r.method]||'?')+'. '+(r.method_reason||'')),
     E('p',{},'Applied width-change method: '+(methods[r.requested_width_method]||'?')+' → '+(methods[r.width_method]||'?')+'. '+(r.width_reason||''))];
    if(r.csa_recovery_left>0)rows.push(E('p',{},'Recent CSA failure remembered for '+Math.ceil(r.csa_recovery_left/60)+' more minutes. Only Auto adapts the method.'));
    if(r.dfs_constraint)rows.push(E('p',{},r.dfs_constraint));
    if(r.ht40_constraint)rows.push(E('p',{},r.ht40_constraint));
    if(r.failed||r.unavailable)rows.push(E('p',{},(r.recovery_status||'Automatic recovery check pending')+(r.recovery_next>st.updated?' — next check in '+Math.ceil(r.recovery_next-st.updated)+' seconds.':'.')+(r.failure?' Last failure: '+r.failure:'')));
    if(r.client_avoid_count)rows.push(E('p',{},r.client_avoid_count+' client-specific placement cooldowns. Healthy clients can still use these placements.'));
    if(r.width_limit&&r.width_limit.until>st.updated)rows.push(E('p',{},r.width_limit.reason+'. Widths above '+r.width_limit.actual+' MHz deferred for '+Math.ceil((r.width_limit.until-st.updated)/60)+' more minutes; configured Auto/manual widths are unchanged.'));
    if(r.hardware_widths)rows.push(E('p',{},'Driver widths: '+r.hardware_widths.join(' / ')+' MHz. Widths to compare: '+(r.candidate_widths||[]).join(' / ')+' MHz.'));
    if((r.unavailable_widths||[]).length)rows.push(E('p',{},'Requested widths unavailable on this radio: '+r.unavailable_widths.join(' / ')+' MHz.'));
    var rejected=(r.rejected||[]).filter(function(x){return x.until>st.updated;});
    if(rejected.length)rows.push(E('p',{},'Temporary destination exclusions: '+rejected.map(function(x){var f=x.target.freq;return 'channel '+(f==2484?14:f<3000?(f-2407)/5:(f-5000)/5)+' / '+x.target.width+' MHz — '+(x.reason||'Connectivity verification failed')+'; '+Math.ceil((x.until-st.updated)/60)+' minutes remaining';}).join('. ')+'.'));
    node.replaceChildren.apply(node,rows);
   });
   var header=E('thead',{},E('tr',{},['Radio','Channel / width','Clients','Traffic','Minimum residence','Radar check'].map(function(x){return E('th',{'scope':'col'},_(x));}))),rows=[];
   Object.keys(st.radios||{}).forEach(function(name){var r=st.radios[name];rows.push(E('tr',{},[
    name,(r.channel||'?')+' / '+(r.width||'?')+' MHz',String(r.clients||0),Number(r.mbps||0).toFixed(3)+' Mbps',
    (r.cooldown_left||0)+' s',r.dfs?(r.dfs_ready?'Cleared DFS channel':'DFS clearance required'):'Not a DFS channel'
   ].map(function(v){return E('td',{},v);})));});
   var p=st.proposal, dfs=st.dfs;
   var items=[E('div',{'class':'wc-table-wrap'},E('table',{'class':'table wc-table'},[header,E('tbody',{},rows)]))],cards=[];
   if(st.scan_coverage)cards.push(E('div',{'class':'wc-summary'},[
    E('h4',{},_('Last survey coverage')),E('p',{},st.scan_coverage.completed+' of '+st.scan_coverage.requested+' frequencies measured ('+st.scan_coverage.policy+').'),
    E('p',{},'Completed at '+timefmt.stamp(st.scan_coverage.at)+'. Only radios with complete fresh coverage may move; missing coverage on another band does not block them.')
   ]));
   if(p)cards.push(E('div',{'class':'wc-summary'},[
    E('h4',{},_('Last completed comparison')),E('p',{},comparisonTime(p,st)),E('p',{},p.neighbors+' nearby networks.'),
    E('p',{},'Service-score improvement: '+Number(p.improvement||0).toFixed(1)+' points. Spectrum separation takes priority when enabled; this is a capacity estimate, not a speed measurement.'),
    (p.changes||[]).length?E('ul',{},p.changes.map(function(c){return E('li',{},'Compared target '+c.radio+': channel '+c.from+' to '+c.to+' ('+c.width+' MHz)');})):E('p',{},_('Placement at comparison retained.')),
    p.placements_changed?E('p',{},_('Radio placements have changed since this comparison.')):'',
    p.separate?E('p',{},_('Separate spectrum takes priority. Each intermediate move must also avoid increasing overlap.')):'',
    p.decision?E('p',{},p.decision.reason+(p.decision.margin!=null?' (required benefit '+Number(p.decision.margin).toFixed(1)+' points; '+Object.keys(p.decision.comparisons||{}).map(function(name){return name+': '+p.decision.comparisons[name]+' supporting surveys';}).join(', ')+')':'')):'',
    p.steps?E('ol',{},p.steps.map(function(c){return E('li',{},c.radio+' to '+c.to+' / '+c.width+' MHz'+(c.staging?' (staging step)':''));})):'',   ]));
   if(dfs){var phase={listening:'Listening for radar',restoring:'Restoring the spare radio',ready:'Completed and shared',recovered:'Restored after an interrupted check',inactive:'Previous check ended','restored-after-error':'Restored after an error'};cards.push(E('div',{'class':'wc-summary'},[
    E('h4',{},_('Last radar preparation')),E('p',{},phase[dfs.phase]||dfs.phase),
    E('p',{},'Channel '+dfs.channel+' / '+dfs.width+' MHz'+(dfs.helper?' using '+dfs.helper:'')),
    dfs.elapsed!=null?E('p',{},'Preparation elapsed: '+dfs.elapsed+' seconds (includes radio setup).'):''
   ]));}
   if(cards.length)items.push(E('div',{'class':'wc-summaries'},cards));
   if(p&&p.alternatives)comparisonContent.replaceChildren.apply(comparisonContent,[
    E('p',{'class':'wc-caption'},comparisonTime(p,st)+' '+
     ('Now: '+operationText(st))+
     (p.placements_changed?' Radio placements have changed; the tables retain the previous comparison.':'')+
     ' Results stay visible until replaced by a completed comparison.'),
    E('p',{},_('The planner jointly maximizes estimated service after applying your spectrum-separation policy. Higher service is better: usable bandwidth is weighted by advertised radio spatial streams. The primary channel matters to narrow clients and to fallback transmissions. Wide channels earn their extra capacity only where the secondary spectrum is usable. This is hardware headroom for present and future clients, not predicted Mbps or a score fitted to currently connected devices.')),
    E('p',{},_('Grey history shows average neighbour pressure. Planning also accounts for the primary channel, bonded subchannels, fresh external busy counters and radar memory. A neighbour spanning a wide channel is counted once per bonded block. Our own traffic is excluded from busy-airtime evidence. Unknown airtime raises uncertainty; a white background does not prove zero interference.')),
    E('p',{},_('Every eligible alternative retains its own supporting-survey count. Repeated support reduces uncertainty. All service improvements, including widening, must meet the evidence margin; only improved spectrum separation can bypass it. Width and legal transmit power break equal-score ties, and an equal-service tie alone does not trigger a move. Sharing below refers to peers at comparison time; a joint plan can move those peers too.')),
    E('div',{},p.alternatives.map(function(a){return E('div',{},[
     E('h4',{},a.radio+(a.hold?' — at comparison: '+a.hold:'')),
     E('p',{},_('Channel pool at comparison: ')+(a.channels||[]).join(' ')),
     E('p',{},_('Widths at comparison: ')+(a.widths||[]).join(' / ')+' MHz'),
     a.width_limit?E('p',{},'Width constraint at comparison: '+a.width_limit.reason+'; widths above '+a.width_limit.actual+' MHz temporarily deferred.'):'',
     ...((a.rejected||[]).length?[E('p',{},'Excluded at comparison: '+a.rejected.map(function(x){return (x.target.freq<3000?(x.target.freq-2407)/5:(x.target.freq-5000)/5)+' / '+x.target.width+' MHz — '+(x.reason||'Connectivity check failed');}).join('; ')+'.')]:[]),
     E('div',{'class':'wc-table-wrap'},E('table',{'class':'table wc-table'},[
      E('thead',{},E('tr',{},['Channel / width','Service index','Congestion: primary / block','Estimated usable width','Sharing','Radar memory','Evidence uncertainty'].map(function(x){return E('th',{},x);}))),
      E('tbody',{},a.candidates.slice().sort(function(x,y){return (p.separate?x.shared-y.shared:0)||x.cost-y.cost;}).map(function(c){return E('tr',{},[
       c.channel+' / '+c.width+' MHz'+(c.current?' (used then)':''),c.service!=null?Number(c.service).toFixed(1):'--',Number(c.primary_occupancy!=null?c.primary_occupancy:c.occupancy).toFixed(0)+' / '+Number(c.occupancy).toFixed(0),Number(c.capacity).toFixed(1)+' MHz',Number(c.shared*100).toFixed(0)+'%',Math.round((c.radar_risk||0)*100)+'%',Number(c.uncertainty||0).toFixed(1)
      ].map(function(x){return E('td',{},x);}));}))
     ]))
    ]);}))
   ]);
   else comparisonContent.replaceChildren(E('p',{},_('No completed comparison yet. ')+operationText(st)));
   items.push(comparison);
   if(st.updated)items.push(E('small',{'class':'wc-caption'},'Updates every 5 seconds. Traffic is measured between samples; it is not a speed-test result.'));
   details.replaceChildren.apply(details,items);
  }
  refresh(state);
  poll.add(function(){return Promise.all([readState(),service('channel-coordinator')]).then(function(x){status.textContent=statusText(x[0],x[1]);status.setAttribute('data-level',x[0].halted&&!x[0].restart_check?'warning':'normal');refresh(x[0]);});},5);
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
  s.tab('general',_('When to act'));s.tab('clients',_('Protect playback'));s.tab('dfs',_('Radar preparation'));s.tab('scan',_('Survey'));s.tab('score',_('Planning details'));s.tab('advanced',_('Advanced'));
  function val(tab,name,title,def,type,desc){var o=s.taboption(tab,form.Value,name,_(title),_(desc||''));o.default=String(def);o.datatype=type;o.rmempty=false;o.retain=true;if(type!='range(0.01,1000)')o.datatype='and(integer,'+type+')';return o;}
  function flag(tab,name,title,def,desc){var o=s.taboption(tab,form.Flag,name,_(title),_(desc||''));o.default=def;o.rmempty=false;return o;}
  var o=flag('general','enabled','Enable channel coordination','1','Turning this off keeps the current channels. Client steering has its own enable switch on the Clients page.');
  o=s.taboption('general',form.ListValue,'mode',_('Operating mode'),_('Observe shows proposed changes. Automatic applies better separation and service improvements that meet the evidence margin. Close comparisons request more measurements.'));
  o.value('observe',_('Observe: recommend only'));o.value('automatic',_('Automatic: prepare and apply'));o.default='automatic';o.rmempty=false;
  val('general','interval','Wait between completed surveys (seconds)',60,'range(30,86400)','Wait at least this long after a completed survey or operation. Close comparisons wait for the next scheduled survey too. Longer intervals reduce scan overhead.');
  val('general','improvement','Required improvement (score points)',3,'range(1,200)','Minimum service gain before moving. Higher values resist small fluctuations. Width increases must meet this margin too; improved spectrum separation can bypass it. Scores represent usable bandwidth and advertised radio spatial capacity, not Mbps. Uncertain comparisons need more evidence; clear gains can act after one complete survey.');
  val('general','min_dwell','Minimum residence after a verified move (seconds)',180,'range(30,86400)','A short anti-hopping period after a completed change. Deferred attempts use a fixed 30-second retry gate.');
  val('dfs','radar_half_life','Radar-memory half-life (seconds)',3600,'range(900,604800)','3600 is one hour. Remembered interruption risk halves over this time; repeated detections strengthen it. This never shortens the kernel radar prohibition or replaces required clearance. Amber history bands use this same decay.');
  flag('general','persist','Remember verified channels after restart','1','Verified placements are checkpointed at most every six hours. Power loss may return to the last saved working placement.');
  flag('general','clear_stop','Clear the safety stop when applying settings','0','Restart recovery is automatic. Use this only after resolving a reported recovery failure and checking the radios. The switch clears itself after use.');
  val('advanced','max_mbps','Quiet-traffic threshold for channel changes (Mbps)',0.05,'range(0.01,1000)','Applies to quiet-only channel changes and sustained-quiet scanning. Automatic live CSA and paced scanning do not require traffic silence.');
  val('advanced','quiet_seconds','Continuous quiet period (seconds)',60,'range(10,600)','For quiet-only channel changes and sustained-quiet scanning, traffic must remain below the threshold for this period. A single quiet sample is insufficient.');
  val('clients','handoff_wait','Time allowed for client handoff (seconds)',90,'range(60,300)','The first third allows a gentle request; the second can use a stronger request; the final third allows the decisive step if selected below. Live CSA does not need a handoff. Without a compatible destination, skip this wait and use brief reconnection if enabled below.');
  o=s.taboption('clients',form.ListValue,'handoff_escalation',_('How to handle clients that stay'),_('One uniform policy applies to every radio. A healthy AP on the same network and a compatible band must be available. Decisive mode can briefly interrupt the selected client; it verifies reconnection elsewhere before using the emptied radio. This setting controls handoff requests only. The separate brief-reconnect option can restart a radio with clients after any handoff mode.'));
  o.value('gentle',_('Gentle requests only'));o.value('strong',_('Gentle, then stronger requests'));o.value('decisive',_('Escalate to one bounded disconnect'));o.default='decisive';o.rmempty=false;
  o=s.taboption('clients',form.Flag,'allow_reconnect',_('Change channel even if handoff cannot finish'),_('Shared Automatic policy for every radio: first try a compatible handoff, then restart only the changing radio if clients remain. With no compatible AP, skip the impossible handoff. Clients briefly disconnect and reconnect to the same Wi-Fi network. Allow a 60-second grace period for missing clients. Verify recovery using available probes, traffic and associations; persistent failure restores the previous channel. Protected clients and explicit quiet-only or empty-only policies still apply.'));o.default='1';o.rmempty=false;
  o=s.taboption('clients',form.DynamicList,'protected_clients',_('Clients protected from automatic handoff'),_('Enter one device\'s Wi-Fi MAC address, for example 02:11:22:33:44:55. Find it under Network → Wireless → Associated Stations, in the MAC address column. Use the address shown for this Wi-Fi network; phones may use a private address. Do not enter an IP address or device name. Click + to add the address to the list, then enter another if needed. Use the remove control beside an entry to delete it. Save & Apply saves your changes. Leave the list empty if no clients need protection. Neither controller automatically asks these clients to roam or forcibly disconnects them. An AP needing a restart stays put while they are attached. This does not prevent scans, announced channel switches (CSA), or mandatory radar evacuation.'));o.datatype='macaddr';o.rmempty=true;
  val('advanced','verify_unprobed','Observe unprobeable clients after a move (seconds)',180,'range(150,600)','Before a switch, up to eight clients with private DHCP addresses are checked for reachability. Previously responsive clients must respond afterwards. Clients without a usable probe need this longer association watch because drivers may retain stale associations. A sustained service failure starts bounded recovery on the affected radio. Fresh bidirectional traffic can establish service even when ICMP is filtered.');
  val('advanced','handoff_target_min','Minimum measured destination signal (dBm)',-72,'range(-90,-30)','A fresh client measurement below this threshold prevents a forced move. Less negative means stronger.');
  val('advanced','handoff_source_min','Required current signal when destination is unmeasured (dBm)',-65,'range(-90,-30)','Some clients cannot measure another radio. A strong current signal is then used as a proximity estimate for these co-located radios. This estimate does not guarantee the destination signal.');
  o=s.taboption('dfs',form.ListValue,'dfs_mode',_('Use radar-shared channels'),_('DFS means Dynamic Frequency Selection. The kernel and hostapd enforce radar listening and channel evacuation under the configured country. Global and radio DFS regions must be known and match. An exposed mwlwifi internal radar-region mismatch also blocks DFS. Set the actual country on every radio; factory restrictions remain in force.'));
  o.value('off',_('Exclude DFS candidates'));o.value('available',_('Use channels already cleared by the kernel'));o.value('prepare',_('Prepare channels with an empty spare radio'));o.default='prepare';o.rmempty=false;
  o=s.taboption('dfs',form.ListValue,'dfs_helper',_('Radio used for radar listening'),_('Only an empty, compatible 5 GHz radio can listen. With handoff enabled, the coordinator first asks its clients to move elsewhere. The spare temporarily stops offering its regular network during the radar check, then restores it before the main radio moves. If clients stay, preparation waits.'));
  o.retain=true;o.depends('dfs_mode','prepare');o.value('',_('Choose a compatible empty radio'));radios.filter(function(r){return r.band!='2g';}).forEach(function(r){o.value(r['.name'],radioName(r));});o.rmempty=false;
  o=s.taboption('scan',form.ListValue,'scan_policy',_('Which radios may scan?'),_('Scanning briefly takes a radio away from its serving channel. Empty-radio scanning offers the least disruption. Radar preparation always requires an empty radio regardless of this setting.'));
  o.value('paced',_('Paced scans while serving clients'));o.value('idle',_('Only radios with no clients'));o.value('low_traffic',_('Also radios with sustained quiet traffic'));o.default='paced';o.rmempty=false;
  val('scan','scan_duty','Maximum scan duty on a serving radio (%)',10,'range(1,30)','Each measured off-channel visit is followed by enough serving time to respect this budget. Empty radios are preferred. Steady traffic does not permanently block coverage.').depends('scan_policy','paced');
  val('scan','scan_gap','Serving time between scan visits (seconds)',3,'range(1,30)','Paced scans visit one frequency at a time. A radio with clients gets at least this much time back on its serving channel before another visit; another radio can scan meanwhile.').depends('scan_policy','paced');
  o=s.taboption('advanced',form.ListValue,'scanner',_('Survey radio'),_('Automatic selection prefers empty radios, then estimates the client capacity interrupted by each scan. It waits for the least-cost scanner during its serving gap; another ready band may be scanned meanwhile.'));
  o.value('',_('Choose automatically'));radios.forEach(function(r){o.value(r['.name'],radioName(r));});o.rmempty=false;
  o=s.taboption('scan',form.ListValue,'scan_type',_('Survey method'),_('Active scans send broadcast probes only where permitted. DFS and other restricted frequencies are always scanned passively.'));
  o.value('passive',_('Passive listening'));o.value('active',_('Active where permitted'));o.default='active';o.rmempty=false;
  val('advanced','max_age','Oldest usable survey (seconds)',900,'range(60,7200)','Stale observations are discarded. An unmeasured channel is unknown, not assumed empty.');
  flag('score','separate_radios','Prefer separate spectrum before comparing scores','1','Choose the least overlapping legal arrangement, then maximize joint estimated service. Includes fixed radios and radios within their minimum residence period. If separation is impossible, minimise overlap; do not create more overlap during a move.');
  val('score','overlap_penalty','Additional cost of overlap between our radios',25,'range(0,500)','With separation enabled, a lower overlap wins regardless of this score. If disabled, overlap competes with other score terms.').depends('separate_radios','0');
  radios.forEach(function(r){
   var name=r['.name'],two=r.band=='2g';if(!uci.get('channel_coordinator',name))uci.add('channel_coordinator','radio',name);
   var q=m.section(form.NamedSection,name,'radio',radioName(r));q.anonymous=true;
   help.sectionStatus(q,methodStatus[name]=E('div',{'class':'wc-caption'}));
   var v=q.option(form.Flag,'managed',_('Include this radio'),_('Excluded radios keep their current placement and are not used for radar preparation. This switch does not turn the radio off or exclude it from scanning or preferred-radio steering.'));v.default='1';v.rmempty=false;
   v=q.option(form.ListValue,'occupied_policy',_('When clients are connected'),_('Automatic uses live CSA with clients where supported, otherwise tries a compatible handoff and then the shared brief-reconnect fallback under Protect playback. Quiet-only and empty-only remain explicit restrictions.'));
   v.value('handoff',_('Automatic: live CSA or coordinated handoff'));v.value('quiet',_('Wait for quiet traffic, then announce the switch'));v.value('empty',_('Wait until the radio is empty'));v.default='handoff';v.rmempty=false;
   v=q.option(form.ListValue,'method',_('How this radio changes channels'),_('Auto adapts to driver capabilities, tested hardware behavior and recent CSA failures. An explicit CSA or restart choice is never substituted for a planned move; an unsupported choice prevents that move. Recovery can still restore service after a failed operation. Regulatory restrictions always apply.'));
   v.value('auto',_('Automatic'));v.value('csa',_('Announce a channel switch (CSA)'));v.value('idle_reconfigure',_('Restart this radio'));v.default='auto';v.rmempty=false;
   v=q.option(form.ListValue,'width_method',_('When channel width also changes'),_('Auto selects a method independently, including restart for tested WRT width changes. This method also applies to 2.4 GHz HT40 channel moves, which need a restart for hostapd coexistence checks. Explicit CSA cannot bypass that check. Follow channel method uses the resolved channel-change method. Explicit choices remain fixed.'));
   v.value('auto',_('Automatic'));v.value('inherit',_('Follow channel method'));v.value('csa',_('Announce a channel switch (CSA)'));v.value('idle_reconfigure',_('Restart this radio'));v.default='auto';v.rmempty=false;
   v=q.option(form.Value,'channels',_('Candidate primary channels'),_('Auto uses all driver-allowed primary channels. Or enter channel numbers separated by spaces. Width is chosen separately; driver and regulatory limits always apply.'));
   v.default='auto';v.placeholder='auto';v.validate=function(section,x){x=x.trim();return x=='auto'||/^\d+(\s+\d+)*$/.test(x)&&x.split(/\s+/).every(function(c){return +c>=1&&+c<=(two?14:184);})?true:_('Enter auto or valid channel numbers separated by spaces.');};v.rmempty=false;
   v=q.option(form.Value,'widths',_('Candidate widths (MHz)'),_('Auto follows this radio\'s advertised HT/VHT widths in its current band. Or enter widths separated by spaces. Legal channel blocks, radar clearance and 2.4 GHz coexistence still apply. The applied status lists driver capabilities and unavailable requests. Extra width earns value where usable; a cleaner narrower placement can win on joint service. Scores estimate hardware capacity for present and future clients, not measured speed.'));
   v.default='auto';v.placeholder='auto';v.validate=function(section,x){return (two?/^(auto|(20|40)(\s+(20|40))*)$/:/^(auto|(20|40|80|160)(\s+(20|40|80|160))*)$/).test(x.trim())?true:_('Enter auto or space-separated widths: 20/40 on 2.4 GHz, 20/40/80/160 on 5 GHz. Driver limits apply.');};v.rmempty=false;
  });
  refresh(state);
  help.compact(m);
  return m.render().then(function(formNode){return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),intro,formNode]);});
 }
});
