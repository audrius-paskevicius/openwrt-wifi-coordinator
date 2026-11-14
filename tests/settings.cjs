'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const options=[],sections=[],polls=[];
function E(tag,attrs,children){return {tag,attrs,children,replaceChildren(...nodes){this.children=nodes;},setAttribute(k,v){this.attrs[k]=v;},addEventListener(){}};}
class Option {
 constructor(type,name,title,description){Object.assign(this,{type,option:name,title,description,values:[],dependencies:[]});}
 cfgvalue(){return this.default;}
 formvalue(){return undefined;}
 value(key,label){this.values.push(key);}
 depends(key,value){this.dependencies.push([key,value]);}
}
class Section {
 constructor(name){this.name=name;this.children=[];this.tabs={};sections.push(this);}
 tab(name){this.tabs[name]={children:[]};}
 option(type,name,title,description,...args){if(type==='section'){const o=new Option(type,name);o.subsection=new Section(description);this.children.push(o);return o;}const o=new Option(type,name,title,description);o.section=this.name;options.push(o);this.children.push(o);return o;}
 taboption(tab,...args){const o=this.option(...args);o.tab=tab;this.tabs[tab].children.push(o);return o;}
}
class Map {
 constructor(config){this.children=[];this.config=config;}
 chain(name){this.chained=name;}
 section(type,name){const s=new Section(name);s.config=this.config;this.children.push(s);return s;}
 render(){return Promise.resolve(E('form',{},[]));}
}
const form={Map,NamedSection:Section,Value:'text',ListValue:'select',Flag:'flag',DynamicList:'list',SectionValue:'section',DummyValue:'dummy'};
const radios=[{'.name':'radio0',band:'5g'},{'.name':'radio1',band:'2g'},{'.name':'radio2',band:'5g'}];
const uci={sections:()=>radios,get:()=>true};
const state={updated:100,radios:{radio0:{requested_method:'auto',method:'csa',requested_width_method:'auto',width_method:'idle_reconfigure',method_reason:'Driver advertises CSA',width_reason:'Tested width changes require restart'},radio1:{requested_method:'csa',method:'csa',csa_recovery_left:120,rejected:[{until:220,target:{freq:2472,width:20},reason:'Client connectivity did not verify'}]}}};
const source=fs.readFileSync(path.join(root,'channel-coordinator/files/wifi-settings.js'),'utf8');
const page=new Function('view','form','uci','rpc','fs','poll','help','E','_','L','timefmt',source)(
 {extend:x=>x},form,uci,{declare:()=>()=>Promise.resolve({})},{read:()=>Promise.resolve(JSON.stringify(state))},
 {add:fn=>polls.push(fn)},{compact:()=>{},sectionStatus:(s,n)=>{s.statusNode=n;}},E,x=>x,{resource:x=>x,url:x=>x},require('./time.cjs'));
