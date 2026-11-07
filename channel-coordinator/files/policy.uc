// Original implementation. Scores are comparative occupancy estimates, not Mbps.
export function channel(f) { return f < 3000 ? int((f - 2407) / 5) : int((f - 5000) / 5); };
export function overlap(a, b) {
    let lo = max(a.center - a.width / 2, b.center - b.width / 2);
    let hi = min(a.center + a.width / 2, b.center + b.width / 2);
    return 1.0 * max(0, hi - lo) / min(a.width, b.width);
};
export function same(a, b) { return a.center == b.center && a.width == b.width; };
export function quiet_ready(since, now, seconds) {
    return since != null && now >= since && now-since >= seconds;
};
export function handoff_before_move(clients,method,policy,ready) {
    return clients>0&&policy=='handoff'&&!(method=='csa'&&ready);
};
export function move_method(config,source,target) {
    return source.width!=target.width?(config.width_method ?? config.method):config.method;
};
export function private_ipv4(ip) {
    if(type(ip)!='string'||!match(ip,/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/))return false;
    let n=map(split(ip,'.'),x=>int(x));
    if(length(filter(n,x=>x<0||x>255)))return false;
    return n[0]==10||n[0]==192&&n[1]==168||n[0]==172&&n[1]>=16&&n[1]<=31;
};
export function liveness_progress(previous,results,t,grace) {
    let failed={},lost=[];
    for(let id,ok in results)if(!ok){failed[id]=previous[id] ?? t;if(t-failed[id]>=grace)push(lost,id);}
    return {failed,lost};
};
export function force_signal_ok(measurements, node, source_signal, target_min, source_min) {
    let fresh=filter(measurements ?? [],m=>m.node==node&&m.age>=0&&m.age<=30000&&m.rcpi>0&&m.rcpi<=220);
    if(length(fresh)){
        let r=fresh[0].rssi;if(r>2147483647)r-=4294967296;
        return r<0&&r>=target_min;
    }
    return source_signal!=null&&source_signal<0&&source_signal>=source_min;
};
export function same_network(a,b) {
    if(!a||!b||!match(a.encryption ?? '',/^(psk|sae|owe|none)/)||a.ssid!=b.ssid||
        a.encryption!=b.encryption||a.key!=b.key||a.ieee80211w!=b.ieee80211w)return false;
    let an=sort(type(a.network)=='array'?[...a.network]:split(a.network ?? '',/\s+/));
    let bn=sort(type(b.network)=='array'?[...b.network]:split(b.network ?? '',/\s+/));
    return length(filter(an,n=>length(n)>0))>0 && sprintf('%J',an)==sprintf('%J',bn);
};
export function delta_busy(a, b) {
    if (!a || !b || a.time == null || b.time == null || a.busy == null || b.busy == null || b.time <= a.time || b.busy < a.busy) return null;
    let dt = b.time - a.time, db = b.busy - a.busy;
    if (db > dt) return null;
    return 100.0 * db / dt;
};
export function group(freq, width) {
    if (freq < 3000) return width == 20 ? {freq, center: freq, width, members: [freq], sec: 0} : null;
    let starts = width == 80 ? [5180,5260,5500,5580,5660,5745] :
        width == 40 ? [5180,5220,5260,5300,5500,5540,5580,5620,5660,5700,5745,5785] : [];
    if (width == 20) return {freq, center: freq, width, members: [freq], sec: 0};
    for (let start in starts) if (freq >= start && freq < start + width && (freq - start) % 20 == 0) {
        let members = [];
        for (let f = start; f < start + width; f += 20) push(members, f);
        return {freq, center: start + width / 2 - 10, width, members,
            sec: int((freq - start) / 20) % 2 ? -1 : 1};
    }
    return null;
};
export function dfs_ready(g, caps) {
    return !!g && !length(filter(g.members, f => !caps[f] || caps[f].disabled ||
        caps[f].radar && caps[f].dfs_state != 2));
};
export function uses_dfs(g, caps) {
    return !!g && !!length(filter(g.members, f => caps[f]?.radar));
};
export function permitted(g, caps, rules, allowed, dfs_mode) {
    if (!g || g.width > 80) return false;
    let dfs = dfs_mode == 'available' || dfs_mode == 'prepare';
    for (let f in g.members) {
        let c = caps[f];
        if (!c || c.disabled || index(allowed, channel(f)) < 0) return false;
        if (c.no_ir && !(dfs && c.radar)) return false;
        if (c.radar && (!dfs || index([0,2], c.dfs_state) < 0 ||
            dfs_mode == 'available' && c.dfs_state != 2)) return false;
        if (g.width >= 80 && c.no_80mhz) return false;
    }
    let p = caps[g.freq];
    if (g.sec == 1 && p.no_ht40_plus || g.sec == -1 && p.no_ht40_minus) return false;
    for (let rule in rules) {
        if (!rule || !dfs && rule.reg_rule_flags & (16 | 128) ||
            rule.reg_rule_flags & 128 && !(dfs && rule.reg_rule_flags & 16)) continue;
        if ((g.center - g.width / 2) * 1000 < rule.freq_range_start ||
            (g.center + g.width / 2) * 1000 > rule.freq_range_end ||
            g.width * 1000 > rule.freq_range_max_bw) continue;
        // Fail closed on the observed Marvell per-phy/global power mismatch.
        let power_ok = true;
        for (let f in g.members) if (caps[f].max_tx_power == null ||
            caps[f].max_tx_power > rule.power_rule_max_eirp) power_ok = false;
        if (power_ok) return true;
    }
    return false;
};
export function neighbor(b) {
    if (!b || b.signal_mbm == null || b.signal_mbm >= 0 || !b.frequency) return null;
    let g = group(b.frequency, 20), load = null;
    for (let ie in b.information_elements ?? []) {
        if (ie.type == 11 && length(ie.data) >= 3) load = ord(ie.data, 2) * 100.0 / 255;
        if (ie.type == 61 && length(ie.data) >= 2) {
            let secondary = ord(ie.data, 1) & 3;
            if (secondary == 1 || secondary == 3)
                g = {freq: b.frequency, center: b.frequency + (secondary == 1 ? 10 : -10), width: 40};
        }
    }
    for (let ie in b.information_elements ?? []) if (ie.type == 192 && length(ie.data) >= 3) {
        let w = ord(ie.data, 0), c = ord(ie.data, 1), c2 = ord(ie.data, 2);
        if (w>=1 && w<=3 && c) {
            g = {freq: b.frequency, center: 5000 + 5 * c, width: w == 2 ? 160 : 80};
            if(w==1&&c2&&max(c2-c,c-c2)==8){
                g.center=5000+5*c2;g.width=160;
            }else if(c2&&(w==3||w==1&&max(c2-c,c-c2)>16)){
                // 80+80 occupies two separate blocks, not the empty gap.
                g.width=160;g.segments=[{center:g.center,width:80},{center:5000+5*c2,width:80}];
            }
        }
    }
    return {...g, signal: b.signal_mbm / 100, load};
};
// The graph and planner share this frequency-area pressure calculation.
// Beacon strength/load is evidence of competition, not measured airtime.
export function pressure(lo, hi, observations) {
    let cost = 0;
    for (let n in observations) {
        let strength = max(0, min(1, (n.signal + 95) / 55.0));
        let weight = n.load == null ? 12 : 4 + n.load / 4;
        for(let part in n.segments ?? [n])
            cost += 1.0*max(0,min(hi,part.center+part.width/2)-max(lo,part.center-part.width/2))/(hi-lo)*strength*weight;
    }
    return cost;
};
export function quality(g, observations, busy, max_width) {
    let total=0, measured=0, members=g.members ?? [g.freq];
    for(let f in members){
        let sensed=busy[f];
        if(sensed!=null)measured++;
        // Missing airtime is unknown, not invented congestion. Scanned neighbour
        // pressure remains evidence; uncertainty is a separate small cost.
        total+=min(100,max(pressure(f-10,f+10,observations)*100/48,sensed ?? 0));
    }
    let occupancy=1.0*total/length(members);
    let capacity=g.width*(1-occupancy/100.0);
    let uncertainty=3.0*(length(members)-measured)/length(members);
    return {cost:100-100*capacity/max_width+uncertainty,occupancy,capacity,measured,uncertainty};
};
export function score(g, observations, busy, max_width) {
    return quality(g,observations,busy,max_width).cost;
};
export function rate_candidate(g, observations, busy, max_width, power_cost) {
    let q=quality(g,observations,busy,max_width);
    // Compare placements on equal terms. The configured improvement threshold
    // supplies hysteresis; an extra destination-only cost would count it twice.
    return {...g,...q,power_cost,cost:q.cost+power_cost};
};
export function prefer_width(candidates,others,threshold) {
    // First find room for a wide channel without overlapping our other radios.
    // A narrower fallback competes on capacity only when wider space is crowded.
    let usable=filter(candidates,g=>g.occupancy<(threshold ?? 70)&&
        !length(filter(others,o=>overlap(g,o)>0.000001)));
    let width=length(usable)?max(...map(usable,g=>g.width)):0;
    return {width,candidates:map(candidates,g=>({...g,width_deficit:max(0,width-g.width)}))};
};
export function placement(choices,penalty) {
    let cost=0,interference=0,width_deficit=0;
    for(let i,g in choices){
        cost+=g.cost;
        width_deficit+=g.width_deficit ?? 0;
        for(let j=0;j<i;j++)interference+=overlap(g,choices[j]);
    }
    return {cost:cost+penalty*interference,overlap:interference,width_deficit};
};
export function better(a,b,separate) {
    if(!b)return true;
    if(separate&&max(a.overlap-b.overlap,b.overlap-a.overlap)>0.000001)return a.overlap<b.overlap;
    if((a.width_deficit ?? 0)!=(b.width_deficit ?? 0))return (a.width_deficit ?? 0)<(b.width_deficit ?? 0);
    return a.cost<b.cost-0.000001;
};
export function plan(radios, penalty, separate) {
    separate=separate ?? true;
    let best = null, count = 0, truncated=false;
    function visit(i, chosen, cost, interference, width_deficit) {
        if (++count > 100000) {truncated=true;return;}
        if(best){
            if(separate&&interference>best.overlap+0.000001)return;
            if(!separate||interference>=best.overlap-0.000001)
                if(width_deficit>best.width_deficit||width_deficit==best.width_deficit&&cost>=best.cost)return;
        }
        if (i == length(radios)) {
            let result={cost,overlap:interference,width_deficit,choices:[...chosen]};
            if(better(result,best,separate))best=result;
            return;
        }
        for (let g in radios[i].candidates) {
            let added=0;for(let p in chosen)added+=overlap(g,p);
            visit(i+1,[...chosen,g],cost+g.cost+penalty*added,interference+added,width_deficit+(g.width_deficit ?? 0));
            if(truncated)return;
        }
    }
    visit(0, [], 0, 0, 0);
    if(best){best.truncated=truncated;best.visited=count;}
    return best;
};
// Only independently beneficial steps are executable. A good final layout
// never licenses an overlapping or worse intermediate arrangement.
export function next_steps(models,chosen,penalty,separate,threshold) {
    let current=map(models,m=>m.current),base=placement(current,penalty),steps=[];
    for(let i,m in models)for(let g in m.candidates){
        if(same(g,m.current))continue;
        let after=[...current];after[i]=g;
        let result=placement(after,penalty),gain=base.cost-result.cost;
        let reduced=result.overlap<base.overlap-0.000001;
        let widened=result.width_deficit<base.width_deficit;
        if(separate&&result.overlap>base.overlap+0.000001)continue;
        if(!(separate&&reduced)&&result.width_deficit>base.width_deficit)continue;
        if(!(separate&&reduced)&&!widened&&gain<threshold)continue;
        push(steps,{index:i,target:g,gain,overlap:result.overlap,
            reduced,widened,width_deficit:result.width_deficit,planned:same(g,chosen.choices[i])});
    }
    return sort(steps,(a,b)=>(separate?a.overlap-b.overlap:0)||
        (b.planned?1:0)-(a.planned?1:0)||b.gain-a.gain);
};
export function confirmations(previous,steps,models,survey,tolerance) {
    let next={};
    for(let s in steps){
        let name=models[s.index].name;if(next[name])continue;
        let old=previous[name];
        function key_for(x){return sprintf('%J',[models[x.index].current.center,models[x.index].current.width,x.target.center,x.target.width]);}
        // Do not restart confirmation just because nearly tied alternatives
        // exchange places in noisy scans. The retained choice must still pass
        // the gain/overlap guards on this fresh survey.
        if(old)for(let x in steps)if(x.index==s.index&&key_for(x)==old.key&&
            x.overlap==s.overlap&&x.width_deficit==s.width_deficit&&x.gain>=s.gain-(tolerance ?? 0)){s=x;break;}
        let key=key_for(s);
        next[name]={key,survey,count:old?.key==key?old.count+(old.survey==survey?0:1):1};
        s.confirmations=next[name].count;
    }
    return next;
};
export function survey_covers(rules,r,frequencies,dfs_mode) {
    let required=[];
    for(let w in r.config.widths)for(let ch in r.config.channels){
        let g=group(r.band=='2g'?2407+ch*5:5000+ch*5,w);
        if(permitted(g,r.caps,rules,r.config.channels,dfs_mode))for(let f in g.members)push(required,f);
    }
    // Adjacent 2.4GHz networks overlap candidate channels, even when only
    // 1/6/11 are selectable. Their frequencies must also have been visited.
    if(r.band=='2g')for(let ch=1;ch<=13;ch++){
        let f=2407+ch*5;if(r.caps[f]&&!r.caps[f].disabled)push(required,f);
    }
    return length(required)>0&&!length(filter(required,f=>index(frequencies,f)<0));
};
export function reconfigure_text(text, g, band) {
    if(type(text)!='string'||!g||index([20,40,80],g.width)<0)return null;
    let lines=split(text,'\n'),count=0,ht=0;
    for(let i,line in lines){
        if(match(line,/^(ieee80211ax|ieee80211be)=1$/)||match(line,/^op_class=[1-9]/))return null;
        if(match(line,/^channel=/)){lines[i]='channel='+channel(g.freq);count++;}
        if(match(line,/^ht_capab=/)){
            line=replace(line,/\[HT40[+-]\]/g,'');
            lines[i]=line+(g.sec?(g.sec>0?'[HT40+]':'[HT40-]'):'');ht++;
        }
        if(match(line,/^vht_oper_chwidth=/))lines[i]='vht_oper_chwidth='+(g.width==80?1:0);
        if(match(line,/^vht_oper_centr_freq_seg0_idx=/))lines[i]='vht_oper_centr_freq_seg0_idx='+channel(g.center);
        if(match(line,/^vht_oper_centr_freq_seg1_idx=/))lines[i]='vht_oper_centr_freq_seg1_idx=0';
    }
    if(count!=1||ht!=1||band=='2g'&&g.width!=20)return null;
    return join('\n',lines);
};
// Temporary, hidden, single-BSS AP for hostapd-managed CAC. Existing credentials
// stay local; the saved original is restored before the serving radio moves.
export function preparation_text(original, g) {
    let text = reconfigure_text(original, g, '5g');
    if (!text || length(filter(split(text,'\n'), l => match(l,/^(interface|bss)=/))) != 1 ||
        !match(text, /\nieee80211h=1\n/)) return null;
    let lines = filter(split(text,'\n'), l => !match(l,/^(ssid|ssid2|ignore_broadcast_ssid|max_num_sta)=/));
    push(lines, 'ssid=Channel-Check', 'ignore_broadcast_ssid=1', 'max_num_sta=0', '');
    return join('\n', lines);
};
// Multiple callbacks can inspect counters in the same uptime second. Preserve
// the last valid rate and its baseline until a measurable interval has elapsed.
export function traffic_sample(prev,rate,quiet,t,bytes,clients,limit) {
    if(!prev||prev.clients!=clients||bytes<prev.bytes||t<prev.t)
        return {sample:{t,bytes,clients},rate:null,quiet:null};
    if(t==prev.t)return {sample:prev,rate,quiet};
    rate=(bytes-prev.bytes)*8.0/(t-prev.t)/1000000;
    return {sample:{t,bytes,clients},rate,quiet:rate>limit?null:quiet ?? t};
};
export function scan_eligible(clients,rate,quiet,last_end,t,cfg) {
    if(!clients)return true;
    if(cfg.scan_policy=='idle'||rate==null)return false;
    if(cfg.scan_policy=='paced')return rate<=cfg.scan_max_mbps&&
        (last_end==null||t-last_end>=cfg.scan_gap);
    return rate<=cfg.max_mbps&&quiet_ready(quiet,t,cfg.quiet_seconds);
};
export function tests() {
    let n = 0;
    function eq(a, b) { if (a != b) die(sprintf('FAIL %J != %J\n',a,b)); n++; }
    eq(overlap(group(5180,80),group(5220,80)),1);
    eq(overlap(group(5180,40),group(5220,40)),0);
    eq(overlap(group(2412,20),group(2437,20)),0);
    eq(overlap(group(2412,20),group(2417,20)),0.75);
    eq(group(5180,80).center,5210); eq(group(5240,80).sec,-1);
    eq(group(5745,80).center,5775); eq(group(2412,40),null);
    eq(delta_busy({time:100,busy:50},{time:200,busy:70}),20);
    eq(delta_busy({time:100,busy:50},{time:100,busy:50}),null);
    eq(delta_busy({time:100,busy:50},{time:200,busy:30}),null);
    eq(delta_busy({time:100,busy:50},{time:200,busy:200}),null);
    eq(delta_busy(null,{time:200,busy:70}),null);
    eq(delta_busy({busy:50},{busy:70}),null);
    let caps = {}; for(let f in [5180,5200,5220,5240]) caps[f]={max_tx_power:2300};
    let rules = [{reg_rule_flags:0,freq_range_start:5150000,freq_range_end:5250000,freq_range_max_bw:80000,power_rule_max_eirp:2300}];
    eq(permitted(group(5180,80),caps,rules,[36,40,44,48]),true);
    caps[5240].radar=true; eq(permitted(group(5180,80),caps,rules,[36,40,44,48]),false);
    caps[5240].radar=false; caps[5180].no_ir=true;
    eq(permitted(group(5180,40),caps,rules,[36,40,44,48]),false);
    caps[5180].no_ir=false; caps[5180].max_tx_power=3000;
    eq(permitted(group(5180,40),caps,rules,[36,40,44,48]),false);
    caps[5180].max_tx_power=2300;
    eq(permitted(group(5180,80),caps,rules,[36,40]),false);
    eq(score(group(5180,20),[],{},20),3);
    let candidates = [{...group(5180,40),cost:10},{...group(5220,40),cost:10},{...group(5180,80),cost:0}];
    let p=plan([{candidates},{candidates}],100);
    eq(p.cost,20); eq(overlap(p.choices[0],p.choices[1]),0);
    eq(neighbor({frequency:5180,signal_mbm:-5000,information_elements:[]}).width,20);
    eq(neighbor({frequency:5180,signal_mbm:0}),null);
    eq(neighbor({frequency:5180,signal_mbm:-5000,information_elements:[{type:192,data:chr(1)+chr(42)+chr(50)}]}).width,160);
    eq(neighbor({frequency:5180,signal_mbm:-5000,information_elements:[{type:192,data:chr(1)+chr(42)+chr(50)}]}).center,5250);
    let splitwide=neighbor({frequency:5180,signal_mbm:-4000,information_elements:[{type:192,data:chr(1)+chr(42)+chr(106)}]});
    eq(pressure(5350,5370,[splitwide]),0);
    eq(pressure(5170,5250,[splitwide]),12);
    eq(pressure(5490,5570,[splitwide]),12);
    eq(neighbor({frequency:2412,signal_mbm:-5000,information_elements:[{type:61,data:chr(1)+chr(1)}]}).center,2422);
    eq(neighbor({frequency:2412,signal_mbm:-5000,information_elements:[{type:11,data:chr(1)+chr(0)+chr(255)}]}).load,100);
    let config='channel=36\nht_capab=[HT40+][LDPC]\nvht_oper_chwidth=1\nvht_oper_centr_freq_seg0_idx=42\nssid=Unchanged\n';
    let changed=reconfigure_text(config,group(5220,40),'5g');
    eq(index(changed,'channel=44')>=0,true);eq(index(changed,'vht_oper_chwidth=0')>=0,true);
    eq(index(changed,'seg0_idx=46')>=0,true);eq(index(changed,'ssid=Unchanged')>=0,true);
    eq(reconfigure_text(config+'ieee80211ax=1\n',group(5220,40),'5g'),null);
    eq(reconfigure_text('channel=36\n',group(5220,40),'5g'),null);
    let dcaps={}; for(let f in [5260,5280,5300,5320])dcaps[f]={radar:true,no_ir:true,dfs_state:0,max_tx_power:2000};
    let drules=[{reg_rule_flags:16,freq_range_start:5250000,freq_range_end:5350000,freq_range_max_bw:80000,power_rule_max_eirp:2000}];
    let dg=group(5260,80), allowed=[52,56,60,64];
    eq(permitted(dg,dcaps,drules,allowed),false);
    eq(permitted(dg,dcaps,drules,allowed,'available'),false);
    eq(permitted(dg,dcaps,drules,allowed,'prepare'),true);
    eq(dfs_ready(dg,dcaps),false);
    for(let f in dg.members)dcaps[f].dfs_state=2;
    eq(dfs_ready(dg,dcaps),true);
    eq(permitted(dg,dcaps,drules,allowed,'available'),true);
    dcaps[5320].dfs_state=1;
    eq(dfs_ready(dg,dcaps),false);
    eq(permitted(dg,dcaps,drules,allowed,'prepare'),false);
    dcaps[5320].dfs_state=null;
    eq(permitted(dg,dcaps,drules,allowed,'prepare'),false);
    eq(uses_dfs(dg,dcaps),true);
    let prep=preparation_text('interface=ap0\nieee80211h=1\n'+config,dg);
    eq(index(prep,'ssid=Unchanged'),-1);
    eq(index(prep,'max_num_sta=0')>=0,true);
    eq(index(prep,'ignore_broadcast_ssid=1')>=0,true);
    eq(preparation_text('interface=ap0\nieee80211h=1\n'+config+'bss=ap1\n',dg),null);
    eq(preparation_text('interface=ap0\n'+config,dg),null);
    eq(quiet_ready(null,100,60),false);eq(quiet_ready(50,100,60),false);
    eq(quiet_ready(40,100,60),true);eq(quiet_ready(110,100,60),false);
    let net={ssid:'test',encryption:'psk2',key:'synthetic',network:['lan']};
    eq(same_network(net,{...net}),true);
    eq(same_network(net,{...net,key:'different'}),false);
    eq(same_network(net,{...net,network:['guest']}),false);
    eq(same_network({...net,network:[]},{...net,network:[]}),false);
    eq(same_network(net,{...net,ssid:'different'}),false);
    eq(force_signal_ok([], 'target', -60, -72, -65),true);
    eq(force_signal_ok([], 'target', -70, -72, -65),false);
    eq(force_signal_ok([], 'target', null, -72, -65),false);
    eq(force_signal_ok([{node:'target',age:100,rcpi:40,rssi:-80}], 'target', -40, -72, -65),false);
    eq(force_signal_ok([{node:'target',age:100,rcpi:90,rssi:-65}], 'target', -75, -72, -65),true);
    printf('PASS: %d channel geometry, regulatory, stale-data and coordination checks\n',n);
};
