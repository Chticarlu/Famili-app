const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const source=html.slice(html.indexOf('function invitationActive()'),html.indexOf('setInterval(()=>{if(household)renderInvitation();}'));
const join=html.slice(html.indexOf('async function joinHH()'),html.indexOf('async function leaveHousehold()'));
function element(){return {disabled:false,textContent:'',classList:{hidden:false,toggle(_,v){this.hidden=v;}}};}
const ids=Object.fromEntries(['inviteCode','familyCode','billingCode','joinInviteBtn'].map(x=>[x,element()]));
const groups=Object.fromEntries(['invitationStatus','invitationCopy','invitationOwnerActions','invitationRevoke','invitationMsg'].map(x=>['.'+x,[element(),element(),element()]]));
let response={data:{status:'invalid'}},calls=[],loaded=0,copied=0,confirm=true;
const household={id:'fixture',invite_code:'A'.repeat(32),invite_expires_at:new Date(Date.now()+86400000).toISOString(),invite_revoked_at:null};
const sb={rpc:async(name,args)=>{calls.push({name,args});return response;},from:()=>({select:()=>({eq:()=>({single:async()=>({data:household})})})})};
const ctx=vm.createContext({household,householdRole:'owner',Date,Math,document:{getElementById:id=>ids[id],querySelectorAll:s=>groups[s]},navigator:{clipboard:{writeText:async()=>copied++}},alert:()=>{},confirm:()=>confirm,notice:(el,msg)=>el.textContent=msg,joinCode:{value:' abcdef12 '},hhMsg:element(),loadState:async()=>loaded++,sb});
vm.runInContext(source+join,ctx);
async function run(code){return vm.runInContext(code,ctx);}
(async()=>{
 await run('renderInvitation()');assert.equal(ids.inviteCode.textContent,household.invite_code);assert.equal(groups['.invitationOwnerActions'][0].classList.hidden,false);
 await run("householdRole='member';renderInvitation()");assert.equal(groups['.invitationOwnerActions'][0].classList.hidden,true);
 await run("changeInvitation('regenerate',document.getElementById('joinInviteBtn'))");assert.equal(calls.length,0);
 await run("householdRole='owner';household.invite_revoked_at=new Date().toISOString();renderInvitation()");assert.equal(ids.familyCode.textContent,'Indisponible');assert.equal(groups['.invitationCopy'][0].disabled,true);
 await run('copyCode()');assert.equal(copied,0);
 await run("household.invite_revoked_at=null;household.invite_expires_at=new Date(Date.now()-1).toISOString();renderInvitation()");assert.match(groups['.invitationStatus'][0].textContent,/expirée/);
 await run('joinHH()');assert.match(ctx.hhMsg.textContent,/invalide/);assert.equal(loaded,0);assert.equal(calls.at(-1).args.p_code,'ABCDEF12');assert.equal(ids.joinInviteBtn.disabled,false);
 response={data:{status:'rate_limited',retry_after_seconds:901}};await run('joinHH()');assert.match(ctx.hhMsg.textContent,/16 minute/);assert.equal(loaded,0);
 response={data:{status:'joined'}};await run('joinHH()');assert.equal(loaded,1);
 confirm=false;const before=calls.length;await run("changeInvitation('revoke',document.getElementById('joinInviteBtn'))");assert.equal(calls.length,before);
 confirm=true;response={error:null};await run("changeInvitation('regenerate',document.getElementById('joinInviteBtn'))");assert.equal(calls.at(-1).name,'regenerate_invite_code');assert.equal(calls.at(-1).args.p_household_id,'fixture');
 assert.match(html,/id="joinCode" maxlength="32"/);assert.equal((html.match(/invitationOwnerActions hidden/g)||[]).length,3);
 console.log('12 UI scenarios passed (mocked API; no Stripe or real data).');
})().catch(e=>{console.error(e);process.exitCode=1;});
