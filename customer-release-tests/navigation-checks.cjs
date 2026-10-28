const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
for(const file of ['customer-app.js','customer-app-v03.js']){
 const source=fs.readFileSync(__dirname+'/fixture-web/assets/'+file,'utf8');
 const ids=new Map();const element=()=>({value:'',hidden:false,children:[],classList:{toggle(){}},append(...nodes){this.children.push(...nodes)},replaceChildren(){this.children=[]},addEventListener(){}});
 const env={E:id=>{if(!ids.has(id))ids.set(id,element());return ids.get(id)},node:(tag,cls,text)=>Object.assign(element(),{tag,className:cls,textContent:text}),step:1,problems:[],cars:[],document:{activeElement:{blur(){}}},CustomEvent:class{constructor(type,opts){this.type=type;this.detail=opts.detail}},window:{dispatchEvent(){},scrollTo(opts){env.scroll=opts.top}},requestAnimationFrame:cb=>cb(),pickupMap:{render(){}},rows:Array.from({length:25},(_,i)=>({id:i,status:'done',short_code:i,created_at:'2026-10-28'})),filter:'all',historyPage:0,pageSize:3,historyBusy:false,historyHasMore:false,terminal:status=>status==='done',statusInfo:{done:['اكتملت الخدمة']},openOrder(){},begin(){}};
 vm.createContext(env);vm.runInContext(source.split('\n').find(l=>l.startsWith(' function setStep(')),env);
 env.setStep(2);assert.equal(env.E('details-step').hidden,true);assert.equal(env.E('location-step').hidden,false);assert.equal(env.E('destination-step').hidden,true);assert.equal(env.scroll,0);
 env.setStep(3);assert.equal(env.E('location-step').hidden,true);assert.equal(env.E('destination-step').hidden,false);env.setStep(2);assert.equal(env.E('destination-step').hidden,true);
 vm.runInContext(source.split('\n').find(l=>l.startsWith(' function paintHistory(')),env);
 env.paintHistory();assert.equal(env.E('history-list').children.length,3);assert.equal(env.E('history-prev').disabled,true);env.historyPage=8;env.paintHistory();assert.equal(env.E('history-list').children.length,1);assert.equal(env.E('history-more').disabled,true);assert.equal(env.E('history-list').children[0].tag,'details');
}
console.log('PASS: both app modes show one booking step, reset scroll, retain three-order pages and fold individual orders');
