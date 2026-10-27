'use strict';
(()=>{
 const E=id=>document.getElementById(id);
 function node(tag,cls='',text){const n=document.createElement(tag);n.className=cls;if(text!==undefined)n.textContent=text;return n;}
 function button(text,action,cls='secondary'){const b=node('button',cls,text);b.type='button';b.addEventListener('click',action);return b;}
 const history=E('view-orders'),account=E('view-account');
 if(history&&account){history.classList.remove('app-view');if(history.parentElement!==account)account.append(history);E('nav-orders')?.remove();document.querySelector('#account-profile [data-go="orders"]')?.remove();}
 // Keep current-request recovery available independently of registered history.
 if(account&&E('restore-section'))account.append(E('restore-section'));
 document.querySelector('.bottom-nav')?.classList.add('customer-nav-three');
 const future=[['الكراجات المعتمدة','اختيار كراج موثوق لخدمة مركبتك.','▤'],['تقييم الكراجات','شارك تجربتك وساعد غيرك على الاختيار.','☆'],['الجولة المرنة','خدمة لأكثر من كراج عندما لم تُحسم الوجهة بعد.','↝']];
 function comingSection(compact){const section=node('section','future-section');section.append(node('h2','',compact?'فزعة عم تكبر معك':'خدمات قيد التطوير'));const grid=node('div','future-grid');for(const [name,description,mark] of future){const card=node('button','future-card');card.type='button';card.disabled=true;card.setAttribute('aria-disabled','true');card.append(node('span','future-symbol',mark),node('span','future-badge','قيد التطوير'),node('strong','',name),node('small','',description));grid.append(card);}section.append(grid);return section;}
 E('view-home')?.append(comingSection(true));E('view-services')?.append(comingSection(false));
 if(account&&new URLSearchParams(location.search).has('app')&&!document.querySelector('.native-notification-link')){const link=node('a','native-notification-link','إعدادات إشعارات الطلب');link.href='./?app=1&native=notifications';account.append(link);}
 const arabic=(navigator.language||'ar').toLowerCase().startsWith('ar');
 for(const img of document.querySelectorAll('.brand-mark img,.hero-art'))img.src='assets/brand/customer-'+(arabic?'ar':'en')+'.png';
})();
