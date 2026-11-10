'use strict';
'require ui';

var summaries={
 enabled:'Enable channel surveys and placement planning.',
 preference_enabled:'Steer clients independently of channel planning mode.',
 mode:'Observe or apply channel changes; steering is independent.',
 interval:'Pause between completed spectrum surveys.',
 improvement:'Base movement cost and required net gain; higher resists disruption.',
 min_dwell:'Minimum time to stay after a successful move.',
 radar_half_life:'Time for remembered radar risk to halve.',
 persist:'Save verified channel settings every six hours.',
 clear_stop:'Resume automatic operation after checking recovery.',
 max_mbps:'Traffic ceiling for the explicit quiet-only policies.',
 quiet_seconds:'How long traffic must remain below the quiet threshold.',
 handoff_wait:'Shared escalation window for preference and channel handoffs.',
 handoff_escalation:'One steering strength for preference and channel/radar handoffs.',
 allow_reconnect:'Allow a brief radio restart if handoff cannot finish.',
 protected_clients:'Enter a Wi-Fi MAC address, then click + to add it. Empty means none.',
 verify_unprobed:'How long to watch clients that cannot answer reachability probes.',
 handoff_target_min:'Fresh weaker reports block requests and disconnections.',
 handoff_source_min:'Decisive only: same-band source signal for an unmeasured destination.',
 dfs_mode:'Choose whether and how to use channels requiring radar clearance.',
 dfs_helper:'Choose a spare radio for the radar check.',
 scan_policy:'Choose when occupied radios may scan.',
 scan_duty:'Maximum share of serving time spent scanning.',
 scan_gap:'Minimum serving time between paced scan visits.',
 scanner:'Choose a scanner, or let the controller select one.',
 scan_type:'Choose passive listening or active probes where allowed.',
 max_age:'Evidence lifetime and initial retry wait after uncertain results.',
 separate_radios:'Prefer non-overlapping placements for our radios.',
 overlap_penalty:'Cost of overlap when strict separation is disabled.',
 managed:'Include this radio in automatic channel planning.',
 occupied_policy:'Choose how channel changes handle connected clients.',
 method:'Auto adapts; an explicit method stays fixed.',
 width_method:'Auto, follow channel method, or a fixed method.',
 channels:'Use Auto, or list primary channels. Width is chosen separately.',
 widths:'Use auto, or list widths in MHz to compare.',
 preferred_radio:'Preferred destination when network and safeguards permit.',
 settle_time:'Wait after connection before recommending a move.',
 cooldown:'Shared pause between client/destination steering attempts.',
 max_attempts:'Shared attempt limit before a longer pause.',
 history_enabled:'Record new history; turning off pauses recording.',
 history_hours:'Maximum history age to retain and display.',
 clear_history:'Delete recorded history when applying settings.'
};
function explain(shortText,longText,title){
 // LuCI Value and NamedSection render descriptions only when they are strings.
 // Serialize DOM-built markup so attribute/text escaping stays with the browser.
 var node=E('span',{'class':'wc-setting-help','role':'button','tabindex':'0',
  'data-tooltip':longText,'data-tooltip-style':'wc-help-tooltip',
  'aria-label':(title||shortText)+'. '+longText});
 node.textContent=shortText;
 return node.outerHTML;
}
var pinned=null;
function helpTarget(target){
 if(!target||!target.closest)return null;
 var node=target.closest('.wc-setting-help');
 if(node)return node;
 // Include the theme's question-mark pseudo-element beside the description.
 var description=target.closest('.cbi-value-description');
 return description&&description.querySelector('.wc-setting-help');
}
function toggle(node){
 if(pinned===node){pinned=null;ui.hideTooltip({target:node});}
 else{pinned=node;ui.showTooltip({target:node});}
}
// Delegation survives LuCI re-rendering after Save & Apply.
document.addEventListener('click',function(e){var node=helpTarget(e.target);if(node)toggle(node);});
document.addEventListener('keydown',function(e){
 var node=helpTarget(e.target);if(!node)return;
 if(e.key=='Escape'){pinned=null;ui.hideTooltip({target:node});e.stopPropagation();}
 else if(e.key=='Enter'||e.key==' '){e.preventDefault();toggle(node);}
});
document.addEventListener('mouseover',function(e){
 var node=helpTarget(e.target);if(node&&node!==e.target&&!node.contains(e.target))ui.showTooltip({target:node});
});
document.addEventListener('tooltip-close',function(){pinned=null;});
document.addEventListener('tooltip-open',function(e){
 var target=e.detail&&e.detail.target;
 if(!target||target.getAttribute('data-tooltip-style')!='wc-help-tooltip')return;
 var box=e.target.getBoundingClientRect(),width=document.documentElement.clientWidth;
 if(box.right>width-8)e.target.style.left=Math.max(8,width-box.width-8)+window.pageXOffset+'px';
});
function compact(element){
 if(typeof element.description=='string'&&element.description&&element.description.indexOf('class="wc-setting-help"')<0){
  var full=element.description,shortText=summaries[element.option];
  if(!shortText)shortText=(full.match(/^.*?[.!?](?:\s|$)/)||[full])[0].trim();
  element.description=explain(_(shortText),full,element.title);
 }
 if(element.subsection)compact(element.subsection);
 (element.children||[]).forEach(compact);
 return element;
}
function sectionStatus(section,node){
 var render=section.renderContents;
 section.renderContents=function(){
  var result=render.apply(this,arguments),heading=result.querySelector('h3');
  var description=E('div',{'class':'cbi-section-descr'},[node]);
  if(heading)heading.after(description);else result.prepend(description);
  return result;
 };
}
return L.Class.extend({compact:compact,explain:explain,sectionStatus:sectionStatus});
