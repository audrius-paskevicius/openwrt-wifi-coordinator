'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';
'require form';
'require uci';
'require rpc';
'require fs';
'require poll';
'require wifi-coordinator.help as help';

var services=rpc.declare({object:'service',method:'list',params:['name'],expect:{'':{}}});
function readState(){return fs.read('/tmp/radio-prefer-state.json').then(JSON.parse).catch(function(){return {};});}
var reasons={
 'protected':'Protected from automatic roaming in Channels / Protect playback',
 'on-preferred-radio':'Already on the preferred radio',
 'settling':'Allowing this connection to settle',
 'measure':'Requesting a fresh signal measurement',
 'await-measurement':'Waiting up to one minute for the client to report the target signal',
 'target-weak':'Preferred radio is below the signal threshold',
 'recommend':'Sending a roaming recommendation',
 'cooldown':'Waiting before another recommendation',
 'attempt-limit':'Attempt limit reached for this episode',
 'unsupported':'Client does not advertise 802.11v roaming support',
 'recommend-unmeasured':'Gentle recommendation; destination measurement unavailable',
 'coordinator-reservation':'Radio reserved by channel coordination',
 'client-placement-cooldown':'This client recovered elsewhere; avoiding the previous placement temporarily',
 'target-unavailable':'Preferred AP information unavailable','target-busy':'Preferred AP busy or full','no-measurement-support':'Client cannot provide the required beacon measurement',
 'no-matching-target':'No available preferred AP with matching network and security'
};
return view.extend({
 load:function(){return Promise.all([uci.load('radio_prefer'),uci.load('wireless'),readState(),services('radio-prefer')]);},
 render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));},
 renderPage:function(data){
  var status=E('p',{'class':'wc-status'}),clients=E('div');
  function refresh(st,svc){
   var running=Object.values(((svc||{})['radio-prefer']||{}).instances||{}).some(function(i){return i.running;});
   status.textContent=!running?'Client preference is stopped.':st.integration_error?'Waiting: '+st.integration_error:
    st.coordination_pause?'Channel operation has priority: '+st.coordination_pause:'Client preference is running. Preferred radio: '+(st.preferred_radio||'not selected')+'.';
   status.setAttribute('data-level',st.integration_error?'warning':'normal');
   var header=E('thead',{},E('tr',{},['Client address','Current connection','Decision','Requests sent'].map(function(x){return E('th',{'scope':'col'},_(x));}))),rows=[];
   Object.keys(st.clients||{}).forEach(function(mac){var c=st.clients[mac];rows.push(E('tr',{},[
    mac,(c.source||'Unknown').replace('hostapd.',''),(reasons[c.decision]||c.decision||'Waiting')+
     (c.decision=='client-placement-cooldown'?' ('+Math.max(0,Math.ceil((c.compatibility_until-st.updated_uptime)/60))+' minutes remaining)':''),String(c.attempts||0)
   ].map(function(x){return E('td',{},x);})));});
   clients.replaceChildren(E('div',{'class':'wc-table-wrap'},E('table',{'class':'table wc-table'},[header,E('tbody',{},rows)])));
  }
  refresh(data[2],data[3]);
  poll.add(function(){return Promise.all([readState(),services('radio-prefer')]).then(function(x){refresh(x[0],x[1]);});},5);
  var intro=E('div',{},[
   E('h2',{},_('Wi-Fi Coordinator: clients')),
   E('p',{},_('A shared Wi-Fi name lets devices roam between radios, but each device decides when to move. A fresh qualifying signal measurement permits your selected recommendation strength. Without measurement support, or after one minute without a usable report, either mode sends a gentle suggestion and lets the client judge the destination. A fresh weak-signal report blocks the recommendation.')),
   E('p',{},_('During channel preparation, normal preference pauses so it does not pull clients back while the channel controller is moving them aside. Afterwards, preference resumes. usteer supplies measurements and neighbour information; this package owns steering decisions.')),
   status,clients,
   E('p',{},_('802.11k supplies signal measurements; 802.11v carries roaming recommendations. A client may support one, both, or neither. Normal radio preference does not force disconnections. Channel-operation handoffs can use the stronger escalation policy configured on the Channels page.'))
  ]);
  var m=new form.Map('radio_prefer',_('Client steering settings'),_('These settings choose a preferred radio. Candidate channels, radar preparation and temporary handoff policy are on the Channels page. Status refreshes every five seconds without changing unsaved settings.'));
  var s=m.section(form.NamedSection,'main','radio_prefer');s.anonymous=true;
  var o=s.option(form.Flag,'enabled',_('Enable preferred-radio steering'),_('Requires full wpad/hostapd with 802.11k/v support and usteer. While enabled, competing usteer steering rules are held passive. Disabling this service restores the previous rules while preserving administrator changes.'));o.rmempty=false;
  o=s.option(form.ListValue,'preferred_radio',_('Radio to prefer'),_('Choose the radio with the capabilities and coverage you want to prefer. On a WRT3200ACM, radio0 is normally the main 5 GHz radio. The preferred AP must use the same Wi-Fi name, security credentials and LAN as the client\'s current AP.'));
  o.value('',_('Select a radio'));uci.sections('wireless','wifi-device').forEach(function(r){o.value(r['.name'],r['.name']+' ('+(r.band=='2g'?'2.4':'5')+' GHz)');});
  o.validate=function(section,v){return this.map.lookupOption('enabled',section)[0].formvalue(section)!='1'||v?true:_('Select a preferred radio.');};o.rmempty=false;
  o=s.option(form.ListValue,'mode',_('How strongly to recommend a move'),_('Gentle sends a suggestion. With a fresh qualifying signal measurement, Strong also signals that disassociation is imminent, but sets no AP disconnect timer. If measurements are unsupported or no usable report arrives within one minute, both modes send Gentle instead; the client decides whether to move. Normal cooldowns and attempt limits apply. Channel-operation handoff escalation is configured separately on the Channels page.'));
  o.value('advisory',_('Gentle recommendation'));o.value('strong',_('Stronger recommendation'));o.default='advisory';o.rmempty=false;
  function value(name,title,def,type,description){var v=s.option(form.Value,name,_(title),_(description));v.default=String(def);v.datatype='and(integer,'+type+')';v.rmempty=false;}
  value('min_rssi','Minimum signal at the preferred radio (dBm)',-67,'range(-90,-30)','Less negative means stronger: -50 dBm is stronger than -70 dBm. At -67, a measured -60 qualifies; -75 does not. A lower threshold allows moves from farther away but may reduce speed.');
  value('settle_time','Wait after a client connects (seconds)',30,'range(10,300)','Lets a new connection settle before asking the client to measure or roam again.');
  value('cooldown','Wait between recommendations (seconds)',300,'range(60,3600)','300 is five minutes per client. This avoids repeatedly disturbing a device that declines to move.');
  value('max_attempts','Maximum recommendations per episode',3,'range(1,10)','After this many attempts, requests pause for this count multiplied by the recommendation interval. The budget also resets after one minute on the preferred radio. Declining a move does not block future recommendations forever.');
  help.compact(m);
  return m.render().then(function(node){return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),intro,node]);});
 }
});
