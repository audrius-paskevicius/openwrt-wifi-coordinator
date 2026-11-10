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
 'cooldown':'Waiting before another steering attempt',
 'gentle-request':'Gentle request sent; observing the client',
 'strong-request':'Escalated request; observing the client',
 'no-request-support':'Client cannot receive requests; Decisive still requires signal and retry eligibility',
 'checking-reconnection':'Checking reconnection after a bounded disconnect',
 'disconnect-not-eligible':'Disconnect withheld by signal or retry limits',
 'stayed-elsewhere':'Client remained connected elsewhere',
 'return-not-observed':'Return not observed; temporary restriction released',
 'steering-cancelled':'Steering stopped because conditions changed',
 'attempt-limit':'Attempt limit reached for this episode',
 'unsupported':'Client does not advertise 802.11v roaming support',
 'recommend-unmeasured':'Gentle recommendation; destination measurement unavailable',
 'coordinator-reservation':'Radio reserved by channel coordination',
 'client-placement-cooldown':'This client recovered elsewhere; avoiding the previous placement temporarily',
 'target-unavailable':'Preferred AP information unavailable','target-busy':'Preferred AP busy or full','no-measurement-support':'Client cannot provide the required beacon measurement',
 'no-matching-target':'No available preferred AP with matching network and security'
};
return view.extend({
 load:function(){return Promise.all([uci.load('radio_prefer'),uci.load('wireless'),readState(),services('channel-coordinator')]);},
 render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));},
 renderPage:function(data){
  var status=E('p',{'class':'wc-status'}),clients=E('div');
  function refresh(st,svc){
   var running=uci.get('radio_prefer','main','enabled')==='1'&&Object.values(((svc||{})['channel-coordinator']||{}).instances||{}).some(function(i){return i.running;});
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
  poll.add(function(){return Promise.all([readState(),services('channel-coordinator')]).then(function(x){refresh(x[0],x[1]);});},5);
  var intro=E('div',{},[
   E('h2',{},_('Wi-Fi Coordinator: clients')),
   E('p',{},_('Preferred-radio steering and radar/channel handoffs use the same Gentle / Strong / Decisive policy. Every attempt starts gently. Strong adds a warning after one third of the handoff window; Decisive may disconnect an eligible remaining client after two thirds, with a 20-second return restriction. Missing measurements do not suppress the stronger warning. Fresh weak measurements block the attempt.')),
   E('p',{},_('During channel work, preference pauses only on reserved radios. A completed preferred-radio operation allows one extra return attempt using the shared escalation policy. Return is observed for two minutes. Other radios continue independently. usteer supplies measurements and neighbour information; this package owns steering decisions.')),
   status,clients,E('p',{},E('a',{href:L.url('admin/network/wifi_coordinator/channels')},_('Shared client steering policy'))),
   E('p',{},_('802.11k supplies signal measurements; 802.11v carries roaming recommendations. A client may support one, both, or neither. Decisive mode can force a bounded disconnect. Without a fresh destination measurement, this requires strong source signal on the same band. It never assumes that a 2.4 GHz client supports 5 GHz. Protected clients are excluded; unsuccessful attempts leave the original AP available.'))
  ]);
  var m=new form.Map('radio_prefer',_('Client steering settings'),_('These settings choose a preferred radio. The shared steering strength, handoff window, signal thresholds and protected-client list are on Channels / Clients. Retry settings below apply to both paths. Status refreshes every five seconds without changing unsaved settings.'));
  var s=m.section(form.NamedSection,'main','radio_prefer');s.anonymous=true;
  var o=s.option(form.Flag,'enabled',_('Enable preferred-radio steering'),_('Requires full wpad/hostapd with 802.11k/v support and usteer. While enabled, competing usteer steering rules are held passive. The shared controller restores previous rules when it stops, preserving administrator changes. Channel planning also keeps usteer passive.'));o.rmempty=false;
  o=s.option(form.ListValue,'preferred_radio',_('Radio to prefer'),_('Choose the radio with the capabilities and coverage you want to prefer. On a WRT3200ACM, radio0 is normally the main 5 GHz radio. The preferred AP must use the same Wi-Fi name, security credentials and LAN as the client\'s current AP.'));
  o.value('',_('Select a radio'));uci.sections('wireless','wifi-device').forEach(function(r){o.value(r['.name'],r['.name']+' ('+(r.band=='2g'?'2.4':'5')+' GHz)');});
  o.validate=function(section,v){return this.map.lookupOption('enabled',section)[0].formvalue(section)!='1'||v?true:_('Select a preferred radio.');};o.rmempty=false;
  function value(name,title,def,type,description){var v=s.option(form.Value,name,_(title),_(description));v.default=String(def);v.datatype='and(integer,'+type+')';v.rmempty=false;}
  value('settle_time','Wait after a client connects (seconds)',30,'range(10,300)','Lets a new connection settle before asking the client to measure or roam again.');
  value('cooldown','Wait between steering attempts (seconds)',300,'range(60,3600)','300 is five minutes per client and destination radio, shared by preference and channel handoffs. Stages within one attempt use the shared handoff window. One post-operation return attempt may bypass this pause.');
  value('max_attempts','Maximum steering attempts before a longer pause',3,'range(1,10)','After this many attempts toward the same radio, both paths pause for this count multiplied by the attempt interval. The budget expires automatically; channel changes do not erase it. Forced disconnections additionally share one five-minute budget per client.');
  help.compact(m);
  return m.render().then(function(node){return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),intro,node]);});
 }
});
