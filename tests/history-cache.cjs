(async()=>{
 const source=require('fs').readFileSync(require('path').join(__dirname,'../channel-coordinator/files/wifi-history.js'),'utf8'), prefix=source.slice(0,source.indexOf('return view.extend'));
 let checks=0,calls=[],listing=[],data={};function check(ok,msg){if(!ok)throw Error(msg);checks++;}
 const sample={time:100,end:200,radio:'radio0',source:'boot',n:1,traffic_sum:2};
 const period={start:100,end:200,radio:'radio0',channel:36};
 const archive={saved:210,samples:[sample],periods:[period],surveys:[],events:[]};
 const ram={samples:[{...sample,end:250,n:2,traffic_sum:6}],periods:[{...period,end:250}],surveys:[],events:[],archive_saved:210};
 const path='/etc/wifi-coordinator/',ramPath='/tmp/wifi-coordinator-history.json';
 data[path+'batch-210.json']=JSON.stringify(archive);data[ramPath]=JSON.stringify(ram);
 listing=[{name:'batch-210.json',type:'file'},{name:'unrelated.txt',type:'file'},{name:'batch-211.json.new',type:'file'}];
 const fs={list:async()=>listing,read:async p=>{calls.push(p);if(!(p in data))throw Object.assign(Error('No such file'),{name:'NotFoundError'});return data[p];}};
 const read=new Function('fs',prefix+';return readHistory;')(fs);
 let h=await read();check(h.samples.length===1&&h.samples[0].n===2,'boundary sample dedup');
 check(h.periods.length===1&&h.periods[0].end===250,'residence extension dedup');
 check(h.archive_files===1&&h.archive_bytes===data[path+'batch-210.json'].length,'owned batch bytes only');
 calls=[];await read();check(calls.length===2&&calls[0]===ramPath,'closed batch cache avoids repeated reads');
 data[path+'batch-300.json']=JSON.stringify({...archive,saved:300,samples:[{...sample,time:300,end:350,n:1}]});listing.push({name:'batch-300.json',type:'file'});
 calls=[];h=await read();check(h.samples.length===2&&calls.length===3,'only new batch, RAM and controller state fetched');
 listing=listing.filter(f=>f.name!=='batch-210.json');data[ramPath]=JSON.stringify({periods:[],samples:[],events:[],surveys:[]});
 h=await read();check(h.samples.length===1&&h.samples[0].time===300,'expired batch removed from cache and graph');
 listing.push({name:'batch-400.json',type:'file'});data[path+'batch-400.json']='invalid';
 h=await read();check(h.read_errors.length===1,'corrupt batch shown as error');
 data[path+'batch-400.json']=JSON.stringify({...archive,saved:400});h=await read();check(h.read_errors.length===0&&h.samples.length===2,'failed read retried');
 listing=[];h=await read();check(h.samples.length===0&&h.archive_bytes===0,'clear removes cached records');
 return {passed:checks};
})().then(r=>console.log('PASS: '+r.passed+' history/cache cases')).catch(e=>{console.error(e);process.exitCode=1;});
