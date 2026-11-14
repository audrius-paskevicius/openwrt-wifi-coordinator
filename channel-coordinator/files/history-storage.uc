// Recording buffer limits and legacy normalization helpers. Durable writes live in history-store.uc.
export const RAM_LIMIT=1048576;
export const INTERVAL=21600;
export function save_interval(minutes,hours) {
    if((type(minutes)!='int'&&type(minutes)!='double')||minutes!=minutes)minutes=INTERVAL/60;
    return min(max(15,min(360,int(minutes)))*60,max(1,min(120,hours))*3600);
};
const LISTS=['periods','samples','clients','events','surveys'];
export function empty() { return {periods:[],samples:[],clients:[],events:[],surveys:[]}; };
function key(k,x) {
    if(x.event=='radio-unavailable')return sprintf('%J',[x.event,x.radio,x.source,x.start]);
    if(k=='periods')return sprintf('%J',[x.radio,x.start,x.channel,x.center,x.width,x.role]);
    if(k=='clients')return sprintf('%J',[x.radio,x.source,x.start,x.count]);
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
export function prune(h,cutoff) {
    for(let k in LISTS)h[k]=filter(h[k] ?? [],x=>(x.updated ?? x.end ?? x.time)>=cutoff);
};
export function bounded(h,limit) {
    let data=sprintf('%J\n',h);
    while(length(data)>limit){
        let available=filter(['samples','clients','events','periods','surveys'],k=>length(h[k]));
        if(!length(available))return null;
        let oldest=sort(available,(a,b)=>(h[a][0].end ?? h[a][0].time)-(h[b][0].end ?? h[b][0].time))[0];
        shift(h[oldest]);h.dropped_records=(h.dropped_records ?? 0)+1;
        data=sprintf('%J\n',h);
    }
    return data;
};
