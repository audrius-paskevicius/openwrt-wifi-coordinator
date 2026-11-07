// Radar is interruption evidence, not Wi-Fi congestion. Kernel DFS eligibility
// remains authoritative and is checked separately by the hardware layer.
import * as fs from 'fs';
export function strength(e,t,half_life) {
    return (e.weight ?? 1)*2 ** (-max(0,t-e.time)/max(60,half_life));
};
export function remember(events,event) {
    if(event.radar_event!=0||!event.center||!event.width)return events;
    let rows=map(events,x=>({...x,phys:[...(x.phys ?? [])]}));
    let old=filter(rows,x=>x.region==event.region&&x.center==event.center&&x.width==event.width&&
        max(x.time-event.time,event.time-x.time)<=5)[0];
    if(old){if(index(old.phys,event.phy)<0)push(old.phys,event.phy);return rows;}
    push(rows,{time:event.time,center:event.center,width:event.width,region:event.region,
        phys:[event.phy],weight:1});
    // Keep the most recent incidents, independently of survey frequency.
    return slice(sort(rows,(a,b)=>a.time-b.time),-128);
};
export function risk(events,g,t,half_life,region) {
    let bins=g.members ?? [g.freq],worst=0;
    for(let f in bins){let sum=0;for(let e in events){
        if(region!=null&&e.region!=null&&region!=e.region)continue;
        if(f+10<=e.center-e.width/2||f-10>=e.center+e.width/2)continue;
        sum+=strength(e,t,half_life);
    }worst=max(worst,sum);}
    return min(1,worst);
};
export function open_memory(path,half_life,wall,uptime,recent) {
    let records=[],saved=wall(),next=uptime()+21600,dirty=false;
    try{let s=fs.stat(path);if(s&&s.size<=65536){let d=json(fs.readfile(path));
        if(d.version==1){records=slice(sort(filter(d.records ?? [],e=>e.time>0&&e.width>0&&e.width<=160&&e.center>=5000&&e.center<5925),(a,b)=>a.time-b.time),-128);saved=d.saved ?? wall();}
    }}catch(e){}
    // A clock reset must not make saved events artificially older.
    if(wall()<saved)for(let e in records)e.time=wall()-max(0,saved-e.time);
    function add(e){let old=sprintf('%J',records);records=remember(records,e);dirty=dirty||old!=sprintf('%J',records);}
    // Same-boot RAM state survives a service restart even when optional graph
    // history is disabled. A reboot deliberately falls back to the checkpoint.
    for(let e in recent ?? [])for(let phy in e.phys ?? [null])add({...e,phy,radar_event:0});
    function flush(force){
        if((!force&&uptime()<next)||!dirty)return true;
        next=uptime()+21600;
        records=filter(records,e=>strength(e,wall(),half_life)>=0.001);
        let data=sprintf('%J\n',{version:1,saved:wall(),records});
        if(!fs.stat('/etc/wifi-coordinator'))fs.mkdir('/etc/wifi-coordinator',0700);
        if(fs.writefile(path+'.new',data)&&fs.rename(path+'.new',path)){dirty=false;return true;}
        return false;
    }
    return {add,flush,records:()=>records,risk:(g,region)=>risk(records,g,wall(),half_life,region)};
};
