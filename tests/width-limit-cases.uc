let checks=0;function check(ok,label){if(!ok)die('FAIL: '+label+'\n');checks++;}
let list=candidates(r,[r],rules);
check(length(list)>1&&!length(filter(list,g=>g.width>20)),'observed width limit still allows narrower channel optimization');
r.current=group(2452,20);list=candidates(r,[r],rules);
check(!length(filter(list,g=>g.width>20)),'changing primary cannot bypass observed width limit');
T=1001;list=candidates(r,[r],rules);
check(length(filter(list,g=>g.width==40))>0,'expiry restores hardware width candidates');
check(join(' ',r.config.widths)=='40 20','runtime evidence does not rewrite configured width intent');
printf('PASS: %d actual width-limit candidate cases\n',checks);
