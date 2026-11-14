// Lossless column encoding: repeated values are runs; observation offsets remain exact.
export const LISTS=['periods','samples','clients','events','surveys'];
export function empty(){return {periods:[],samples:[],clients:[],events:[],surveys:[]};};
export function key(k,x){
 if(x._id)return x._id;
 if(x.event=='radio-unavailable')return sprintf('%J',[x.event,x.radio,x.source,x.start]);
 if(k=='periods')return sprintf('%J',[x.radio,x.start,x.channel,x.center,x.width,x.role]);
 if(k=='clients')return sprintf('%J',[x.radio,x.source,x.start,x.count]);
 if(k=='samples')return sprintf('%J',[x.radio,x.time,x.channel,x.width,x.role,x.source]);
 if(k=='surveys')return ''+(x.cycle ?? x.time);
 return sprintf('%J',x);
};
function runs(values){let out=[];for(let v in values){let p=out[length(out)-1];if(p&&p[1]==v)p[0]++;else push(out,[1,v]);}let plain={raw:values};return length(sprintf('%J',plain))<length(sprintf('%J',out))?plain:out;}
function expand(rows,n){if(type(rows)=='object'){if(type(rows.raw)!='array'||length(rows.raw)!=n)die('Invalid plain survey column');return rows.raw;}let out=[];for(let r in rows){if(type(r)!='array'||length(r)!=2||type(r[0])!='int'||r[0]<1||length(out)+r[0]>n)die('Invalid survey run');for(let i=0;i<r[0];i++)push(out,r[1]);}if(length(out)!=n)die('Incomplete survey column');return out;}
export function pack(h){
 let out={...h},sessions=[],lookup={};
 for(let k in LISTS)out[k]=map(h[k] ?? [],r=>{
  if(!r._id)return r;let x={...r};
  if(!exists(lookup,r._session)){lookup[r._session]=length(sessions);push(sessions,r._session);}
  x._s=lookup[r._session];delete x._id;delete x._session;return x;
 });
 if(length(sessions))out.record_sessions=sessions;
 let frames=out.surveys;if(length(frames)<2)return out;
 let layout=map(frames[0].bands,b=>[b.start,b.step,length(b.levels)]);
 for(let f in frames){if(sprintf('%J',map(f.bands,b=>[b.start,b.step,length(b.levels)]))!=sprintf('%J',layout))return out;
  for(let b in f.bands)if(length(b.offsets ?? [])!=length(b.levels))return out;}
 let headers=[],columns=[];
 for(let f in frames){let header={...f};delete header.bands;push(headers,header);}
 for(let bi=0;bi<length(layout);bi++)for(let j=0;j<layout[bi][2];j++)push(columns,[runs(map(frames,f=>f.bands[bi].levels[j])),runs(map(frames,f=>f.bands[bi].offsets[j]))]);
 delete out.surveys;out.survey_columns={layout,headers,columns};return out;
};
export function unpack(h){
 let out={...h};
 if(h?.survey_columns){
 let c=h.survey_columns,n=length(c.headers),frames=map(c.headers,f=>({...f,bands:map(c.layout,l=>({start:l[0],step:l[1],levels:[],offsets:[]}))})),ci=0;
 if(n>100000)die('Too many survey frames');
 for(let bi=0;bi<length(c.layout);bi++)for(let j=0;j<c.layout[bi][2];j++){
  let column=c.columns[ci++],levels=expand(column[0],n),offsets=expand(column[1],n);
  for(let i=0;i<n;i++){push(frames[i].bands[bi].levels,levels[i]);push(frames[i].bands[bi].offsets,offsets[i]);}
 }
 out.surveys=frames;delete out.survey_columns;
 }
 if(h?.record_sessions){
  for(let k in LISTS)out[k]=map(out[k] ?? [],r=>{
   if(r._s==null)return r;let session=h.record_sessions[r._s];if(type(session)!='string'||type(r._seq)!='int')die('Invalid history identity');
   let x={...r,_session:session,_id:session+':'+r._seq};delete x._s;return x;
  });delete out.record_sessions;
 }
 return out;
};
