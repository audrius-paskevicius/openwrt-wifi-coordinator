import * as fs from 'fs';
import {pressure} from './policy.uc';
import {RAM_LIMIT,INTERVAL,archive_info,clear_archive,expire_archive,prune,bounded,checkpoint} from './history-storage.uc';
const PATH='/tmp/wifi-coordinator-history.json',LIMIT=RAM_LIMIT;
export function open_history(boot,enabled,hours) {
    hours=max(1,min(200,hours));
    let h={boot,started:time(),periods:[],samples:[],events:[],surveys:[]},last_record=0,last_flush=0;
    try { if((fs.stat(PATH)?.size ?? LIMIT+1)<=LIMIT){let old=json(fs.readfile(PATH));
        if(old.boot==boot&&type(old.periods)=='array'&&type(old.samples)=='array'&&type(old.events)=='array'&&type(old.surveys)=='array')
            h=old;
    } }catch(e){}
    let archive=archive_info();
    let saved=archive.saved ?? 0;
    archive=null; // Older history is loaded only during a checkpoint, not held by the daemon.
    let last_attempt=max(h.archive_attempt ?? 0,saved,h.started);
    if(last_attempt>time())last_attempt=time();
    function flush(force,shutdown) {
        let t=time();if(!force&&t-last_flush<60)return true;
        let ok=true;
        let cutoff=t-hours*3600;
        h.periods=filter(h.periods,p=>p.end>=cutoff);
        h.samples=filter(h.samples,s=>s.end>=cutoff);
        h.events=filter(h.events,e=>e.time>=cutoff);
        h.surveys=filter(h.surveys,s=>(s.updated ?? s.time)>=cutoff);
        h.updated=t;h.retention_hours=hours;h.limit_bytes=LIMIT;h.enabled=enabled;
        if(shutdown||t-last_attempt>=INTERVAL){
            last_attempt=t;h.archive_attempt=t;
            expire_archive(t,hours);
            let changed=h.archive_dirty||length(filter(h.samples,s=>s.end>saved))||length(filter(h.events,e=>e.time>saved))||length(filter(h.surveys,s=>(s.updated ?? s.time)>saved))||length(filter(h.periods,p=>p.end>saved));
            if(changed){
                if(checkpoint(h,t,hours)){saved=t;h.archive_dirty=false;h.archive_error=null;prune(h,t-3600);}
                else {ok=false;h.archive_error='Archive write failed or less than 4 MiB would remain free. Recent history kept in RAM; next scheduled attempt in six hours.';}
            }
        }
        h.archive_saved=saved;h.archive_next=last_attempt+INTERVAL;
        let data=bounded(h,LIMIT);
        if(!fs.writefile(PATH+'.new',data)||!fs.rename(PATH+'.new',PATH))ok=false;
        last_flush=t;
        return ok;
    }
    function record(rows) {
        let t=time();if(!enabled){flush(false);return;}if(t-last_record<5)return;last_record=t;h.archive_dirty=true;
        let bucket=int(t/300)*300;
        for(let r in rows){
            let period=null;
            for(let i=length(h.periods)-1;i>=0;i--)if(h.periods[i].radio==r.radio){period=h.periods[i];break;}
            if(!period||t-period.end>15||period.channel!=r.channel||period.width!=r.width||period.center!=r.center||period.role!=r.role){
                period={radio:r.radio,channel:r.channel,center:r.center,width:r.width,role:r.role,start:t,end:t};push(h.periods,period);
            }else period.end=t;
            let sample=null;
            for(let i=length(h.samples)-1;i>=0&&h.samples[i].time>=bucket;i--){
                let s=h.samples[i];if(s.radio==r.radio&&s.channel==r.channel&&s.width==r.width&&s.role==r.role){sample=s;break;}
            }
            if(!sample){
                sample={time:bucket,end:t,source:boot,radio:r.radio,channel:r.channel,width:r.width,role:r.role,n:0,traffic_sum:0,traffic_peak:0,clients_peak:0,busy_sum:0,busy_n:0,signal_min:null};push(h.samples,sample);
            }
            sample.end=t;sample.n++;sample.traffic_sum+=r.traffic;sample.traffic_peak=max(sample.traffic_peak,r.traffic);
            sample.clients_peak=max(sample.clients_peak,r.clients);
            if(r.busy!=null){sample.busy_sum+=r.busy;sample.busy_n++;}
            if(r.signal!=null)sample.signal_min=sample.signal_min==null?r.signal:min(sample.signal_min,r.signal);
        }
        flush(false);
    }
    function event(e) {
        if(!enabled)return;
        h.archive_dirty=true;
        let clean={time:e.time ?? time()};
        for(let k in ['event','radio','from','to','channel','width','center','region','clients','clients_missing','clients_unproven','disconnect_events','helper','elapsed','ban_seconds','radar_event','freq','phy','neighbors','missing_count','scanned_frequencies','missing_frequencies'])
            if(e[k]!=null)clean[k]=e[k];
        if(e.reason)clean.reason=substr(replace(''+e.reason,/[0-9a-f]{2}(:[0-9a-f]{2}){5}/gi,'[client]'),0,240);
        push(h.events,clean);flush(true);
    }
    function survey(observations,frequencies,cycle,batch_frequencies) {
        if(!enabled)return;
        h.archive_dirty=true;
        let t=time(),frame=null;
        if(cycle!=null)for(let s in h.surveys)if(s.cycle==cycle)frame=s;
        if(!frame){frame={time:t,bands:[]};if(cycle!=null)frame.cycle=cycle;push(h.surveys,frame);}
        let bands=[];
        for(let band in [{start:2400,step:5,count:19},{start:5170,step:20,count:34}]){
            let old=filter(frame.bands,b=>b.start==band.start&&b.step==band.step)[0];
            let levels=[],offsets=[];
            for(let i=0;i<band.count;i++){
                let lo=band.start+i*band.step,hi=lo+band.step;
                let covered=length(filter(frequencies,f=>f+10>lo&&f-10<hi));
                if(!covered){push(levels,old?.levels[i]);push(offsets,old?.offsets?.[i]);continue;}
                let cost=pressure(lo,hi,observations);
                let level=int(min(100,cost*100/48));push(levels,level);
                let touched=length(filter(batch_frequencies ?? frequencies,f=>f+10>lo&&f-10<hi));
                push(offsets,touched||old?.levels[i]!=level?t-frame.time:old?.offsets?.[i] ?? 0);
            }
            push(bands,{start:band.start,step:band.step,levels,offsets});
        }
        frame.bands=bands;frame.updated=t;flush(true);
    }
    function clear() { h={boot,started:time(),periods:[],samples:[],events:[],surveys:[]};last_record=0;last_flush=0;saved=0;last_attempt=time();fs.unlink(PATH);clear_archive();flush(true); }
    return {record,event,flush,clear,survey,shutdown:()=>flush(true,true)};
};
