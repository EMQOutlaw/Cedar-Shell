const fs=require('fs'),vm=require('vm'),assert=require('assert');
const p={};vm.createContext(p);vm.runInContext(fs.readFileSync(process.argv[2],'utf8').replace('.pragma library',''),p);
const quiet={idle:true,cpu:.01,activities:0};
assert.equal(p.state(quiet),'QUIET');
assert.equal(p.state({...quiet,warning:true,watching:true}),'EMBER');
assert.equal(p.state({...quiet,watching:true,performance:true}),'WATCH');
assert.equal(p.state({...quiet,performance:true}),'HUNT');
assert.equal(p.state({...quiet,resting:true}),'REST');
assert.equal(p.state({...quiet,activities:2}),'FLOW');
assert.equal(p.state({...quiet,cpu:-1}),'AWAKE');
let trails=[],echoes=[];
for(let i=0;i<100;i++){trails=p.trail(trails,{key:String(i),label:'Page'},i);echoes=p.echo(echoes,{id:String(i),type:'volume',icon:'v'},i);}
assert.equal(trails.length,24);assert.equal(echoes.length,3);
assert.equal(p.trail(trails,{key:'99',label:'Page'},101).length,24);
assert.equal(p.echo([],{id:'private',type:'clipboard',icon:'c'},1).length,0);
console.log('PASS: Forest states, priority, bounded Trails and private Echo exclusions');
