const fs=require('fs'),vm=require('vm'),assert=require('assert'),path=require('path');
const root=fs.existsSync(path.join(__dirname,'./fixture-web/assets/customer-push.js'))?'./fixture-web/':'../';
const source=fs.readFileSync(path.join(__dirname,root+'assets/customer-push.js'),'utf8');
const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',order='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
function setup(native=true){
 const calls=[],listeners={},callbacks=[],timers=new Map();let seq=0,session={user:{id:'user-A'}},failUnregister=false,opened=true;
 const element=()=>({className:'',textContent:'',append(){}});
 const api={auth:{getSession:async()=>({data:{session}}),onAuthStateChange:fn=>callbacks.push(fn),signOut:async()=>{calls.push({action:'signed-out'});session=null;callbacks.forEach(f=>f('SIGNED_OUT',null));return{error:null};}},rpc:async(name,args)=>{calls.push({name,args,user:session?.user.id});return name==='unregister_customer_push_device'&&failUnregister?{error:{message:'offline'}}:{data:{ok:true}};}};
 const window={addEventListener:(event,fn)=>listeners[event]=fn,FazaaApp:{authBusy:false,openRequest:async request=>{calls.push({action:'open',request});return opened;},navigate:target=>calls.push({action:'navigate',target})}};
 if(native)window.FazaaPushDevice={installation_id:id,token:'T'.repeat(150),permission:true};
 const context={client:api,window,document:{hidden:false,addEventListener(){},createElement:element,getElementById:element},setTimeout:(fn,ms)=>{timers.set(++seq,{fn,ms});return seq;},clearTimeout:key=>timers.delete(key),setInterval(){},message:text=>calls.push({action:'message',text}),console};
 vm.createContext(context);vm.runInContext(source,context);
 return{window,api,calls,listeners,setUser:user=>{session={user:{id:user}};callbacks.forEach(f=>f('SIGNED_IN',session));},fail:v=>failUnregister=v,openResult:v=>opened=v};
}
(async()=>{
 const a=setup();await a.window.FazaaPush.sync();assert.equal(a.calls[0].name,'register_customer_push_device');assert.equal(a.calls[0].user,'user-A');assert.equal(a.calls[0].args.p_enabled,true);await a.window.FazaaPush.sync();assert.equal(a.calls.length,1,'unchanged binding should not be rewritten');a.setUser('user-B');await a.window.FazaaPush.sync();assert.equal(a.calls.at(-1).user,'user-B');a.window.FazaaPushDevice.permission=false;await a.window.FazaaPush.sync();assert.equal(a.calls.at(-1).args.p_enabled,false);
 a.fail(true);await assert.rejects(()=>a.api.auth.signOut());assert(!a.calls.some(c=>c.action==='signed-out'),'logout must not leave a server token attached to the previous account');a.fail(false);await a.api.auth.signOut();assert.equal(a.calls.at(-2).name,'unregister_customer_push_device');assert.equal(a.calls.at(-1).action,'signed-out');
 const b=setup(false);await b.window.FazaaPush.sync();assert.equal(b.calls.length,0,'ordinary browser must not register native devices');await b.api.auth.signOut();assert.equal(b.calls[0].action,'signed-out');
 const c=setup();c.window.FazaaPushOpenRequest=order;await c.listeners['fazaa-push-open']();assert.equal(c.calls[0].request,order);assert(!c.window.FazaaPushOpenRequest);c.window.FazaaPushOpenRequest='https://attacker.test/';await c.listeners['fazaa-push-open']();assert.equal(c.calls.length,1,'notification must not navigate to an arbitrary URL');c.window.FazaaPushOpenRequest=order;c.openResult(false);await c.listeners['fazaa-push-open']();assert(c.calls.some(x=>x.action==='navigate'&&x.target==='account'));
 console.log('PASS: device/account binding, permission revocation, unsubscribe before logout, failed unsubscribe preserves login, browser isolation and authorized request opening');
})().catch(e=>{console.error(e);process.exitCode=1;});
