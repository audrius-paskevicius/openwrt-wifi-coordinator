'use strict';
'require baseclass';
'require form';
'require uci';
'require fs';
'require poll';
'require wifi-coordinator.time as timefmt';
var retentionChoices=[1,3,6,12,24,48,72,96,120];
var saveChoices=[15,30,60,180,360];
function saveLabel(minutes){return minutes<60?minutes+' minutes':minutes%60?minutes+' minutes':(minutes/60)+' hour'+(minutes==60?'':'s');}
async function readStorage(){
 var errors=[],ram={},files=[];
 try { var raw=await fs.read_direct('/tmp/wifi-coordinator-history.json','text');ram=JSON.parse(raw);ram.ram_bytes=new TextEncoder().encode(raw).length; }
 catch(e){if(e.name!='NotFoundError'&&!/No such file/i.test(e.message||''))errors.push('Cannot read recent history storage: '+(e.message||e));}
 try {var index=JSON.parse(await fs.read_direct('/etc/wifi-coordinator/history-index.json','text'));files=index.blocks.concat(index.tail?[index.tail]:[]);}
 catch(e){try {files=(await fs.list('/etc/wifi-coordinator/')).filter(function(f){return f.type=='file'&&/^batch-[0-9]+\.json$/.test(f.name);});}
 catch(e){if(e.name!='NotFoundError'&&!/No such file/i.test(e.message||''))errors.push('Cannot list history storage: '+(e.message||e));}}
 return Object.assign({},ram,{archive_bytes:files.reduce(function(n,f){return n+(f.size||0);},0),archive_files:files.length,read_errors:errors});
}
return baseclass.extend({
 read:readStorage,
 addOptions:function(s,tab,initial){
  var retain=Math.max(1,Math.min(120,Number(uci.get('channel_coordinator','main','history_hours'))||24));
  var saveMinutes=Math.max(15,Math.min(360,Number(uci.get('channel_coordinator','main','history_save_minutes'))||360));
  var o=s.taboption(tab,form.Flag,'history_enabled',_('Record Wi-Fi history'),_('Turn off to pause new recording. Existing graphs and actions are kept until their retention period expires. Use Clear recorded history to delete them.'));o.default='1';o.rmempty=false;
  o=s.taboption(tab,form.ListValue,'history_hours',_('Retain up to this many hours'),_('Limits the history available to view and export. Reducing this period removes access to older observations.'));o.default='24';o.datatype='range(1,120)';o.rmempty=false;o.cfgvalue=function(){return String(retain);};
  var configured=retentionChoices.slice();if(configured.indexOf(retain)<0)configured.push(retain);configured.sort(function(a,b){return a-b;}).forEach(function(h){o.value(String(h),h+' hour'+(h==1?'':'s'));});
  o=s.taboption(tab,form.ListValue,'history_save_minutes',_('Save history to flash every'),_('Recent observations are buffered in RAM. Shorter save intervals reduce the history exposed to sudden power loss, but write to flash more often: 30 minutes allows up to 48 scheduled saves per day; 6 hours allows 4. Unsaved observations since the last successful save may be lost. Failed saves or stalled recording can cause longer gaps. This changes neither measurement frequency nor retention, channel decisions or radar-memory saves. If retention is shorter, saving uses that shorter interval. An orderly shutdown also attempts to save pending history.'));o.default='360';o.datatype='and(integer,range(15,360))';o.rmempty=false;o.cfgvalue=function(){return String(saveMinutes);};
  var saves=saveChoices.slice();if(saves.indexOf(saveMinutes)<0)saves.push(saveMinutes);saves.sort(function(a,b){return a-b;}).forEach(function(minutes){o.value(String(minutes),saveLabel(minutes)+(minutes==360?' (default)':''));});
  o=s.taboption(tab,form.Flag,'clear_history',_('Clear recorded history'),_('Delete recorded graphs, surveys and actions from RAM and flash when settings are applied. This switch resets itself. Recording follows the setting above; radar-avoidance memory is preserved.'));o.default='0';o.rmempty=false;
  var storageBody=E('div'),storageDetails=E('details',{'class':'wc-history-storage'},[E('summary',{},_('History storage')),storageBody]);
  function redrawStorage(h){
   var nodes=(h.read_errors||[]).map(function(e){return E('p',{'class':'alert-message warning'},e);});
   nodes.push(E('p',{},'Memory: '+Math.round((h.ram_bytes||0)/1024)+' / 1024 KiB. Saved history: '+((h.archive_bytes||0)/1048576).toFixed(2)+' MiB.'));
   nodes.push(E('p',{},(h.archive_saved?'Last saved: '+timefmt.stamp(h.archive_saved)+'. ':'No saved archive yet. ')+(h.archive_next?'Next save due: '+timefmt.stamp(h.archive_next)+'.':'')));
   nodes.push(E('p',{'class':'wc-caption'},'Active save interval: '+saveLabel((h.archive_interval||Math.min(saveMinutes*60,retain*3600))/60)+'. Pending history is also saved during an orderly shutdown.'));
   if(h.archive_error)nodes.push(E('p',{'class':'alert-message warning'},h.archive_error));
   if(h.dropped_records)nodes.push(E('p',{'class':'alert-message warning'},h.dropped_records+' records were dropped because the recent RAM buffer filled before a successful offload.'));
   storageBody.replaceChildren.apply(storageBody,nodes);
  }
  redrawStorage(initial||{});
  poll.add(function(){return readStorage().then(redrawStorage);},60);
  o=s.taboption(tab,form.DummyValue,'_history_storage',_('Storage status'));
  o.renderWidget=function(){return storageDetails;};o.write=function(){};o.remove=function(){};
 }
});
