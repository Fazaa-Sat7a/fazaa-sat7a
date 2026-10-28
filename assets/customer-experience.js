'use strict';
(()=>{
 const E=id=>document.getElementById(id),node=(tag,cls='',text)=>{const n=document.createElement(tag);n.className=cls;if(text!==undefined)n.textContent=text;return n;};
 const button=(text,action,cls)=>{const b=node('button',cls,text);b.type='button';b.addEventListener('click',action);return b;};
 // Keep account actions compact and reachable independently of the order count.
 const profileDetails=node('details','account-fold');profileDetails.id='profile-details';profileDetails.append(node('summary','','بياناتي وتعديل الملف الشخصي'),E('profile-email'),E('profile-form'),E('account-link-retry'));E('account-profile').append(profileDetails,E('account-logout'));
 const orders=E('view-orders'),ordersFold=node('details','account-fold');ordersFold.id='orders-fold';ordersFold.append(node('summary','','طلباتي'));for(const child of [...orders.children])ordersFold.append(child);orders.replaceChildren(ordersFold);if(ordersFold.querySelector('.page-title'))ordersFold.querySelector('.page-title').hidden=true;
 const settingsDialog=node('dialog','fare-dialog settings-dialog');settingsDialog.id='settings-dialog';settingsDialog.setAttribute('aria-label','إعدادات التطبيق');const settingsOpen=button('⚙ الإعدادات',()=>settingsDialog.showModal(),'settings-open');settingsOpen.id='settings-open';settingsOpen.setAttribute('aria-haspopup','dialog');E('view-account').querySelector('.page-title').append(settingsOpen);settingsDialog.append(button('إغلاق',()=>settingsDialog.close(),'text-button'));document.body.append(settingsDialog);
 const preferences=node('section','experience-settings');preferences.append(node('span','eyebrow','على راحتك'),node('h2','','إعدادات التطبيق'));
 const updates=node('a','settings-tile update-tile');updates.href='./?app=1&native=updates';updates.innerHTML='<span class="settings-symbol" aria-hidden="true">↻</span><span><strong>تحديث تطبيق فزعة</strong><small>تحقّق من أحدث إصدار بسهولة</small></span><span aria-hidden="true">←</span>';
 updates.hidden=!new URLSearchParams(location.search).has('app');preferences.append(updates);
 const notification=node('a','settings-tile');notification.href='./?app=1&native=notifications';notification.innerHTML='<span class="settings-symbol" aria-hidden="true"><svg viewBox="0 0 24 24" width="25" height="25" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 17h14l-2-3V9a5 5 0 0 0-10 0v5zM10 20h4M12 2v2"/></svg></span><span><strong>إشعارات طلبك</strong><small>خليك على اطلاع بقبول الكابتن ووصوله</small></span><span aria-hidden="true">←</span>';notification.hidden=updates.hidden;preferences.append(notification);
 for(const old of document.querySelectorAll('.native-notification-link'))old.remove();
 let muted=localStorage.getItem('fazaa.sound.muted')==='yes',audio;
 function unlock(){try{audio=audio||new (window.AudioContext||window.webkitAudioContext)();if(audio.state==='suspended')audio.resume().catch(()=>{});}catch{}}
 document.addEventListener('pointerdown',unlock,{once:true});document.addEventListener('keydown',unlock,{once:true});
 const mute=button('',()=>{muted=!muted;localStorage.setItem('fazaa.sound.muted',muted?'yes':'no');paintMute();if(!muted){unlock();play('confirm');}},'settings-tile sound-tile');
 function paintMute(){mute.replaceChildren(node('span','settings-symbol',muted?'♪':'♫'));const text=node('span');text.append(node('strong','',muted?'أصوات داخل التطبيق مكتومة':'أصوات داخل التطبيق مفعّلة'),node('small','','نغمات قصيرة لتأكيد الإجراءات وتغيّر حالة الطلب'));mute.append(text,node('span','sound-switch',muted?'إيقاف':'تشغيل'));mute.setAttribute('aria-pressed',String(!muted));}paintMute();preferences.append(mute);settingsDialog.append(preferences);updates.addEventListener('click',()=>settingsDialog.close());notification.addEventListener('click',()=>settingsDialog.close());
 function play(kind){if(muted||document.hidden||!audio||audio.state!=='running')return;const tones={confirm:[660,880],accepted:[660,880,1100],arrived:[880,660,880],in_progress:[523,784],done:[523,659,784,1046],error:[220,196],cancelled_customer:[330,220],cancelled_driver:[330,220]};try{(tones[kind]||tones.confirm).forEach((f,i)=>{const osc=audio.createOscillator(),gain=audio.createGain(),at=audio.currentTime+i*.14;osc.type='sine';osc.frequency.value=f;gain.gain.setValueAtTime(0,at);gain.gain.linearRampToValueAtTime(.045,at+.015);gain.gain.exponentialRampToValueAtTime(.0001,at+.13);osc.connect(gain);gain.connect(audio.destination);osc.start(at);osc.stop(at+.14);});}catch{}}
 const oldPersist=persistId;persistId=function(id){oldPersist(id);play('confirm');};
 const oldMessage=message;message=function(text,type){oldMessage(text,type);if(text&&type==='error')play('error');else if(text&&type==='success')play('confirm');};
 const approach=node('section','approach-card');approach.id='tow-approach';approach.setAttribute('aria-label','اقتراب السطحة');approach.hidden=true;
 const heading=node('div','approach-heading'),title=node('strong'),distance=node('span','distance-chip'),track=node('div','approach-road'),truck=node('div','approach-truck');truck.innerHTML='<svg viewBox="0 0 80 42" aria-hidden="true"><path fill="#FFC21C" d="M2 25h50V10h15l11 15v10H2z"/><path fill="#13243C" d="M57 15h8l7 10H57zM8 22l6-8h18l9 8z"/><circle cx="18" cy="34" r="7" fill="#13243C"/><circle cx="66" cy="34" r="7" fill="#13243C"/><circle cx="18" cy="34" r="3" fill="white"/><circle cx="66" cy="34" r="3" fill="white"/></svg>';
 const target=node('span','approach-target'),targetIcon=node('span','target-icon'),targetLabel=node('span','target-label'),origin=node('span','approach-origin','السطحة'),note=node('p','map-help');target.append(targetIcon,targetLabel);heading.append(title,distance);track.append(truck,origin,target);
 const radar=node('div','tow-radar');radar.setAttribute('aria-hidden','true');radar.innerHTML='<span class="radar-sweep"></span><span class="radar-ring"></span><span class="radar-dot"></span><span class="radar-truck">'+truck.innerHTML+'</span>';
 approach.append(heading,radar,track,note);E('tracking-description').after(approach);
 let lastRequest=null,lastTrip=null;
 function km(a,b){const rad=x=>x*Math.PI/180,dlat=rad(b.lat-a.lat),dlng=rad(b.lng-a.lng),h=Math.sin(dlat/2)**2+Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(dlng/2)**2;return 6371*2*Math.atan2(Math.sqrt(h),Math.sqrt(1-h));}
 const carIcon='<svg viewBox="0 0 64 38" aria-hidden="true"><path fill="#2786B6" d="M5 26V17l10-3 8-10h19l10 12 8 4v11H5z"/><path fill="#D5EEF8" d="M21 15l5-7h13l6 7z"/><circle cx="16" cy="30" r="6" fill="#13243c"/><circle cx="49" cy="30" r="6" fill="#13243c"/></svg>';
 const garageIcon='<svg viewBox="0 0 64 40" aria-hidden="true"><path fill="#299A93" d="M4 15L32 2l28 13v24H4z"/><path fill="#D5EEF8" d="M14 18h36v21H14z"/><path stroke="#13243c" stroke-width="2" d="M17 23h30M17 28h30M17 33h30"/></svg>';
 let drawnStage='';
 function draw(r){const active=['new','accepted','arrived','in_progress'].includes(r.status);approach.hidden=!active;if(!active)return;const searching=r.status==='new',enroute=r.status==='in_progress',stage=searching?'searching':enroute?'destination':'pickup';approach.dataset.stage=stage;
  approach.classList.toggle('searching',searching);radar.hidden=!searching;track.hidden=searching;approach.classList.remove('stale');distance.textContent='';
  if(searching){title.textContent='عم نبحث عن سطحة قريبة';note.textContent='بانتظار قبول كابتن لطلبك.';drawnStage='searching';return;}
  targetLabel.textContent=enroute?'وجهة التوصيل':'سيارتك';targetIcon.innerHTML=enroute?garageIcon:carIcon;
  const stageKey=requestId+'.'+stage;if(drawnStage!==stageKey){truck.style.transition='none';truck.style.setProperty('--progress','0%');void truck.offsetWidth;truck.style.transition='';drawnStage=stageKey;}
  title.textContent=enroute?'السطحة بطريقها لوجهة التوصيل':r.status==='arrived'?'الكابتن وصل إلى سيارتك':'السطحة بطريقها إلى سيارتك';
  if(r.status==='arrived'){truck.style.setProperty('--progress','100%');note.textContent='بانتظار بدء نقل السيارة. ستظهر وجهة التوصيل عند بدء النقل.';return;}
  const dest=enroute?(lastTrip?.id===requestId?lastTrip.trip.stops?.at(-1):null):{lat:r.lat,lng:r.lng};
  const age=Date.now()-new Date(r.driver_location_at||0).getTime(),fresh=Number.isFinite(age)&&age>=-30000&&age<90000;
  if(!fresh||!dest||!window.FazaaMaps.valid(r.driver_lat,r.driver_lng)||!window.FazaaMaps.valid(dest.lat,dest.lng)){approach.classList.add('stale');note.textContent='بانتظار تحديث موقع الكابتن؛ تبقى آخر حركة معروفة ظاهرة.';return;}
  const remaining=km({lat:Number(r.driver_lat),lng:Number(r.driver_lng)},{lat:Number(dest.lat),lng:Number(dest.lng)}),key='fazaa.approach.'+requestId+'.'+stage;
  let baseline=Number(sessionStorage.getItem(key));if(!baseline||baseline<remaining){baseline=Math.max(remaining,.1);sessionStorage.setItem(key,String(baseline));}
  const progress=Math.max(0,Math.min(95,95*(1-remaining/baseline)));truck.style.setProperty('--progress',progress+'%');distance.textContent=remaining<1?Math.round(remaining*1000)+' م تقريباً':remaining.toFixed(1)+' كم تقريباً';note.textContent='مؤشر تقريبي بحسب موقع الكابتن. المسافة مباشرة وليست مسافة الطريق أو وقت الوصول.';
 }
 const oldRender=renderRequest;renderRequest=function(r){oldRender(r);lastRequest={id:requestId,value:r};const key='fazaa.sound.status.'+requestId,previous=sessionStorage.getItem(key);if(previous&&previous!==r.status)play(r.status);sessionStorage.setItem(key,r.status);draw(r);};
 window.addEventListener('fazaa-trip-details',event=>{if(event.detail.id!==requestId)return;lastTrip=event.detail;if(lastRequest?.id===requestId)draw(lastRequest.value);});
 setInterval(()=>{if(lastRequest?.id===requestId&&!document.hidden)draw(lastRequest.value);},15000);
 window.FazaaExperience={play,km};
 // State is injected only by the native shell on this trusted page.
 window.addEventListener('fazaa-update-state',()=>{const value=window.FazaaUpdateState;if(value&&updates.querySelector('small'))updates.querySelector('small').textContent=value;});
})();
