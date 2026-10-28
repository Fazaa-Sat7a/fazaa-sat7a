const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
const root=__dirname+'/fixture-web';
(async()=>{
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
 console.log('PASS: inaccessible startup pointer cleared; network failure and concurrent request changes preserved');
})().catch(e=>{console.error(e);process.exitCode=1});
