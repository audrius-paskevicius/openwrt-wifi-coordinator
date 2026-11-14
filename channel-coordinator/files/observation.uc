// Validate observed geometry before it reaches planning, counters or history.
import {group,live_width} from './policy.uc';
export function observed_placement(live,caps){
    let freq=live?.wiphy_freq,index=live?.channel_width,center=live?.center_freq1;
    if(type(freq)!='int'||freq<2412||freq>=5925||!caps?.[freq]||
       type(index)!='int'||index<0||index>5||live.center_freq2) return null;
    let width=live_width(index);
    if(!width||width>20&&type(center)!='int')return null;
    let geometry=group(freq,width,center);
    if(!geometry||center!=null&&center!=geometry.center||
       length(filter(geometry.members,f=>!caps[f])))return null;
    return geometry;
};
