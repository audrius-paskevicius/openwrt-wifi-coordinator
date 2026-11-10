'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';
'require uci';
'require rpc';
'require fs';
'require poll';
'require wifi-coordinator.time as timefmt';

var service = rpc.declare({object:'service',method:'list',params:['name'],expect:{'':{}}});
function radioName(r) { return r['.name']+' ('+(r.band=='2g'?'2.4':'5')+' GHz)'; }
function readState() { return fs.read('/tmp/channel-coordinator-state.json').then(JSON.parse).catch(function(){return {};}); }
function operationText(st) {
 return st.restart_check?(st.status||'Checking radios after interruption'):
  st.halted?'Coordination paused: '+st.halted+(st.recovery_retry_at>st.updated?' — automatic retry in '+Math.ceil(st.recovery_retry_at-st.updated)+' seconds.':' — automatic reassessment pending.'):(st.status||'No evaluation yet.');
}
function statusText(st, services) {
 if(uci.get('channel_coordinator','main','enabled')!='1')return _('Channel planning disabled.');
 var running=Object.values(((services||{})['channel-coordinator']||{}).instances||{}).some(function(i){return i.running;});
 return (running?'Running. ':'Stopped. ')+operationText(st);
}
return view.extend({
 load:function(){return Promise.all([uci.load('channel_coordinator'),uci.load('wireless'),readState(),service('channel-coordinator')]);},
 render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));},
 renderPage:function(data){
  var state=data[2];
  var status=E('p',{'class':'wc-status','data-level':state.halted&&!state.restart_check?'warning':'normal'},statusText(state,data[3]));
  var details=E('div');
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
    E('p',{},'Completed at '+timefmt.stamp(st.scan_coverage.at))
   ]));
   if(dfs){var phase={listening:'Listening for radar',restoring:'Restoring the spare radio',ready:'Completed and shared',recovered:'Restored after an interrupted check',inactive:'Previous check ended','restored-after-error':'Restored after an error'};cards.push(E('div',{'class':'wc-summary'},[
    E('h4',{},_('Last radar preparation')),E('p',{},phase[dfs.phase]||dfs.phase),
    E('p',{},'Channel '+dfs.channel+' / '+dfs.width+' MHz'+(dfs.helper?' using '+dfs.helper:'')),
    dfs.elapsed!=null?E('p',{},'Total preparation time: '+dfs.elapsed+' seconds'):''
   ]));}
   if(cards.length)items.push(E('div',{'class':'wc-summaries'},cards));
   if(st.updated)items.push(E('small',{'class':'wc-caption'},'Traffic shows current usage. Updated every 5 seconds.'));
   details.replaceChildren.apply(details,items);
  }
  refresh(state);
  poll.add(function(){return Promise.all([readState(),service('channel-coordinator')]).then(function(x){status.textContent=statusText(x[0],x[1]);status.setAttribute('data-level',x[0].halted&&!x[0].restart_check?'warning':'normal');refresh(x[0]);});},5);
  var intro=E('div',{},[
   E('h2',{},_('Wi-Fi Coordinator: channels')),
   status,details
  ]);
  return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),intro,
   E('p',{},E('a',{href:L.url('admin/network/wifi_coordinator/settings')},_('Settings')))]);
 },
 handleSaveApply:null,handleSave:null,handleReset:null
});
