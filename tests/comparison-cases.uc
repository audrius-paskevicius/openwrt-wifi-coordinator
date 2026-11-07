let checks=0;
function check(ok,label){if(!ok)die('FAIL: '+label+'\n');checks++;}
let original={evaluated_at:1234,alternatives:[{radio:'radio0',current:group(5180,80),candidates:[{cost:7}]}]};
state.proposal=original;
sample([{name:'radio0',current:group(5180,80)}]);
check(state.proposal==original&&!state.proposal.placements_changed,'unchanged placement retains comparison');
sample([{name:'radio0',current:group(5500,80)}]);
check(state.proposal==original&&state.proposal.placements_changed,'channel move marks snapshot instead of deleting it');
check(state.proposal.evaluated_at==1234&&state.proposal.alternatives[0].candidates[0].cost==7,'timestamp and comparison evidence stay intact');
sample([]);
check(state.proposal==original&&state.proposal.placements_changed,'temporarily absent radio retains comparison');
sample([{name:'radio0',current:group(5180,80)}]);
check(!state.proposal.placements_changed,'restored placement is identified correctly');
delete state.proposal;sample([]);
check(state.proposal==null,'startup does not invent a comparison');
printf('PASS: %d actual comparison-snapshot sampling cases\n',checks);
