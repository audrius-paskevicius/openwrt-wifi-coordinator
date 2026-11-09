// Read-only export engine. One source batch and one dataset's key index at a
// time; never assemble the archive or the completed download in memory.
export const DATASETS=['periods','traffic','surveys','radar','actions'];
const LIST={periods:'periods',traffic:'samples',surveys:'surveys',actions:'events'};
const FIELDS={
 periods:['radio','channel','center','width','role','start','end'],
 traffic:['time','end','source','radio','channel','width','role','n','traffic_sum','traffic_peak','clients_peak','busy_sum','busy_n','signal_min'],
 actions:['time','event','operation','kind','affected','retry_seconds','preflight','stage','radio','from','to','channel','width','center','region','clients','clients_missing','clients_unproven','disconnect_events','forced_disconnects','returned','elsewhere','absent','total','declined','response','mode','helper','elapsed','ban_seconds','radar_event','freq','phy','neighbors','missing_count','scanned_frequencies','missing_frequencies','reason'],
 radar:['time','center','width','region','phys','weight'],
 surveys:['time','cycle','updated']
};
export function iso(t){
 if(t==null)return null;
 let d=gmtime(t);
 return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',d.year,d.mon,d.mday,d.hour,d.min,d.sec);
};
function key(k,x){
 if(k=='periods')return sprintf('%J',[x.radio,x.start,x.channel,x.center,x.width,x.role]);
 if(k=='traffic')return sprintf('%J',[x.radio,x.time,x.channel,x.width,x.role,x.source]);
 if(k=='surveys')return ''+(x.cycle ?? x.time);
 return sprintf('%J',x);
}
function clean(k,x){
 let out={};
 for(let f in FIELDS[k])if(x[f]!=null)out[f]=x[f];
 for(let f in ['time','start','end','updated'])if(out[f]!=null)out[f+'_iso']=iso(out[f]);
 if(k=='surveys')out.bands=map(x.bands ?? [],b=>({start:b.start,step:b.step,levels:b.levels,offsets:b.offsets ?? []}));
 if(k=='traffic'){
  out.traffic_avg_mbps=x.n>0?x.traffic_sum/x.n:null;
  out.busy_avg_percent=x.busy_n>0?x.busy_sum/x.busy_n:null;
 }
 return out;
}
export function csv_cell(x){
 if(x==null)return '';
 let s=type(x)=='object'||type(x)=='array'?sprintf('%J',x):''+x;
 // Protect spreadsheet users without changing numeric negative measurements.
 if(type(x)=='string'&&match(s,/^[[:space:]]*[=+@-]/))s="'"+s;
 return '"'+replace(s,'"','""')+'"';
};
const COLUMNS={
 periods:['start_iso','end_iso','radio','channel','center','width','role','start','end'],
 traffic:['time_iso','end_iso','radio','channel','width','role','traffic_avg_mbps','traffic_peak','clients_peak','busy_avg_percent','signal_min','n','traffic_sum','busy_sum','busy_n','source','time','end'],
 surveys:['time_iso','observed_iso','low_mhz','high_mhz','congestion','context','cycle','time','observed'],
 radar:['time_iso','center','width','region','weight','phys','time'],
 actions:['time_iso','event','radio','reason','details','time']
};
export function stream(options,read_source,write){
 let warnings=[],warned={},counts={},now=options.now,start=options.start,retained=options.retained;
 function warn(s){if(!warned[s]){warned[s]=true;push(warnings,s);}}
 for(let s in options.warnings ?? [])warn(s);
 let buffer='';
 function flush(){if(length(buffer)){write(buffer);buffer='';}}
 function emit(s){buffer+=s;if(length(buffer)>=16384)flush();}
 let meta={format:'wifi-coordinator-history',version:1,package_version:options.version,
  exported_at:iso(now),window:{start,end:now,start_iso:iso(start),end_iso:iso(now)},
  retention_hours:options.hours,declared_bands:options.bands ?? [],radar_half_life_seconds:options.radar?.half_life ?? 3600,
  units:{timestamps:'Unix seconds and ISO 8601 UTC',frequencies:'MHz',width:'MHz',traffic:'Mbit/s',signal:'dBm',congestion:'estimate 0-100, not airtime percent',busy:'measured airtime percent'},
  notes:['Best-effort snapshot at request start; immutable archives plus a fixed RAM snapshot.',
   'Intervals keep original boundaries; filter to the requested window when plotting. No prorating of traffic summaries.',
   'Survey context includes earlier retained observations needed at the window start. Null means unmeasured, not clear.',
   'Radar memory can predate retained graph history. Apply the exported half-life to each detection.',
   'Records are in source order; sort by start/time for chronological use. Check the final result for completeness.'],
  dropped_ram_records:options.dropped ?? 0};
 let datasets=options.format=='json'?DATASETS:[options.dataset];
 function row(k,type,data,message){
  emit(join(',',map([type,...map(COLUMNS[k],c=>data?.[c]),message],csv_cell))+'\r\n');
 }
 if(options.format=='json'){let header=sprintf('%J',meta);emit(substr(header,0,length(header)-1)+',"datasets":{');}
 else {emit(join(',',['record_type',...COLUMNS[options.dataset],'message'])+'\r\n');row(options.dataset,'metadata',null,sprintf('%J',meta));}
 flush();
 for(let di=0;di<length(datasets);di++){
  let k=datasets[di],first=true;counts[k]=0;
  if(options.format=='json')emit((di?',':'')+sprintf('%J',k)+':[');
  function output(x){
   let record=clean(k,x);counts[k]++;
   if(options.format=='json'){emit((first?'':',')+sprintf('%J',record));first=false;return;}
   if(k=='surveys'){
    for(let b in record.bands)for(let i=0;i<length(b.levels ?? []);i++){
     let observed=x.time+(b.offsets?.[i] ?? 0);
     row(k,'data',{time_iso:record.time_iso,observed_iso:iso(observed),low_mhz:b.start+i*b.step,
      high_mhz:b.start+(i+1)*b.step,congestion:b.levels[i],context:observed<start,
      cycle:x.cycle,time:x.time,observed},null);
    }
   }else row(k,'data',k=='actions'?{...record,details:sprintf('%J',record)}:record,null);
  }
  if(k=='radar'){
   for(let x in options.radar?.events ?? [])if(x.time<=now)output(x);
  }else{
   let winners={},context={},needed={};
   function source(i){
    let h=read_source(i);
    if(!h){warn('Cannot read source '+options.sources[i]);return null;}
    if(type(h[LIST[k]])!='array'){warn('Invalid '+k+' in '+options.sources[i]);return null;}
    return h[LIST[k]];
   }
   // Store references and update times only, not record bodies.
   for(let si=0;si<length(options.sources);si++){
    let rows=source(si);if(!rows)continue;
    for(let ri=0;ri<length(rows);ri++){
     let x=rows[ri],at=x?.updated ?? x?.end ?? x?.time,begin=x?.start ?? x?.time;
     if(type(x)!='object'||type(at)!='int'&&type(at)!='double'||begin==null){warn('Invalid record in '+options.sources[si]);continue;}
     if(at<retained||begin>now)continue;
     let id=key(k,x),old=winners[id];
     if(!old||at>=old.at)winners[id]={si,ri,at};
    }
    if(options.format=='json')emit('\n');flush();
   }
   // For each frequency bin retain its last pre-window observation. Whole
   // selected frames retain the original compact survey representation.
   if(k=='surveys')for(let si=0;si<length(options.sources);si++){
    let rows=source(si);if(!rows)continue;
    for(let ri=0;ri<length(rows);ri++){
     let x=rows[ri],id=key(k,x),w=winners[id];if(w?.si!=si||w?.ri!=ri)continue;
     for(let b in x.bands ?? [])for(let bi=0;bi<length(b.levels ?? []);bi++){
      if(b.levels[bi]==null)continue;
      let t=x.time+(b.offsets?.[bi] ?? 0),bin=''+b.start+':'+b.step+':'+bi;
      if(t<=start&&(!context[bin]||t>=context[bin].time))context[bin]={time:t,id};
     }
    }
   }
   for(let c in values(context))needed[c.id]=true;
   for(let si=0;si<length(options.sources);si++){
    let rows=source(si);if(!rows)continue;
    for(let ri=0;ri<length(rows);ri++){
     let x=rows[ri],id=key(k,x),w=winners[id];if(w?.si!=si||w?.ri!=ri)continue;
     if((x.updated ?? x.end ?? x.time)>=start||needed[id])output(x);
    }
    flush();
   }
  }
  if(options.format=='json')emit(']');
 }
 let result={complete:!length(warnings),warnings,counts};
 if(options.format=='json')emit('},"result":'+sprintf('%J',result)+'}\n');
 else {for(let w in warnings)row(options.dataset,'warning',null,w);row(options.dataset,'summary',null,sprintf('%J',result));}
 flush();return result;
};
