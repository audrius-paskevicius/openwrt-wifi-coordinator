setup('reconnect');check(restore_preparation()&&content=='old'&&!j&&applies[0].allow,'interrupted occupied restart restores missing AP');
setup('reconnect');live={ifname:'phy1-ap0',wiphy_freq:2412,center_freq1:2412,channel_width:1};
check(restore_preparation()&&content=='old'&&!j&&!length(applies),'already recovered AP does not get restarted again');
setup('reconnect');content='administrator edit';let denied=false;try{restore_preparation();}catch(e){denied=true;}
check(denied&&content=='administrator edit'&&!length(applies)&&!j,'external configuration edits remain untouched');
setup('cac');denied=false;try{restore_preparation();}catch(e){denied=true;}
check(denied&&!length(applies)&&j,'radar preparation still requires an empty AP');
setup('reconnect');j.boot='previous';check(!restore_preparation()&&!j&&!length(applies),'previous boot journal cannot apply stale runtime config');
print('PASS: '+checks+' actual recovery-helper checks\n');
