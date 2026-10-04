const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync(process.argv[2],'utf8').replace('.pragma library',''),ctx);
let state=ctx.create(),time=1000;
function put(event){state=ctx.publish(state,event,time);}
put({id:'recording',type:'recording',title:'Recording',persistent:true,priority:'high',timeout:3000});
put({id:'volume',type:'volume',title:'Volume',priority:'normal',timeout:2000});
assert.equal(ctx.foreground(state,time).id,'recording','A later volume event cannot replace a higher priority event');
time=4500;state=ctx.expire(state,time,'');
put({id:'volume',type:'volume',title:'Volume',priority:'normal',timeout:2000});
assert.equal(ctx.foreground(state,time).id,'volume','A settled recording allows timely transient controls');
assert(state.rows.some(r=>r.id==='recording'),'Recording remains in the stack');
const sequence=state.sequence;time+=20;put({id:'volume',type:'volume',title:'Volume',progress:.8,priority:'normal',timeout:2000});
assert.equal(state.sequence,sequence,'Updating an activity retains its identity and sequence');
assert.equal(state.rows.filter(r=>r.id==='volume').length,1);
time+=3000;state=ctx.expire(state,time,'volume');assert(state.rows.some(r=>r.id==='volume'),'Hover holds expiry');
put({id:'thermal',type:'warning',priority:'critical',sticky:true,persistent:true,title:'Hot'});
assert.equal(ctx.foreground(state,time,'volume','volume').id,'thermal','Critical warnings preempt held/selected activities');
state=ctx.remove(state,'thermal',time,false);state=ctx.expire(state,time,'');assert(!state.rows.some(r=>r.id==='volume'));
for(let n=0;n<100;n++){put({id:'event'+n,type:'bluetooth',title:'Connected',remember:true});state=ctx.remove(state,'event'+n,time,true);}
assert.equal(state.history.length,32,'History is bounded');
put({id:'notice',type:'notification',title:'Private notification',remember:true});state=ctx.remove(state,'notice',time,true);assert(!state.history.some(r=>r.type==='notification'),'Core does not duplicate notification history');
let event=ctx.external({id:'download',source:'example',type:'progress',persistent:true,title:'A real download',actions:[{id:'exec',label:'Danger'}],priority:'critical'},time);
assert.equal(event.priority,'normal');assert.equal(event.actions.length,0);assert.equal(event.leaseMs,30000);
put(event);time+=31000;state=ctx.expire(state,time,'');assert(!state.rows.some(r=>r.id===event.id),'Stopped providers expire their progress');
assert.throws(()=>ctx.external({source:'../../bad',id:'x',type:'integration'}));
assert.throws(()=>ctx.external({source:'example',id:'x',type:'camera'}));
assert.throws(()=>ctx.publish(state,{id:'bad',type:'progress',timeout:NaN},time));
state=ctx.create();for(let n=0;n<100;n++)put({id:'event'+n,type:'network',remember:true});assert.equal(state.rows.length,64);
console.log('PASS: activity priority, stable identity, preemption, hover hold, bounded history and leased providers');
