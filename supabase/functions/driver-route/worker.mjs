const ORIGIN='https://fazaa-sat7a.github.io';
const ROUTER='https://api.heigit.org/openrouteservice/v2/directions/driving-car/geojson';
const validPoint=p=>p&&Number.isFinite(p.lat)&&Number.isFinite(p.lng)&&Math.abs(p.lat)<=90&&Math.abs(p.lng)<=180;
export function createDriverRoute({env,fetchImpl=fetch,now=()=>Date.now()}) {
 const seen=new Map(),cache=new Map();
 const headers={'access-control-allow-origin':ORIGIN,'access-control-allow-headers':'authorization, apikey, content-type, x-client-info','access-control-allow-methods':'POST, OPTIONS','vary':'Origin','cache-control':'no-store','content-type':'application/json'};
 const respond=(status,error)=>new Response(JSON.stringify(typeof error==='string'?{error}:error),{status,headers});
 const call=(url,options)=>fetchImpl(url,{...options,redirect:'error',signal:AbortSignal.timeout(12000)});
 return async request=>{
  const origin=request.headers.get('origin');
  if(origin&&origin!==ORIGIN)return respond(403,'ORIGIN_NOT_ALLOWED');
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return respond(405,'METHOD_NOT_ALLOWED');
  const authorization=request.headers.get('authorization')||'';
  if(!/^Bearer \S{20,4096}$/.test(authorization))return respond(401,'AUTH_REQUIRED');
  const base=env('SUPABASE_URL'),key=env('SUPABASE_ANON_KEY'),orsKey=env('FAZAA_ORS_API_KEY');
  if(!base||!key||!orsKey)return respond(503,'ROUTER_NOT_CONFIGURED');
  let stage='auth';
  try {
   const authHeaders={authorization,apikey:key,'content-type':'application/json'};
   const userResponse=await call(base+'/auth/v1/user',{headers:authHeaders});
   if(!userResponse.ok)return respond(401,'AUTH_REQUIRED');
   const user=await userResponse.json();
   if(!/^[a-f0-9-]{36}$/i.test(user?.id||''))return respond(401,'AUTH_REQUIRED');
   const raw=await request.text();if(raw.length>2048)return respond(413,'INVALID_INPUT');
   let input;try{input=JSON.parse(raw);}catch{return respond(400,'INVALID_INPUT');}
   if(!input||typeof input!=='object'||!/^[a-f0-9-]{36}$/i.test(input.request_id||'')||!Number.isInteger(input.stop_index)||input.stop_index< -2||input.stop_index>3)return respond(400,'INVALID_INPUT');
   // The origin and destination come from authorized database records, never caller coordinates.
   stage='profile';
   const profileResponse=await call(base+'/rest/v1/drivers?select=id,status,lat,lng,location_updated_at&id=eq.'+encodeURIComponent(user.id),{headers:authHeaders});
   if(!profileResponse.ok)return respond(403,'DRIVER_REQUIRED');
   const profiles=await profileResponse.json(),profile=Array.isArray(profiles)?profiles.find(p=>p.id===user.id):null;
   if(!profile||profile.status!=='active')return respond(403,'DRIVER_REQUIRED');
   if(!validPoint(profile)||!Number.isFinite(Date.parse(profile.location_updated_at))||now()-Date.parse(profile.location_updated_at)>90000||Date.parse(profile.location_updated_at)-now()>30000)return respond(409,'DRIVER_LOCATION_STALE');
   const rpc=async(name,args)=>{const r=await call(base+'/rest/v1/rpc/'+name,{method:'POST',headers:authHeaders,body:JSON.stringify(args)});if(!r.ok)throw Error('RPC_REJECTED');return r.json();};
   stage='request';
   const current=await rpc('driver_current_request',{});
   let trip=Array.isArray(current)?current.find(r=>r.id===input.request_id&&['accepted','arrived','in_progress'].includes(r.status)):null;
   if(!trip){const offers=await rpc('driver_open_requests',{p_radius_km:15});trip=Array.isArray(offers)?offers.find(r=>r.id===input.request_id):null;}
   if(!trip)return respond(403,'REQUEST_NOT_AVAILABLE');
   const pickup={lat:trip.lat,lng:trip.lng,label:'موقع العميل',driver:false,delivery:false};
   let targets=[pickup];
   if(input.stop_index>=0||input.stop_index===-2){
    const cards=await rpc('get_fazaa_driver_cards',{p_ids:[input.request_id]});
    const detail=cards?.[input.request_id];if(!detail)return respond(403,'REQUEST_NOT_AVAILABLE');
    const stops=detail.stops||[];if(!Array.isArray(stops)||stops.length>4)return respond(422,'INVALID_TARGET');
    const normalized=stops.map((stop,i)=>({lat:stop?.lat,lng:stop?.lng,label:typeof stop?.label==='string'?stop.label.slice(0,120):'وجهة التوصيل',driver:false,delivery:true,number:i+1}));
    if(input.stop_index===-2)targets=[pickup,...normalized];
    else{const stop=normalized[input.stop_index];if(!stop)return respond(400,'INVALID_STOP');targets=[stop];}
   }
   if(targets.some(p=>!validPoint(p)))return respond(422,'INVALID_TARGET');
   const target=targets[targets.length-1],routePoints=[{lat:profile.lat,lng:profile.lng},...targets];
   // Small, bounded per-instance cache. Authorization above is rechecked on every hit.
   const cacheKey=JSON.stringify([user.id,input.request_id,input.stop_index,routePoints]);
   const cached=cache.get(cacheKey);if(cached&&now()-cached.at<60000)return respond(200,cached.data);
   for(const [k,v] of seen)if(now()-v>120000)seen.delete(k);
   for(const [k,v] of cache)if(now()-v.at>60000)cache.delete(k);
   if(seen.has(user.id)&&now()-seen.get(user.id)<3000)return respond(429,'ROUTE_RATE_LIMIT');
   if(seen.size>=256)seen.delete(seen.keys().next().value);
   seen.set(user.id,now());stage='router';
   const routing=await call(ROUTER,{method:'POST',headers:{authorization:orsKey,'content-type':'application/json'},body:JSON.stringify({coordinates:routePoints.map(p=>[p.lng,p.lat]),radiuses:routePoints.map(()=>300),instructions:false,geometry:true,units:'m'})});
   if(!routing.ok){console.warn('driver-route provider_status='+routing.status);return respond(503,'ROUTE_UNAVAILABLE');}
   const result=await routing.json(),feature=result.features?.[0],summary=feature?.properties?.summary,geometry=feature?.geometry;
   if(!summary||!Number.isFinite(summary.distance)||!Number.isFinite(summary.duration)||summary.distance<0||summary.duration<0||summary.distance>3000000||summary.duration>604800||geometry?.type!=='LineString'||!Array.isArray(geometry.coordinates)||geometry.coordinates.length<2||geometry.coordinates.length>100000||geometry.coordinates.some(c=>!Array.isArray(c)||!validPoint({lng:c[0],lat:c[1]})))return respond(422,'ROUTE_UNAVAILABLE');
   const data={geometry,metres:summary.distance,seconds:summary.duration,origin:{lat:profile.lat,lng:profile.lng},target,targets,calculated_at:new Date(now()).toISOString()};
   if(cache.size>=128)cache.delete(cache.keys().next().value);
   cache.set(cacheKey,{at:now(),data});return respond(200,data);
  }catch{console.warn('driver-route failed_stage='+stage);return respond(503,'ROUTE_UNAVAILABLE');}
 };
}
