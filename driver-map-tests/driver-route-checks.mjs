import assert from 'node:assert/strict';
import {createDriverRoute} from '../supabase/functions/driver-route/worker.mjs';
const uid='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',rid='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const token='USER_'+'a'.repeat(40),tick=Date.parse('2026-10-26T10:00:00Z');
const pickup={lat:33.51,lng:36.31},stop={lat:33.52,lng:36.32,label:'كراج تجريبي'};
const geometry={type:'LineString',coordinates:[[36.3,33.5],[36.305,33.505],[36.31,33.51]]};
const route={features:[{geometry,properties:{summary:{distance:1700,duration:300}}}]};
const logs=[],warn=console.warn;console.warn=(...xs)=>logs.push(xs.join(' '));
function fixture(opts={}){
 const calls=[];let clock=tick,revoked=false;
 const config={SUPABASE_URL:'https://db.example',SUPABASE_ANON_KEY:'PUBLIC',FAZAA_ORS_API_KEY:opts.missing?'':'ORS_SECRET'};
 const fetchImpl=async(url,options)=>{
  calls.push({url,options});assert.equal(options.redirect,'error');assert(options.signal);
  if(url.endsWith('/auth/v1/user'))return Response.json(opts.auth===false?{}:{id:uid},{status:opts.auth===false?401:200});
  if(url.includes('/rest/v1/drivers?'))return Response.json(opts.noDriver?[]:[{id:uid,status:opts.inactive?'suspended':'active',lat:33.5,lng:36.3,location_updated_at:new Date(clock-(opts.stale?100000:1000)).toISOString()}]);
  if(url.endsWith('/driver_current_request'))return Response.json(opts.offer||revoked?[]:[{id:rid,status:'accepted',...pickup}]);
  if(url.endsWith('/driver_open_requests'))return Response.json(opts.forbidden||revoked?[]:[{id:rid,...pickup}]);
  if(url.endsWith('/get_fazaa_driver_cards'))return Response.json({[rid]:{stops:opts.noStop?[]:[stop]}});
  if(url==='https://api.heigit.org/openrouteservice/v2/directions/driving-car/geojson'){
   const body=JSON.parse(options.body);assert.equal(options.headers.authorization,'ORS_SECRET');
   assert.deepEqual(body.coordinates,[[36.3,33.5],opts.targetStop?[36.32,33.52]:[36.31,33.51]]);
   assert.deepEqual(body.radiuses,[300,300]);assert.equal(body.geometry,true);assert.equal(body.units,'m');
   if(opts.throwRouter)throw Error('ORS_SECRET');
   return Response.json(opts.route||route,{status:opts.routerStatus||200});
  }
  throw Error('Unexpected network '+url);
 };
 const handler=createDriverRoute({env:k=>config[k],fetchImpl,now:()=>clock});
 const invoke=(input={},headers={})=>handler(new Request('https://edge.example/driver-route',{method:'POST',headers:{authorization:'Bearer '+token,...headers},body:JSON.stringify({request_id:rid,stop_index:opts.targetStop?0:-1,origin:{lat:0,lng:0},destination:{lat:0,lng:0},total:1,...input})}));
 return {handler,calls,invoke,advance:()=>{clock+=5000;},revoke:()=>{revoked=true;}};
}
try{
 let f=fixture(),r=await f.invoke();assert.equal(r.status,200);assert.equal((await r.json()).metres,1700);
 assert(!f.calls.some(c=>/finish_fazaa_quote|create_fazaa|set_status/.test(c.url)),'route lookup must not mutate fare or trip');
 f=fixture({targetStop:true});assert.equal((await f.invoke()).status,200);
 f=fixture({offer:true});assert.equal((await f.invoke()).status,200);
 for(const [opts,status] of [[{auth:false},401],[{missing:true},503],[{noDriver:true},403],[{inactive:true},403],[{stale:true},409],[{offer:true,forbidden:true},403],[{targetStop:true,noStop:true},400],[{routerStatus:429},503],[{routerStatus:403},503],[{throwRouter:true},503],[{route:{features:[]}},422],[{route:{features:[{geometry:{type:'LineString',coordinates:[[36,95],[36,33]]},properties:{summary:{distance:1,duration:1}}}]}},422]]){
  f=fixture(opts);r=await f.invoke();assert.equal(r.status,status,JSON.stringify(opts));assert(!/ORS_SECRET|USER_/.test(await r.text()));
  if([401,403,409,400].includes(status))assert(!f.calls.some(c=>c.url.includes('api.heigit.org')));
 }
 f=fixture();assert.equal((await f.invoke({}, {authorization:''})).status,401);assert.equal(f.calls.length,0);
 f=fixture();assert.equal((await f.invoke({}, {origin:'https://evil.example'})).status,403);assert.equal(f.calls.length,0);
 f=fixture();assert.equal((await f.invoke({request_id:'wrong'})).status,400);
 f=fixture();assert.equal((await f.invoke({stop_index:4})).status,400);
 f=fixture();assert.equal((await f.invoke()).status,200);assert.equal((await f.invoke()).status,200);assert.equal(f.calls.filter(c=>c.url.includes('api.heigit.org')).length,1,'cache hit must avoid another route request');
 f.revoke();assert.equal((await f.invoke()).status,403,'revoked request access must invalidate a cached route');
 f=fixture();assert.equal((await f.invoke()).status,200);assert.equal((await f.invoke({stop_index:0})).status,429,'rapid cache miss is limited per instance');
 assert(logs.every(s=>!s.includes('ORS_SECRET')&&!s.includes(token)));
 console.log('PASS: authenticated active drivers, authorized active/offered trips, server-selected origin/destination, stale GPS rejection, read-only route, geometry validation, current HeiGIT API, private key, bounded cache and authorization recheck, local throttling, provider failures and CORS.');
}finally{console.warn=warn;}
