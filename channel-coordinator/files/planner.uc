// Pure observe/plan/decide policy. Scores describe expected usable spectrum,
// not Mbps. Execution never adds another hidden benefit threshold.
import {same,group,overlap,pressure} from './policy.uc';
import {risk} from './radar.uc';
// Advertised bidirectional spatial capacity, never a client's momentary rate.
export function spatial_streams(caps) {
    let v=caps?.vht_mcs_set,ht=caps?.ht_mcs_set;
    if(length(v?.rx_mcs_set)&&length(v?.tx_mcs_set)){
        let rx=filter(v.rx_mcs_set,x=>length(x.mcs_indexes)),tx=filter(v.tx_mcs_set,x=>length(x.mcs_indexes));
        if(length(rx)&&length(tx))return max(1,min(8,max(...map(rx,x=>x.streams)),max(...map(tx,x=>x.streams))));
    }
    let indexes=filter(ht?.rx_mcs_indexes ?? [],i=>i>=0&&i<32);
    // Unequal HT TX/RX stream declarations need a separate decoder. Do not
    // overstate unknown transmit capacity by assuming RX is symmetric.
    if(length(indexes)&&ht.tx_mcs_set_defined){
        let rx=min(4,1+int(max(...indexes)/8));
        return ht.tx_rx_mcs_set_equal?rx:min(rx,max(1,ht.tx_max_spatial_streams ?? 1));
    }
    return 1;
};
export function assess(g,snapshot,max_width,radars,wall,half_life,region,previous,streams) {
    let neighbours=0,airtime=0,measured=0,sources={},occupied=0,free={};
    for(let f in g.members){
        let p=min(100,pressure(f-10,f+10,snapshot.observations)*100/48),b=snapshot.busy?.[f];
        neighbours+=p;if(b!=null){airtime+=b;measured++;}
        occupied+=max(p,b ?? 0);sources[snapshot.scanners?.[f] ?? 'unknown']=true;
        free[f]=1.0-max(p,b ?? 0)/100.0;
    }
    let n=length(g.members),occupancy=occupied/(1.0*n),radar=risk(radars,g,wall,half_life,region);
    // Nested primary 20/40/80/160 blocks: a busy secondary need not cost the
    // entire transmission, but a busy primary affects every width. Count each
    // neighbouring BSS once per nested block, not once per occupied 20 MHz.
    // Busy counters cannot reveal cross-channel correlation: use their maximum
    // as additional evidence rather than pretending they are independent.
    let usable=0,last=0,at_width={};
    for(let w in [20,40,80,160]){
        if(w>g.width)break;
        let part=w==g.width?g:group(g.freq,w),pressure_sum=0,peak_busy=0;
        for(let observation in snapshot.observations){
            let peak=0;
            for(let f in part.members)peak=max(peak,pressure(f-10,f+10,[observation])*100/48);
            pressure_sum+=peak;
        }
        for(let f in part.members)peak_busy=max(peak_busy,snapshot.busy?.[f] ?? 0);
        usable+=(w-last)*max(0,1-max(pressure_sum,peak_busy)/100.0);last=w;at_width[w]=usable;
    }
    let capacity=usable*(1-0.75*radar),reference=g.freq<3000?40.0:160.0;
    streams=max(1,min(8,streams ?? 1));
    let service=100*capacity*streams/reference,scale=max_width*streams/reference;
    // Confidence is separate from the score. Compare repeated estimates to
    // distinguish survey noise from a change; mixed scanners widen uncertainty.
    let uncertainty=measured==n?1:3,source=join(',',sort(keys(sources)));
    if(previous){uncertainty=max(uncertainty,min(15,100*max(previous.capacity-capacity,capacity-previous.capacity)/max_width));
        if(previous.source!=source)uncertainty=max(6,uncertainty);}
    return {...g,occupancy,neighbour_pressure:neighbours/n,airtime:measured?airtime/measured:null,
        measured,radar_risk:radar,capacity,primary_occupancy:100*(1-free[g.freq]),at_width,
        streams,service,cost:100-service,uncertainty:uncertainty*scale,source};
};
export function layout(choices,cfg) {
    let interference=0,width=0,cost=0,power=0;
    for(let i,g in choices){
        for(let j=0;j<i;j++)interference+=overlap(g,choices[j]);
        width+=g.width/(1.0*(g.max_width ?? g.width));
        cost+=g.cost;power+=g.power ?? 0;
    }
    return {overlap:interference,width,cost:cost+(cfg.separate?0:cfg.overlap_penalty*interference),power};
};
export function better(a,b,cfg) {
    if(!b)return true;
    if(cfg.separate&&max(a.overlap-b.overlap,b.overlap-a.overlap)>0.000001)return a.overlap<b.overlap;
    if(max(a.cost-b.cost,b.cost-a.cost)>0.000001)return a.cost<b.cost;
    if(max(a.width-b.width,b.width-a.width)>0.000001)return a.width>b.width;
    return a.power>b.power; // allowed power only breaks an otherwise equal tie
};
function route(start,goal,cfg,order) {
    function visit(at,path){
        if(!length(filter(at,(g,i)=>!same(g,goal[i]))))return path;
        for(let i in order){let g=at[i];if(same(g,goal[i]))continue;
            let next=[...at];next[i]=goal[i];
            if(cfg.separate&&layout(next,cfg).overlap>layout(at,cfg).overlap+0.000001)continue;
            let found=visit(next,[...path,{index:i,target:goal[i],staging:false}]);if(found)return found;
        }
        return null;
    }
    return visit(start,[]);
}
export function transition(models,goal,cfg) {
    // Replanning must not let the first independent radio monopolize execution.
    // Oldest-served eligible moves go first; overlap dependencies still apply.
    let order=[];for(let i,m in models)push(order,i);
    order=sort(order,(a,b)=>(models[a].last_action ?? 0)-(models[b].last_action ?? 0)||a-b);
    let start=map(models,m=>m.current),direct=route(start,goal,cfg,order);if(direct)return direct;
    let best=null;
    // One neutral staging move is enough to break ordinary two-radio swaps.
    // Bound the search, do not claim a path exists if more staging is required.
    for(let i in order)for(let g in models[i].candidates){
        if(same(g,start[i])||same(g,goal[i]))continue;
        let via=[...start];via[i]=g;
        if(cfg.separate&&layout(via,cfg).overlap>layout(start,cfg).overlap+0.000001)continue;
        let path=route(via,goal,cfg,order);
        if(path&&(!best||length(path)+1<length(best)))best=[{index:i,target:g,staging:true},...path];
    }
    return best;
};
export function choose(models,cfg) {
    // Primary choices with the same footprint have identical route constraints.
    // Keep the best-scored one (the incumbent on ties) to bound joint search;
    // retain every eligible choice in the explanatory comparison outside here.
    models=map(models,m=>{
        let best={};
        for(let g in m.candidates){let key=g.center+':'+g.width,old=best[key];
            if(!old||g.cost<old.cost-0.000001||max(g.cost-old.cost,old.cost-g.cost)<=0.000001&&same(g,m.current))best[key]=g;
        }
        return {...m,candidates:values(best)};
    });
    let current=map(models,m=>m.current),base=layout(current,cfg),best={...base,choices:current,path:[]},visited=0,truncated=false;
    function visit(i,choices){
        if(++visited>100000){truncated=true;return;}
        if(i==length(models)){
            let candidate=layout(choices,cfg);
            if(!better(candidate,best,cfg))return;
            let path=transition(models,choices,cfg);if(!path)return;
            best={...candidate,choices:[...choices],path};return;
        }
        for(let g in models[i].candidates){
            let next=[...choices,g];
            if(cfg.separate&&layout(next,cfg).overlap>best.overlap+0.000001)continue;
            visit(i+1,next);if(truncated)return;
        }
    }
    visit(0,[]);
    return {...best,base,gain:base.cost-best.cost,visited,truncated};
};
function comparison_evidence(models,previous,stamp,cfg) {
    let evidence={};
    for(let m in models){
        let current=sprintf('%J',[m.current.freq,m.current.center,m.current.width]);
        let old=previous?.evidence?.[m.name],options={};
        for(let g in m.candidates){
            if(same(g,m.current)||g.cost>=m.current.cost)continue;
            let key=sprintf('%J',[g.freq,g.center,g.width]);
            let prior=old?.current==current?old.options[key]:null;
            // Count completed surveys, including those where another candidate
            // ranked first. Never borrow support from a different placement.
            let fresh=prior&&stamp>=prior.stamp&&stamp-prior.stamp<=(cfg.max_age ?? 900);
            options[key]={stamp,count:fresh?min(64,prior.count+(stamp>prior.stamp?1:0)):1};
        }
        evidence[m.name]={current,options};
    }
    return evidence;
}
export function decide(plan,models,previous,stamp,cfg,intent) {
    if(plan.truncated)return {action:'hold',reason:'Planner search limit reached'};
    if(!length(plan.path))return {action:'hold',reason:'Current layout retained'};
    let signature=sprintf('%J',map(plan.choices,g=>[g.freq,g.center,g.width]));
    let evidence=comparison_evidence(models,previous,stamp,cfg),comparisons={},count=64,confidence=0;
    for(let i,m in models)if(!same(m.current,plan.choices[i])){
        let g=plan.choices[i],key=sprintf('%J',[g.freq,g.center,g.width]);
        let n=evidence[m.name].options[key]?.count ?? 1;
        comparisons[m.name]=n;count=min(count,n);
        confidence=max(confidence,max(m.current.uncertainty ?? 3,g.uncertainty ?? 3)/(n ** 0.5));
    }
    let required=max(cfg.improvement,confidence);
    let policy=cfg.separate&&plan.overlap<plan.base.overlap-0.000001;
    let continuing=intent==signature&&plan.gain>0;
    if(!policy&&plan.gain<=0)return {action:'hold',reason:'No estimated service benefit from changing layout'};
    let act=policy||continuing||plan.gain>=required;
    return {action:act?'move':'measure',signature,stamp,count,comparisons,evidence,required,gain:plan.gain,
        reason:policy?'Better spectrum separation':act?'Service benefit exceeds evidence uncertainty':'Comparison needs more evidence',
        next:plan.path[0],path:plan.path};
};
