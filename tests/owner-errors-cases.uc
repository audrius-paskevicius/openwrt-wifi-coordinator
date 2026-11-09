let checks=0;
function check(v,label){if(!v)die('FAIL: '+label+'\n');checks++;}
survey_action(()=>{die('Resource busy');});
check(scan_cancelled==1&&operation_aborted==0,'busy scanner does not abort a separate channel operation');
check(next_eval==130,'survey failure schedules a bounded retry');
execution_action(()=>{die('Prepared action invalid');});
check(operation_aborted==1&&scan_cancelled==1,'operation failure does not cancel an unrelated survey');
survey_action(()=>{});execution_action(()=>{});
check(operation_aborted==1&&scan_cancelled==1,'successful component work is unchanged');
printf('PASS: %d actual shared-owner error isolation checks\n',checks);
