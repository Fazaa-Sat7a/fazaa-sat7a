const ORIGIN='https://fazaa-sat7a.github.io';
export function createFareWorker({env,fetchImpl=fetch}) {
 const headers={'access-control-allow-origin':ORIGIN,'access-control-allow-headers':'authorization, apikey, content-type, x-client-info','access-control-allow-methods':'POST, OPTIONS','vary':'Origin','cache-control':'no-store','content-type':'application/json'};
 const response=(status,body)=>new Response(JSON.stringify(body),{status,headers});
 const call=(url,options)=>fetchImpl(url,{...options,redirect:'error',signal:AbortSignal.timeout(15000)});
 return async request=>{
  const origin=request.headers.get('origin');
  if(origin&&origin!==ORIGIN)return response(403,{error:'ORIGIN_NOT_ALLOWED'});
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return response(405,{error:'METHOD_NOT_ALLOWED'});
  const authorization=request.headers.get('authorization')||'';
  if(!/^Bearer \S{20,4096}$/.test(authorization))return response(401,{error:'AUTH_REQUIRED'});
  const base=env('SUPABASE_URL'),key=env('SUPABASE_ANON_KEY'),service=env('SUPABASE_SERVICE_ROLE_KEY'),router=env('FAZAA_ROUTER_URL');
  if(!base||!key||!service||!router)return response(503,{error:'ROUTER_NOT_CONFIGURED'});
  let routeBase;try{routeBase=new URL(router);if(routeBase.protocol!=='https:'||routeBase.username||routeBase.password||routeBase.search||routeBase.hash)throw Error();}catch{return response(503,{error:'ROUTER_NOT_CONFIGURED'});}
  try{
   const user=await call(base+'/auth/v1/user',{headers:{authorization,apikey:key}});
   if(!user.ok||!(await user.json()).id)return response(401,{error:'AUTH_REQUIRED'});
   const raw=await request.text();if(raw.length>12000)return response(413,{error:'INVALID_INPUT'});
   let input;try{input=JSON.parse(raw);}catch{return response(400,{error:'INVALID_INPUT'});}
   const prep=await call(base+'/rest/v1/rpc/prepare_fazaa_quote',{method:'POST',headers:{authorization,apikey:key,'content-type':'application/json'},body:JSON.stringify({p_input:input})});
   const prepared=await prep.json();
   if(!prep.ok){const allowed=['PRICING_NOT_READY','QUOTE_RATE_LIMIT','VEHICLE_NOT_APPROVED','VEHICLE_YEAR_REQUIRED','OUTSIDE_SERVICE_AREA','NO_MATCHING_TRUCK','INVALID_STOPS','CHANGE_NOT_ALLOWED','TOO_MANY_STOPS'];return response(400,{error:allowed.find(x=>String(prepared.message).includes(x))||'INVALID_INPUT'});}
   const {points,ticket_id}=prepared;
   if(!/^[a-f0-9-]{36}$/i.test(ticket_id)||!Array.isArray(points)||points.length<2||points.length>5||points.some(p=>!Number.isFinite(p.lat)||!Number.isFinite(p.lng)||Math.abs(p.lat)>90||Math.abs(p.lng)>180))throw Error('PREPARE_RESPONSE');
   const url=routeBase.toString().replace(/\/$/,'')+'/route/v1/driving/'+points.map(p=>p.lng+','+p.lat).join(';')+'?overview=false&steps=false&alternatives=false';
   const routing=await call(url,{headers:env('FAZAA_ROUTER_AUTHORIZATION')?{authorization:env('FAZAA_ROUTER_AUTHORIZATION')}: {}});
   if(!routing.ok)return response(503,{error:'ROUTE_UNAVAILABLE'});
   const route=await routing.json(),best=route.routes?.[0];
   if(route.code!=='Ok'||!best||!Number.isFinite(best.distance)||!Number.isFinite(best.duration)||best.distance<1||best.duration<1||best.distance>3000000||best.duration>604800||best.legs?.length!==points.length-1||route.waypoints?.length!==points.length||route.waypoints.some(p=>!Number.isFinite(p.distance)||p.distance>300))return response(422,{error:'ROUTE_UNAVAILABLE'});
   const result=await call(base+'/rest/v1/rpc/finish_fazaa_quote',{method:'POST',headers:{authorization:'Bearer '+service,apikey:service,'content-type':'application/json'},body:JSON.stringify({p_ticket:ticket_id,p_metres:best.distance,p_seconds:best.duration})});
   if(!result.ok)return response(409,{error:'QUOTE_EXPIRED'});
   return response(200,await result.json());
  }catch{return response(503,{error:'ROUTE_UNAVAILABLE'});}
 };
}
