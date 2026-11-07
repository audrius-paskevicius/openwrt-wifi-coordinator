'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
const made=[];
function escape(s){return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function E(tag,attrs,children){const node={tag,attrs:attrs||{},children,textContent:'',
 getAttribute(k){return this.attrs[k];},contains(n){return n===this;},
 closest(selector){return selector==='.wc-setting-help'&&this.attrs.class==='wc-setting-help'?this:null;},
 get outerHTML(){return '<'+tag+' '+Object.entries(this.attrs).map(([k,v])=>k+'="'+escape(v)+'"').join(' ')+'>'+escape(this.textContent)+'</'+tag+'>';}};
 made.push(node);return node;}
const document={events:{},documentElement:{clientWidth:800},addEventListener(k,v){this.events[k]=v;}};
const calls=[],ui={showTooltip:e=>calls.push(['show',e.target]),hideTooltip:e=>calls.push(['hide',e.target])};
const api=new Function('E','L','_','document','ui','window',fs.readFileSync(path.join(__dirname,'../channel-coordinator/files/wifi-coordinator.help.js'),'utf8'))(E,{Class:{extend:o=>o}},s=>s,document,ui,{pageXOffset:0});
const full='Auto uses all driver-allowed primary channels. Width is chosen separately.';
const field={option:'channels',title:'Channels',description:full};
const map={description:'Map introduction. Extended details.',children:[{children:[field]}]};
api.compact(map);const node=made[made.length-1];
assert.equal(typeof field.description,'string','LuCI renders only string option descriptions');
assert(field.description.includes('data-tooltip="'+full+'"'));assert.equal(node.attrs.tabindex,'0');
assert.equal(node.attrs.role,'button');assert(node.attrs['aria-label'].includes(full));
document.events.click({target:node});assert.deepEqual(calls.pop(),['show',node]);
document.events.click({target:node});assert.deepEqual(calls.pop(),['hide',node]);
let prevented=false,stopped=false;
document.events.keydown({target:node,key:'Enter',preventDefault(){prevented=true;}});assert(prevented);assert.equal(calls.pop()[0],'show');
document.events.keydown({target:node,key:'Escape',stopPropagation(){stopped=true;}});assert(stopped);assert.equal(calls.pop()[0],'hide');
document.events.keydown({target:node,key:' ',preventDefault(){}});assert.equal(calls.pop()[0],'show');
document.events['tooltip-close']();document.events.click({target:node});assert.equal(calls.pop()[0],'show');
const description={closest:s=>s==='.cbi-value-description'?description:null,querySelector:()=>node};
document.events.mouseover({target:description});assert.deepEqual(calls.pop(),['show',node]);
const popup={style:{},getBoundingClientRect(){return {right:900,width:300};}};
document.events['tooltip-open']({detail:{target:node},target:popup});assert.equal(popup.style.left,'492px');
const first=field.description;api.compact(map);assert.strictEqual(field.description,first);
const escaped=api.explain('Text <not markup>','" onmouseover="unsafe <script>','Title');
assert(escaped.includes('&lt;not markup&gt;'));assert(escaped.includes('&quot; onmouseover=&quot;unsafe &lt;script&gt;'));
// New DOM after a form re-render still receives delegated interactions.
const rerender=made[made.length-1];document.events.click({target:rerender});assert.deepEqual(calls.pop(),['show',rerender]);
let inserted;const section={renderContents(){return {querySelector:()=>({after:n=>{inserted=n;}})};}};
api.sectionStatus(section,node);section.renderContents();assert.equal(inserted.attrs.class,'cbi-section-descr');assert.strictEqual(inserted.children[0],node);
console.log('PASS: LuCI-compatible help markup, escaping, delegated interactions, theme icon, repeated rendering and section status mounting');
