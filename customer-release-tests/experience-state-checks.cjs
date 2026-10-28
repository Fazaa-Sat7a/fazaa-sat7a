'use strict';
const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
const root=__dirname+'/fixture-web';
const ids=new Map();let calls=[],changes=0;
class Element{
 constructor(tag){this.tagName=tag;this.children=[];this.events={};this.dataset={};this.attrs={};this.value='';this.hidden=false;this.classList={toggle(){}};}
 set id(v){this._id=v;ids.set(v,this)}get id(){return this._id}
 append(...items){this.children.push(...items)}replaceChildren(...items){this.children=items}setAttribute(k,v){this.attrs[k]=v}removeAttribute(k){delete this.attrs[k]}
 addEventListener(e,f){(this.events[e]??=[]).push(f)}dispatchEvent(e){for(const f of this.events[e.type]||[])f(e)}
 querySelectorAll(tag){return this.children.flatMap(c=>c instanceof Element?[...(c.tagName===tag?[c]:[]),...c.querySelectorAll(tag)]:[])}scrollIntoView(){}
 click(){this.dispatchEvent({type:'click'})}
}
const create=tag=>new Element(tag);for(const id of ['car-options','car-type']){const el=create('div');el.id=id;}
const context={document:{getElementById:id=>ids.get(id),createElement:create,createElementNS:(ns,tag)=>create(tag)},window:{FazaaApp:{regionCode:'damascus'},dispatchEvent(){changes++}},Event:class{constructor(type){this.type=type}},Option:class{},setTimeout(){},localStorage:{getItem:()=>null},rpc:async(name,args)=>{calls.push({name,args});return 'booked'},errorText:String,Date,Number};
vm.createContext(context);vm.runInContext(fs.readFileSync(root+'/assets/vehicle-directory.js','utf8'),context);vm.runInContext(fs.readFileSync(root+'/assets/vehicle-categories.js','utf8'),context);
(async()=>{
 const vehicle=context.window.FazaaVehicle,buttons=ids.get('car-options').querySelectorAll('button');
 assert.equal(vehicle.validate(),false);
 buttons.find(b=>b.dataset.category==='passenger').click();assert.equal(vehicle.validate(),false,'truck type required');
 buttons.find(b=>b.dataset.service==='enclosed').click();assert.equal(vehicle.validate(),true,'make/model/year optional even enclosed');
 assert.equal(vehicle.payload().vehicle_year,null);assert.equal(vehicle.payload().vehicle_name,'');
 ids.get('vehicle-year').value='٢٠٢٠';assert.equal(vehicle.payload().vehicle_year,2020);
 ids.get('vehicle-year').value='1800';assert.equal(vehicle.validate(),false);
 ids.get('vehicle-year').value='';ids.get('vehicle-make').value='Toyota';ids.get('vehicle-model').value='Corolla';assert.equal(vehicle.payload().vehicle_name,'Toyota Corolla');
 ids.get('vehicle-make').value='تو';ids.get('vehicle-make').dispatchEvent({type:'input'});assert.equal(ids.get('vehicle-model').value,'','changing brand clears dependent model');
 assert(ids.get('vehicle-make-suggestions').children.some(b=>b.textContent?.includes('Toyota')),'Arabic make search');
 ids.get('vehicle-make').value='Toyota';ids.get('vehicle-model').value='كور';ids.get('vehicle-model').dispatchEvent({type:'input'});assert(ids.get('vehicle-model-suggestions').children.some(b=>b.textContent?.includes('Corolla')),'Arabic model search');
 ids.get('vehicle-make').value='ماركة أخرى';ids.get('vehicle-model').value='موديل آخر';assert.equal(vehicle.validate(),true,'free text supported');
 await context.rpc('create_request',{p_lat:33.5,p_lng:36.2,p_problem:'other',p_phone:'0999999999'});assert.equal(calls[0].args.p_enclosed,true);assert.equal(calls[0].args.p_year,null);assert.equal(calls[0].args.p_vehicle_name,'ماركة أخرى موديل آخر');
 const directory=context.window.FazaaVehicleDirectory;assert(directory.length>=150);assert(directory.reduce((n,b)=>n+b.models.length,0)>=1400);assert.equal(new Set(directory.map(b=>b.name)).size,directory.length);
 console.log('PASS: required category and truck, optional blank/custom vehicle fields, Arabic make/model search, optional Arabic year, model reset and category RPC payload');
})().catch(e=>{console.error(e);process.exitCode=1});
