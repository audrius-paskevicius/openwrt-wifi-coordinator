'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..'),text=fs.readFileSync(path.join(root,'DISCLAIMER.txt'),'utf8');
const source=fs.readFileSync(path.join(root,'channel-coordinator/files/wifi-coordinator.disclaimer.js'),'utf8');
function E(tag,attrs,children){return {tag,attrs:attrs||{},children:Array.isArray(children)?children:children==null?[]:[children],
 get firstChild(){return this.children[0];},appendChild(n){this.children.push(n);},replaceChildren(...nodes){this.children=nodes;}};}
function find(n,tag){if(n.tag===tag)return n;for(const c of n.children||[]){if(typeof c==='object'){const got=find(c,tag);if(got)return got;}}}
function fixture(store,notice=text){
 let modal=null;
 const api=new Function('E','L','ui','window',source.replace('@WIFI_COORDINATOR_DISCLAIMER_JSON@',JSON.stringify(notice)))(
  E,{Class:{extend:x=>x},resource:x=>x},{showModal:(title,body)=>{modal={title,body};},hideModal:()=>{modal=null;}},{localStorage:store});
 return {api,modal:()=>modal};
}
module.exports=(async()=>{
 let value=null,writes=0,rendered=0;
 const storage={getItem:()=>value,setItem:(k,v)=>{assert.equal(k,'wifi-coordinator-disclaimer');value=v;writes++;}};
 const f=fixture(storage),render=()=>{rendered++;return Promise.resolve(E('main',{},'settings'));};
 const page=await f.api.gate(render);
 assert.equal(rendered,0,'settings and polling must not start before acknowledgement');
 assert(JSON.stringify(page).includes(text.trim().split('\n\n')[1]),'full notice is visible on first visit');
 const gate=find(page,'section');await find(gate,'button').attrs.click();
 assert.equal(rendered,1);assert.equal(writes,1);assert.equal(value,text);
 assert(!find(page,'section'));assert(!find(page,'aside'),'no recurring banner after acknowledgement');
 assert(JSON.stringify(f.api.page()).includes(text.trim().split('\n\n')[4]),'dedicated disclaimer page contains full text');
 const menu=JSON.parse(fs.readFileSync(path.join(root,'wifi-coordinator/menu.json'),'utf8'));
 assert.equal(menu['admin/network/wifi_coordinator/disclaimer'].action.path,'wifi-disclaimer');
 assert.equal(menu['admin/network/wifi_coordinator/disclaimer'].title,'Experimental, AI-generated software. Use at your own risk.');
 const tab=fs.readFileSync(path.join(root,'channel-coordinator/files/wifi-disclaimer.js'),'utf8');
 const view=new Function('view','disclaimer',tab)({extend:x=>x},f.api);
 const direct=await view.render();assert(JSON.stringify(direct).includes(text.trim().split('\n\n')[1]));
 assert.equal(view.handleSave,null);assert.equal(view.handleSaveApply,null);
 await fixture(storage).api.gate(render);assert.equal(rendered,2,'same text stays acknowledged across module loads and upgrades');
 const changed=await fixture(storage,text+'\nRevised notice.').api.gate(render);
 assert(find(changed,'section'));assert.equal(rendered,2,'changed text requires new acknowledgement');
 const blocked=fixture({getItem(){throw Error('blocked');},setItem(){throw Error('blocked');}});
 const blockedPage=await blocked.api.gate(render);await find(find(blockedPage,'section'),'button').attrs.click();
 await blocked.api.gate(render);assert.equal(rendered,4,'blocked storage still permits use after acknowledgement');
 for(const file of ['channel-coordinator/files/wifi-channels.js','channel-coordinator/files/wifi-history.js','channel-coordinator/files/wifi-storage.js','radio-prefer/files/wifi-clients.js']){
  const view=fs.readFileSync(path.join(root,file),'utf8');
  assert(view.includes("'require wifi-coordinator.disclaimer as disclaimer';"));
  assert(view.includes('render:function(data){return disclaimer.gate(this.renderPage.bind(this,data));}'));
 }
 const readme=fs.readFileSync(path.join(root,'README.md'),'utf8');
 for(const paragraph of text.trim().split('\n\n'))assert(readme.includes(paragraph),'README and APK wording must match');
 assert(readme.indexOf('<!-- project-disclaimer:start -->')<readme.indexOf('Coordinated channel selection'));
 assert(fs.readFileSync(path.join(root,'wifi-coordinator/build-apk.sh'),'utf8').includes('"$BASE/../DISCLAIMER.txt"'));
 console.log('PASS: canonical disclaimer, first-use gates, browser acknowledgement, text revisions, unavailable storage and dedicated tab without recurring banners');
})().catch(e=>{console.error(e);process.exitCode=1;});
