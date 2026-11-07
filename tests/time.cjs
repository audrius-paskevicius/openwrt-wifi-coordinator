'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert');
const time=new Function('baseclass',fs.readFileSync(path.join(__dirname,'../channel-coordinator/files/wifi-coordinator.time.js'),'utf8'))({extend:x=>x});
const previous=process.env.TZ;
try {
 process.env.TZ='Europe/Berlin';
 const epoch=s=>new Date(s).getTime()/1000;
 const start=epoch('2026-11-07T09:05:00+01:00'),end=start+6*3600;
 assert.equal(time.stamp(start),'2026-11-07 09:05:00');
 assert.equal(time.label(start,start,end),'09:05');
 assert(time.sameDay(start,end));
 const midnight=epoch('2026-12-31T23:30:00+01:00');
 assert(!time.sameDay(midnight,midnight+3600));
 assert.deepEqual(time.label(midnight+3600,midnight,midnight+3600),['2027-01-01','00:30']);
 assert(time.ticks(start,end,300).length<time.ticks(start,end,1000).length);
 assert(time.ticks(start,start+200*3600,1000).length<=7);
 const fall=epoch('2026-10-25T00:00:00+02:00'),fallEnd=epoch('2026-10-25T05:00:00+01:00');
 const values=time.ticks(fall,fallEnd,1000),twos=values.filter(t=>time.clock(t)==='02:00');
 assert.equal(twos.length,2);
 assert.deepEqual(time.label(twos[0],fall,fallEnd,values),['02:00','UTC+02:00']);
 assert.deepEqual(time.label(twos[1],fall,fallEnd,values),['02:00','UTC+01:00']);
 const spring=epoch('2026-03-29T00:00:00+01:00');
 assert(!time.ticks(spring,spring+5*3600,1000).some(t=>time.clock(t)==='02:00'));
 const days=time.ticks(spring,spring+4*86400,1000);
 assert(days.every(t=>time.clock(t)==='00:00'));
 assert.equal(time.zone(),'Europe/Berlin');
 console.log('PASS: ISO local timestamps, midnight/year rollover, adaptive ticks and both DST transitions');
} finally {if(previous===undefined)delete process.env.TZ;else process.env.TZ=previous;}
module.exports=time;
