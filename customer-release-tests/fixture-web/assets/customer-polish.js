'use strict';
(()=>{
 const E=id=>document.getElementById(id);
 function node(tag,cls='',text){const n=document.createElement(tag);n.className=cls;if(text!==undefined)n.textContent=text;return n;}
 function button(text,action,cls='secondary'){const b=node('button',cls,text);b.type='button';b.addEventListener('click',action);return b;}
 const history=E('view-orders'),account=E('view-account');
 if(history&&account){history.classList.remove('app-view');if(history.parentElement!==account)account.append(history);E('nav-orders')?.remove();document.querySelector('#account-profile [data-go="orders"]')?.remove();}
 document.querySelector('.bottom-nav')?.classList.add('customer-nav-three');
 const future=[['الكراجات المعتمدة','اختيار كراج موثوق لخدمة مركبتك.','▤'],['تقييم الكراجات','شارك تجربتك وساعد غيرك على الاختيار.','☆'],['الجولة المرنة','خدمة لأكثر من كراج عندما لم تُحسم الوجهة بعد.','↝']];
 function comingSection(compact){const section=node('section','future-section');section.append(node('h2','',compact?'فزعة عم تكبر معك':'خدمات قيد التطوير'));const grid=node('div','future-grid');for(const [name,description,mark] of future){const card=node('button','future-card');card.type='button';card.disabled=true;card.setAttribute('aria-disabled','true');card.append(node('span','future-symbol',mark),node('span','future-badge','قيد التطوير'),node('strong','',name),node('small','',description));grid.append(card);}section.append(grid);return section;}
 E('view-home')?.append(comingSection(true));E('view-services')?.append(comingSection(false));
 const dialog=node('dialog','vehicle-suggestion-dialog');dialog.id='vehicle-suggestion-dialog';
 const heading=node('div','suggestion-heading');heading.append(node('h2','','ما لقيت مركبتك؟'),button('×',()=>dialog.close(),'dialog-close'));
 dialog.append(heading,node('p','muted','اقترح الماركة والموديل لنراجعهما ونحدّد السطحة المناسبة قبل إتاحتهما للحجز.'));
 const form=node('form'),fields={};for(const [id,label,placeholder] of [['make','الماركة','مثلاً: اسم الشركة'],['model','الموديل','اسم الموديل أو الفئة'],['year','سنة الصنع — اختياري','مثلاً 2020']]){const l=node('label','',label),input=node('input');input.id='suggestion-'+id;l.htmlFor=input.id;input.placeholder=placeholder;input.required=id!=='year';input.maxLength=id==='year'?4:80;if(id==='year'){input.type='number';input.inputMode='numeric';input.min='1900';input.max=String(new Date().getFullYear()+2);}fields[id]=input;form.append(l,input);}
 const feedback=node('p','suggestion-feedback');feedback.setAttribute('role','status');
 const send=node('button','primary wide','إرسال الاقتراح');send.type='submit';
 form.append(feedback,send,button('الذهاب إلى حسابي',()=>{dialog.close();window.FazaaApp?.navigate('account');},'text-button'));dialog.append(form);document.body.append(dialog);
 function openSuggestion(){feedback.textContent='';dialog.showModal();fields.make.focus();}
 form.addEventListener('submit',async event=>{event.preventDefault();if(send.disabled)return;send.disabled=true;feedback.textContent='جاري إرسال الاقتراح…';try{const s=await session();if(!s.user?.email||s.user.is_anonymous||!s.user.email_confirmed_at){feedback.textContent='سجّل الدخول بحسابك المؤكد من حسابي قبل إرسال الاقتراح.';return;}const year=fields.year.value?Number(fields.year.value):null;await rpc('submit_fazaa_vehicle_suggestion',{p_make:fields.make.value.trim(),p_model:fields.model.value.trim(),p_year:year});feedback.textContent='وصل اقتراحك للإدارة. يظهر الموديل للحجز بعد اعتماد مواصفاته.';fields.make.value=fields.model.value=fields.year.value='';}catch(error){const m=String(error?.message||error);feedback.textContent=m.includes('SUGGESTION_RATE_LIMIT')?'وصلت للحد اليومي للاقتراحات. حاول غداً.':m.includes('SIGN_IN_REQUIRED')?'سجّل الدخول بحساب مؤكد أولاً.':m.includes('INVALID_VEHICLE')?'راجع اسم الماركة والموديل وسنة الصنع.':'تعذّر إرسال الاقتراح حالياً. حاول مجدداً.';}finally{send.disabled=false;}});
 account?.append(button('اقترح إضافة موديل مركبة',openSuggestion,'menu-link'));
 if(account&&new URLSearchParams(location.search).has('app')&&!document.querySelector('.native-notification-link')){const link=node('a','native-notification-link','إعدادات إشعارات الطلب');link.href='./?app=1&native=notifications';account.append(link);}
 const select=E('vehicle-model');
 if(select){
  const search=node('input');search.id='vehicle-search';search.type='search';search.placeholder='ابحث بالماركة أو الموديل…';search.setAttribute('aria-label','بحث في المركبات المعتمدة');select.before(search);
  const hint=node('p','vehicle-search-hint');select.after(hint,button('لم أجد مركبتي',openSuggestion,'vehicle-missing'));
  const normalize=s=>String(s).normalize('NFKC').toLocaleLowerCase().replace(/[أإآ]/g,'ا').replace(/ى/g,'ي').trim();
  function filter(){const query=normalize(search.value);let count=0;for(const option of select.options){const match=!option.value||normalize(option.textContent).includes(query);option.hidden=!match;if(option.value&&match)count++;}const selected=select.selectedOptions[0];if(selected?.value&&selected.hidden){select.value='';select.dispatchEvent(new Event('change',{bubbles:true}));}hint.textContent=query?(count?'نتائج البحث: '+count:'لا يوجد موديل معتمد مطابق. يمكنك اقتراح إضافته.'):'الموديلات الظاهرة معتمدة في فزعة. نضيف المزيد بعد مراجعة المقاسات.';}
  search.addEventListener('input',filter);new MutationObserver(filter).observe(select,{childList:true});filter();
 }else E('car-options')?.after(button('اقترح إضافة موديل مركبتك',openSuggestion,'vehicle-missing'));
})();
