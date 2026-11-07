'use strict';
'require view';
'require wifi-coordinator.disclaimer as disclaimer';

return view.extend({
 render:function(){return disclaimer.gate(function(){return disclaimer.page();});},
 handleSave:null,
 handleSaveApply:null,
 handleReset:null
});
