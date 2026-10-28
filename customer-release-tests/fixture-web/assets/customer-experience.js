'use strict';
(()=>{
 const E=id=>document.getElementById(id),node=(tag,cls='',text)=>{const n=document.createElement(tag);n.className=cls;if(text!==undefined)n.textContent=text;return n;};
 const button=(text,action,cls)=>{const b=node('button',cls,text);b.type='button';b.addEventListener('click',action);return b;};
 const preferences=node('section','experience-settings');preferences.append(node('span','eyebrow','على راحتك'),node('h2','','إعدادات التطبيق'));
 const updates=node('a','settings-tile update-tile');updates.href='./?app=1&native=updates';updates.innerHTML='<span class="settings-symbol" aria-hidden="true">↻</span><span><strong>تحديث تطبيق فزعة</strong><small>تحقّق من أحدث إصدار بسهولة</small></span><span aria-hidden="true">←</span>';
 updates.hidden=!new URLSearchParams(location.search).has('app');preferences.append(updates);
 const notification=node('a','settings-tile');notification.href='./?app=1&native=notifications';notification.innerHTML='<span class="settings-symbol" aria-hidden="true"><svg viewBox="0 0 24 24" width="25" height="25" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 17h14l-2-3V9a5 5 0 0 0-10 0v5zM10 20h4M12 2v2"/></svg></span><span><strong>إشعارات طلبك</strong><small>خليك على اطلاع بقبول الكابتن ووصوله</small></span><span aria-hidden="true">←</span>';notification.hidden=updates.hidden;preferences.append(notification);
 for(const old of document.querySelectorAll('.native-notification-link'))old.remove();
 let muted=localStorage.getItem('fazaa.sound.muted')==='yes',audio;
 function unlock(){try{audio=audio||new (window.AudioContext||window.webkitAudioContext)();if(audio.state==='suspended')audio.resume().catch(()=>{});}catch{}}
 document.addEventListener('pointerdown',unlock,{once:true});document.addEventListener('keydown',unlock,{once:true});
 const mute=button('',()=>{muted=!muted;localStorage.setItem('fazaa.sound.muted',muted?'yes':'no');paintMute();if(!muted){unlock();play('confirm');}},'settings-tile sound-tile');
 function paintMute(){mute.replaceChildren(node('span','settings-symbol',muted?'♪':'♫'));const text=node('span');text.append(node('strong','',muted?'أصوات داخل التطبيق مكتومة':'أصوات داخل التطبيق مفعّلة'),node('small','','نغمات قصيرة لتأكيد الإجراءات وتغيّر حالة الطلب'));mute.append(text,node('span','sound-switch',muted?'إيقاف':'تشغيل'));mute.setAttribute('aria-pressed',String(!muted));}paintMute();preferences.append(mute);E('view-account').append(preferences);
 function play(kind){if(muted||document.hidden||!audio||audio.state!=='running')return;const tones={confirm:[660,880],accepted:[660,880,1100],arrived:[880,660,880],in_progress:[523,784],done:[523,659,784,1046],error:[220,196],cancelled_customer:[330,220],cancelled_driver:[330,220]};try{(tones[kind]||tones.confirm).forEach((f,i)=>{const osc=audio.createOscillator(),gain=audio.createGain(),at=audio.currentTime+i*.14;osc.type='sine';osc.frequency.value=f;gain.gain.setValueAtTime(0,at);gain.gain.linearRampToValueAtTime(.045,at+.015);gain.gain.exponentialRampToValueAtTime(.0001,at+.13);osc.connect(gain);gain.connect(audio.destination);osc.start(at);osc.stop(at+.14);});}catch{}}
 const oldPersist=persistId;persistId=function(id){oldPersist(id);play('confirm');};
 const oldMessage=message;message=function(text,type){oldMessage(text,type);if(text&&type==='error')play('error');else if(text&&type==='success')play('confirm');};
 const approach=node('section','approach-card');approach.id='tow-approach';approach.setAttribute('aria-label','اقتراب السطحة');approach.hidden=true;
 const heading=node('div','approach-heading'),title=node('strong'),distance=node('span','distance-chip'),track=node('div','approach-road'),truck=node('div','approach-truck');truck.innerHTML='<svg viewBox="0 0 80 42" aria-hidden="true"><path fill="#FFC21C" d="M2 25h50V10h15l11 15v10H2z"/><path fill="#13243C" d="M57 15h8l7 10H57zM8 22l6-8h18l9 8z"/><circle cx="18" cy="34" r="7" fill="#13243C"/><circle cx="66" cy="34" r="7" fill="#13243C"/><circle cx="18" cy="34" r="3" fill="white"/><circle cx="66" cy="34" r="3" fill="white"/></svg>';
 const target=node('span','approach-target','●'),note=node('p','map-help');heading.append(title,distance);track.append(truck,target);approach.append(heading,track,note);E('tracking-description').after(approach);
 let lastRequest=null,lastTrip=null;
 function km(a,b){const rad=x=>x*Math.PI/180,dlat=rad(b.lat-a.lat),dlng=rad(b.lng-a.lng),h=Math.sin(dlat/2)**2+Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(dlng/2)**2;return 6371*2*Math.atan2(Math.sqrt(h),Math.sqrt(1-h));}
 function draw(r){const active=['new','accepted','arrived','in_progress'].includes(r.status);approach.hidden=!active;if(!active)return;const searching=r.status==='new';approach.classList.toggle('searching',searching);approach.classList.remove('stale');distance.textContent='';if(searching){title.textContent='عم ندوّر على كابتن قريب';note.textContent='هذه حركة انتظار؛ سيظهر الاقتراب الفعلي بعد قبول الطلب.';return;}
  const enroute=r.status==='in_progress';title.textContent=enroute?'سيارتك بطريقها للوجهة':r.status==='arrived'?'الكابتن وصل لعندك':'الكابتن بطريقه لعندك';
  if(r.status==='arrived'){truck.style.setProperty('--progress','95%');note.textContent='أكد الكابتن وصوله إلى موقع السيارة.';return;}
  const dest=enroute?(lastTrip?.id===requestId?lastTrip.trip.stops?.at(-1):null):{lat:r.lat,lng:r.lng};
  const fresh=Date.now()-new Date(r.driver_location_at||0).getTime()<90000;
  if(!fresh||!dest||!window.FazaaMaps.valid(r.driver_lat,r.driver_lng)||!window.FazaaMaps.valid(dest.lat,dest.lng)){approach.classList.add('stale');truck.style.setProperty('--progress','5%');note.textContent='بانتظار موقع حديث من الكابتن؛ مؤشر الاقتراب متوقف مؤقتاً.';return;}
  const remaining=km({lat:Number(r.driver_lat),lng:Number(r.driver_lng)},{lat:Number(dest.lat),lng:Number(dest.lng)}),key='fazaa.approach.'+requestId+'.'+r.status;
  let baseline=Number(sessionStorage.getItem(key));if(!baseline||baseline<remaining){baseline=Math.max(remaining,.1);sessionStorage.setItem(key,String(baseline));}
  const progress=Math.max(5,Math.min(95,5+90*(1-remaining/baseline)));truck.style.setProperty('--progress',progress+'%');distance.textContent=remaining<1?Math.round(remaining*1000)+' م تقريباً':remaining.toFixed(1)+' كم تقريباً';note.textContent=(enroute?'الاقتراب من الوجهة النهائية':'الاقتراب من موقع سيارتك')+' بحسب آخر موقع للكابتن. المسافة مباشرة وليست مسافة الطريق أو وقت الوصول.';
 }
 const oldRender=renderRequest;renderRequest=function(r){oldRender(r);lastRequest={id:requestId,value:r};const key='fazaa.sound.status.'+requestId,previous=sessionStorage.getItem(key);if(previous&&previous!==r.status)play(r.status);sessionStorage.setItem(key,r.status);draw(r);};
 window.addEventListener('fazaa-trip-details',event=>{if(event.detail.id!==requestId)return;lastTrip=event.detail;draw(event.detail.request);});
 setInterval(()=>{if(lastRequest?.id===requestId&&!document.hidden)draw(lastRequest.value);},15000);
 window.FazaaExperience={play,km};
 // State is injected only by the native shell on this trusted page.
 window.addEventListener('fazaa-update-state',()=>{const value=window.FazaaUpdateState;if(value&&updates.querySelector('small'))updates.querySelector('small').textContent=value;});
})();
