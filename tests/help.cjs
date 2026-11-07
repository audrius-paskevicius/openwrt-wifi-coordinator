'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
function E(tag,attrs,children){return {tag,attrs:attrs||{},children,events:{},
 getAttribute(k){return this.attrs[k];},addEventListener(k,v){this.events[k]=v;}};}
const document={events:{},documentElement:{clientWidth:800},addEventListener(k,v){this.events[k]=v;}};
const calls=[],ui={showTooltip:e=>calls.push(['show',e.target]),hideTooltip:e=>calls.push(['hide',e.target])};
const api=new Function('E','L','_','document','ui','window',fs.readFileSync(path.join(__dirname,'../channel-coordinator/files/wifi-coordinator.help.js'),'utf8'))(E,{Class:{extend:o=>o}},s=>s,document,ui,{pageXOffset:0});
const full='Auto uses all driver-allowed primary channels. Width is chosen separately.';
const field={option:'channels',title:'Channels',description:full};
const map={description:'Map introduction. Extended details.',children:[{children:[field]}]};
api.compact(map);const node=field.description;
assert.equal(node.attrs['data-tooltip'],full);assert.equal(node.attrs.tabindex,'0');
assert.equal(node.attrs.role,'button');assert(node.attrs['aria-label'].includes(full));
node.events.click();assert.deepEqual(calls.pop(),['show',node]);
node.events.click();assert.deepEqual(calls.pop(),['hide',node]);
let prevented=false,stopped=false;
node.events.keydown({key:'Enter',preventDefault(){prevented=true;}});assert(prevented);assert.equal(calls.pop()[0],'show');
node.events.keydown({key:'Escape',stopPropagation(){stopped=true;}});assert(stopped);assert.equal(calls.pop()[0],'hide');
node.events.keydown({key:' ',preventDefault(){}});assert.equal(calls.pop()[0],'show');
node.events.blur();node.events.click();assert.equal(calls.pop()[0],'show');
const popup={style:{},getBoundingClientRect(){return {right:900,width:300};}};
document.events['tooltip-open']({detail:{target:node},target:popup});assert.equal(popup.style.left,'492px');
assert(map.description.tag==='span');const first=field.description;api.compact(map);assert.strictEqual(field.description,first);
console.log('PASS: native LuCI help attributes, settings traversal, click/tap, keyboard, Escape, accessible text and viewport fit');
