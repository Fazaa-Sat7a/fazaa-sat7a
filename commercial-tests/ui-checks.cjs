require('node:child_process').execFileSync(process.execPath,[require('node:path').join(__dirname,'commercial-startup-checks.cjs')],{stdio:'inherit'});
const {chromium}=require('playwright');
const fs=require('node:fs'),http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'fixture-web');
const ids={user:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',vehicle:'33333333-3333-4333-8333-333333333333',request:'44444444-4444-4444-8444-444444444444',quote:'55555555-5555-4555-8555-555555555555'};
const mock=`(()=>{
 window.__calls=[];window.__tripStatus='accepted';window.__total=210;window.__uid='${ids.user}';
 const user={id:window.__uid,email:'test@example.test',email_confirmed_at:'2026-01-01',is_anonymous:false,user_metadata:{display_name:'خليل اختبار'}};
 const session={user,access_token:'TEST_TOKEN_'+ 'a'.repeat(40)};
 const regions=[{code:'damascus',name:'دمشق',enabled:true}];
 const vehicle={id:'${ids.vehicle}',make:'مركبة اختبار',model:'سيدان',car_type:'small',year_from:2010,year_to:2025};
 const classes=[{id:'test-class',name:'فئة سطحة اختبار',length_m:5,width_m:2.2,capacity_kg:2000,enabled:true}];
 const catalog={enabled:!new URLSearchParams(location.search).has('test_public'),trial_mode:!new URLSearchParams(location.search).has('test_public'),vehicles:[vehicle],matches:[false,true].map(enclosed=>({vehicle_id:vehicle.id,region_code:'damascus',enclosed,truck_name:enclosed?'سطحة مغلقة اختبار':'سطحة عادية اختبار',length_m:5}))};
 const admin={settings:{enabled:false,commission_pct:0,currency_label:'ل.س — اختبار',credit_limit:null,settlement_days:7},classes,vehicles:[vehicle],regions,drivers:[],fleet:[],ledger:[],tariffs:[],zones:[]};
 const client={auth:{getSession:async()=>({data:{session},error:null}),getUser:async()=>({data:{user},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signInAnonymously:async()=>({data:{session},error:null}),signOut:async()=>({error:null})},rpc:async(name,args={})=>{
 window.__calls.push({name,args});let data;
 switch(name){
 case 'get_customer_catalog':data={regions,services:[{code:'tow',name:'سطحة ونقل سيارة',enabled:true}],coverage:[{region_code:'damascus',service_code:'tow',enabled:true}]};break;
 case 'get_fazaa_commercial_catalog':data=catalog;break;
 case 'get_customer_history':data=[];break;
 case 'create_fazaa_request':data='${ids.request}';break;
 case 'get_customer_request':data=[{id:'${ids.request}',short_code:'123456',status:window.__tripStatus,lat:33.5,lng:36.2,created_at:new Date().toISOString(),driver_name:'سائق اختبار',driver_phone:'0999999999',driver_plate:'اختبار',driver_lat:33.52,driver_lng:36.22,driver_location_at:new Date().toISOString(),can_share:true,has_rating:false}];break;
 case 'get_fazaa_trip_details':data={request_id:'${ids.request}',priced:true,total:window.__total,currency_label:'ل.س — اختبار',vehicle_name:'مركبة اختبار سيدان',truck_name:'سطحة عادية اختبار',stops:[{label:'كراج اختبار',lat:33.6,lng:36.3}],driver_rating:{average:4.5,count:12},can_extend:window.__tripStatus==='accepted'};break;
 case 'approve_fazaa_extension':window.__total+=40;data=window.__total;break;
 case 'rate_customer_request':data=null;break;
 case 'is_admin':data=true;break;
 case 'admin_get_fazaa_commercial':data=admin;break;
 case 'admin_save_fazaa_commercial':data=null;break;
 case 'admin_get_fazaa_trial_customers':data=[];break;
 default:return {data:null,error:{message:'Unexpected RPC '+name}};
 }return {data,error:null};
 },from:()=>{const builder=new Proxy({}, {get(t,key){if(key==='then')return resolve=>Promise.resolve({data:[],error:null,count:0}).then(resolve);return ()=>builder}});return builder;}};
 window.supabase={createClient:()=>client};
 window.__mapById={};class Map {constructor(opts){this.center={lng:opts.center[0],lat:opts.center[1]};this.events={};window.__mapById[opts.container.id||opts.container]=this;}on(n,cb){(this.events[n]||=[]).push(cb);if(n==='load')setTimeout(cb,0);}trigger(n,e={}){for(const cb of this.events[n]||[])cb(e)}addControl(){}resize(){}isSourceLoaded(){return true;}getCenter(){return this.center;}easeTo(opts){this.center={lng:opts.center[0],lat:opts.center[1]};this.trigger('moveend');}fitBounds(){}remove(){}}
 class Marker {constructor(opts){this.el=opts.element;}setLngLat(){return this}addTo(){return this}getElement(){return this.el}remove(){}on(){return this}}
 window.maplibregl={Map,Marker,NavigationControl:class{},AttributionControl:class{},LngLatBounds:class{extend(){}}};
})();`;
(async()=>{
 const server=http.createServer((req,res)=>{let file=path.join(root,decodeURIComponent(req.url.split('?')[0]));if(req.url.split('?')[0]==='/')file=path.join(root,'index.html');if(!file.startsWith(root)||!fs.existsSync(file)){res.writeHead(404);return res.end();}res.setHeader('content-type',file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':file.endsWith('.png')?'image/png':'text/html');res.end(fs.readFileSync(file));});await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']}).catch(e=>{server.close();throw e;});
 let page;
 try{
 page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});const errors=[];page.on('pageerror',e=>{errors.push(e.message);console.error('BROWSER SCRIPT ERROR:',e.stack||e.message);});
 await page.addInitScript(mock);
 await page.route('https://**/*',async route=>{const url=route.request().url();if(url.includes('/functions/v1/fare-quote')){if(route.request().method()==='OPTIONS'){await route.fulfill({status:204,headers:{'access-control-allow-origin':'*','access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST, OPTIONS'}});return;}const input=route.request().postDataJSON();await route.fulfill({status:200,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify({quote_id:ids.quote,total:input.request_id?40:210,currency_label:'ل.س — اختبار',truck_name:'سطحة عادية اختبار',distance_km:3.2,minutes:10,expires_at:new Date(Date.now()+600000).toISOString(),is_extension:!!input.request_id})});}else if(url.includes('supabase-js'))await route.fulfill({contentType:'application/javascript',body:''});else if(url.endsWith('.js'))await route.fulfill({contentType:'application/javascript',body:''});else await route.abort();});
 const base='http://127.0.0.1:'+server.address().port;
 await page.goto(base);await page.waitForFunction(()=>document.querySelector('#vehicle-model')?.options.length===2);
 assert.equal(await page.locator('.bottom-nav button').count(),3);
 await page.click('#nav-account');await page.waitForSelector('#view-orders:visible');assert(await page.locator('#profile-name').innerText()==='خليل اختبار');
 await page.click('#nav-home');await page.click('#home-order');await page.locator('#problem-options button').first().click();await page.selectOption('#vehicle-model',ids.vehicle);await page.fill('#phone','0999999999');
 await page.selectOption('#truck-service','enclosed');await page.click('#details-next');assert(await page.locator('#details-step').isVisible());assert(await page.locator('#vehicle-year').isVisible());await page.selectOption('#truck-service','standard');await page.click('#details-next');await page.waitForSelector('#location-step:visible');
 await page.evaluate(()=>{document.querySelector('#lat').value='33.5';document.querySelector('#lng').value='36.2';updateLocation();});
 async function pick(lat,lng){await page.waitForFunction(()=>window.__mapById['destination-map']);await page.evaluate(({lat,lng})=>{const map=window.__mapById['destination-map'];map.center={lat,lng};map.trigger('moveend');},{lat,lng});await page.getByRole('button',{name:'اعتماد الموقع',exact:true}).click();}
 await page.getByRole('button',{name:'تحديد الموقع على الخريطة',exact:true}).click();await pick(33.6,36.3);await page.getByRole('button',{name:'حساب السعر',exact:true}).click();await page.waitForFunction(()=>document.querySelector('.fare-price')?.textContent.match(/210|٢١٠/));
 await page.locator('.fare-stop input').first().fill('تغيير الوجهة');await page.click('#submit');await page.waitForTimeout(100);assert.equal((await page.evaluate(()=>window.__calls.filter(x=>x.name==='create_fazaa_request'))).length,0,'changed inputs cannot book a stale quote');
 await page.getByRole('button',{name:'حساب السعر',exact:true}).click();await page.waitForTimeout(100);
 fs.mkdirSync(path.join(__dirname,'screenshots'),{recursive:true});await page.screenshot({path:path.join(__dirname,'screenshots/customer-quote.png'),fullPage:true});
 await page.click('#submit');await page.waitForSelector('#tracking:visible');await page.waitForFunction(()=>window.__calls.some(x=>x.name==='create_fazaa_request'));
 assert.equal((await page.evaluate(()=>window.__calls.filter(x=>x.name==='create_fazaa_request')))[0].args.p_quote,ids.quote);
 await page.getByRole('button',{name:'＋ إضافة وجهة بسعر متفق عليه'}).click();await page.getByRole('button',{name:'تحديد الوجهة الجديدة',exact:true}).click();await pick(33.7,36.4);await page.getByRole('button',{name:'حساب تكلفة الإضافة',exact:true}).click();await page.waitForFunction(()=>[...document.querySelectorAll('button')].some(b=>b.textContent==='الموافقة على الإضافة'&&!b.disabled));await page.getByRole('button',{name:'الموافقة على الإضافة',exact:true}).click();await page.waitForFunction(()=>window.__total===250);
 await page.evaluate(()=>{window.__tripStatus='done';refresh();});await page.waitForSelector('#rating-form:visible');await page.getByRole('button',{name:'3 من 5 نجوم',exact:true}).click();await page.fill('#rating-comment','تعليق خاص بالإدارة');await page.click('#rate');await page.waitForFunction(()=>window.__calls.some(x=>x.name==='rate_customer_request'));
 const rating=await page.evaluate(()=>window.__calls.find(x=>x.name==='rate_customer_request'));assert.equal(rating.args.p_stars,3);assert.equal(rating.args.p_comment,'تعليق خاص بالإدارة');assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'mobile layout must not overflow');
 await page.screenshot({path:path.join(__dirname,'screenshots/customer-invoice.png'),fullPage:true});
 await page.goto(base+'/?test_public=1');await page.waitForFunction(()=>!!window.FazaaApp);assert.equal(await page.locator('.bottom-nav button').count(),4,'public users retain legacy navigation while pricing is disabled');assert.equal(await page.locator('#vehicle-model').count(),0,'public users do not receive the private pricing UI');
 await page.setViewportSize({width:1280,height:900});await page.goto(base+'/admin.html');await page.waitForSelector('#dashboard:visible');await page.getByRole('button',{name:'التعرفة والأسطول والعمولات'}).click();await page.waitForSelector('#fare-admin-settings-commission_pct');assert.equal(await page.inputValue('#fare-admin-settings-commission_pct'),'0');assert.equal(await page.locator('#fare-admin-settings-enabled').isChecked(),false);await page.screenshot({path:path.join(__dirname,'screenshots/admin-commercial.png'),fullPage:true});
 assert.deepEqual(errors,[]);console.log('PASS: real browser mobile booking, VIP year required, account/history merged, stale quote blocked, fixed fare booking, approved extension, private rating, admin zero commission defaults and no mobile overflow');
 }catch(error){
  if(page){
   try{
    console.error('BROWSER FAILURE STATE:',JSON.stringify(await page.evaluate(()=>({url:location.href,modelOptions:document.querySelector('#vehicle-model')?.options.length,lastCalls:window.__calls?.slice(-8),notice:document.querySelector('#global-message')?.textContent})),null,2));
    fs.mkdirSync(path.join(__dirname,'screenshots'),{recursive:true});
    await page.screenshot({path:path.join(__dirname,'screenshots/failure.png'),fullPage:true});
   }catch(diagnostic){console.error('Diagnostic failed:',diagnostic.message);}
  }
  throw error;
 }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
