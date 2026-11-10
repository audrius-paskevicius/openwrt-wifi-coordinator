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
 load:function(){return Promise.all([uci.load('channel_coordinator'),uci.load('radio_prefer'),uci.load('wireless'),readState()]);},
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
  }
  var m=new form.Map('channel_coordinator',_('Wi-Fi Coordinator: settings'),_('Settings for channel planning and client steering. Save & Apply restarts the shared coordinator. Existing choices are retained; changing tabs does not apply them.'));
  m.chain('radio_prefer');
  var s=m.section(form.NamedSection,'main','coordinator');s.anonymous=true;
  s.tab('general',_('Operation'),_('Channel planning and preferred-radio steering are independent. Observe mode does not stop enabled client steering.'));
  s.tab('radios',_('Radios'),_('Restrict where each radio may operate. Excluding a radio fixes its placement but still permits scanning and client steering. Driver overrides are separate from placement restrictions.'));
  s.tab('clients',_('Client steering'),_('One policy for preferred-radio returns and handoffs before channel or radar work. Brief radio restart is a separate permission from steering strength.'));
  s.tab('scan',_('Survey & radar'),_('Gather fresh evidence while serving clients. Radar preparation needs an empty compatible helper; mandatory radar evacuation remains under kernel control.'));
  s.tab('advanced',_('Advanced'),_('Planning balance and verification controls. Quiet-traffic fields appear only for a quiet-only radio policy or sustained-quiet scanning. Values are retained when controls are hidden.'));
  if(typeof location!='undefined'&&location.hash=='#clients')s.selected_tab='clients';
  function val(tab,name,title,def,type,desc){var o=s.taboption(tab,form.Value,name,_(title),_(desc||''));o.default=String(def);o.datatype=type;o.rmempty=false;o.retain=true;if(type!='range(0.01,1000)')o.datatype='and(integer,'+type+')';return o;}
  function flag(tab,name,title,def,desc){var o=s.taboption(tab,form.Flag,name,_(title),_(desc||''));o.default=def;o.rmempty=false;return o;}
  var o=flag('general','enabled','Enable channel coordination','1','Turning this off keeps the current channels. Preferred-radio steering has its own switch below and can continue while channel planning is disabled.');
  o=s.taboption('general',form.ListValue,'mode',_('Channel planning mode'),_('Observe surveys and proposes channel changes; preferred-radio steering remains independently enabled or disabled. Recovery and mandatory radar evacuation remain active. Automatic applies better separation and service improvements that meet the evidence margin. Close comparisons request more measurements.'));
  o.value('observe',_('Observe only'));o.value('automatic',_('Automatic'));o.default='automatic';o.rmempty=false;
  val('scan','interval','Wait between completed surveys (seconds)',60,'range(30,86400)','Wait at least this long after a completed survey or operation. Close comparisons wait for the next scheduled survey too. Longer intervals reduce scan overhead.');
  val('advanced','improvement','Movement caution (service-score points)',3,'range(1,200)','Sets both the base movement cost and the minimum net gain after that cost. Higher values require more benefit, especially with more affected clients, restarts, helper handoffs or observed CSA departures. Improved spectrum separation bypasses the net-gain margin, but movement cost still helps select the route. Evidence uncertainty can raise the margin. These scores estimate service capacity, not Mbps.');
  val('advanced','min_dwell','Minimum residence after a verified move (seconds)',180,'range(30,86400)','A short anti-hopping period after a completed change. Deferred attempts use a fixed 30-second retry gate.');
  val('advanced','radar_half_life','Radar-memory half-life (seconds)',3600,'range(900,604800)','3600 is one hour. Remembered interruption risk halves over this time; repeated detections strengthen it. This never shortens the kernel radar prohibition or replaces required clearance. Amber history bands use this same decay.');
  flag('general','persist','Remember verified channels after restart','1','Verified placements are checkpointed at most every six hours. Power loss may return to the last saved working placement.');
  if(state.halted||Object.values(state.radios||{}).some(function(r){return r.failed||r.unavailable;}))flag('general','clear_stop','Clear the safety stop when applying settings','0','Restart recovery is automatic. Use this only after resolving a reported recovery failure and checking the radios. The switch clears itself after use.');
  val('advanced','max_mbps','Quiet-traffic threshold (Mbps)',0.05,'range(0.01,1000)','Applies to quiet-only channel changes and sustained-quiet scanning. Automatic live CSA and paced scanning do not require traffic silence.');
  val('advanced','quiet_seconds','Continuous quiet period (seconds)',60,'range(10,600)','For quiet-only channel changes and sustained-quiet scanning, traffic must remain below the threshold for this period. A single quiet sample is insufficient.');
  o=s.taboption('general',form.Flag,'preference_enabled',_('Enable preferred-radio steering'),_('Requires full wpad/hostapd with 802.11k/v support and usteer. While enabled, competing usteer steering rules are held passive. The shared controller restores previous rules when it stops, preserving administrator changes. Channel planning also keeps usteer passive.'));o.rmempty=false;o.uciconfig='radio_prefer';o.ucisection='main';o.ucioption='enabled';
  o=s.taboption('clients',form.ListValue,'preferred_radio',_('Radio to prefer'),_('Choose the radio with the capabilities and coverage you want to prefer. On a WRT3200ACM, radio0 is normally the main 5 GHz radio. The preferred AP must use the same Wi-Fi name, security credentials and LAN as the client\'s current AP.'));
  o.uciconfig='radio_prefer';o.ucisection='main';o.retain=true;o.depends('preference_enabled','1');
  o.value('',_('Select a radio'));uci.sections('wireless','wifi-device').forEach(function(r){o.value(r['.name'],r['.name']+' ('+(r.band=='2g'?'2.4':'5')+' GHz)');});
  o.validate=function(section,v){return this.map.lookupOption('radio_prefer.main.preference_enabled',section)[0].formvalue(section)!='1'||v?true:_('Select a preferred radio.');};o.rmempty=false;
  function value(name,title,def,type,description){var v=s.taboption('clients',form.Value,name,_(title),_(description));v.uciconfig='radio_prefer';v.ucisection='main';v.retain=true;if(name=='settle_time')v.depends('preference_enabled','1');v.default=String(def);v.datatype='and(integer,'+type+')';v.rmempty=false;}
  value('settle_time','Wait after a client connects (seconds)',30,'range(10,300)','Lets a new connection settle before asking the client to measure or roam again.');
  value('cooldown','Wait between steering attempts (seconds)',300,'range(60,3600)','300 is five minutes per client and destination radio, shared by preference and channel handoffs. Stages within one attempt use the shared handoff window. One post-operation return attempt may bypass this pause.');
  value('max_attempts','Maximum steering attempts before a longer pause',3,'range(1,10)','After this many attempts toward the same radio, both paths pause for this count multiplied by the attempt interval. The budget expires automatically; channel changes do not erase it. Forced disconnections additionally share one five-minute budget per client.');
  val('clients','handoff_wait','Time allowed for client handoff (seconds)',90,'range(60,300)','The first third allows a gentle request; the second can use a stronger request; the final third allows the decisive step if selected below. This window also applies to preferred-radio steering. Live CSA does not need a handoff. Without a compatible destination, skip this wait and use brief reconnection if enabled below.');
  o=s.taboption('clients',form.ListValue,'handoff_escalation',_('Client steering strength'),_('One shared policy applies to preferred-radio steering and channel/radar handoffs on every radio. A healthy AP on the same network and a compatible band must be available. Decisive mode can briefly interrupt the selected client; it verifies reconnection elsewhere before using the emptied radio. The same escalation timing, protected-client rules and retry budgets apply to both paths. Missing target measurements still permit Strong warnings; Decisive requires a qualifying target measurement or strong same-band source signal. The separate brief-reconnect option can restart a radio with clients after any handoff mode.'));
  o.value('gentle',_('Gentle'));o.value('strong',_('Strong'));o.value('decisive',_('Decisive'));o.default='decisive';o.rmempty=false;
  o=s.taboption('clients',form.Flag,'allow_reconnect',_('Change channel even if handoff cannot finish'),_('Shared Automatic policy for every radio: first try a compatible handoff, then restart only the changing radio if clients remain. With no compatible AP, skip the impossible handoff. Clients briefly disconnect and reconnect to the same Wi-Fi network. Allow a 60-second grace period for missing clients. Verify recovery using available probes, traffic and associations; persistent failure restores the previous channel. Protected clients and explicit quiet-only or empty-only policies still apply.'));o.default='1';o.rmempty=false;
  o=s.taboption('clients',form.DynamicList,'protected_clients',_('Clients protected from automatic handoff'),_('Enter one device\'s Wi-Fi MAC address, for example 02:11:22:33:44:55. Find it under Network → Wireless → Associated Stations, in the MAC address column. Use the address shown for this Wi-Fi network; phones may use a private address. Do not enter an IP address or device name. Click + to add the address to the list, then enter another if needed. Use the remove control beside an entry to delete it. Save & Apply saves your changes. Leave the list empty if no clients need protection. Neither controller automatically asks these clients to roam or forcibly disconnects them. An AP needing a restart stays put while they are attached. This does not prevent scans, announced channel switches (CSA), or mandatory radar evacuation.'));o.datatype='macaddr';o.rmempty=true;
  val('advanced','verify_unprobed','Observe unprobeable clients after a move (seconds)',180,'range(150,600)','Before a switch, up to eight clients with private DHCP addresses are checked for reachability. Previously responsive clients must respond afterwards. Clients without a usable probe need this longer association watch because drivers may retain stale associations. A sustained service failure starts bounded recovery on the affected radio. Fresh bidirectional traffic can establish service even when ICMP is filtered.');
  val('clients','handoff_target_min','Minimum measured destination signal (dBm)',-72,'range(-90,-30)','A fresh weak destination measurement blocks both requests and forced moves. Missing measurements still allow Gentle and Strong requests. Decisive disconnection then requires the same-band source-signal check below. Less negative means stronger.');
  val('clients','handoff_source_min','Required current signal when destination is unmeasured (dBm)',-65,'range(-90,-30)','Used only for Decisive disconnection when no qualifying destination measurement is available. A strong source signal is a proximity estimate only between co-located radios on the same band. It never authorizes an unmeasured 2.4-to-5 GHz disconnect. A fresh weak destination report still blocks the move.');
  o=s.taboption('scan',form.ListValue,'dfs_mode',_('Use radar-shared channels'),_('DFS means Dynamic Frequency Selection. Prepare mode lets the coordinator use available radar-shared spectrum after required clearance, leave when radar is detected, and reconsider it when the kernel permits. The kernel and hostapd enforce listening, evacuation and exclusion periods under the configured country. Global and radio DFS regions must be known and match. Set the actual country on every radio; factory restrictions remain in force.'));
  o.value('off',_('Exclude DFS'));o.value('available',_('Already cleared only'));o.value('prepare',_('Prepare with a spare radio'));o.default='prepare';o.rmempty=false;
  o=s.taboption('scan',form.ListValue,'dfs_helper',_('Radio used for radar listening'),_('Only an empty, compatible 5 GHz radio can listen. When permitted, the coordinator first uses the shared client-steering policy to empty the helper. The spare temporarily stops offering its regular network during the radar check, then restores it before the main radio moves. If clients stay, preparation waits. A fixed selection is not substituted when unavailable; Automatic can choose another compatible helper.'));
  o.retain=true;o.depends('dfs_mode','prepare');o.value('',_('Automatic'));radios.filter(function(r){return r.band!='2g';}).forEach(function(r){o.value(r['.name'],radioName(r));});o.rmempty=true;
  o=s.taboption('scan',form.ListValue,'scan_policy',_('Which radios may scan?'),_('Scanning briefly takes a radio away from its serving channel. Empty-radio scanning offers the least disruption. Radar preparation always requires an empty radio regardless of this setting.'));
  o.value('paced',_('Paced while serving'));o.value('idle',_('Empty radios only'));o.value('low_traffic',_('Quiet radios too'));o.default='paced';o.rmempty=false;
  val('scan','scan_duty','Maximum scan duty on a serving radio (%)',10,'range(1,30)','Each measured off-channel visit is followed by enough serving time to respect this budget. Empty radios are preferred. Steady traffic does not permanently block coverage.').depends('scan_policy','paced');
  val('scan','scan_gap','Serving time between scan visits (seconds)',3,'range(1,30)','Paced scans visit one frequency at a time. A radio with clients gets at least this much time back on its serving channel before another visit; another radio can scan meanwhile.').depends('scan_policy','paced');
  o=s.taboption('scan',form.ListValue,'scanner',_('Survey radio'),_('Automatic selection prefers empty radios, then estimates the client capacity interrupted by each scan. A fixed scanner can leave other bands unmeasured; it is never silently substituted. It waits for the least-cost scanner during its serving gap; another ready band may be scanned meanwhile.'));
  o.value('',_('Choose automatically'));radios.forEach(function(r){o.value(r['.name'],radioName(r));});o.rmempty=true;
  o=s.taboption('scan',form.ListValue,'scan_type',_('Survey method'),_('Active scans send broadcast probes only where permitted. DFS and other restricted frequencies are always scanned passively.'));
  o.value('passive',_('Passive listening'));o.value('active',_('Active where permitted'));o.default='active';o.rmempty=false;
  val('scan','max_age','Oldest usable survey (seconds)',900,'range(60,7200)','Limits survey duration, usable evidence age and pending plan validity. It also sets the initial wait after inconclusive verification or a refused width; repeated width refusals back off up to six hours. Too short for a complete survey can prevent planning. An unmeasured channel is unknown, not assumed empty.');
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
   v=q.taboption('advanced',form.ListValue,'width_method',_('When channel width also changes'),_('Auto selects a method independently, including restart for tested WRT width changes. This method also applies to 2.4 GHz HT40 channel moves, which need a restart for hostapd coexistence checks. Explicit CSA cannot bypass that check. Follow channel method uses the resolved channel-change method. Explicit choices remain fixed.'));
   v.value('auto',_('Automatic'));v.value('inherit',_('Follow channel method'));v.value('csa',_('Announce switch (CSA)'));v.value('idle_reconfigure',_('Restart radio'));v.default='auto';v.rmempty=false;
   v=q.taboption('general',form.Value,'channels',_('Candidate primary channels'),_('Auto uses all driver-allowed primary channels. Or enter channel numbers separated by spaces. Width is chosen separately; driver and regulatory limits always apply.'));
   v.default='auto';v.placeholder='auto';v.validate=function(section,x){x=x.trim();return x=='auto'||/^\d+(\s+\d+)*$/.test(x)&&x.split(/\s+/).every(function(c){return +c>=1&&+c<=(two?14:184);})?true:_('Enter auto or valid channel numbers separated by spaces.');};v.rmempty=false;
   v=q.taboption('general',form.Value,'widths',_('Candidate widths (MHz)'),_('Auto follows this radio\'s advertised HT/VHT widths in its current band. Or enter widths separated by spaces. Legal channel blocks, radar clearance and 2.4 GHz coexistence still apply. The applied status lists driver capabilities and unavailable requests. Extra width earns value where usable; a cleaner narrower placement can win on joint service. Scores estimate hardware capacity for present and future clients, not measured speed.'));
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
  return m.render().then(function(node){updateGuidance();node.addEventListener('change',updateGuidance);node.addEventListener('input',updateGuidance);return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),node]);});
 }
});
