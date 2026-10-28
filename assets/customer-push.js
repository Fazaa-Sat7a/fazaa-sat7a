'use strict';
/* Optional Android push integration. Browser sessions keep their existing behavior. */
(()=>{
 const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
 let lastBinding='',syncing=null,dirty=false,scheduled=null,signingOut=false,opening=false;
 let card=null,caption=null;
 function device(){const d=window.FazaaPushDevice;return d&&UUID.test(d.installation_id)&&typeof d.token==='string'?d:null;}
 function status(text){if(!device())return;if(!card){card=document.createElement('section');card.className='surface push-card';const title=document.createElement('h2');title.textContent='إشعارات الطلب';caption=document.createElement('p');caption.className='muted';card.append(title,caption);document.getElementById('view-account').append(card);}caption.textContent=text;card.hidden=!text;}
 function schedule(delay=100){clearTimeout(scheduled);scheduled=setTimeout(()=>sync().catch(()=>{}),delay);}
 async function sync(){
  if(syncing){dirty=true;return syncing;}
  if(!client||!device()||signingOut)return;
  if(window.FazaaApp?.authBusy){schedule(500);return;}
  syncing=(async()=>{
   do {
    dirty=false;const d=device();if(!d||signingOut)return;
    const {data,error}=await client.auth.getSession();if(error)throw error;
    const session=data.session;if(!session){status('جاري تهيئة إشعارات الطلب…');return;}
    const key=JSON.stringify([session.user.id,d.installation_id,d.token,d.permission]);
    if(!d.token){status('جاري تجهيز الإشعارات. تحقّق من الإنترنت وأعد فتح التطبيق إذا استمر الانتظار.');return;}
    if(key===lastBinding)return;
    const result=await client.rpc('register_customer_push_device',{p_device_id:d.installation_id,p_token:d.token,p_enabled:d.permission===true});
    if(result.error)throw result.error;
    const current=await client.auth.getSession();
    if(current.data.session?.user.id!==session.user.id){dirty=true;continue;}
    lastBinding=key;
    status(d.permission?'':'الإشعارات متوقفة. افتح الإعدادات ← إشعارات طلبك لتشغيلها.');
   }while(dirty&&!signingOut);
  })();
  try{await syncing;}catch(e){lastBinding='';status('تعذّر ربط إشعارات الجهاز. افتح التطبيق عند عودة الإنترنت للمحاولة مجدداً.');schedule(30000);throw e;}
  finally{syncing=null;}
 }
 window.FazaaPush={sync};
 window.addEventListener('fazaa-push-device',()=>{dirty=true;schedule();});
 window.addEventListener('online',()=>schedule());
 document.addEventListener('visibilitychange',()=>{if(!document.hidden){lastBinding='';schedule();openNotification();}});
 if(client){
  client.auth.onAuthStateChange(()=>{lastBinding='';schedule();});
  const originalSignOut=client.auth.signOut.bind(client.auth);
  client.auth.signOut=async function(...args){
   if(!device())return originalSignOut(...args);
   signingOut=true;clearTimeout(scheduled);
   try{
    if(syncing)await syncing.catch(()=>{});
    const d=device(),current=await client.auth.getSession();
    if(d.token&&current.data.session){const result=await client.rpc('unregister_customer_push_device',{p_device_id:d.installation_id,p_token:d.token});if(result.error)throw Error('تعذّر إيقاف إشعارات الحساب على الجهاز. تحقّق من الإنترنت ثم حاول تسجيل الخروج مجدداً.');}
    lastBinding='';return await originalSignOut(...args);
   }finally{signingOut=false;schedule();}
  };
 }
 async function openNotification(){
  if(opening||!UUID.test(window.FazaaPushOpenRequest||''))return;
  if(!window.FazaaApp?.openRequest||window.FazaaApp.authBusy){setTimeout(openNotification,500);return;}
  opening=true;const id=window.FazaaPushOpenRequest;
  try{
   const ok=await window.FazaaApp.openRequest(id);
   if(ok===null){setTimeout(openNotification,500);return;}
   if(window.FazaaPushOpenRequest===id)delete window.FazaaPushOpenRequest;
   if(ok===false){window.FazaaApp.navigate('account');message('الطلب غير متاح لهذه الجلسة. سجّل الدخول بالحساب الذي أرسل الطلب، ثم اضغط الإشعار مجدداً.','error');}
  }finally{opening=false;}
 }
 window.addEventListener('fazaa-push-open',openNotification);
 schedule();openNotification();
 // Renew the device lease while the application is in use; no background polling service.
 setInterval(()=>{if(!document.hidden){lastBinding='';schedule();}},30*60*1000);
})();
