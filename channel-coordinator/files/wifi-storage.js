'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';
'require uci';
var retentionChoices=[1,3,6,12,24,48,72,96,120];
return view.extend({
 handleSaveApply:null,handleSave:null,handleReset:null,
 load:function(){return uci.load('channel_coordinator');},
 render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));},
 renderPage:function(){
  var retain=Math.max(1,Math.min(120,Number(uci.get('channel_coordinator','main','history_hours'))||24));
  var configured=retentionChoices.slice();if(configured.indexOf(retain)<0)configured.push(retain);configured.sort(function(a,b){return a-b;});
  var exportPeriod=E('select',{'class':'cbi-input-select','id':'wc-export-period'},[
   E('option',{value:'all'},_('All retained history'))
  ]);
  configured.filter(function(h){return h<=retain;}).forEach(function(h){exportPeriod.appendChild(E('option',{value:h},_('Last ')+h+(h==1?_(' hour'):_(' hours'))));});
  var exportDataset=E('select',{'class':'cbi-input-select','id':'wc-export-dataset'},[
   ['periods','Channel placements'],['clients','Client counts'],['traffic','Traffic summaries'],['surveys','Spectrum surveys'],['radar','Radar detections'],['actions','Recent actions']
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
   E('p',{'class':'wc-caption'},_('Choose one dataset for CSV, or download all datasets as JSON. Export timestamps use UTC.')),
   E('p',{},[E('label',{'for':'wc-export-period'},_('Period: ')),exportPeriod]),
   E('p',{},[E('label',{'for':'wc-export-dataset'},_('CSV data: ')),exportDataset,' ',E('button',{type:'button','class':'cbi-button cbi-button-action','data-export-format':'csv','aria-label':_('Download CSV data'),click:function(){download('csv');}},_('Download'))]),
   E('p',{},[_('JSON data: All graph data and actions '),E('button',{type:'button','class':'cbi-button cbi-button-action','data-export-format':'json','aria-label':_('Download JSON data'),click:function(){download('json');}},_('Download'))]),
   E('iframe',{name:'wc-history-download',title:_('Export download status'),'class':'wc-export-status'})
  ]);
  return E('div',{'class':'wifi-coordinator'},[
   E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),E('h2',{},_('Wi-Fi Coordinator: export')),exportSection
  ]);
 }
});
