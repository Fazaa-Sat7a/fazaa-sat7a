const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
const root=__dirname+'/fixture-web';
(async()=>{
 const ids=new Map();let changes=0,captured;
 class Element{
  constructor(tag){this.tagName=tag;this.children=[];this.handlers={};this.dataset={};this.value='';this.classList={toggle(){}};this.hidden=false;}
  set id(v){this._id=v;ids.set(v,this)}get id(){return this._id}
  append(...items){this.children.push(...items)}replaceChildren(...items){this.children=items}setAttribute(){}
  addEventListener(e,f){this.handlers[e]=f}querySelectorAll(tag){return this.children.filter(c=>c.tagName===tag)}
 }
 const element=tag=>new Element(tag);for(const id of ['car-options','car-type']){const n=element('div');n.id=id;}
 const context={document:{getElementById:id=>ids.get(id),createElement:element,createElementNS:(ns,t)=>element(t)},window:{FazaaApp:{regionCode:'damascus'},dispatchEvent(){changes++}},Option:class extends Element{constructor(t,v){super('option');this.value=v}},Event:class{},localStorage:{getItem:()=>null},rpc:async(name,args)=>{captured={name,args};return 'created'},errorText:String,Date,Number};
 vm.createContext(context);vm.runInContext(fs.readFileSync(root+'/assets/vehicle-categories.js','utf8'),context);
 const vehicle=context.window.FazaaVehicle;
 assert.equal(vehicle.validate(),false);assert.equal(ids.get('vehicle-year').hidden,true);
 const grid=ids.get('car-options').children[0];grid.children.find(x=>x.dataset.category==='pickup').handlers.click();ids.get('vehicle-name').value='فورد F-150';
 assert.equal(vehicle.validate(),true);assert.equal(ids.get('car-type').value,'truck');
 ids.get('truck-service').value='enclosed';ids.get('truck-service').handlers.change();assert.equal(vehicle.validate(),false);assert.equal(ids.get('vehicle-year').hidden,false);
 ids.get('vehicle-year').value='2020';assert.equal(vehicle.validate(),true);
 await context.rpc('create_request',{p_lat:33.5,p_lng:36.2,p_problem:'engine',p_phone:'0999999999'});
 assert.equal(captured.name,'create_fazaa_category_request');assert.equal(captured.args.p_category,'pickup');assert.equal(captured.args.p_vehicle_name,'فورد F-150');assert.equal(captured.args.p_year,2020);assert.equal(captured.args.p_enclosed,true);
 ids.get('truck-service').value='standard';ids.get('truck-service').handlers.change();assert.equal(ids.get('vehicle-year').value,'');assert(changes>=3);
 // Both pricing modes must open the saved request even when history is empty.
 for(const name of ['customer-app.js','customer-app-v03.js']){
  const source=fs.readFileSync(root+'/assets/'+name,'utf8');
  const line=source.split('\n').find(x=>x.includes("E('active-banner').addEventListener('click'"));
  const handler=line.slice(line.indexOf("E('active-banner').addEventListener"));
  let click,opened=null,navigated=null;
  const env={E:()=>({addEventListener:(type,f)=>{click=f}}),rows:[],requestId:'saved-order',terminal:()=>false,openOrder:id=>{opened=id},go:page=>{navigated=page}};
  vm.runInNewContext(handler,env);click();assert.equal(opened,'saved-order',name+' saved request banner');assert.equal(navigated,null);
 }
 const html=fs.readFileSync(root+'/index.html','utf8');const refresh=html.split('\n').find(x=>x.startsWith('async function refresh(){'));const clear=html.split('\n').find(x=>x.startsWith('function clearUnavailableRequest('));const schedule=html.split('\n').find(x=>x.startsWith('function schedule('));
 const elements=new Map(),memory=new Map([['active','id-1']]);let mode='missing',rendered=0,retries=0;
 const state={requestId:'id-1',currentStatus:null,timer:null,loading:false,ACTIVE_KEY:'active',$:id=>{if(!elements.has(id))elements.set(id,{});return elements.get(id)},localStorage:{removeItem:k=>memory.delete(k)},clearTimeout(){},setTimeout(){retries++;},terminal:()=>false,clearHandoff(){},message(){},errorText:String,renderRequest(){rendered++},rpc:async()=>{if(mode==='offline')throw Error('offline');if(mode==='race'){state.requestId='id-2';return [];}return mode==='missing'?[]:[{status:'accepted'}]},Date};
 vm.createContext(state);vm.runInContext(clear+'\n'+schedule+'\n'+refresh,state);
 await state.refresh();assert.equal(state.requestId,null);assert(!memory.has('active'));assert.equal(retries,0);
 mode='offline';state.requestId='id-1';memory.set('active','id-1');await state.refresh();assert.equal(state.requestId,'id-1');assert(memory.has('active'));assert.equal(retries,1);
 mode='race';await state.refresh();assert.equal(state.requestId,'id-2');assert(memory.has('active'));
 mode='valid';await state.refresh();assert.equal(rendered,1);
 console.log('PASS: category/VIP validation and actual public RPC payload; inaccessible startup pointer cleared; network failure and concurrent request changes preserved');
})().catch(e=>{console.error(e);process.exitCode=1});
