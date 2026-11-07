import * as fs from 'fs';
import {open_history,set_now} from './history-test-module.uc';
import {DIRECTORY,ARCHIVE,RAM_LIMIT,archive_info,read_archive,merge_history,checkpoint,clear_archive,expire_archive,prune,bounded} from './history-storage-test.uc';
let checks=0;
function check(ok,why){if(!ok)die('FAIL: '+why+'\n');checks++;}
const PATH='/tmp/wifi-history-test.json';
let start=int(time()/21600)*21600;
set_now(start);let h=open_history('storage-test',true,200);h.clear();
function row(n){return {radio:'radio'+n,channel:n==1?6:36,center:n==1?2437:5210,width:n==1?20:80,role:'serving',traffic:n+1,clients:1,busy:20,signal:-60};}
h.record([row(0),row(1),row(2)]);
check(!length(archive_info().files),'no startup archive write');
set_now(start+21599);h.record([row(0)]);
check(!length(archive_info().files),'no early checkpoint');
set_now(start+21600);h.flush(true);
let info=archive_info(),a=read_archive(),r=json(fs.readfile(PATH));
check(info.saved==start+21600&&length(info.files)==1,'one six-hour batch');
check(!length(filter(r.samples,s=>s.end<start+18000)),'older records offloaded from RAM');
check(length(a.samples)>length(r.samples),'archive holds offloaded records');
let saved=fs.readfile(DIRECTORY+'/'+info.files[0].name);
h=open_history('storage-test',true,200);h.flush(true);
check(fs.readfile(DIRECTORY+'/'+info.files[0].name)==saved&&length(archive_info().files)==1,'restart does not rewrite archive');
set_now(start+43200);h.flush(true);
check(length(archive_info().files)==1,'unchanged history makes no new batch');
// Full 216-hour run, every five-minute summary, survey and action retained.
set_now(start);h.clear();h.record([row(0),row(1),row(2)]);
let snapshots={},max_ram=0;
for(let i=1;i<=2592;i++){
    set_now(start+i*300);h.record([row(0),row(1),row(2)]);
    h.survey([{center:2412,width:20,signal:-55,load:null},{center:5210,width:80,signal:-50,load:10}],[2412,2437,2462,5180,5200,5220,5240],'cycle-'+i);
    h.event({event:'test-action',radio:'radio0',reason:'Observation '+i});
    if(i%72==0){
        let files=archive_info().files;
        for(let f in files){let content=fs.readfile(DIRECTORY+'/'+f.name);if(snapshots[f.name]!=null)check(content==snapshots[f.name],'closed batch stays byte-identical');else snapshots[f.name]=content;}
        max_ram=max(max_ram,fs.stat(PATH).size);
    }
}
r=json(fs.readfile(PATH));info=archive_info();a=read_archive();
check(info.bytes>1048576,'archive grows beyond old cap at full detail');
check(max_ram<=RAM_LIMIT&&!r.dropped_records,'recent RAM stays bounded without dropped records');
check(r.samples[0].time>=start+2592*300-25200,'RAM holds at most offload cycle plus one hour');
check(length(info.files)<=34,'expired batches removed by time');
let merged=merge_history(a,r);prune(merged,start+2592*300-200*3600);
check(length(merged.samples)==7203,'all 200-hour five-minute samples preserved exactly');
check(length(merged.surveys)==2401,'every five-minute spectrum survey preserved');
check(length(merged.events)==2401,'all actions preserved without count cap');
check(!length(filter(merged.samples,s=>s.interval==7200))&&!length(filter(merged.surveys,s=>s.interval==7200)),'no two-hour aggregation');
check(!length(filter(merged.samples,s=>s.traffic_sum/s.n!=int(substr(s.radio,5))+1)),'original traffic values unchanged');
check(merged.surveys[0].cycle=='cycle-192'&&merged.surveys[0].bands[0].levels[2]>0,'old survey detail and identity retained');
let again=merge_history(merged,r);prune(again,start+2592*300-200*3600);
check(length(again.samples)==length(merged.samples),'overlapping boundary snapshots deduplicated');
let latest=info.files[length(info.files)-1],latest_text=fs.readfile(DIRECTORY+'/'+latest.name);
set_now(start+2592*300+10);h=open_history('new-boot',true,200);h.flush(true);
check(fs.readfile(DIRECTORY+'/'+latest.name)==latest_text&&!length(json(fs.readfile(PATH)).samples),'reboot keeps archives and resets RAM');
h=open_history('new-boot',true,1);h.flush(true);
check(length(archive_info().files)==length(info.files),'retention reduction waits for scheduled deletion');
h=open_history('new-boot',true,200);
let failtime=start+2592*300+21610;
fs.mkdir(DIRECTORY+'/batch-'+failtime+'.json.new',0700);
set_now(failtime);h.record([row(0)]);h.flush(true);r=json(fs.readfile(PATH));
check(r.archive_error!=null&&length(r.samples)>0,'failed write retains RAM and exposes error');
check(fs.readfile(DIRECTORY+'/'+latest.name)==latest_text,'failed write preserves previous batch');
let attempt=r.archive_attempt;h=open_history('new-boot',true,200);h.flush(true);
check(json(fs.readfile(PATH)).archive_attempt==attempt,'failed write retries rate limited across restart');
fs.rmdir(DIRECTORY+'/batch-'+failtime+'.json.new');
h.clear();check(!length(archive_info().files),'clear deletes all batches');
// Upgrade imports existing history without rewriting or inventing lost detail.
let legacy={...r,saved:failtime};fs.writefile(ARCHIVE,sprintf('%J',legacy));
let legacy_text=fs.readfile(ARCHIVE);
let newer={periods:[],samples:[{...r.samples[0],time:failtime+21600,end:failtime+21600}],surveys:[],events:[]};
check(checkpoint(newer,failtime+21600,200),'new batch alongside legacy archive');
check(fs.readfile(ARCHIVE)==legacy_text&&length(archive_info().files)==2,'legacy archive kept byte-identical');
check(length(read_archive().samples)==2,'legacy and new samples both readable');
expire_archive(failtime+21600,1);
check(!fs.stat(ARCHIVE)&&length(archive_info().files)==1,'only wholly expired files deleted');
// File-size safeguard reports loss rather than silently hiding it.
let huge={periods:[],samples:[],surveys:[],events:[]};for(let i=0;i<100;i++)push(huge.events,{time:i,event:'x',reason:'0123456789012345678901234567890123456789'});
check(length(bounded(huge,1024))<=1024&&huge.dropped_records>0,'RAM overflow is bounded and counted');
fs.writefile(DIRECTORY+'/unrelated.txt','preserve');
h=open_history('new-boot',false,200);
check(fs.stat(PATH)&&length(archive_info().files)==1,'pausing preserves RAM and archives');
let paused=json(fs.readfile(PATH));
h.event({event:'must-not-record'});h.record([row(0)]);h.survey([],[]);h.flush(true);
check(sprintf('%J',json(fs.readfile(PATH)).events)==sprintf('%J',paused.events),'paused event recording stays off');
check(sprintf('%J',json(fs.readfile(PATH)).samples)==sprintf('%J',paused.samples),'paused traffic recording stays off');
// Shutdown is the only automatic exception to the six-hour offload interval.
h.clear();set_now(failtime+43200);h=open_history('shutdown-test',true,200);
h.event({event:'before-reboot'});h.record([row(0)]);h.flush(true);
check(!length(archive_info().files),'ordinary forced RAM flush does not force flash');
check(h.shutdown()&&length(archive_info().files)==1,'orderly shutdown checkpoints pending data before six hours');
let shutdownText=fs.readfile(DIRECTORY+'/'+archive_info().files[0].name);
h=open_history('shutdown-test',false,200);check(h.shutdown(),'paused history can be saved at shutdown');
check(length(archive_info().files)==1&&fs.readfile(DIRECTORY+'/'+archive_info().files[0].name)==shutdownText,'repeated unchanged shutdown does not write again');
h=open_history('after-reboot',false,200);h.flush(true);
check(length(read_archive().events)==1&&read_archive().events[0].event=='before-reboot','paused history survives reboot in flash');
check(!length(json(fs.readfile(PATH)).events),'new boot starts with an empty RAM tier');
// Resuming within the checkpoint second must not hide an unsaved event.
h=open_history('after-reboot',true,200);h.event({event:'same-second-new'});
set_now(failtime+43201);check(h.shutdown(),'later shutdown saves same-second dirty records');
check(length(read_archive().events)==2,'boundary event survives without duplication');
h.clear();check(!length(archive_info().files)&&!length(json(fs.readfile(PATH)).events),'explicit clear erases both tiers');
check(fs.readfile(DIRECTORY+'/unrelated.txt')=='preserve','clear only touches owned history files');fs.unlink(DIRECTORY+'/unrelated.txt');
print(sprintf('PASS: %d batch storage checks; 200h retained in %d bytes, %d batches; all 7203 samples and 2401 surveys intact\n',checks,info.bytes,length(info.files)));