function option(name,section='main'){const o=options.find(x=>x.option===name&&x.section===section);assert(o,'Missing '+section+'.'+name);return o;}
module.exports=page.renderPage([null,null,null,state]).then(async()=>{
 const display=sections.find(s=>s.config==='wifi_coordinator_display');assert(display,'shared router graph settings have a separate UCI map');
 assert.deepEqual(display.children.map(o=>o.option),['decimation','triangles','squares','crosses','popups']);
 for(const o of display.children){assert.equal(o.type,'flag');assert.equal(o.default,'1');assert.equal(o.rmempty,false);assert(o.description.length>60);}
 for(const name of ['retry_delay','scan_wait','scan_batch','cac_timeout','csa_count','ban_seconds','wide_threshold'])assert(!options.some(x=>x.option===name));
 for(const radio of radios){
  const name=radio['.name'];
  for(const key of ['channels','widths','method','width_method'])assert.equal(option(key,name).default,'auto');
  assert.deepEqual(option('method',name).values,['auto','csa','idle_reconfigure']);
  assert(option('width_method',name).values.includes('inherit'));
  assert.equal(option('channels',name).type,'text');assert.equal(option('widths',name).type,'text');
 }
 assert.equal(option('channels','radio1').validate('', '1 9 13'),true);
 assert.notEqual(option('channels','radio1').validate('', '15'),true);
 assert.notEqual(option('channels','radio0').validate('', '36x'),true);
 assert.equal(option('widths','radio0').validate('', '20 80'),true);
 assert.equal(option('widths','radio1').validate('', '40'),true);
 assert.equal(option('widths','radio0').validate('', '160 80'),true);
 assert.notEqual(option('widths','radio1').validate('', '80'),true);
 assert.deepEqual(option('scan_gap').dependencies,[['scan_policy','paced']]);
 assert.deepEqual(option('scan_duty').dependencies,[['scan_policy','paced']]);
 assert.deepEqual(option('dfs_helper').dependencies,[['dfs_mode','prepare']]);
 assert.deepEqual(option('overlap_penalty').dependencies,[['separate_radios','0']]);
 for(const key of ['scan_gap','scan_duty','dfs_helper','overlap_penalty'])assert.equal(option(key).retain,true);
 assert.equal(option('interval').datatype,'and(integer,range(30,86400))');
 assert.equal(option('max_mbps').datatype,'range(0.01,1000)');
 assert.equal(option('verify_unprobed').tab,'advanced');
 assert.equal(option('scanner').tab,'scan');
 assert.equal(option('scanner').rmempty,true,'Automatic scanner is a valid empty selection');
 assert.equal(option('dfs_helper').rmempty,true,'Automatic helper is a valid empty selection');
 assert.equal(option('preference_enabled').uciconfig,'radio_prefer');
 assert.equal(option('preference_enabled').ucioption,'enabled');
 assert.equal(option('preference_enabled').ucisection,'main');
 const preferenceValidation={map:{lookupOption(name){assert.equal(name,'radio_prefer.main.preference_enabled');return [{formvalue:()=>'1'}];}}};
 assert.notEqual(option('preferred_radio').validate.call(preferenceValidation,'main',''),true);
 assert.equal(option('preferred_radio').validate.call(preferenceValidation,'main','radio0'),true);
 for(const key of ['preferred_radio','settle_time','cooldown','max_attempts']){
  assert.equal(option(key).uciconfig,'radio_prefer');assert.equal(option(key).ucisection,'main');
 }
 assert(!options.some(o=>o.option==='clear_stop'),'recovery action absent when healthy');
 assert.deepEqual(option('handoff_source_min').dependencies,[['handoff_escalation','decisive']]);
 assert.equal(option('handoff_source_min').retain,true);
 assert.deepEqual(option('allow_reconnect').dependencies,[[{enabled:'1',mode:'automatic'},undefined]]);
 assert(option('max_mbps').dependencies.some(d=>d[0]['channel_coordinator.radio1.occupied_policy']==='quiet'&&d[0]['channel_coordinator.radio1.managed']==='1'));
 for(const key of ['handoff_escalation','handoff_wait','handoff_target_min','handoff_source_min','cooldown','max_attempts','protected_clients'])assert.equal(option(key).tab,'clients');
 assert.equal(option('improvement').tab,'advanced');
 const main=sections.find(s=>s.name==='main');
 assert.deepEqual(main.children.filter(o=>o.tab==='clients').slice(0,4).map(o=>o.option),['preferred_radio','handoff_escalation','_steering_summary','protected_clients']);
 assert(option('improvement').description.includes('base movement cost'));
 for(const name of ['wifi-channels.js','wifi-clients.js']){
  const file=(name==='wifi-clients.js'?'radio-prefer':'channel-coordinator')+'/files/'+name;
  const text=fs.readFileSync(path.join(root,file),'utf8');
  assert(!text.includes('new form.Map'));assert(text.includes('handleSaveApply:null'));
 }
 const status=sections.find(x=>x.name==='radio1').statusNode;
 assert(JSON.stringify(status).includes('channel 13 / 20 MHz'));
 assert(JSON.stringify(status).includes('2 minutes remaining'));
 await polls[0]();
 assert(JSON.stringify(status).includes('Auto will use an alternative'));
 console.log('PASS: consolidated settings, namespace bindings, retained conditional values, recovery visibility, status-only views and refreshed constraints');
}).catch(e=>{console.error(e);process.exitCode=1;});
