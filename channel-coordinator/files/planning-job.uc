// One bounded, read-only calculation at a time. Only the owner accepts results.
import * as uloop from 'uloop';
export function create_job(io) {
    let job=null,serial=0;
    function cancel(reason) {
        if(!job)return;
        let old=job;job=null;serial++;
        old.task?.kill();
        io.report('planning-discarded',old.kind,io.now()-old.started,reason);
    }
    function start(kind,key,calculate) {
        if(job)return false;
        let id=++serial;
        job={id,kind,key,started:io.now(),result:null};
        job.task=uloop.task(pipe=>{
            try{pipe.send({value:calculate()});}
            catch(e){pipe.send({error:''+e});}
        },output=>{if(job?.id==id&&output!=null)job.result=output;});
        if(!job.task){job=null;die('Cannot start planning calculation');}
        return true;
    }
    function take(kind,key) {
        if(!job||job.kind!=kind)return null;
        if(job.key!=key){cancel('Planning inputs changed');return null;}
        if(io.now()-job.started>60){cancel('Calculation exceeded 60 seconds');return {error:'Planning calculation timed out'};}
        if(!job.result){
            if(job.task.finished()){cancel('Calculation exited without a result');return {error:'Planning calculation failed'};}
            return null;
        }
        let old=job;job=null;
        // The task can still be exiting after its last pipe write.
        old.task.kill();
        io.report(old.result.error?'planning-failed':'planning-complete',kind,io.now()-old.started,old.result.error,old.result.value?.timings);
        return old.result;
    }
    return {start,take,cancel,busy:()=>!!job,kind:()=>job?.kind};
};
