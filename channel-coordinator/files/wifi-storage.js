'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';
'require form';
'require uci';
'require fs';
'require poll';
'require wifi-coordinator.help as help';
'require wifi-coordinator.time as timefmt';
var retentionChoices=[1,3,6,12,24,48,72,96,120,168,200];
async function readStorage(){
 var errors=[],ram={},files=[];
 try { var raw=await fs.read_direct('/tmp/wifi-coordinator-history.json','text');ram=JSON.parse(raw);ram.ram_bytes=new TextEncoder().encode(raw).length; }
 catch(e){if(e.name!='NotFoundError'&&!/No such file/i.test(e.message||''))errors.push('Cannot read recent history storage: '+(e.message||e));}
 try {files=(await fs.list('/etc/wifi-coordinator/')).filter(function(f){return f.type=='file'&&/^batch-[0-9]+\.json$/.test(f.name);});}
 catch(e){if(e.name!='NotFoundError'&&!/No such file/i.test(e.message||''))errors.push('Cannot list history storage: '+(e.message||e));}
 return Object.assign({},ram,{archive_bytes:files.reduce(function(n,f){return n+(f.size||0);},0),archive_files:files.length,read_errors:errors});
}
return view.extend({
 load:function(){return Promise.all([uci.load('channel_coordinator'),readStorage()]);},
 render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));},
 renderPage:function(data){
  var retain=Math.max(1,Math.min(200,Number(uci.get('channel_coordinator','main','history_hours'))||24));
  var storageBody=E('div'),storageDetails=E('details',{'class':'wc-history-storage'},[E('summary',{},_('History storage')),storageBody]);
  function redrawStorage(h){
   var nodes=(h.read_errors||[]).map(function(e){return E('p',{'class':'alert-message warning'},e);});
   nodes.push(E('small',{'class':'wc-caption'},'RAM buffer: '+Math.round((h.ram_bytes||0)/1024)+' / 1024 KiB. Flash history: '+((h.archive_bytes||0)/1048576).toFixed(2)+' MiB in '+(h.archive_files||0)+' batch file(s). Offload every 6 hours; the most recent hour stays cached in RAM. '+(h.archive_saved?'Last offload: '+timefmt.stamp(h.archive_saved)+'. ':'First offload has not happened yet. ')+(h.archive_next?'Next eligible offload: '+timefmt.stamp(h.archive_next)+'. ':'')+'Refreshes every minute. An orderly reboot saves pending history to flash. Unexpected power loss can lose recent data since the last successful offload.'));
   if(h.archive_error)nodes.push(E('p',{'class':'alert-message warning'},h.archive_error));
   if(h.dropped_records)nodes.push(E('p',{'class':'alert-message warning'},h.dropped_records+' records were dropped because the recent RAM buffer filled before a successful offload.'));
   storageBody.replaceChildren.apply(storageBody,nodes);
  }
  redrawStorage(data[1]||{});
  poll.add(function(){return readStorage().then(redrawStorage);},60);
  var m=new form.Map('channel_coordinator',_('History retention'),_('Keep history for the selected duration. Recent records stay in RAM and are saved to flash every six hours and during an orderly shutdown.'));
  var s=m.section(form.NamedSection,'main','coordinator');s.anonymous=true;
  var o=s.option(form.Flag,'history_enabled',_('Record Wi-Fi history'),_('Turn off to pause new recording. Existing graphs and actions are kept until their retention period expires. Use Clear recorded history to delete them.'));o.default='1';o.rmempty=false;
  o=s.option(form.ListValue,'history_hours',_('Retain up to this many hours'),_('Show follows this selection. Reducing retention hides older records immediately; the next scheduled offload prunes the archive without an extra flash rewrite.'));o.default='24';o.datatype='range(1,200)';o.rmempty=false;
  var configured=retentionChoices.slice();if(configured.indexOf(retain)<0)configured.push(retain);configured.sort(function(a,b){return a-b;}).forEach(function(h){o.value(String(h),h+' hour'+(h==1?'':'s'));});
  o=s.option(form.Flag,'clear_history',_('Clear recorded history'),_('Delete recorded graphs, surveys and actions from RAM and flash when settings are applied. This switch resets itself. Recording follows the setting above; radar-avoidance memory is preserved.'));o.default='0';o.rmempty=false;
  help.compact(m);
  var exportPeriod=E('select',{'class':'cbi-input-select','id':'wc-export-period'},[
   E('option',{value:'all'},_('All retained history'))
  ]);
  configured.filter(function(h){return h<=retain;}).forEach(function(h){exportPeriod.appendChild(E('option',{value:h},_('Last ')+h+(h==1?_(' hour'):_(' hours'))));});
  var exportDataset=E('select',{'class':'cbi-input-select','id':'wc-export-dataset'},[
   ['periods','Channel placements'],['traffic','Traffic summaries'],['surveys','Spectrum surveys'],['radar','Radar detections'],['actions','Recent actions']
  ].map(function(pair){return E('option',{value:pair[0]},_(pair[1]));}));
  function download(format){
   // A native POST download streams to the browser download manager. No Blob,
   // complete JS response buffer, or export file on the router is involved.
   var f=E('form',{method:'POST',action:'/cgi-bin/wifi-coordinator-export',target:'wc-history-download',style:'display:none'},
    Object.entries({sessionid:L.env.sessionid,format:format,dataset:exportDataset.value,hours:exportPeriod.value=='all'?0:Number(exportPeriod.value)}).map(function(pair){return E('input',{type:'hidden',name:pair[0],value:String(pair[1])});}));
   document.body.appendChild(f);f.submit();f.remove();
  }
  var exportSection=E('section',{'class':'wc-export'},[
   E('h3',{},_('Export history')),
   E('p',{'class':'wc-caption','title':'Read-only download: no temporary export file or flash writes. The file includes UTC timestamps, units and a final completeness report. Survey context and radar memory may start before the selected window. Original interval boundaries are preserved.'},_('Download graph data and actions directly. Times use ISO 8601 UTC.')),
   E('p',{},[E('label',{'for':'wc-export-period'},_('Period: ')),exportPeriod,' ',E('button',{type:'button','class':'cbi-button cbi-button-action',click:function(){download('json');}},_('Download all data (JSON)'))]),
   E('p',{},[E('label',{'for':'wc-export-dataset'},_('CSV data: ')),exportDataset,' ',E('button',{type:'button','class':'cbi-button cbi-button-action',click:function(){download('csv');}},_('Download CSV'))]),
   E('iframe',{name:'wc-history-download',title:_('Export download status'),'class':'wc-export-status'})
  ]);
  return m.render().then(function(node){return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),E('h2',{},_('Wi-Fi Coordinator: storage & export')),storageDetails,node,exportSection
  ]);});
 }
});
