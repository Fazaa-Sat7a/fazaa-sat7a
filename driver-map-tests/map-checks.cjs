const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const html=fs.readFileSync(__dirname+'/../android/app/src/main/assets/map.html','utf8');
const js=html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
const maps=[],pins=[],note={hidden:false},elements=[];
class MapMock{
 constructor(){this.events={};this.sources={};this.layers=[];maps.push(this);}
 addControl(){}on(k,fn){this.events[k]=fn;}
 addSource(k,source){this.sources[k]={data:source.data,setData(data){this.data=data;}};}
 getSource(k){return this.sources[k];}addLayer(layer){this.layers.push(layer);}fitBounds(bounds){this.bounds=bounds;}
}
class Marker{
 constructor(opts){this.el=opts.element;pins.push(this);}setLngLat(p){this.point=p;return this;}addTo(){return this;}remove(){this.removed=true;}
}
class Bounds{constructor(){this.points=[];}extend(c){this.points.push(c);}}
const document={getElementById:()=>note,head:{appendChild(){}},createElement:tag=>{const n={tag,setAttribute(k,v){this[k]=v;}};elements.push(n);return n;}};
const c={document,window:{},maplibregl:{Map:MapMock,Marker,LngLatBounds:Bounds,NavigationControl:class{}},Number,Array,JSON,String};vm.createContext(c);vm.runInContext(js,c);
const route={calculated_at:'2026-10-26T10:00:00Z',geometry:{type:'LineString',coordinates:[[36.3,33.5],[36.31,33.51],[36.32,33.52]]}};
const points=[{lat:33.5,lng:36.3,driver:true},{lat:33.52,lng:36.32,delivery:true,label:'<img src=x onerror=alert(1)>'}];
c.window.setMapState({points,route});c.init();maps[0].events.load();
assert.equal(maps[0].layers.filter(l=>l.type==='line').length,2);
assert.equal(JSON.stringify(maps[0].sources['trip-route'].data.features[0].geometry),JSON.stringify(route.geometry));
assert.equal(pins.filter(p=>!p.removed).length,2);assert.equal(pins.at(-1).el.textContent,'و');assert.equal(pins.at(-1).el['aria-label'],points[1].label);assert(!('innerHTML' in pins.at(-1).el));
assert.equal(maps[0].bounds.points.length,5,'fit includes route bends and both markers');
c.window.setMapState({points:[{lat:33.501,lng:36.301,driver:true,stale:true}],route});assert(pins.at(-1).el.className.includes('stale'));
c.window.setMapState({points,route:null});assert.equal(maps[0].sources['trip-route'].data.features.length,0,'failed/refreshed route clears previous geometry');
c.window.setMapState({points:[{lat:100,lng:0}],route:{calculated_at:'bad',geometry:{type:'LineString',coordinates:[[0,95],[1,1]]}}});assert.equal(maps[0].sources['trip-route'].data.features.length,0);assert(pins.every(p=>p.removed));
c.window.setMapState({points:[{lat:33.5,lng:36.3,driver:true},{lat:33.51,lng:36.31,preview:true,delivery:false,label:'العميل'},{lat:33.52,lng:36.32,preview:true,delivery:true,number:1,label:'كراج أول'},{lat:33.53,lng:36.33,preview:true,delivery:true,number:2,label:'كراج ثان'}],route});
const active=pins.filter(p=>!p.removed);assert.equal(active.length,4);assert.equal(active[1].el.textContent,'ع');assert.equal(active[2].el.textContent,'1');assert.equal(active[3].el.textContent,'2');assert(active[2].el.className.includes('delivery'));assert(active[3].el.className.includes('delivery'));
assert(html.includes('openrouteservice.org'));assert(html.includes('openstreetmap.org/copyright'));
console.log('PASS: actual map JS queues geometry until load, draws provider line, includes bends in bounds, updates GPS pins, marks stale GPS, clears missing/invalid routes and renders labels as text.');
