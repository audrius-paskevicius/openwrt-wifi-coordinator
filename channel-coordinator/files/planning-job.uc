// One bounded, read-only calculation at a time. Only the owner accepts results.
import * as uloop from 'uloop';
import * as fs from 'fs';
const PREFIX='/tmp/wifi-coordinator-plan.',LIMIT=4194304;
function identity(pid){
    let text=fs.readfile('/proc/'+pid+'/stat');
    return text?split(split(text,') ')[1],' ')[19]:null;
}
function remove(dir){
    for(let name in ['pending','result','owner'])fs.unlink(dir+'/'+name);
    fs.rmdir(dir);
}
function reap(){
    for(let dir in fs.glob(PREFIX+'*')){
        if(fs.lstat(dir)?.type!='directory')continue;
        let owner=null;try{owner=json(fs.readfile(dir+'/owner'));}catch(e){}
        if(owner?.pid>0&&owner.start!=null){
            if(identity(owner.pid)==owner.start)continue;
        }else if(time()-(fs.stat(dir)?.mtime ?? time())<60)continue;
        remove(dir);
    }
}
export function create_job(io) {
    reap();
    let job=null,serial=0;
    function cancel(reason) {
        if(!job)return;
        let old=job;job=null;serial++;
        old.task?.kill();
        remove(old.dir);
        io.report('planning-discarded',old.kind,io.now()-old.started,reason);
    }
    function start(kind,key,calculate) {
        if(job)return false;
        reap();
        let id=++serial;
        let dir=fs.mkdtemp(PREFIX+'XXXXXX');
        if(!dir)die('Cannot create planning result directory');
        let pid=int(split(fs.readfile('/proc/self/stat'),' ')[0]);
        let owner=sprintf('%J',{pid,start:identity(pid)}),file=fs.open(dir+'/pending','w',0600);
        if(!file||fs.writefile(dir+'/owner',owner)!=length(owner)){
            file?.close();remove(dir);die('Cannot prepare planning result');
        }
        job={id,kind,key,dir,started:io.now()};
        // Old uloop versions lose partial large pipe messages on EAGAIN. Only
        // a small completion notice uses the pipe; the result lives in RAM.
        // Open before fork so cancellation can unlink it without a late child
        // recreating files. A rename publishes only a flushed, closed result.
        job.task=uloop.task(()=>{
            let text;
            try{
                text=sprintf('%J',{id,value:calculate()});
                if(length(text)>LIMIT)die('Planning result exceeds size limit');
            }catch(e){text=sprintf('%J',{id,error:substr(''+e,0,1024)});}
            let n=file.write(text),flushed=file.flush(),closed=file.close();
            if(n!=length(text)||!flushed||!closed||!fs.rename(dir+'/pending',dir+'/result'))
                return {id,error:'Cannot publish planning result'};
            return {id,complete:true};
        },output=>{if(job?.id==id&&output?.id==id&&output.error)job.failure=output.error;});
        file.close();
        if(!job.task){job=null;remove(dir);die('Cannot start planning calculation');}
        return true;
    }
    function take(kind,key) {
        if(!job||job.kind!=kind)return null;
        if(job.key!=key){cancel('Planning inputs changed');return null;}
        if(io.now()-job.started>60){cancel('Calculation exceeded 60 seconds');return {error:'Planning calculation timed out'};}
        let stat=fs.lstat(job.dir+'/result'),result=null;
        if(stat){
            try{
                if(stat.type!='file'||stat.size<1||stat.size>LIMIT)die('Invalid planning result size or type');
                let file=fs.open(job.dir+'/result','r');if(!file)die('Cannot read planning result');
                let text=file.read(LIMIT+1);file.close();
                if(text==null||length(text)!=stat.size)die('Incomplete planning result');
                let record=json(text);
                if(type(record)!='object'||record.id!=job.id||exists(record,'value')==exists(record,'error')||
                    exists(record,'error')&&type(record.error)!='string')die('Invalid planning result envelope');
                result=exists(record,'error')?{error:record.error}:{value:record.value};
            }catch(e){result={error:''+e};}
        }
        if(!result){
            if(job.failure){let error=job.failure;cancel(error);return {error};}
            if(job.task.finished()){cancel('Calculation exited without a result');return {error:'Planning calculation failed'};}
            return null;
        }
        let old=job;job=null;
        // The task can still be exiting after its last pipe write.
        old.task.kill();
        remove(old.dir);
        io.report(result.error?'planning-failed':'planning-complete',kind,io.now()-old.started,result.error,result.value?.timings);
        return result;
    }
    return {start,take,cancel,busy:()=>!!job,kind:()=>job?.kind};
};
