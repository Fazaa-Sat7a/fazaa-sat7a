import assert from 'node:assert/strict';
import {createFareWorker} from './fare-worker.mjs';
const token='USER_TOKEN_'+'a'.repeat(40),ticket='11111111-1111-4111-8111-111111111111';
const input={vehicle_id:'33333333-3333-4333-8333-333333333333',pickup:{lat:33.5,lng:36.2},stops:[{lat:33.6,lng:36.3}],metres:1,total:1,customer_id:'ATTACKER'};
function fixture({authenticated=true,router=true,far=false,prepareError=null}={}){
 const calls=[];const config={SUPABASE_URL:'https://db.example',SUPABASE_ANON_KEY:'PUBLIC',SUPABASE_SERVICE_ROLE_KEY:'SERVICE_SECRET',FAZAA_ROUTER_URL:router?'https://routes.example':''};
 const fetchImpl=async(url,opts)=>{
  calls.push({url,opts});assert.equal(opts.redirect,'error');
  if(url.endsWith('/auth/v1/user')){assert.equal(opts.headers.authorization,'Bearer '+token);return Response.json(authenticated?{id:'USER'}:{error:'invalid'},{status:authenticated?200:401});}
  if(url.endsWith('/prepare_fazaa_quote')){assert.equal(opts.headers.authorization,'Bearer '+token);return Response.json(prepareError?{message:prepareError}:{ticket_id:ticket,points:[input.pickup,input.stops[0]]},{status:prepareError?400:200});}
  if(url.startsWith('https://routes.example/'))return Response.json({code:'Ok',routes:[{distance:3200,duration:600,legs:[{}]}],waypoints:[{distance:0},{distance:far?2000:0}]});
  if(url.endsWith('/finish_fazaa_quote')){
   assert.equal(opts.headers.authorization,'Bearer SERVICE_SECRET');assert.deepEqual(JSON.parse(opts.body),{p_ticket:ticket,p_metres:3200,p_seconds:600});return Response.json({quote_id:ticket,total:210});
  }
  throw Error('unexpected network');
 };
 const handler=createFareWorker({env:k=>config[k],fetchImpl});
 const invoke=(authorization='Bearer '+token,origin='https://fazaa-sat7a.github.io',body=input)=>handler(new Request('https://edge.example/fare-quote',{method:'POST',headers:{authorization,origin},body:JSON.stringify(body)}));
 return {calls,invoke,handler};
}
let f=fixture();let r=await f.invoke();assert.equal(r.status,200);assert.equal((await r.json()).total,210);assert(!JSON.stringify(await r.text().catch(()=>'' )).includes('SERVICE_SECRET'));
f=fixture();assert.equal((await f.invoke('')).status,401);assert.equal(f.calls.length,0);
f=fixture();assert.equal((await f.invoke('Bearer '+token,'https://evil.example')).status,403);assert.equal(f.calls.length,0);
f=fixture({authenticated:false});assert.equal((await f.invoke()).status,401);assert.equal(f.calls.length,1);
f=fixture({router:false});assert.equal((await f.invoke()).status,503);assert.equal(f.calls.length,0);
f=fixture({far:true});assert.equal((await f.invoke()).status,422);assert(!f.calls.some(c=>c.url.endsWith('/finish_fazaa_quote')));
f=fixture({prepareError:'NO_MATCHING_TRUCK'});r=await f.invoke();assert.equal(r.status,400);assert.equal((await r.json()).error,'NO_MATCHING_TRUCK');assert(!f.calls.some(c=>c.url.startsWith('https://routes.example')));
f=fixture();assert.equal((await f.invoke('Bearer '+token,undefined,{note:'x'.repeat(13000)})).status,413);
console.log('PASS: authenticated quotes, CORS isolation, no client-supplied price/distance trust, service-only metrics, provider missing, no route, excessive snapping and request limits');
