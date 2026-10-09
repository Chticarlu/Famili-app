const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const script=html.slice(html.indexOf('<script>')+8,html.lastIndexOf('</script>'));
new vm.Script(script);
const source=script.slice(script.indexOf('function showNetworkError('),script.indexOf('\nfunction euro('));
function element(value=''){return {value,textContent:'',classList:{hidden:true,remove(){this.hidden=false},add(){this.hidden=true}}};}
let mode='error',calls=0,loads=0,renders=0;
const q={insert:async()=>result(),upsert:async()=>result(),update(){return q},delete(){return q},eq:async()=>result()};
function result(){calls++;if(mode==='throw')throw Error('offline');return mode==='ok'?{}:{error:{message:'connection lost'}};}
const ctx={navigator:{onLine:true},window:{addEventListener(){}},networkStatus:element(),sb:{from:()=>q},household:{id:'fixture'},user:{id:'fixture'},confirm:()=>true,render:()=>renders++,loadAll:async()=>loads++};
for(const id of ['eventTitle','eventDate','eventTime','eventPerson','taskTitle','taskPerson','taskRepeat','mealDate','mealLunch','mealDinner','groceryName','groceryCategory','budgetLabel','budgetAmount','budgetType'])ctx[id]=element('test');
ctx.budgetAmount.value='12.34';
vm.createContext(ctx);vm.runInContext(source,ctx);
async function run(code){return vm.runInContext(code,ctx)}
(async()=>{
 let count=0;
 for(const [fn,field] of [['addEvent','eventTitle'],['addTask','taskTitle'],['saveMeal','mealLunch'],['addGrocery','groceryName'],['addBudget','budgetLabel']]){
  for(const failure of ['error','throw']){mode=failure;ctx[field].value='conserver';await run(`${fn}()`);assert.equal(ctx[field].value,'conserver');assert.match(ctx.networkStatus.textContent,/saisies sont conservées/);count++;}
  mode='ok';await run(`${fn}()`);assert.equal(ctx[field].value,'');count++;
 }
 ctx.navigator.onLine=false;const before=calls;ctx.taskTitle.value='hors connexion';await run('addTask()');assert.equal(calls,before);assert.equal(ctx.taskTitle.value,'hors connexion');count++;
 ctx.navigator.onLine=true;mode='error';await run("toggleTask('fixture',true)");await run("toggleGrocery('fixture',true)");assert.equal(renders,2);count+=2;
 ctx.sb=null;await run('updateNetworkStatus()');assert.match(ctx.networkStatus.textContent,/ne peut pas démarrer/);count++;
 assert.equal(loads,5);
 const loadSource=script.slice(script.indexOf('async function loadAll(){'),script.indexOf('\nfunction subscribeRealtime()'));
 let queryMode='error';const readQ={select(){return readQ},eq(){return readQ},order(){return readQ},maybeSingle(){return readQ},then(resolve,reject){if(queryMode==='throw')reject(Error('network'));else resolve(queryMode==='error'?{error:{message:'network'}}:{data:[]});}};
 const readCtx={navigator:{onLine:true},household:{id:'fixture'},Date,sb:{from:()=>readQ},events:['cached'],tasks:['cached'],meals:['cached'],groceries:['cached'],budget:['cached'],members:['cached'],aiUsage:null,render(){},updateNetworkStatus(){},showNetworkError(){}};
 vm.createContext(readCtx);vm.runInContext(loadSource,readCtx);
 for(const failure of ['error','throw']){queryMode=failure;await vm.runInContext('loadAll()',readCtx);assert.equal(readCtx.events[0],'cached');assert.equal(readCtx.tasks[0],'cached');count++;}
 readCtx.navigator.onLine=false;await vm.runInContext('loadAll()',readCtx);assert.equal(readCtx.events[0],'cached');count++;
 readCtx.navigator.onLine=true;queryMode='ok';await vm.runInContext('loadAll()',readCtx);assert.equal(readCtx.events.length,0);count++;
 console.log(`${count} mobile UX scenarios passed (mocked API). Inline JS syntax valid.`);
})().catch(e=>{console.error(e);process.exitCode=1});
