// Immutable six-hour batches: retention controls flash use, not an archive byte cap.
import * as fs from 'fs';
export const DIRECTORY='/etc/wifi-coordinator';
export const RAM_LIMIT=1048576;
export const INTERVAL=21600;
const LISTS=['periods','samples','events','surveys'];
export function empty() { return {periods:[],samples:[],events:[],surveys:[]}; };
function read_file(path) {
    try {
        // Bounds a single input allocation, not the size of the archive.
        if((fs.stat(path)?.size ?? RAM_LIMIT*2+1)>RAM_LIMIT*2)return null;
        let h=json(fs.readfile(path));
        for(let k in LISTS)if(type(h[k])!='array')return null;
        return h;
    }catch(e){return null;}
}
export function archive_info() {
    let files=[],saved=0,bytes=0;
    for(let name in fs.lsdir(DIRECTORY) ?? []){
        let m=match(name,/^batch-([0-9]+)\.json$/);
        if(!m)continue;
        let at=int(m[1]);
        let stat=fs.stat(DIRECTORY+'/'+name);
        if(stat?.type!='file')continue;
        push(files,{name,saved:at,size:stat.size});saved=max(saved,at);bytes+=stat.size;
    }
    return {saved,bytes,files:sort(files,(a,b)=>a.saved-b.saved)};
};
export function clear_archive() {
    for(let name in fs.lsdir(DIRECTORY) ?? [])
        if(match(name,/^batch-[0-9]+\.json(\.new)?$/))fs.unlink(DIRECTORY+'/'+name);
};
export function expire_archive(t,hours) {
    for(let file in archive_info().files)
        if(file.saved<t-hours*3600)fs.unlink(DIRECTORY+'/'+file.name);
};
function key(k,x) {
    if(k=='periods')return sprintf('%J',[x.radio,x.start,x.channel,x.center,x.width,x.role]);
    if(k=='samples')return sprintf('%J',[x.radio,x.time,x.channel,x.width,x.role,x.source]);
    if(k=='surveys')return ''+(x.cycle ?? x.time);
    return sprintf('%J',x);
}
export function merge_history(a,b) {
    let out=empty();
    for(let k in LISTS){
        let seen={};
        for(let x in [...(a[k] ?? []),...(b[k] ?? [])]){
            let id=key(k,x),old=seen[id];
            if(!old||(x.updated ?? x.end ?? x.time)>=(old.updated ?? old.end ?? old.time))seen[id]=x;
        }
        out[k]=sort(values(seen),(x,y)=>(x.start ?? x.time)-(y.start ?? y.time));
    }
    return out;
};
// Diagnostics/tests only; the daemon reads just the small directory listing.
export function read_archive() {
    let out=empty(),info=archive_info();
    for(let file in info.files){let h=read_file(DIRECTORY+'/'+file.name);if(h)out=merge_history(out,h);}
    out.saved=info.saved;return out;
};
export function prune(h,cutoff) {
    for(let k in LISTS)h[k]=filter(h[k] ?? [],x=>(x.updated ?? x.end ?? x.time)>=cutoff);
};
export function bounded(h,limit) {
    let data=sprintf('%J\n',h);
    while(length(data)>limit){
        let available=filter(['samples','events','periods','surveys'],k=>length(h[k]));
        if(!length(available))return null;
        let oldest=sort(available,(a,b)=>(h[a][0].end ?? h[a][0].time)-(h[b][0].end ?? h[b][0].time))[0];
        shift(h[oldest]);h.dropped_records=(h.dropped_records ?? 0)+1;
        data=sprintf('%J\n',h);
    }
    return data;
};
function free_bytes() {
    // Fixed package-owned directory, never user-provided shell text.
    let p=fs.popen("df -Pk '"+DIRECTORY+"'",'r');if(!p)return null;
    let text=p.read('all');p.close();
    let rows=split(trim(text ?? ''),/\n/),fields=split(trim(rows[length(rows)-1] ?? ''),/\s+/);
    return length(fields)>=6?int(fields[3])*1024:null;
}
export function checkpoint(h,t,hours) {
    let info=archive_info(),out=empty();
    // Boundary records can be extended later; the reader merges by stable key.
    for(let k in LISTS)out[k]=filter(h[k] ?? [],x=>(x.updated ?? x.end ?? x.time)>=info.saved);
    prune(out,t-hours*3600);
    if(!length(out.samples)&&!length(out.periods)&&!length(out.events)&&!length(out.surveys))return true;
    out.saved=t;out.retention_hours=hours;out.format=2;
    let data=sprintf('%J\n',out),path=DIRECTORY+'/batch-'+t+'.json';
    if(!fs.stat(DIRECTORY)&&!fs.mkdir(DIRECTORY,0700))return false;
    expire_archive(t,hours);
    let free=free_bytes();
    // Leave room for normal router operation; never evict unexpired data to fit.
    if(free==null||free-length(data)<4194304)return false;
    if(fs.stat(path))return false; // Closed batches are never rewritten.
    let f=fs.open(path+'.new','w',0600);if(!f)return false;
    let written=f.write(data),flushed=f.flush(),closed=f.close();
    if(written!=length(data)||!flushed||!closed){fs.unlink(path+'.new');return false;}
    if(system('sync')!=0)return false;
    if(!fs.rename(path+'.new',path))return false;
    if(system('sync')!=0)return false;
    return true;
};
