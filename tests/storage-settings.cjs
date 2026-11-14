'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
const source=fs.readFileSync(path.join(__dirname,'../channel-coordinator/files/wifi-storage.js'),'utf8');
function E(tag,attrs,children){return {tag,attrs,children,replaceChildren(...nodes){this.children=nodes;},appendChild(node){this.children.push(node);},remove(){}};}
async function render(config,runtime={}){
 const options=[];
 class FormMap {
  section(){return {option(type,name,title,description){const o={option:name,title,description,choices:[],value(value,label){this.choices.push([value,label]);}};options.push(o);return o;}};}
  render(){return Promise.resolve(E('form',{},[]));}
 }
 const page=new Function('view','disclaimer','form','uci','fs','poll','help','timefmt','E','_','L',source)(
  {extend:o=>o},{},{Map:FormMap},{get:(c,s,k)=>config[k]}, {},{add(){}},{compact(){}},{stamp:t=>String(t)},E,s=>s,{resource:s=>s});
 const node=await page.renderPage([null,runtime]);return {options,node};
}
(async()=>{
 const defaults=await render({});let option=defaults.options.find(o=>o.option==='history_save_minutes');
 assert.equal(option.cfgvalue(),'360');assert.equal(option.default,'360');assert.equal(option.rmempty,false);
 assert.equal(option.datatype,'and(integer,range(15,360))');
 assert.deepEqual(option.choices.map(x=>x[0]),['15','30','60','180','360']);
 for(const text of ['RAM','flash','power loss','48','Failed saves','measurement frequency','retention','radar-memory','orderly shutdown'])assert(option.description.includes(text),text);
 const custom=await render({history_save_minutes:'45',history_hours:'120'},{archive_interval:1800,archive_saved:100,archive_next:1900});
 option=custom.options.find(o=>o.option==='history_save_minutes');assert.equal(option.cfgvalue(),'45');assert(option.choices.some(x=>x[0]==='45'));
 const rendered=JSON.stringify(custom.node);assert(rendered.includes('Active save interval: 30 minutes'),'status reflects active daemon schedule');assert(rendered.includes('Next save due: 1900'));
 const short=await render({history_save_minutes:'360',history_hours:'1'});assert(JSON.stringify(short.node).includes('Active save interval: 1 hour'));
 assert(short.options.find(o=>o.option==='history_save_minutes').description.includes('If retention is shorter'));
 console.log('PASS: storage save choices, preserved defaults/custom values, loss/write explanations and active interval display');
})().catch(e=>{console.error(e);process.exitCode=1;});
