#!/usr/bin/env python3
"""Build an isolated browser integration fixture using the target router's LuCI.

Usage: python3 scripts/prepare-browser-check.py RESOURCE_DIR OUTPUT_HTML
RESOURCE_DIR contains luci.js, form.js, ui.js and cascade.css downloaded from LuCI.
No router configuration, credentials or browser profile are used by the fixture.
"""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
resources = Path(sys.argv[1])
output = Path(sys.argv[2])

def portion(text, begin, end):
    start = text.index(begin)
    return text[start:text.index(end, start)]

form = (resources / 'form.js').read_text(encoding='utf-8')
ui = (resources / 'ui.js').read_text(encoding='utf-8')
luci = (resources / 'luci.js').read_text(encoding='utf-8')
methods = {
    'append': portion(luci, 'append(node,children){', ',content(node,children){'),
    'frame': portion(form, 'renderFrame(section_id,in_table,option_index,nodes){', ',renderWidget(section_id,option_index,cfgvalue){'),
    'section': portion(form[form.index('const CBINamedSection='):], 'renderContents(data){', ',render(){'),
    'show': portion(ui, 'showTooltip(ev){', ',hideTooltip(ev){'),
    'hide': portion(ui, 'hideTooltip(ev){', ',addNotification(')
}
sources = {name: (root / file).read_text(encoding='utf-8') for name, file in [
    ('time', 'channel-coordinator/files/wifi-coordinator.time.js'),
    ('help', 'channel-coordinator/files/wifi-coordinator.help.js'),
    ('channels', 'channel-coordinator/files/wifi-channels.js'),
    ('comparison', 'channel-coordinator/files/wifi-comparison.js'),
    ('clients', 'radio-prefer/files/wifi-clients.js'),
    ('history', 'channel-coordinator/files/wifi-history.js'),
    ('storage', 'channel-coordinator/files/wifi-storage.js')
]}
payload = json.dumps({'methods': methods, 'sources': sources}).replace('</', '<\\/')
style = (resources / 'cascade.css').read_text(encoding='utf-8') + '\n' + (root / 'wifi-coordinator/wifi-coordinator.css').read_text(encoding='utf-8')
script = r'''
const result=document.getElementById('result');
function assert(ok,message){if(!ok)throw Error(message);}
String.prototype.format=function(...args){let i=0;return this.replace(/%s/g,()=>args[i++]);};
function E(tag,attrs,children){
 const node=document.createElement(tag);
 Object.entries(attrs||{}).forEach(([k,v])=>{if(v==null)return;if(typeof v==='function')node.addEventListener(k,v);else node.setAttribute(k,typeof v==='object'?JSON.stringify(v):v);});
 dom.append(node,children);return node;
}
const dom={append:eval('({'+payload.methods.append+'})').append,elem:x=>x instanceof Node,bindClassInstance:()=>{}};
const L={Class:{extend:o=>o},resource:()=>'',bind:(f,self,...a)=>f.bind(self,...a),env:{sessionid:'synthetic-session'}};
const _=x=>x;
const findParent=(n,s)=>n&&n.closest?n.closest(s):null;
const tooltipDiv=document.body.appendChild(E('div',{'class':'cbi-tooltip'}));let tooltipTimeout=null;
const ui={...eval('({'+payload.methods.show+'})'),...eval('({'+payload.methods.hide+'})')};
// These are the actual UI module's document-level hover/focus registrations.
document.addEventListener('mouseover',ui.showTooltip.bind(ui),true);
document.addEventListener('mouseout',ui.hideTooltip.bind(ui),true);
document.addEventListener('focus',ui.showTooltip.bind(ui),true);
document.addEventListener('blur',ui.hideTooltip.bind(ui),true);
const help=new Function('E','L','_','document','ui','window',payload.sources.help)(E,L,_,document,ui,window);
const renderFrame=eval('({'+payload.methods.frame+'})').renderFrame;
const renderContents=eval('({'+payload.methods.section+'})').renderContents;
const maps=[],polls=[];
class Option{
 constructor(section,type,name,title,description){Object.assign(this,{section,map:section.map,type,option:name,title,description,values:[],dependencies:[]});}
 value(key,label){this.values.push([key,label]);}
 depends(key,value){this.dependencies.push([key,value]);}
 transformDepList(){return [];}
 cbid(sid){return this.map.config+'.'+sid+'.'+this.option;}
 handleValueChange(){}
 render(){const widget=this.values.length?E('select',{},this.values.map(v=>E('option',{value:v[0]},v[1]))):E('input',{type:this.type==='flag'?'checkbox':'text',value:this.default||''});return renderFrame.call(this,this.section.section,false,0,widget);}
}
class Section{
 constructor(map,name,type,title,description){Object.assign(this,{map,section:name,sectiontype:type,title,description,children:[]});}
 tab(){}
 option(...args){const o=new Option(this,...args);this.children.push(o);return o;}
 taboption(tab,...args){return this.option(...args);}
 renderContents(data){return renderContents.call(this,data);}
 render(){return this.renderContents([{},this.children.map(o=>o.render())]);}
}
class FormMap{
 constructor(config,title,description){Object.assign(this,{config,title,description,children:[]});maps.push(this);}
 section(type,...args){const s=new Section(this,...args);this.children.push(s);return s;}
 checkDepends(){}
 render(){return Promise.resolve(E('div',{'class':'cbi-map'},[E('h2',{},this.title),E('div',{},this.description),...this.children.map(s=>s.render())]));}
}
const form={Map:FormMap,NamedSection:Section,Value:'text',ListValue:'select',Flag:'flag',DynamicList:'list'};
const radios=[{'.name':'radio0',band:'5g'},{'.name':'radio1',band:'2g'},{'.name':'radio2',band:'5g'}];
const state={updated:100,radios:{radio0:{requested_method:'auto',method:'csa',requested_width_method:'auto',width_method:'idle_reconfigure',method_reason:'Driver advertises CSA',width_reason:'Width changes require restart',rejected:[{until:700,target:{freq:5500,width:80},reason:'Synthetic connectivity failure'}]},radio1:{},radio2:{}}};
state.proposal={evaluated_at:1700000000,evaluated_uptime:90,neighbors:12,alternatives:[{radio:'radio0',channels:[36,100],widths:[80,40,20],candidates:[{channel:36,width:80,current:true,cost:7,occupancy:7,capacity:74,shared:0}]}]};
let retentionValue='200';
const uci={sections:()=>radios,get:(c,s,k)=>k==='history_hours'?retentionValue:true};
const rpc={declare:()=>()=>Promise.resolve({})};
let failState=false;
const fs={read:()=>Promise.resolve(JSON.stringify(state)),read_direct:()=>failState?Promise.reject(Error('Synthetic interruption')):Promise.resolve(JSON.stringify(state))};
const poll={add:fn=>polls.push(fn)};
const view={extend:x=>x};
const graphs={};
const timefmt=new Function('baseclass',payload.sources.time)({extend:x=>x});
function page(name){return new Function('view','form','uci','rpc','fs','poll','help','E','_','L','graphs','timefmt',payload.sources[name])(view,form,uci,rpc,fs,poll,help,E,_,L,graphs,timefmt);}
function tooltip(node){node.scrollIntoView({block:'center'});node.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));assert(tooltipDiv.style.opacity==='1','hover must open native tooltip');assert(tooltipDiv.textContent.includes(node.dataset.tooltip),'hover must expose full explanation');assert(tooltipDiv.getBoundingClientRect().right<=innerWidth+1,'tooltip must fit viewport');}
(async()=>{
 let comparisonPoll;
 for(const name of ['channels','clients','history','storage','comparison']){
  const pane=await page(name).renderPage(name==='comparison'?[null,{state:state}]:['history','storage'].includes(name)?[null,{}]:[null,null,state,{}]);
  pane.dataset.fixturePage=name;if(name==='comparison')comparisonPoll=polls[polls.length-1];
  // Fixture uses locally embedded style, never navigates to the router.
  pane.querySelectorAll('link').forEach(n=>n.remove());
  document.getElementById('pages').appendChild(pane);
 }
 const downloads=[];HTMLFormElement.prototype.submit=function(){downloads.push({action:this.getAttribute('action'),method:this.method,target:this.target,fields:Object.fromEntries(new FormData(this))});};
 const exportSection=document.querySelector('.wc-export');
 assert(exportSection.previousElementSibling.classList.contains('cbi-map'),'export follows retention');
 document.querySelector('#wc-export-period').value='6';exportSection.querySelector('[data-export-format=json]').click();
 assert(downloads[0].method==='post'&&downloads[0].fields.format==='json'&&downloads[0].fields.hours==='6','JSON uses selected window in native POST');
 assert(downloads[0].fields.sessionid==='synthetic-session'&&!downloads[0].action.includes('session'),'session is only in POST body');
 document.querySelector('#wc-export-period').value='all';document.querySelector('#wc-export-dataset').value='actions';
 exportSection.querySelector('[data-export-format=csv]').click();
 assert(downloads[1].fields.hours==='0'&&downloads[1].fields.dataset==='actions'&&downloads[1].fields.format==='csv','CSV all-retained selection');
 assert(!document.querySelector('form'),'temporary submission form removed');
 const fields=maps.flatMap(m=>m.children.flatMap(s=>s.children));
 const explanations=document.querySelectorAll('.cbi-value-description .wc-setting-help');
 assert(explanations.length===fields.filter(o=>o.description).length,'every setting description must survive the native form renderer');
 for(const node of explanations){assert(node.getBoundingClientRect().height>0,'short help must be visible');tooltip(node);}
 let node=explanations[0];
 node.parentElement.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));assert(tooltipDiv.textContent.includes(node.dataset.tooltip),'theme question icon must open help');
 node.focus();assert(tooltipDiv.style.opacity==='1','keyboard focus must open help');
 node.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));assert(tooltipDiv.style.opacity==='0','Escape must dismiss help');
 node.click();assert(tooltipDiv.style.opacity==='1','tap must open help');node.click();assert(tooltipDiv.style.opacity==='0','second tap must close help');
 const statuses=document.querySelectorAll('.cbi-section-descr .wc-caption');assert(statuses.length===3,'all three applied-method descriptions must render');
 assert(statuses[0].textContent.includes('Synthetic connectivity failure'),'temporary exclusions must be visible');
 const comparison=document.querySelector('[data-fixture-page=comparison]');
 assert(!comparison.querySelector('details'),'comparison is displayed directly');
 assert(!document.querySelector('[data-fixture-page=channels]').textContent.includes('Compare all eligible placements'),'comparison removed from Channels');
 const textNodes=document.createTreeWalker(document.getElementById('pages'),NodeFilter.SHOW_TEXT);
 while(textNodes.nextNode())assert(textNodes.currentNode.textContent.trim()!=='null','absent optional lines must not render literal null');
 const unsaved=document.querySelector('input[type="text"]');unsaved.value='unsaved edit';
 state.pending='scan';state.status='Paced survey in progress';state.updated=150;state.proposal.placements_changed=true;
 state.proposal.evaluated_at=Math.floor(Date.now()/1000)-60;
 await polls[0]();await comparisonPoll();assert(statuses[0].isConnected,'status must remain attached after polling');
 assert(comparison.querySelector('tbody').textContent.includes('36 / 80 MHz (used then)'),'previous comparison rows must remain during a survey');
 assert(comparison.textContent.includes('60 seconds')||comparison.textContent.includes('1 minutes'),'comparison age must advance');
 assert(comparison.textContent.includes('Paced survey in progress')&&comparison.textContent.includes('Radio placements have changed'),'current progress and changed placement must be explicit');
 state.proposal={...state.proposal,evaluated_uptime:150,evaluated_at:1700000060,placements_changed:false,alternatives:[{radio:'radio0',channels:[149],widths:[80],candidates:[{channel:149,width:80,current:true,cost:2,occupancy:2,capacity:78,shared:0}]}]};
 await comparisonPoll();assert(comparison.querySelector('tbody').textContent.includes('149 / 80 MHz'),'completed evaluation replaces previous rows');
 const retainedTable=comparison.querySelector('table');await comparisonPoll();assert(comparison.querySelector('table')===retainedTable,'unchanged results keep table DOM during refresh');
 failState=true;await comparisonPoll();assert(comparison.querySelector('table')===retainedTable&&!comparison.querySelector('.alert-message').hidden,'failed read retains results and warns');
 failState=false;await comparisonPoll();assert(comparison.querySelector('.alert-message').hidden,'successful refresh clears warning');
 assert(unsaved.value==='unsaved edit','polling must preserve unsaved input');
 const map=maps[0],fresh=await map.render();document.getElementById('pages').appendChild(fresh);
 const after=fresh.querySelector('.wc-setting-help');tooltip(after);after.click();assert(tooltipDiv.style.opacity==='1','delegation must survive form rerender');
 const failedHistory=await page('history').renderPage([null,{read_errors:['Synthetic unreadable recent history']}]);
 assert(failedHistory.querySelector('.alert-message.warning').textContent.includes('History is incomplete'),'failed reads must stay visible even without any radio records');
 assert(failedHistory.textContent.indexOf('History is incomplete')<failedHistory.textContent.indexOf('History is collecting'),'read failure must precede the empty-history message');
 const recent=Math.floor(Date.now()/1000);
 const historyData={periods:[{radio:'radio0',channel:36,width:80,start:recent-60,end:recent}],samples:[],events:[],surveys:[],ram_bytes:100,archive_bytes:0,archive_files:0};
 graphs.channelChart=graphs.clientChart=graphs.trafficChart=()=>({destroy(){}});
 graphs.clientFinStyle=()=>'';
 graphs.colour=()=>'#005dff';graphs.patternStyle=()=>'';graphs.patternName=()=>'diagonal lines';graphs.radarGradient=()=> '#fff';
 fs.list=async()=>[];fs.read_direct=async path=>JSON.stringify(path.includes('state')?state:historyData);
 const historyPane=await page('history').renderPage([null,historyData]);
 historyPane.querySelectorAll('link').forEach(n=>n.remove());document.getElementById('pages').appendChild(historyPane);
 assert(!historyPane.querySelector('.wc-history-storage')&&!historyPane.querySelector('.wc-export')&&!historyPane.querySelector('.cbi-map'),'History contains graphs and actions only');
 assert(page('history').handleSaveApply===null,'History has no save controls');
 const show=historyPane.querySelector('select');show.value='24';show.dispatchEvent(new Event('change'));
 const storagePane=await page('storage').renderPage([null,historyData]);
 storagePane.querySelectorAll('link').forEach(n=>n.remove());document.getElementById('pages').appendChild(storagePane);
 const storage=storagePane.querySelector('.wc-history-storage');assert(!storage.open,'storage diagnostics start collapsed');
 storage.open=true;await polls[polls.length-1]();assert(storage.open,'expanded storage diagnostics survive refresh');
 assert(storagePane.querySelector('#wc-export-period').value==='all','export defaults to all, independent of History');
 storagePane.querySelector('#wc-export-period').value='12';
 storagePane.querySelector('.wc-export button').click();assert(downloads[downloads.length-1].fields.hours==='12','export posts its own window independently');
 retentionValue='12';
 const cappedHistory=await page('history').renderPage([null,{}]);
 const cappedStorage=await page('storage').renderPage([null,{}]);
 assert(Math.max(...Array.from(cappedHistory.querySelector('select').options,o=>Number(o.value)))===12,'History Show capped by saved retention');
 assert(Math.max(...Array.from(cappedStorage.querySelector('#wc-export-period').options,o=>Number(o.value)||0))===12,'Export Period capped by same retention independently');
 result.textContent='PASS: '+explanations.length+' setting descriptions rendered through actual LuCI Value/NamedSection methods; native hover, icon hover, focus, tap, Escape, status polling and form rerender passed.';
 result.dataset.status='pass';
 // Leave one useful example visible in the screenshot.
 window.scrollTo(0,0);const first=document.querySelector('.wc-setting-help');first.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));
})().catch(e=>{result.textContent='FAIL: '+e.stack;result.dataset.status='fail';});
'''
output.write_text('<!doctype html><meta charset="utf-8"><title>LuCI integration check</title><style>' + style + '\nbody{padding:24px}#result{position:sticky;top:0;z-index:2000;background:#fff;color:#111;padding:12px;white-space:pre-wrap}</style><pre id="result">RUNNING</pre><main id="pages"></main><script>const payload=' + payload + ';\n' + script + '</script>', encoding='utf-8')
print('Prepared native LuCI browser fixture: ' + str(output))
