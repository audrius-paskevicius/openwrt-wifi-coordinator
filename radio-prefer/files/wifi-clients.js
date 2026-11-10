'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';
'require uci';
'require rpc';
'require fs';
'require poll';

var services=rpc.declare({object:'service',method:'list',params:['name'],expect:{'':{}}});
function readState(){return fs.read('/tmp/radio-prefer-state.json').then(JSON.parse).catch(function(){return {};});}
var reasons={
 'protected':'Protected from automatic roaming in Settings / Client steering',
 'on-preferred-radio':'Already on the preferred radio',
 'settling':'Allowing this connection to settle',
 'target-weak':'Preferred radio is below the signal threshold',
 'recommend':'Sending a roaming recommendation',
 'cooldown':'Waiting before another steering attempt',
 'gentle-request':'Gentle request sent; observing the client',
 'strong-request':'Escalated request; observing the client',
 'no-request-support':'Client cannot receive roaming requests',
 'checking-reconnection':'Checking whether the client reconnected',
 'disconnect-not-eligible':'Disconnect withheld by signal or retry limits',
 'stayed-elsewhere':'Client remained connected elsewhere',
 'return-not-observed':'Client has not returned to the preferred radio',
 'steering-cancelled':'Steering stopped because conditions changed',
 'attempt-limit':'Attempt limit reached; waiting before trying again',
 'unsupported':'Client does not advertise 802.11v roaming support',
 'coordinator-reservation':'Radio reserved by channel coordination',
 'client-placement-cooldown':'This client recovered elsewhere; avoiding the previous placement temporarily',
 'target-unavailable':'Preferred AP information unavailable','target-busy':'Preferred AP busy or full',
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
   var header=E('thead',{},E('tr',{},['Client address','Current connection','Decision','Recent attempts'].map(function(x){return E('th',{'scope':'col','title':x=='Recent attempts'?'Attempts to move this client to the preferred radio. One attempt can include several requests.':null},_(x));}))),rows=[];
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
   status,clients,E('p',{},E('a',{href:L.url('admin/network/wifi_coordinator/settings')+'#clients'},_('Client steering settings')))

  ]);
  return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),intro]);
 },
 handleSaveApply:null,handleSave:null,handleReset:null
});
