let checks=0;
function check(v,s){if(!v)die('FAIL: '+s+'\n');checks++;}
radar.add({time:W,center:5570,width:160,region:2,phy:0,radar_event:0});
state.radar={half_life:3600,events:radar.records()};save();
check(length(written.radar.events)==1&&written.radar.events[0].width==160,'snapshot records current full-width detection');
T+=43200;W+=43200;
check(radar.flush()&&length(radar.records())==0,'expired detection pruned at checkpoint');
save();
check(length(written.radar.events)==0,'actual daemon save replaces stale array after pruning');
let restored=open_memory(path,3600,()=>W,()=>T,written.radar.events);
check(length(restored.records())==0,'service restart does not resurrect pruned detections from RAM');
radar.add({time:W,center:5290,width:80,region:2,phy:2,radar_event:0});save();
restored=open_memory(path,3600,()=>W,()=>T,written.radar.events);
check(length(restored.records())==1&&restored.records()[0].center==5290,'new detection survives service restart after old records expire');
fs.unlink(path);fs.unlink(path+'.new');
printf('PASS: %d actual radar-snapshot lifecycle cases\n',checks);
