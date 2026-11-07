// Pure observe/plan/decide policy. Scores describe expected usable spectrum,
// not Mbps. Execution never adds another hidden benefit threshold.
import {same,overlap,pressure} from './policy.uc';
import {risk} from './radar.uc';
export function assess(g,snapshot,max_width,radars,wall,half_life,region,previous) {
    let neighbours=0,airtime=0,measured=0,sources={},occupied=0;
    for(let f in g.members){
        let p=min(100,pressure(f-10,f+10,snapshot.observations)*100/48),b=snapshot.busy?.[f];
        neighbours+=p;if(b!=null){airtime+=b;measured++;}
        occupied+=max(p,b ?? 0);sources[snapshot.scanners?.[f] ?? 'unknown']=true;
    }
    let n=length(g.members),occupancy=occupied/n,radar=risk(radars,g,wall,half_life,region);
    let capacity=g.width*(1-occupancy/100)*(1-0.75*radar);
    // Confidence is separate from the score. Compare repeated estimates to
    // distinguish survey noise from a change; mixed scanners widen uncertainty.
    let uncertainty=measured==n?1:3,source=join(',',sort(keys(sources)));
    if(previous){uncertainty=max(uncertainty,min(15,max(previous.occupancy-occupancy,occupancy-previous.occupancy)));
        if(previous.source!=source)uncertainty=max(6,uncertainty);}
    return {...g,occupancy,neighbour_pressure:neighbours/n,airtime:measured?airtime/measured:null,
        measured,radar_risk:radar,capacity,cost:100-100*capacity/max_width,uncertainty,source};
};
export function layout(choices,cfg) {
    let interference=0,width=0,cost=0,power=0;
    for(let i,g in choices){
        for(let j=0;j<i;j++)interference+=overlap(g,choices[j]);
        // Width is evaluated in the JOINT layout, not against the old locations
        // of other radios. Crowded or radar-prone width receives no preference.
        if(g.occupancy<cfg.wide_threshold&&g.radar_risk<0.5)width+=g.width/(g.max_width ?? g.width);
        cost+=g.cost;power+=g.power ?? 0;
    }
    return {overlap:interference,width,cost:cost+(cfg.separate?0:cfg.overlap_penalty*interference),power};
};
export function better(a,b,cfg) {
    if(!b)return true;
    if(cfg.separate&&max(a.overlap-b.overlap,b.overlap-a.overlap)>0.000001)return a.overlap<b.overlap;
    if(max(a.width-b.width,b.width-a.width)>0.000001)return a.width>b.width;
    if(max(a.cost-b.cost,b.cost-a.cost)>0.000001)return a.cost<b.cost;
    return a.power>b.power; // allowed power only breaks an otherwise equal tie
};
export function worthwhile_narrowing(current,choices,base,candidate,cfg) {
    // Giving up bandwidth must buy capacity or spectrum separation. Crossing
    // the congestion boundary alone is not a reason to accept less service.
    return !length(filter(choices,(g,i)=>g.width<current[i].width))||candidate.cost<base.cost||
        cfg.separate&&candidate.overlap<base.overlap-0.000001;
};
function route(start,goal,cfg) {
    function visit(at,path){
        if(!length(filter(at,(g,i)=>!same(g,goal[i]))))return path;
        for(let i,g in at){if(same(g,goal[i]))continue;
            let next=[...at];next[i]=goal[i];
            if(cfg.separate&&layout(next,cfg).overlap>layout(at,cfg).overlap+0.000001)continue;
            let found=visit(next,[...path,{index:i,target:goal[i],staging:false}]);if(found)return found;
        }
        return null;
    }
    return visit(start,[]);
}
export function transition(models,goal,cfg) {
    let start=map(models,m=>m.current),direct=route(start,goal,cfg);if(direct)return direct;
    let best=null;
    // One neutral staging move is enough to break ordinary two-radio swaps.
    // Bound the search, do not claim a path exists if more staging is required.
    for(let i,m in models)for(let g in m.candidates){
        if(same(g,start[i])||same(g,goal[i]))continue;
        let via=[...start];via[i]=g;
        if(cfg.separate&&layout(via,cfg).overlap>layout(start,cfg).overlap+0.000001)continue;
        let path=route(via,goal,cfg);
        if(path&&(!best||length(path)+1<length(best)))best=[{index:i,target:g,staging:true},...path];
    }
    return best;
};
export function choose(models,cfg) {
    let current=map(models,m=>m.current),base=layout(current,cfg),best={...base,choices:current,path:[]},visited=0,truncated=false;
    function visit(i,choices){
        if(++visited>100000){truncated=true;return;}
        if(i==length(models)){
            let candidate=layout(choices,cfg);
            if(!worthwhile_narrowing(current,choices,base,candidate,cfg)||!better(candidate,best,cfg))return;
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
    let signature=sprintf('%J',map(plan.choices,g=>[g.center,g.width]));
    let evidence=comparison_evidence(models,previous,stamp,cfg),comparisons={},count=64,confidence=0;
    for(let i,m in models)if(!same(m.current,plan.choices[i])){
        let g=plan.choices[i],key=sprintf('%J',[g.freq,g.center,g.width]);
        let n=evidence[m.name].options[key]?.count ?? 1;
        comparisons[m.name]=n;count=min(count,n);
        confidence=max(confidence,max(m.current.uncertainty ?? 3,g.uncertainty ?? 3)/(n ** 0.5));
    }
    let required=max(cfg.improvement,confidence);
    let policy=(cfg.separate&&plan.overlap<plan.base.overlap-0.000001)||plan.width>plan.base.width+0.000001;
    let continuing=intent==signature&&plan.gain>0;
    if(!policy&&plan.gain<=0)return {action:'hold',reason:'No estimated service benefit from changing layout'};
    let act=policy||continuing||plan.gain>=required;
    return {action:act?'move':'measure',signature,stamp,count,comparisons,evidence,required,gain:plan.gain,
        reason:policy?'Better spectrum separation or usable width':act?'Benefit exceeds evidence uncertainty':'Comparison needs more evidence',
        next:plan.path[0],path:plan.path};
};
