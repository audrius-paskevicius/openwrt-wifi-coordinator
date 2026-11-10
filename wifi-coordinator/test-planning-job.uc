import * as uloop from 'uloop';
import * as fs from 'fs';
import {create_job} from '../channel-coordinator/files/planning-job.uc';
import {choose} from '../channel-coordinator/files/planner.uc';
import {group} from '../channel-coordinator/files/policy.uc';
let checks=0;function check(v,s){if(!v)die('FAIL: '+s+'\n');checks++;}
function clock(){return +split(fs.readfile('/proc/uptime'),' ')[0];}
let offset=0,reports=[],ticks=0,phase=0,began=clock(),owner=7;
let old={...group(5180,80),cost:50,uncertainty:1},better={...group(5500,80),cost:0,uncertainty:1};
let models=[{name:'test',current:old,candidates:[old,better]}],cfg={separate:true,improvement:3};
let expected=sprintf('%J',choose(models,cfg));
uloop.init();
let job=create_job({now:()=>clock()+offset,report:(...args)=>push(reports,args)});
check(job.start('comparison','first',()=>{
    owner=99;let until=clock()+1.2;while(clock()<until){};
    return choose(models,cfg);
}),'worker starts');
check(!job.start('comparison','other',()=>null),'one calculation at a time');
let tick;
tick=uloop.timer(50,()=>{
    ticks++;
    if(clock()-began>15)die('Worker lifecycle test timed out');
    if(phase==0){
        let result=job.take('comparison','first');
        if(result){
            check(ticks>=5,'owner timers continue during CPU work');
            check(owner==7,'worker cannot mutate owner memory');
            check(sprintf('%J',result.value)==expected,'background search exactly equals synchronous search');
            check(!job.busy(),'completed task released');
            job.start('comparison','stale',()=>{let until=clock()+2;while(clock()<until){};return 123;});phase=1;
        }
    }else if(phase==1){
        check(job.take('comparison','changed')==null&&!job.busy(),'changed inputs discard worker');
        check(reports[-1][0]=='planning-discarded','discard recorded');
        job.start('validation','timeout',()=>{let until=clock()+2;while(clock()<until){};return true;});offset=61;phase=2;
    }else if(phase==2){
        check(job.take('validation','timeout').error!=null&&!job.busy(),'bounded timeout releases worker');
        offset=0;job.start('validation','error',()=>{die('deliberate test error');});phase=3;
    }else if(phase==3){
        let result=job.take('validation','error');
        if(result){check(!!result.error,'calculation errors are returned safely');phase=4;}
    }else {
        job.start('comparison','shutdown',()=>{let until=clock()+2;while(clock()<until){};return true;});
        job.cancel('test shutdown');check(!job.busy(),'shutdown cancels worker');uloop.end();return;
    }
    tick.set(50);
});
uloop.run();
printf('PASS: %d worker lifecycle, responsiveness and equivalence checks\n',checks);
