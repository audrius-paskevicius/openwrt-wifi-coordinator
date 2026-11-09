let scan_cancelled=0,operation_aborted=0,next_eval=0;
let cfg={retry_delay:30},scanner={cancel:reason=>{scan_cancelled++;}},executor={abort:err=>{operation_aborted++;}};
function now(){return 100;}
