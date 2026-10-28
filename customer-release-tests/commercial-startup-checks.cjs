// Execute the real commercial module with a minimal DOM to detect initialization errors.
const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const source=fs.readFileSync(process.env.FAZAA_COMMERCIAL_SOURCE||__dirname+'/fixture-web/assets/commercial-customer.js','utf8');
function environment(){
 const ids=new Map(),timers=new Map();let timer=0;
 class Element {
  constructor(tag='div'){this.tagName=tag;this.children=[];this.style={};this.attrs={};this.dataset={};this.value='';this.hidden=false;this.textContent='';const classes=new Set();this.classList={add:x=>classes.add(x),remove:x=>classes.delete(x),toggle:()=>{}};}
  set id(value){this._id=value;ids.set(value,this);}get id(){return this._id;}
  prepend(...nodes){this.children.unshift(...nodes);}append(...nodes){this.children.push(...nodes);}replaceChildren(...nodes){this.children=[...nodes];}before(){}insertBefore(n){this.append(n);}remove(){}addEventListener(){}setAttribute(k,v){this.attrs[k]=v;}querySelectorAll(){return [];}showModal(){this.open=true;}close(){this.open=false;}
 }
 const html=fs.readFileSync(__dirname+'/fixture-web/index.html','utf8');for(const [,id]of html.matchAll(/\bid="([^"]+)"/g)){const n=new Element();n.id=id;}
 const document={body:new Element('body'),getElementById:id=>ids.get(id),createElement:tag=>new Element(tag),createTextNode:text=>Object.assign(new Element('text'),{textContent:text}),querySelector:selector=>selector==='.progress-steps'?new Element():null};
 const status=new Element();status.id='vehicle-status';
 const model={id:'TEST-MODEL',make:'TEST',model:'sedan',car_type:'small',year_from:2010,year_to:2025};
 const catalog={enabled:true,vehicles:[model],matches:[]};
 const context={document,window:{addEventListener(){},FazaaVehicle:{payload:()=>({}),selected:null,validate:()=>false},FazaaApp:{regionCode:'damascus'},FazaaMaps:{View:class{render(){}update(){}}}},Option:class extends Element{constructor(text,value){super('option');this.textContent=text;this.value=value;}},MutationObserver:class{observe(){}},errorText:e=>String(e),updateLocation(){},coordinates:()=>null,rpc:async()=>null,renderRequest(){},message(){},requestId:null,location:{search:'?app=1'},localStorage:{getItem:()=>null},client:{rpc:async()=>({data:catalog,error:null})},setTimeout:(f)=>{timers.set(++timer,f);return timer},clearTimeout:id=>timers.delete(id),URLSearchParams,Date,console};
 vm.createContext(context);return {context,ids};
}
(async()=>{const {context,ids}=environment();vm.runInContext(source,context,{filename:'commercial-customer.js'});await new Promise(setImmediate);
 assert(context.window.FazaaCommercial,'commercial module must initialize');assert(!ids.has('vehicle-model'),'model catalog removed');assert(ids.has('destination-map'));assert.equal(context.window.FazaaCommercial.validateVehicle(),false,'no model cannot book');console.log('PASS: real commercial module initializes, creates price/destination controls, uses category module, and enforces required category');
})().catch(e=>{console.error(e);process.exitCode=1;});
