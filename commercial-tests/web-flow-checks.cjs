const fs=require('fs'),vm=require('vm'),assert=require('assert');
const path=require('path');
const webRoot=fs.existsSync(path.join(__dirname,'./fixture-web/index.html'))?'./fixture-web/':'../';
const html=fs.readFileSync(path.join(__dirname,webRoot+'index.html'),'utf8');
function setup({legacy=false,restored=false}={}){
 const nodes={};
 for(const match of html.matchAll(/<([a-z][a-z0-9-]*)\b([^>]*\bid="([^"]+)"[^>]*)>/g)){
  const [,tag,attrs,id]=match;nodes[id]={id,tagName:tag.toUpperCase(),value:'',textContent:'',hidden:/\bhidden\b/.test(attrs),disabled:/\bdisabled\b/.test(attrs),style:{},offsetWidth:0,offsetHeight:0,events:{},classList:{add(){}},addEventListener(name,fn){(this.events[name]??=[]).push(fn);},setAttribute(){},focus(){},select(){}};
 }
 for(const node of Object.values(nodes))Object.defineProperty(node,'value',{get(){return this._value||'';},set(value){this._value=String(value);}});
 const storage=new Map(),calls=[],timers=new Map();let timerId=0,clip='';
 const id='11111111-2222-4333-8444-555555555555';
 const row={id,status:'new',short_code:'600659',created_at:new Date().toISOString(),lat:33.5,lng:36.2,can_share:!restored,has_rating:false};
 const auth={getSession:async()=>({data:{session:null},error:null}),signInAnonymously:async()=>({data:{session:{user:{id:'test-customer'}}},error:null})};
 const state={row,redeemOk:true,rated:false};
 const api={auth,rpc:async(name,args)=>{
  calls.push({name,args});
  if(legacy&&['create_customer_request','get_customer_request','cancel_customer_request','rate_customer_request'].includes(name))return {error:{code:'PGRST202',message:'function unavailable'}};
  if(['create_request','create_customer_request'].includes(name))return {data:id};
  if(['get_my_request','get_customer_request'].includes(name))return {data:[{...row,has_rating:state.rated}]};
  if(['cancel_my_request','cancel_customer_request'].includes(name)){row.status='cancelled_customer';return {data:true};}
  if(['rate_request','rate_customer_request'].includes(name)){state.rated=true;return {data:null};}
  if(name==='issue_customer_handoff')return {data:{token:'abcdef00112233445566778899aabbcc',short_code:row.short_code,expires_at:new Date(Date.now()+600000).toISOString()}};
  if(name==='redeem_customer_handoff')return {data:state.redeemOk?{ok:true,request_id:id}:{ok:false,reason:'invalid_code'}};
  throw Error(name);
 }};
 const window={addEventListener(){},supabase:{createClient:()=>api},FazaaMaps:undefined,isSecureContext:true};
 const context={window,document:{getElementById:id=>{assert(nodes[id],`missing ${id}`);return nodes[id];},addEventListener(){},documentElement:{classList:{add(){}}}},navigator:{clipboard:{writeText:async v=>{clip=v;}},geolocation:{getCurrentPosition:success=>success({coords:{latitude:33.5,longitude:36.2}})}},location:{search:'?app=1',hash:''},localStorage:{getItem:k=>storage.get(k)??null,setItem:(k,v)=>storage.set(k,String(v)),removeItem:k=>storage.delete(k)},setTimeout:(fn,ms)=>{timers.set(++timerId,{fn,ms});return timerId;},clearTimeout:id=>timers.delete(id),requestAnimationFrame:fn=>fn(),URLSearchParams,Date,confirm:()=>true,console};
 vm.createContext(context);
 for(const [,script]of html.matchAll(/<script(?:\s[^>]*)?>(.*?)<\/script>/gs))if(script.trim())vm.runInContext(script,context);
 return {nodes,storage,calls,state,id,clip:()=>clip,run:js=>vm.runInContext(js,context),event:async(id,name='click')=>{assert(nodes[id].events[name],`${id} has no ${name}`);for(const handler of nodes[id].events[name])await handler({preventDefault(){}});}};
}
(async()=>{
 const a=setup();await new Promise(setImmediate);
 a.nodes.phone.value='٠٩٠٠٠٠٠٠٠٠';a.nodes.problem.value='engine';a.nodes['car-type'].value='small';
 await a.event('request-form','submit');assert.equal(a.calls.length,0,'missing location must not create request');
 await a.event('locate');await a.event('request-form','submit');
 assert.equal(a.storage.get('fazaa.customer.active.v0'),a.id);assert.equal(a.nodes['search-indicator'].hidden,false);assert.equal(a.nodes['restore-section'].hidden,true);
 assert.equal(a.calls.find(x=>x.name==='create_customer_request').args.p_phone,'0900000000');
 await a.event('handoff-create');assert.equal(a.nodes['handoff-result'].hidden,false);assert(/^[A-F0-9]{8}(-[A-F0-9]{8}){3}$/.test(a.nodes['handoff-code'].value));
 await a.event('handoff-copy');assert.equal(a.clip(),a.nodes['handoff-code'].value);assert(![...a.storage.values()].includes('abcdef00112233445566778899aabbcc'));
 a.state.row.status='accepted';a.state.row.driver_phone='0900000000';a.state.row.driver_name='سائق اختبار';await a.run('refresh()');assert.equal(a.nodes['search-indicator'].hidden,true);assert.equal(a.nodes['driver-info'].hidden,false);
 await a.event('cancel');assert.equal(a.state.row.status,'cancelled_customer');await a.event('new-request');assert.equal(a.nodes['restore-section'].hidden,false);assert.equal(a.nodes['handoff-code'].value,'');
 console.log('PASS: location validation, Arabic phone, creation, handoff display/copy, acceptance, cancellation and new-request reset');
 const b=setup({restored:true});await new Promise(setImmediate);b.nodes['restore-number'].value='٦٠٠٦٥٩';b.nodes['restore-token'].value='ABCDEF00-11223344-55667788-99AABBCC';b.state.redeemOk=false;
 await b.event('restore-form','submit');assert(!b.storage.has('fazaa.customer.active.v0'));assert(b.nodes['restore-message'].textContent.includes('غير صحيح'));
 b.state.redeemOk=true;await b.event('restore-form','submit');assert.equal(b.storage.get('fazaa.customer.active.v0'),b.id);assert.equal(b.nodes['handoff-section'].hidden,true);assert.equal(b.nodes['restore-token'].value,'');
 b.state.row.status='done';await b.run('refresh()');assert.equal(b.nodes['rating-form'].hidden,false);b.nodes.stars.value='4';await b.event('rating-form','submit');assert.equal(b.nodes['rating-form'].hidden,true);
 console.log('PASS: invalid restore refusal, Arabic order number, successful restore, no delegation sharing and rating');
 const c=setup({legacy:true});await new Promise(setImmediate);c.nodes.phone.value='0900000000';c.nodes.problem.value='battery';c.nodes['car-type'].value='small';await c.event('locate');await c.event('request-form','submit');assert(c.calls.some(x=>x.name==='create_request'));assert.equal(c.storage.get('fazaa.customer.active.v0'),c.id);
 console.log('PASS: shared legacy request layer retains its compatibility fallback (v0.2 UI itself requires migration)');
})().catch(e=>{console.error(e);process.exit(1);});
