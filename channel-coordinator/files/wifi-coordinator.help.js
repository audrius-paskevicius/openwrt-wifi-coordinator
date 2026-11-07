'use strict';
'require ui';

var summaries={
 enabled:'Enable or stop this controller.',
 mode:'Choose how this controller acts.',
 interval:'Pause between completed spectrum surveys.',
 improvement:'Minimum score improvement for a cost-based move.',
 min_dwell:'Minimum time to stay after a successful move.',
 retry_delay:'Delay before retrying a deferred attempt.',
 radar_half_life:'Time for remembered radar risk to halve.',
 persist:'Save verified channel settings every six hours.',
 clear_stop:'Resume automatic operation after checking recovery.',
 max_mbps:'Traffic ceiling for the explicit quiet-only policies.',
 quiet_seconds:'How long traffic must remain below the quiet threshold.',
 handoff_wait:'Time to try moving clients before a required restart.',
 handoff_escalation:'Choose how firmly to move clients to another radio.',
 ban_seconds:'Briefly prevent return after a forced handoff.',
 allow_reconnect:'Allow a brief radio restart if handoff cannot finish.',
 protected_clients:'Keep these clients out of automatic handoffs and occupied restarts.',
 csa_count:'Number of channel-switch announcements before moving.',
 dfs_mode:'Choose whether and how to use channels requiring radar clearance.',
 dfs_helper:'Choose a spare radio for the radar check.',
 cac_timeout:'Maximum wait for radar preparation to finish.',
 scan_policy:'Choose when occupied radios may scan.',
 scan_duty:'Maximum share of serving time spent scanning.',
 scan_gap:'Minimum serving time between paced scan visits.',
 scan_wait:'Extra time to wait for an available scanner.',
 scanner:'Choose a scanner, or let the controller select one.',
 scan_type:'Choose passive listening or active probes where allowed.',
 scan_batch:'Frequencies per visit in non-paced scan modes.',
 max_age:'Maximum age of evidence used for planning.',
 separate_radios:'Prefer non-overlapping placements for our radios.',
 overlap_penalty:'Cost of overlap when strict separation is disabled.',
 wide_threshold:'Congestion level above which narrower channels may compete.',
 managed:'Include this radio in automatic channel planning.',
 occupied_policy:'Choose how channel changes handle connected clients.',
 method:'Use a live announcement or restart this radio.',
 width_method:'Choose how changes of channel width are applied.',
 channels:'Use Auto, or list primary channels. Width is chosen separately.',
 widths:'Use auto, or list widths in MHz to compare.',
 preferred_radio:'Radio to recommend when its signal is sufficient.',
 min_rssi:'Minimum measured signal at the preferred radio.',
 settle_time:'Wait after connection before recommending a move.',
 cooldown:'Minimum time between roaming recommendations.',
 max_attempts:'Limit recommendations before a longer pause.',
 history_enabled:'Record new history; turning off pauses recording.',
 history_hours:'Maximum history age to retain and display.',
 clear_history:'Delete recorded history when applying settings.'
};
function explain(shortText,longText,title){
 var opened=false;
 // LuCI supplies hover/focus handling, placement and theme colours.
 var node=E('span',{'class':'wc-setting-help','role':'button','tabindex':'0',
  'data-tooltip':longText,'data-tooltip-style':'wc-help-tooltip',
  'aria-label':(title||shortText)+'. '+longText},shortText);
 function toggle(){opened=!opened;ui[opened?'showTooltip':'hideTooltip']({target:node});}
 node.addEventListener('click',toggle);
 node.addEventListener('blur',function(){opened=false;});
 node.addEventListener('keydown',function(e){
  if(e.key=='Escape'){opened=false;ui.hideTooltip({target:node});e.stopPropagation();}
  else if(e.key=='Enter'||e.key==' '){e.preventDefault();toggle();}
 });
 return node;
}
document.addEventListener('tooltip-open',function(e){
 var target=e.detail&&e.detail.target;
 if(!target||target.getAttribute('data-tooltip-style')!='wc-help-tooltip')return;
 var box=e.target.getBoundingClientRect(),width=document.documentElement.clientWidth;
 if(box.right>width-8)e.target.style.left=Math.max(8,width-box.width-8)+window.pageXOffset+'px';
});
function compact(element){
 if(typeof element.description=='string'&&element.description){
  var full=element.description,shortText=summaries[element.option];
  if(!shortText)shortText=(full.match(/^.*?[.!?](?:\s|$)/)||[full])[0].trim();
  element.description=explain(_(shortText),full,element.title);
 }
 (element.children||[]).forEach(compact);
 return element;
}
return L.Class.extend({compact:compact,explain:explain});
