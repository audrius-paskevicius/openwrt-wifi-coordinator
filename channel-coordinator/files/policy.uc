// Shared channel geometry, regulatory checks and execution helpers.
export function dfs_policy(mode,global_region,radio_region,driver_report,driver_present) {
    if(mode=='off')return {mode:'off',reason:null};
    if(index([1,2,3],global_region)<0||radio_region!=global_region)
        return {mode:'off',reason:'DFS blocked: global and radio DFS regions must be known and match'};
    if(driver_present){
        let m=match(driver_report ?? '',/dfs_region:\s*([0-9]+)/);
        if(!m||int(m[1])!=global_region)
            return {mode:'off',reason:'DFS blocked: mwlwifi internal radar region is unknown or differs from the kernel region'};
    }
    return {mode,reason:null};
};
export function configured_country(radios) {
    let countries=[];
    for(let r in radios)if(index(countries,r.country ?? '')<0)push(countries,r.country ?? '');
    return length(countries)==1&&match(countries[0],/^[A-Z]{2}$/)?countries[0]:null;
};
// Display bands come from PHY declarations, including disabled frequencies.
// They deliberately do not depend on active APs, configured pools or history.
export function declared_bands(phys) {
    let found={};
    for(let p in phys ?? [])for(let index,b in p.wiphy_bands ?? [])if(b){
        let key=index==0?'2g':index==1?'5g':index==4?'6g':null;
        if(key)found[key]=true;
    }
    return filter(['2g','5g','6g'],b=>found[b]);
};
export function channel(f) { return f==2484?14:f < 3000 ? int((f - 2407) / 5) : int((f - 5000) / 5); };
export function frequency(ch,band) { return band=='2g'?(ch==14?2484:2407+5*ch):5000+5*ch; };
export function hardware_widths(band,capabilities) {
    let widths=[20],ht=capabilities?.ht_capa ?? 0,vht=capabilities?.vht_capa;
    if(ht&2)push(widths,40);
    if(band=='5g'&&vht!=null){
        push(widths,80);
        if(index([1,2],(vht>>2)&3)>=0)push(widths,160);
    }
    return sort(widths,(a,b)=>b-a);
};
export function configured_widths(setting,band,hardware) {
    let value=trim(setting ?? 'auto'),supported=band=='2g'?[40,20]:[160,80,40,20],widths=[];
    if(value=='auto')return hardware ?? [20];
    if(!match(value,/^[0-9]+(\s+[0-9]+)*$/))die('Use auto or space-separated widths');
    for(let token in split(value,/\s+/)){
        let width=int(token);
        if(index(supported,width)<0)die('Unsupported channel width');
        if(index(widths,width)<0)push(widths,width);
    }
    return sort(widths,(a,b)=>b-a);
};
export function configured_channels(setting,band,caps) {
    let value=trim(setting ?? 'auto'),channels=[];
    if(value=='auto'){
        for(let key,c in caps){
            let f=int(key),ch=channel(f);
            if(c.disabled||c.no_ir&&!c.radar)continue;
            if(band=='2g'?(f<2412||f>2484):(f<5005||f>=5925))continue;
            if(frequency(ch,band)!=f)continue;
            push(channels,ch);
        }
    }else{
        if(!match(value,/^[0-9]+(\s+[0-9]+)*$/))die('Use auto or space-separated channel numbers');
        for(let token in split(value,/\s+/)){
            let ch=int(token);
            if(ch<1||ch>(band=='2g'?14:184))die('Invalid channel number');
            if(index(channels,ch)<0)push(channels,ch);
        }
    }
    return sort(channels,(a,b)=>a-b);
};
export function overlap(a, b) {
    let lo = max(a.center - a.width / 2, b.center - b.width / 2);
    let hi = min(a.center + a.width / 2, b.center + b.width / 2);
    return 1.0 * max(0, hi - lo) / min(a.width, b.width);
};
export function same_block(a, b) { return a.center == b.center && a.width == b.width; };
export function same(a, b) { return a.freq == b.freq && same_block(a,b); };
export function quiet_ready(since, now, seconds) {
    return since != null && now >= since && now-since >= seconds;
};
// Only Auto can substitute a planned operation. Recovery may still restore service.
export function switch_methods(method,width_method,wrt,name,band,csa,failed_until,t) {
    method=method ?? 'auto';width_method=width_method ?? 'auto';
    if(index(['auto','csa','idle_reconfigure'],method)<0)die('Invalid switch method');
    if(index(['auto','inherit','csa','idle_reconfigure'],width_method)<0)die('Invalid width-change method');
    let automatic=!csa||wrt&&name=='radio2'?'idle_reconfigure':'csa';
    let reason=!csa?'Driver does not advertise CSA':wrt&&name=='radio2'?'Tested radio2 restart requirement':'Driver advertises CSA';
    let remaining=max(0,(failed_until ?? 0)-t);
    if(remaining>0){automatic='idle_reconfigure';reason='Recent CSA command or service failure';}
    let effective=method=='auto'?automatic:method;
    let width_restart=band=='2g'||wrt;
    let width=width_method=='inherit'?effective:width_method=='auto'?(width_restart?'idle_reconfigure':automatic):width_method;
    return {method:effective,width_method:width,requested_method:method,requested_width_method:width_method,
        method_reason:method=='auto'?reason:!csa&&method=='csa'?'Explicit CSA unavailable: driver does not advertise it':'Explicit choice',
        width_reason:width_method=='auto'?(band=='2g'?'Restart runs the HT40 coexistence check':wrt?'Tested width changes require restart':reason):width_method=='inherit'?'Follows selected channel method':!csa&&width_method=='csa'?'Explicit CSA unavailable: driver does not advertise it':'Explicit choice',
        csa_recovery_left:remaining};
};

