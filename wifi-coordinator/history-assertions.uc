import {snapshot,read_block,manifest} from './history-store-test.uc';
import {LISTS,empty} from '../channel-coordinator/files/history-codec.uc';
export function history(){let s=snapshot(),out=empty();for(let d in s.manifest.blocks){let h=read_block(d);for(let k in LISTS)out[k]=[...out[k],...h[k]];}for(let k in LISTS){out[k]=[...out[k],...s.active[k]];out[k]=sort(out[k],(a,b)=>(a.start ?? a.time)-(b.start ?? b.time));}s.release();return out;};
export function archive(){let m=manifest(),bytes=0;for(let d in m.blocks)bytes+=d.size;return {...m,files:m.blocks,bytes};};
