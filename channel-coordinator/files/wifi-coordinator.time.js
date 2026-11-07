'use strict';
'require baseclass';

function pad(n){return String(n).padStart(2,'0');}
function date(t){var d=new Date(t*1000);return d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate());}
function clock(t,seconds){var d=new Date(t*1000);return pad(d.getHours())+':'+pad(d.getMinutes())+(seconds?':'+pad(d.getSeconds()):'');}
function stamp(t){return date(t)+' '+clock(t,true);}
function zone(){return Intl.DateTimeFormat().resolvedOptions().timeZone||'Browser local time';}
function offset(t){var n=-new Date(t*1000).getTimezoneOffset();return 'UTC'+(n<0?'-':'+')+pad(Math.floor(Math.abs(n)/60))+':'+pad(Math.abs(n)%60);}
function sameDay(start,end){return date(start)===date(end);}
function ticks(start,end,width){
 var count=Math.max(2,Math.min(7,Math.floor(Math.max(1,width)/(sameDay(start,end)?85:115))));
 var step=[1,5,15,30,60,300,900,1800,3600,7200,10800,21600,43200,86400,172800,604800].find(s=>s>=(end-start)/(count-1))||604800;
 // Anchor at local midnight. Daily ticks use calendar days across DST changes.
 var d=new Date(start*1000);d.setHours(0,0,0,0);
 var t=d.getTime()/1000,values=[];
 if(step<86400)t+=Math.ceil((start-t)/step)*step;
 while(t<=end){
  if(t>=start)values.push(t);
  if(step>=86400){d.setDate(d.getDate()+step/86400);t=d.getTime()/1000;}else t+=step;
 }
 return values.length?values:[start];
}
function label(t,start,end,values){
 var seconds=end-start<120,c=clock(t,seconds),lines=sameDay(start,end)?[c]:[date(t),c];
 // Repeated local hours during the autumn clock change need an offset.
 if((values||[]).some(v=>v!==t&&date(v)===date(t)&&clock(v,seconds)===c))lines.push(offset(t));
 return lines.length===1?lines[0]:lines;
}
return baseclass.extend({date:date,clock:clock,stamp:stamp,zone:zone,offset:offset,sameDay:sameDay,ticks:ticks,label:label});
