'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';
'require form';
'require uci';
'require fs';
'require poll';
'require wifi-coordinator.help as help';

function radioName(r){return r['.name']+' ('+(r.band=='2g'?'2.4':'5')+' GHz)';}
function readState(){return fs.read('/tmp/channel-coordinator-state.json').then(JSON.parse).catch(function(){return {};});}
return view.extend({
 load:function(){return Promise.all([uci.load('channel_coordinator'),uci.load('radio_prefer'),uci.load('wireless'),readState(),uci.load('wifi_coordinator_display')]);},
 render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));},
 renderPage:function(data){
  var state=data[3]||{},radios=uci.sections('wireless','wifi-device'),methodStatus={};
  function refresh(st){
   var methods={auto:'Auto',inherit:'Follow channel method',csa:'CSA',idle_reconfigure:'Restart'};
   Object.keys(methodStatus).forEach(function(name){
    var r=(st.radios||{})[name],node=methodStatus[name];
    if(!r){node.replaceChildren(E('p',{},_('No live status for this radio.')));return;}
    var rows=[E('p',{},'Applied channel method: '+(methods[r.requested_method]||'?')+' → '+(methods[r.method]||'?')+'. '+(r.method_reason||'')),
     E('p',{},'Applied width-change method: '+(methods[r.requested_width_method]||'?')+' → '+(methods[r.width_method]||'?')+'. '+(r.width_reason||''))];
    if(r.csa_recovery_left>0)rows.push(E('p',{},'Announced channel switching recently failed. Auto will use an alternative for '+Math.ceil(r.csa_recovery_left/60)+' more minutes.'));
    if(r.dfs_constraint)rows.push(E('p',{},r.dfs_constraint));
    if(r.ht40_constraint)rows.push(E('p',{},r.ht40_constraint));
    if(r.failed||r.unavailable)rows.push(E('p',{},(r.recovery_status||'Automatic recovery check pending')+(r.recovery_next>st.updated?' — next check in '+Math.ceil(r.recovery_next-st.updated)+' seconds.':'.')+(r.failure?' Last failure: '+r.failure:'')));
    if(r.client_avoid_count)rows.push(E('p',{},'Temporary restrictions after client connection failures: '+r.client_avoid_count+'.'));
    if(r.width_limit&&r.width_limit.until>st.updated)rows.push(E('p',{},r.width_limit.reason+'. Widths above '+r.width_limit.actual+' MHz deferred for '+Math.ceil((r.width_limit.until-st.updated)/60)+' more minutes.'));
    if(r.hardware_widths)rows.push(E('p',{},'Supported widths: '+r.hardware_widths.join(' / ')+' MHz. Widths to compare: '+(r.candidate_widths||[]).join(' / ')+' MHz.'));
    if((r.unavailable_widths||[]).length)rows.push(E('p',{},'Requested widths unavailable on this radio: '+r.unavailable_widths.join(' / ')+' MHz.'));
    var rejected=(r.rejected||[]).filter(function(x){return x.until>st.updated;});
    if(rejected.length)rows.push(E('p',{},'Temporary destination exclusions: '+rejected.map(function(x){var f=x.target.freq;return 'channel '+(f==2484?14:f<3000?(f-2407)/5:(f-5000)/5)+' / '+x.target.width+' MHz — '+(x.reason||'Connectivity verification failed')+'; '+Math.ceil((x.until-st.updated)/60)+' minutes remaining';}).join('. ')+'.'));
    node.replaceChildren.apply(node,rows);
   });
  }
  var m=new form.Map('channel_coordinator',_('Wi-Fi Coordinator: settings'),_('Operation changes restart coordination. Graph display settings below are shared by all browsers and do not restart coordination.'));
  m.chain('radio_prefer');
  var s=m.section(form.NamedSection,'main','coordinator');s.anonymous=true;
  s.tab('general',_('Operation'),_('Channel planning and preferred-radio steering are independent. Observe mode does not stop enabled client steering.'));
  s.tab('radios',_('Radios'),_('Choose which radios may change channel and which channels and widths they may use.'));
  s.tab('clients',_('Client steering'),_('Control how clients move between radios. Permission to restart an occupied radio is set separately.'));
  s.tab('scan',_('Survey & radar'),_('Balance spectrum measurements with service to connected clients.'));
  s.tab('advanced',_('Advanced'),_('Adjust channel-change caution and connection checks.'));
  if(typeof location!='undefined'&&location.hash=='#clients')s.selected_tab='clients';
  function val(tab,name,title,def,type,desc){var o=s.taboption(tab,form.Value,name,_(title),_(desc||''));o.default=String(def);o.datatype=type;o.rmempty=false;o.retain=true;if(type!='range(0.01,1000)')o.datatype='and(integer,'+type+')';return o;}
  function flag(tab,name,title,def,desc){var o=s.taboption(tab,form.Flag,name,_(title),_(desc||''));o.default=def;o.rmempty=false;return o;}
  var o=flag('general','enabled','Enable channel coordination','1','Turning this off keeps the current channels. Preferred-radio steering has its own switch below and can continue while channel planning is disabled.');
  o=s.taboption('general',form.ListValue,'mode',_('Channel planning mode'),_('Observe surveys the spectrum and proposes changes. Automatic applies suitable changes. Preferred-radio steering has its own switch; recovery and mandatory radar evacuation remain active in either mode.'));
  o.value('observe',_('Observe only'));o.value('automatic',_('Automatic'));o.default='automatic';o.rmempty=false;
  val('scan','interval','Wait between completed surveys (seconds)',60,'range(30,86400)','Wait at least this long after a completed survey or operation. Longer intervals reduce scanning overhead.');
  val('advanced','improvement','Movement caution (service-score points)',3,'range(1,200)','Higher values require more benefit before moving, especially when more clients would be interrupted. This sets both the base movement cost and the minimum benefit after that cost. Reducing overlap takes priority when spectrum separation is enabled. Scores estimate capacity, not speed.');
  val('advanced','min_dwell','Minimum residence after a verified move (seconds)',180,'range(30,86400)','Minimum time to remain on a channel after a verified move, to avoid frequent changes.');
  val('advanced','radar_half_life','Radar-memory half-life (seconds)',3600,'range(900,604800)','3600 is one hour. Remembered interruption risk halves over this time; repeated detections strengthen it. This never shortens the kernel radar prohibition or replaces required clearance. Amber history bands use this same decay.');
  flag('general','persist','Remember verified channels after restart','1','Save verified channels every six hours. After power loss, the router may return to the last saved placement.');
  if(state.halted||Object.values(state.radios||{}).some(function(r){return r.failed||r.unavailable;}))flag('general','clear_stop','Clear the safety stop when applying settings','0','Restart recovery is automatic. Use this only after resolving a reported recovery failure and checking the radios. The switch clears itself after use.');
  val('advanced','max_mbps','Quiet-traffic threshold (Mbps)',0.05,'range(0.01,1000)','Applies to quiet-only channel changes and sustained-quiet scanning. Automatic live CSA and paced scanning do not require traffic silence.');
  val('advanced','quiet_seconds','Continuous quiet period (seconds)',60,'range(10,600)','For quiet-only channel changes and sustained-quiet scanning, traffic must remain below the threshold for this period. A single quiet sample is insufficient.');
  o=s.taboption('general',form.Flag,'preference_enabled',_('Enable preferred-radio steering'),_('Encourage clients to use the preferred radio. Requires 802.11k/v support and usteer. Other usteer steering rules are suspended while coordination runs and restored when it stops.'));o.rmempty=false;o.uciconfig='radio_prefer';o.ucisection='main';o.ucioption='enabled';
  o=s.taboption('clients',form.ListValue,'preferred_radio',_('Radio to prefer'),_('Choose the radio whose capabilities and coverage best suit your clients. It must offer the same Wi-Fi name, security and network as their current connection.'));
  o.uciconfig='radio_prefer';o.ucisection='main';o.retain=true;o.depends('preference_enabled','1');
  o.value('',_('Select a radio'));uci.sections('wireless','wifi-device').forEach(function(r){o.value(r['.name'],r['.name']+' ('+(r.band=='2g'?'2.4':'5')+' GHz)');});
  o.validate=function(section,v){return this.map.lookupOption('radio_prefer.main.preference_enabled',section)[0].formvalue(section)!='1'||v?true:_('Select a preferred radio.');};o.rmempty=false;
  function value(name,title,def,type,description){var v=s.taboption('clients',form.Value,name,_(title),_(description));v.uciconfig='radio_prefer';v.ucisection='main';v.retain=true;if(name=='settle_time')v.depends('preference_enabled','1');v.default=String(def);v.datatype='and(integer,'+type+')';v.rmempty=false;}
  value('settle_time','Wait after a client connects (seconds)',30,'range(10,300)','Lets a new connection settle before asking the client to measure or roam again.');
  value('cooldown','Wait between steering attempts (seconds)',300,'range(60,3600)','Pause between attempts for the same client and destination. A return attempt after channel or radar work may happen sooner.');
  value('max_attempts','Maximum steering attempts before a longer pause',3,'range(1,10)','After this many attempts toward the same radio, pause for the attempt count multiplied by the wait between attempts. Forced disconnections are also limited to one per client every five minutes.');
  val('clients','handoff_wait','Time allowed for client handoff (seconds)',90,'range(60,300)','Time allowed for an attempt to move clients. The selected sequence below shows when requests become stronger. With no suitable destination, the separate brief-restart option determines whether the channel change can proceed.');
  o=s.taboption('clients',form.ListValue,'handoff_escalation',_('Client steering strength'),_('Gentle recommends a move. Strong warns more firmly. Decisive may briefly disconnect an eligible client to encourage reconnection on another radio. The same strength applies to preferred-radio returns and handoffs for channel or radar work. Protected clients and signal limits still apply.'));
  o.value('gentle',_('Gentle'));o.value('strong',_('Strong'));o.value('decisive',_('Decisive'));o.default='decisive';o.rmempty=false;
  o=s.taboption('clients',form.Flag,'allow_reconnect',_('Change channel even if handoff cannot finish'),_('If clients cannot move to another radio, allow the changing radio to restart briefly. Clients reconnect to the same Wi-Fi network. Persistent connection failure restores the previous channel. Protected clients and quiet-only or empty-only policies still apply.'));o.default='1';o.rmempty=false;
  o=s.taboption('clients',form.DynamicList,'protected_clients',_('Clients protected from automatic handoff'),_('Add Wi-Fi MAC addresses from Network → Wireless → Associated Stations. Use the address shown for this network; phones may use private addresses. These clients will not be asked to roam or forcibly disconnected, and their radio will not be restarted automatically. Scanning, announced channel switches and mandatory radar evacuation can still occur. An empty list protects no clients.'));o.datatype='macaddr';o.rmempty=true;
  val('advanced','verify_unprobed','Observe unprobeable clients after a move (seconds)',180,'range(150,600)','How long to watch clients that cannot answer a reachability check after a channel change. Reconnection and traffic help confirm working service. Persistent failure triggers recovery of the affected radio.');
  val('clients','handoff_target_min','Minimum measured destination signal (dBm)',-72,'range(-90,-30)','A fresh weak destination measurement blocks both requests and forced moves. Missing measurements still allow Gentle and Strong requests. Decisive disconnection then requires the same-band source-signal check below. Less negative means stronger.');
  val('clients','handoff_source_min','Required current signal when destination is unmeasured (dBm)',-65,'range(-90,-30)','Used only for Decisive disconnection when no qualifying destination measurement is available. A strong source signal is a proximity estimate only between co-located radios on the same band. It never authorizes an unmeasured 2.4-to-5 GHz disconnect. A fresh weak destination report still blocks the move.');
  o=s.taboption('scan',form.ListValue,'dfs_mode',_('Use radar-shared channels'),_('Exclude radar-shared channels, use already cleared channels, or prepare them with a spare radio. Radar detection requires leaving the channel. Set the actual country on every radio; required listening and exclusion periods always apply.'));
  o.value('off',_('Exclude DFS'));o.value('available',_('Already cleared only'));o.value('prepare',_('Prepare with a spare radio'));o.default='prepare';o.rmempty=false;
  o=s.taboption('scan',form.ListValue,'dfs_helper',_('Radio used for radar listening'),_('The helper temporarily stops serving its network while listening for radar. Clients must first move to another radio; if they remain, preparation waits. Automatic can choose another compatible helper when needed. A fixed selection waits for that radio.'));
  o.retain=true;o.depends('dfs_mode','prepare');o.value('',_('Automatic'));radios.filter(function(r){return r.band!='2g';}).forEach(function(r){o.value(r['.name'],radioName(r));});o.rmempty=true;
  o=s.taboption('scan',form.ListValue,'scan_policy',_('Which radios may scan?'),_('Scanning briefly takes a radio away from its serving channel. Empty-radio scanning offers the least disruption. Radar preparation always requires an empty radio regardless of this setting.'));
  o.value('paced',_('Paced while serving'));o.value('idle',_('Empty radios only'));o.value('low_traffic',_('Quiet radios too'));o.default='paced';o.rmempty=false;
  val('scan','scan_duty','Maximum scan duty on a serving radio (%)',10,'range(1,30)','Each measured off-channel visit is followed by enough serving time to respect this budget. Empty radios are preferred. Steady traffic does not permanently block coverage.').depends('scan_policy','paced');
  val('scan','scan_gap','Serving time between scan visits (seconds)',3,'range(1,30)','Paced scans visit one frequency at a time. A radio with clients gets at least this much time back on its serving channel before another visit; another radio can scan meanwhile.').depends('scan_policy','paced');
  o=s.taboption('scan',form.ListValue,'scanner',_('Survey radio'),_('Automatic prefers empty radios and otherwise minimizes disruption to clients. A fixed selection waits for that radio and may leave other bands unmeasured.'));
  o.value('',_('Choose automatically'));radios.forEach(function(r){o.value(r['.name'],radioName(r));});o.rmempty=true;
  o=s.taboption('scan',form.ListValue,'scan_type',_('Survey method'),_('Active scans send broadcast probes only where permitted. DFS and other restricted frequencies are always scanned passively.'));
  o.value('passive',_('Passive listening'));o.value('active',_('Active where permitted'));o.default='active';o.rmempty=false;
  val('scan','max_age','Oldest usable survey (seconds)',900,'range(60,7200)','Maximum age of survey results used for channel decisions. Allow enough time to complete a survey. This also sets the initial retry delay after an inconclusive connection check or refused width. Repeated width refusals extend that delay, up to six hours.');
  flag('advanced','separate_radios','Prefer separate spectrum before comparing scores','1','Choose the least overlapping legal arrangement, then maximize joint estimated service. Includes fixed radios and radios within their minimum residence period. If separation is impossible, minimise overlap; do not create more overlap during a move.');
  val('advanced','overlap_penalty','Additional cost of overlap between our radios',25,'range(0,500)','With separation enabled, a lower overlap wins regardless of this score. If disabled, overlap competes with other score terms.').depends('separate_radios','0');
  function setting(name){return s.children.filter(function(o){return o.option===name;})[0];}
  setting('mode').retain=true;setting('mode').depends('enabled','1');
  setting('handoff_source_min').depends('handoff_escalation','decisive');
  setting('allow_reconnect').retain=true;setting('allow_reconnect').depends({enabled:'1',mode:'automatic'});
  ['max_mbps','quiet_seconds'].forEach(function(key){var v=setting(key);v.depends('scan_policy','low_traffic');radios.forEach(function(r){var dep={};dep['channel_coordinator.'+r['.name']+'.occupied_policy']='quiet';dep['channel_coordinator.'+r['.name']+'.managed']='1';v.depends(dep);});});
  radios.forEach(function(r){
   var name=r['.name'],two=r.band=='2g';if(!uci.get('channel_coordinator',name))uci.add('channel_coordinator','radio',name);
   var q=s.taboption('radios',form.SectionValue,'_radio_'+name,form.NamedSection,name,'radio',radioName(r)).subsection;q.anonymous=true;
   q.tab('general',_('Placement'));q.tab('advanced',_('Driver overrides'));
   help.sectionStatus(q,methodStatus[name]=E('div',{'class':'wc-caption'}));
   var v=q.taboption('general',form.Flag,'managed',_('Allow automatic channel management'),_('Excluded radios keep their current placement and are not used for radar preparation. This switch does not turn the radio off or exclude it from scanning or preferred-radio steering.'));v.default='1';v.rmempty=false;
   v=q.taboption('general',form.ListValue,'occupied_policy',_('When clients are connected'),_('Automatic uses live CSA with clients where supported, otherwise tries a compatible handoff and then the shared brief-reconnect fallback under Client steering. Quiet-only and empty-only remain explicit restrictions.'));
   v.value('handoff',_('Automatic'));v.value('quiet',_('Quiet traffic only'));v.value('empty',_('No clients only'));v.default='handoff';v.rmempty=false;
   v=q.taboption('advanced',form.ListValue,'method',_('How this radio changes channels'),_('Auto adapts to driver capabilities, tested hardware behavior and recent CSA failures. An explicit CSA or restart choice is never substituted for a planned move; an unsupported choice prevents that move. Recovery can still restore service after a failed operation. Regulatory restrictions always apply.'));
   v.value('auto',_('Automatic'));v.value('csa',_('Announce switch (CSA)'));v.value('idle_reconfigure',_('Restart radio'));v.default='auto';v.rmempty=false;
   v=q.taboption('advanced',form.ListValue,'width_method',_('When channel width also changes'),_('Automatic chooses a supported method, which may require a brief restart. Follow channel method uses the choice above. A fixed method prevents changes it cannot perform. On 2.4 GHz, 40 MHz operation may require a restart to check for neighbouring networks.'));
   v.value('auto',_('Automatic'));v.value('inherit',_('Follow channel method'));v.value('csa',_('Announce switch (CSA)'));v.value('idle_reconfigure',_('Restart radio'));v.default='auto';v.rmempty=false;
   v=q.taboption('general',form.Value,'channels',_('Candidate primary channels'),_('Auto uses all driver-allowed primary channels. Or enter channel numbers separated by spaces. Width is chosen separately; driver and regulatory limits always apply.'));
   v.default='auto';v.placeholder='auto';v.validate=function(section,x){x=x.trim();return x=='auto'||/^\d+(\s+\d+)*$/.test(x)&&x.split(/\s+/).every(function(c){return +c>=1&&+c<=(two?14:184);})?true:_('Enter auto or valid channel numbers separated by spaces.');};v.rmempty=false;
   v=q.taboption('general',form.Value,'widths',_('Candidate widths (MHz)'),_('Auto compares the widths supported by this radio. Or enter widths separated by spaces. Wider channels can offer more capacity; a narrower channel can be better in crowded spectrum. Radio capabilities, radar clearance and neighbouring networks may limit the width used.'));
   v.default='auto';v.placeholder='auto';v.validate=function(section,x){return (two?/^(auto|(20|40)(\s+(20|40))*)$/:/^(auto|(20|40|80|160)(\s+(20|40|80|160))*)$/).test(x.trim())?true:_('Enter auto or space-separated widths: 20/40 on 2.4 GHz, 20/40/80/160 on 5 GHz. Driver limits apply.');};v.rmempty=false;
   q.children.forEach(function(v){if(v.option!='managed'){v.retain=true;v.depends('managed','1');}});
  });
  var guidance=E('p',{'class':'wc-caption','aria-live':'polite'});
  o=s.taboption('clients',form.DummyValue,'_steering_summary',_('Selected steering sequence'));
  o.renderWidget=function(){return guidance;};o.write=function(){};o.remove=function(){};
  function updateGuidance(){
   function selected(name){var v=setting(name);return v.formvalue('main')??v.cfgvalue('main');}
   var seconds=Number(selected('handoff_wait')),strength=selected('handoff_escalation');
   if(!Number.isInteger(seconds)||seconds<60||seconds>300){guidance.textContent=_('Enter a valid handoff window to show its timing.');return;}
   guidance.textContent='Gentle request now'+(strength!='gentle'?' → Strong warning after '+Math.floor(seconds/3)+' seconds':'')+
    (strength=='decisive'?' → Eligible disconnect after '+Math.floor(seconds*2/3)+' seconds, with at most 20 seconds of return restriction':'')+
    '. Attempt window: '+seconds+' seconds. Protection, signal and retry checks always apply.';
  }
  var order={general:['enabled','mode','preference_enabled','persist','clear_stop'],
   clients:['preferred_radio','handoff_escalation','_steering_summary','protected_clients','allow_reconnect','handoff_wait','settle_time','handoff_target_min','handoff_source_min','cooldown','max_attempts'],
   scan:['scan_policy','interval','scan_duty','scan_gap','scan_type','scanner','max_age','dfs_mode','dfs_helper'],
   advanced:['separate_radios','overlap_penalty','improvement','min_dwell','radar_half_life','max_mbps','quiet_seconds','verify_unprobed']};
  var tabOrder=['general','radios','clients','scan','advanced'];
  s.children.sort(function(a,b){
   if(a.tab!=b.tab)return tabOrder.indexOf(a.tab)-tabOrder.indexOf(b.tab);
   var names=order[a.tab];return names?names.indexOf(a.option)-names.indexOf(b.option):0;
  });
  refresh(state);
  poll.add(function(){return readState().then(refresh);},5);
  help.compact(m);
  var display=new form.Map('wifi_coordinator_display',_('Graph display'),_('Saved on this router for every browser. History uses new settings on its next refresh. These controls do not change recording, retention, exports or channel decisions.'));
  var ds=display.section(form.NamedSection,'main','display');ds.anonymous=true;
  [['decimation','Adapt graph detail to screen resolution','Request only the selected time window and reduce graph data on the router to match the plotting width. Preserve traffic extrema, client-count steps, channel changes and unknown gaps. Heatmap columns show time-weighted estimates with their range. Turn off to draw available stored detail; this does not recover measurements absent from stored summaries.'],
   ['triangles','Show action markers (triangles)','Show recorded actions such as channel changes and client departures. Hiding markers does not remove actions from the log or exports. Crowded markers are grouped when screen adaptation is enabled.'],
   ['squares','Show missing-observation markers (squares)','Mark intervals where observations are missing and service continuity is unknown. Hiding these squares leaves the underlying gaps blank.'],
   ['crosses','Show unavailability markers (crosses)','Mark intervals when hostapd confirmed that no access point was enabled. Hiding these crosses does not fill the gap or remove its records.'],
   ['popups','Show graph popups','Show graph values, intervals, aggregate ranges and marker details on hover or tap. Also enables graph-heading and legend hints. Settings explanations remain available.']].forEach(function(row){var option=ds.option(form.Flag,row[0],_(row[1]),_(row[2]));option.default='1';option.rmempty=false;});
  help.compact(display);
  return Promise.all([m.render(),display.render()]).then(function(nodes){var node=nodes[0];updateGuidance();node.addEventListener('change',updateGuidance);node.addEventListener('input',updateGuidance);return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),node,nodes[1]]);});
 }
});
