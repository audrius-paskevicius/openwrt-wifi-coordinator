'use strict';
'require ui';

// The build inserts DISCLAIMER.txt here; acknowledgement follows the exact text,
// independently of package version. Nothing is written to the router's flash.
var text = @WIFI_COORDINATOR_DISCLAIMER_JSON@;
var key='wifi-coordinator-disclaimer',acknowledged=false;
function fullText(){
 var paragraphs=text.trim().split(/\n\s*\n/);
 return E('div',{'class':'wc-disclaimer-full'},paragraphs.map(function(p,i){return E(i?'p':'h3',{},p);}));
}
function accepted(){
 if(acknowledged)return true;
 try{return window.localStorage.getItem(key)===text;}catch(e){return false;}
}
function banner(){
 return E('aside',{'class':'wc-disclaimer-banner','aria-label':'Software risk warning'},[
  E('strong',{},'AI-generated software. No warranties. Use entirely at your own risk.'),
  E('button',{'type':'button','class':'cbi-button','click':function(){
   ui.showModal('Software disclaimer',[fullText(),E('div',{'class':'right'},[
    E('button',{'type':'button','class':'cbi-button','click':ui.hideModal},'Close')])]);
  }},'Read full disclaimer')
 ]);
}
function gate(render){
 var host=E('div',{'class':'wifi-coordinator wc-disclaimer-host'},[
  E('link',{rel:'stylesheet',href:L.resource('view/wifi-coordinator.css')+'?v=@WIFI_COORDINATOR_VERSION@'}),banner()
 ]);
 function showPage(){return Promise.resolve().then(render).then(function(page){
  host.replaceChildren(host.firstChild,banner(),page);return host;
 });}
 if(accepted())return showPage();
 var error=E('p',{'role':'alert'});
 var button=E('button',{'type':'button','class':'cbi-button cbi-button-action','click':function(){
  button.disabled=true;error.textContent='';
  acknowledged=true;
  try{window.localStorage.setItem(key,text);}catch(e){}
  return showPage().catch(function(e){button.disabled=false;error.textContent='Unable to load this page: '+e.message;});
 }},'I understand — continue');
 host.appendChild(E('section',{'class':'wc-disclaimer-gate'},[fullText(),
  E('p',{},'Acknowledgement is remembered in this browser for this router. It does not enable, disable, or change the running services.'),button,error]));
 return Promise.resolve(host);
}
return L.Class.extend({gate:gate});
