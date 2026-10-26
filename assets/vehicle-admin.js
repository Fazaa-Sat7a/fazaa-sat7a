'use strict';
(()=>{
 const E=id=>document.getElementById(id);
 function node(tag,cls='',text){const n=document.createElement(tag);n.className=cls;if(text!==undefined)n.textContent=text;return n;}
 function button(text,action){const b=node('button','secondary',text);b.type='button';b.addEventListener('click',action);return b;}
 if(!E('dashboard')||!document.querySelector('.tabs'))return;
 const tab=button('اقتراحات ودليل المركبات',()=>{if(!authorized)return;for(const id of ['requests','drivers','ratings','commercial']){const p=E('panel-'+id);if(p)p.hidden=true;}panel.hidden=false;document.querySelector('.pagination').hidden=true;load();});document.querySelector('.tabs').append(tab);
 const panel=node('section','card');panel.id='panel-vehicle-directory';panel.hidden=true;E('dashboard').append(panel);
 for(const other of document.querySelectorAll('.tabs button'))if(other!==tab)other.addEventListener('click',()=>{panel.hidden=true;});
 if(client)client.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT'){panel.hidden=true;panel.replaceChildren();}});
 async function call(name,args={}){const result=await client.rpc(name,args);if(result.error)throw result.error;return result.data;}
 E('refresh').addEventListener('click',()=>{if(!panel.hidden)load();});
 let serial=0;
 async function load(){const version=++serial;panel.replaceChildren(node('p','','جاري تحميل اقتراحات المركبات…'));try{const rows=await call('admin_get_fazaa_vehicle_suggestions');if(version!==serial||!authorized)return;panel.replaceChildren(node('h2','','اقتراحات العملاء واستيراد المركبات'));const box=node('div','commercial-box');box.append(node('h3','','استيراد قائمة موديلات ومقاسات معتمدة'),node('p','commercial-muted','CSV بترميز UTF-8، حتى 500 موديل في الدفعة. كل صف يحتاج مرجع مواصفات في source. يُحفظ الملف كاملاً أو يُرفض كاملاً عند وجود خطأ. لا تُقدّر المقاسات اعتماداً على اسم الموديل.'));
 const file=node('input');file.type='file';file.accept='.csv,text/csv';file.setAttribute('aria-label','ملف موديلات المركبات المعتمدة');const confirmLabel=node('label','inline-check'),checked=node('input');checked.type='checkbox';checked.style.width='auto';confirmLabel.append(checked,document.createTextNode('راجعت المقاسات والمراجع وحالة التفعيل لكل موديل.'));
 const message=node('p','commercial-form-error');message.setAttribute('role','status');
 const upload=button('استيراد الملف',async()=>{if(!file.files?.[0]||!checked.checked){message.textContent='اختر الملف وأكد مراجعة مواصفاته أولاً.';return;}upload.disabled=true;try{const items=window.FazaaVehicleCSV.parse(await file.files[0].text());const count=await call('admin_import_fazaa_vehicle_models',{p_rows:items});message.textContent='تم حفظ '+count+' موديل. راجع القائمة من التعرفة والأسطول والعمولات.';file.value='';checked.checked=false;}catch(e){message.textContent=String(e.message||e);}finally{upload.disabled=false;}});
 box.append(file,confirmLabel,upload,message);panel.append(box,node('h3','','اقتراحات العملاء'));
 if(!rows.length)panel.append(node('p','commercial-muted','لا توجد اقتراحات بعد.'));
 for(const row of rows){const card=node('div','commercial-box');card.append(node('h3','',row.make+' — '+row.model+(row.model_year?' · '+row.model_year:'')),node('p','commercial-muted',row.email+' · '+new Date(row.created_at).toLocaleString('ar-SY')),node('p','commercial-muted','الحالة: '+({pending:'بانتظار المراجعة',reviewed:'تمت المراجعة',rejected:'مرفوض'}[row.status]||row.status)));
 if(row.status==='pending'){const hint=node('p','commercial-muted','أضف الموديل ومقاساته من قسم كتالوج المركبات المعتمدة أولاً؛ مراجعة الاقتراح وحدها لا تجعله متاحاً للحجز.');card.append(hint);for(const [label,status] of [['تمت المراجعة','reviewed'],['رفض الاقتراح','rejected']])card.append(button(label,async()=>{try{await call('admin_review_fazaa_vehicle_suggestion',{p_id:row.id,p_status:status});await load();}catch(e){hint.textContent=String(e.message||e);}}));}panel.append(card);}
 }catch(e){if(version===serial)panel.replaceChildren(node('p','commercial-form-error','تعذّر تحميل الدليل. '+String(e.message||e)));}}
})();
