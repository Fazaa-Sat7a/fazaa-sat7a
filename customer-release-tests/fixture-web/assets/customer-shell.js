'use strict';
/* Keep the existing public booking UI until pricing is enabled or this account is explicitly approved. */
(async()=>{
 let commercial=false,booted=false,checkTimer;
 function script(src){return new Promise((resolve,reject)=>{const n=document.createElement('script');n.src=src+'?v=051';n.onload=resolve;n.onerror=()=>reject(Error('تعذّر تحميل واجهة فزعة. أعد تحميل الصفحة.'));document.body.append(n);});}
 async function mode(){await session();const r=await client.rpc('get_fazaa_commercial_catalog',{});if(r.error)throw r.error;return r.data?.enabled===true;}
 async function checkAfterLogin(){
  if(!booted)return;
  if(window.FazaaApp?.authBusy||sending||restoreBusy||loading){checkTimer=setTimeout(checkAfterLogin,500);return;}
  try{if(await mode()!==commercial)location.reload();}catch{/* Keep the working UI; the server continues to enforce quote authorization. */}
 }
 try{
  try{commercial=await mode();}catch{commercial=false;}
  if(commercial){const css=document.createElement('link');css.rel='stylesheet';css.href='assets/commercial.css?v=051';document.head.append(css);}
  await script(commercial?'assets/customer-app-v03.js':'assets/customer-app.js');
  await script('assets/customer-push.js');
  await script('assets/vehicle-categories.js');
  if(commercial)await script('assets/commercial-customer.js');
  await script('assets/customer-polish.js');
  window.FazaaCustomerReady=true;
  booted=true;
  if(requestId)refresh();
  client.auth.onAuthStateChange(event=>{if(['SIGNED_IN','SIGNED_OUT','USER_UPDATED'].includes(event)){clearTimeout(checkTimer);checkTimer=setTimeout(checkAfterLogin,1500);}});
 }catch(e){message(e.message,'error');}
})();
