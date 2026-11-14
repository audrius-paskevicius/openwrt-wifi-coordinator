check(observed_placement(live,caps)?.width==160,'valid live 160 MHz placement retained');
for(let invalid in [null,{}, {...live,wiphy_freq:null},{...live,wiphy_freq:0},{...live,wiphy_freq:6000},
 {...live,channel_width:null},{...live,channel_width:4},{...live,channel_width:-1},
 {...live,center_freq1:null},{...live,center_freq1:5250},{...live,center_freq2:5610}]){
 check(observed_placement(invalid,caps)==null,'invalid or incomplete geometry rejected');
 fixture=invalid;traffic.radio0={time:90,bytes:100};rates.radio0=1;quiet_since.radio0=50;client_reads=0;
 check(!length(inventory()),'incomplete interface cannot enter planner inventory');
 check(unavailable_rows[0].availability=='unknown'&&state.radios.radio0.observation_unknown,'missing observation is explicit');
 check(!client_reads&&!exists(traffic,'radio0')&&!exists(rates,'radio0')&&!exists(quiet_since,'radio0'),'no fabricated counters; baseline invalidated');
 check(planning_result('comparison',[],null)==null&&cancellations>0,'incomplete live layout cannot start or accept comparison');
 check(planning_result('validation',[],{})==null,'final action validation also waits for a complete live layout');
}
check(observed_placement({...live,wiphy_freq:2412,channel_width:1,center_freq1:null},caps)?.center==2412,'20 MHz centre is the explicitly observed primary');
check(observed_placement({...live,wiphy_freq:2412,channel_width:2,center_freq1:2422},caps)?.width==40,'valid HT40 geometry retained');
check(observed_placement({...live,wiphy_freq:2412,channel_width:5,center_freq1:2412},caps)==null,'160 MHz cannot be fabricated on 2.4 GHz');
check(observed_placement(live,{'5620':{}})==null,'missing wide-block members reject inconsistent capability snapshot');
fixture=live;client_reads=0;
check(inventory()[0].current.center==5570&&client_reads==1&&!length(unavailable_rows),'fresh valid placement resumes observation');
printf('PASS: %d observation geometry and actual inventory checks\n',checks);