export function setting_integer(value,lo,hi) {
    if(!match(''+value,/^-?[0-9]+$/))die('Expected an integer setting');
    let v=int(value);if(v<lo||v>hi)die('Integer setting outside allowed range');return v;
};

export function move_method(config,source,target) {
    return source.width!=target.width||target.freq<3000&&target.width==40?(config.width_method ?? config.method):config.method;
};
export function live_width(index) { return [20,20,40,80,null,160][index]; };
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
export function group(freq, width, center) {
    if (width == 20) return {freq, center: freq, width, members: [freq], sec: 0};
    if(freq<3000){
        if(width!=40||freq<2412||freq>2472||(freq-2412)%5)return null;
        let sec=center!=null?(center>freq?1:-1):(freq<=2452?1:-1),other=freq+sec*20;
        if(center!=null&&center!=freq+sec*10||other<2412||other>2472)return null;
        return {freq,center:freq+sec*10,width,members:sort([freq,other]),sec};
    }
    let starts = width==160?[5180,5500,5745]:width == 80 ? [5180,5260,5500,5580,5660,5745,5825] :
        width == 40 ? [5180,5220,5260,5300,5500,5540,5580,5620,5660,5700,5745,5785,5825,5865] : [];
    for (let start in starts) if (freq >= start && freq < start + width && (freq - start) % 20 == 0) {
        let members = [];
        for (let f = start; f < start + width; f += 20) push(members, f);
        return {freq, center: start + width / 2 - 10, width, members,
            sec: int((freq - start) / 20) % 2 ? -1 : 1};
    }
    return null;
};
export function placements(freq,width) {
    if(freq<3000&&width==40)return filter([group(freq,width,freq-10),group(freq,width,freq+10)],g=>g!=null);
    let g=group(freq,width);return g?[g]:[];
};
export function dfs_ready(g, caps) {
    return !!g && !length(filter(g.members, f => !caps[f] || caps[f].disabled ||
        caps[f].radar && caps[f].dfs_state != 2));
};
export function uses_dfs(g, caps) {
    return !!g && !!length(filter(g.members, f => caps[f]?.radar));
};
export function permitted(g, caps, rules, allowed, dfs_mode) {
    if (!g || index([20,40,80,160],g.width)<0 || index(allowed,channel(g.freq))<0) return false;
    let dfs = dfs_mode == 'available' || dfs_mode == 'prepare';
    for (let f in g.members) {
        let c = caps[f];
        if (!c || c.disabled) return false;
        if (c.no_ir && !(dfs && c.radar)) return false;
        if (c.radar && (!dfs || index([0,2], c.dfs_state) < 0 ||
            dfs_mode == 'available' && c.dfs_state != 2)) return false;
        if (g.width >= 80 && c.no_80mhz) return false;
        if (g.width==160 && c.no_160mhz || c.no_20mhz) return false;
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
    // AUTO_BW permits a block spanning contiguous regulatory rules. Retain
    // each member's own power/restriction checks; never bridge a spectrum gap.
    let automatic=filter(rules,r=>r&&(r.reg_rule_flags&2048)&&
        !(!dfs&&r.reg_rule_flags&(16|128))&&!(r.reg_rule_flags&128&&!(dfs&&r.reg_rule_flags&16)));
    let edge=(g.center-g.width/2)*1000,end=(g.center+g.width/2)*1000;
    for(let rule in sort(automatic,(a,b)=>a.freq_range_start-b.freq_range_start)){
        if(rule.freq_range_start<=edge&&rule.freq_range_end>edge)edge=rule.freq_range_end;
    }
    if(edge<end)return false;
    for(let f in g.members)if(!length(filter(automatic,r=>r.freq_range_start<=(f-10)*1000&&r.freq_range_end>=(f+10)*1000&&
        r.freq_range_max_bw>=20000&&caps[f].max_tx_power!=null&&caps[f].max_tx_power<=r.power_rule_max_eirp)))return false;
    if(length(automatic))return true;
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
export function survey_covers(rules,r,frequencies,dfs_mode) {
    let required=[];
    for(let w in r.config.widths)for(let ch in r.config.channels)for(let g in placements(frequency(ch,r.band),w)){
        if(permitted(g,r.caps,rules,r.config.channels,dfs_mode))for(let f in g.members)push(required,f);
    }
    // Adjacent 2.4GHz networks overlap candidate channels, even when only
    // 1/6/11 are selectable. Their frequencies must also have been visited.
    if(r.band=='2g')for(let ch=1;ch<=13;ch++){
        let f=2407+ch*5;if(r.caps[f]&&!r.caps[f].disabled)push(required,f);
    }
    return length(required)>0&&!length(filter(required,f=>index(frequencies,f)<0));
};
export function reconfigure_text(text, g, band, capabilities) {
    if(type(text)!='string'||!g||index([20,40,80,160],g.width)<0)return null;
    let lines=split(text,'\n'),count=0,ht=0,vht=0,op=0,segment=0;
    for(let i,line in lines){
        if(match(line,/^(ieee80211ax|ieee80211be)=1$/)||match(line,/^op_class=[1-9]/))return null;
        if(match(line,/^channel=/)){lines[i]='channel='+channel(g.freq);count++;}
        if(match(line,/^ht_capab=/)){
            line=replace(line,/\[HT40[+-]\]/g,'');
            lines[i]=line+(g.sec?(g.sec>0?'[HT40+]':'[HT40-]'):'');ht++;
        }
        if(match(line,/^vht_capab=/)){
            vht++;line=replace(line,/\[(VHT160|VHT160-80PLUS80|SHORT-GI-160)\]/g,'');
            lines[i]=line+(g.width==160?'[VHT160]'+((capabilities?.vht_capa ?? 0)&64?'[SHORT-GI-160]':''):'');
        }
        if(match(line,/^vht_oper_chwidth=/)){lines[i]='vht_oper_chwidth='+(g.width==160?2:g.width==80?1:0);op++;}
        if(match(line,/^vht_oper_centr_freq_seg0_idx=/)){lines[i]='vht_oper_centr_freq_seg0_idx='+channel(g.center);segment++;}
        if(match(line,/^vht_oper_centr_freq_seg1_idx=/))lines[i]='vht_oper_centr_freq_seg1_idx=0';
    }
    if(count!=1||ht!=1||band=='2g'&&g.width>40||g.width==160&&(vht!=1||op!=1||segment!=1))return null;
    // A 2.4 GHz HT40 restart must let hostapd run its mandatory coexistence check.
    if(band=='2g'&&g.width==40){
        lines=filter(lines,l=>!match(l,/^(noscan|obss_interval)=/));
        push(lines,'noscan=0','obss_interval=300');
    }
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
