(function(root){
 'use strict';
 const columns=['make','model','car_type','length_m','width_m','height_m','weight_kg','year_from','year_to','source','enabled'];
 function parse(text){
  text=String(text).replace(/^\uFEFF/,'');if(text.length>1000000)throw Error('الملف أكبر من الحد المسموح.');
  const rows=[];let row=[],cell='',quoted=false,closed=false;
  for(let i=0;i<text.length;i++){const c=text[i];if(closed&&c!==','&&c!=='\n'&&c!=='\r')throw Error('تنسيق علامات الاقتباس غير صحيح.');if(c==='"'){if(quoted&&text[i+1]==='"'){cell+='"';i++;}else if(quoted){quoted=false;closed=true;}else if(cell==='')quoted=true;else throw Error('تنسيق علامات الاقتباس غير صحيح.');}else if(c===','&&!quoted){row.push(cell);cell='';closed=false;}else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&text[i+1]==='\n')i++;row.push(cell);if(row.some(x=>x.trim()))rows.push(row);row=[];cell='';closed=false;}else cell+=c;}
  if(quoted)throw Error('علامة اقتباس غير مغلقة.');row.push(cell);if(row.some(x=>x.trim()))rows.push(row);
  if(rows.length<2||rows.length>501)throw Error('يجب أن يحتوي الملف من 1 إلى 500 موديل.');
  const header=rows.shift().map(x=>x.trim());if(header.length!==columns.length||new Set(header).size!==header.length||columns.some(k=>!header.includes(k)))throw Error('استخدم عناوين أعمدة القالب دون تغيير.');
  return rows.map((values,index)=>{
   if(values.length!==header.length)throw Error('عدد الأعمدة غير صحيح في السطر '+(index+2));
   const item={};header.forEach((k,i)=>{item[k]=values[i].trim();});
   for(const k of ['make','model','source'])if(!item[k])throw Error('حقل '+k+' مطلوب في السطر '+(index+2));
   if(!['small','suv','truck'].includes(item.car_type))throw Error('car_type يجب أن يكون small أو suv أو truck.');
   for(const k of ['length_m','width_m','height_m','weight_kg','year_from','year_to']){if(!/^\d+(\.\d+)?$/.test(item[k]))throw Error('استخدم أرقاماً إنجليزية ونقطة عشرية في '+k);item[k]=Number(item[k]);if(!Number.isFinite(item[k])||item[k]<=0)throw Error('القيمة غير صحيحة في '+k);}
   if(!Number.isInteger(item.year_from)||!Number.isInteger(item.year_to)||item.year_from<1900||item.year_to>2200||item.year_from>item.year_to)throw Error('راجع سنوات الصنع.');
   if(!['','0','1','true','false'].includes(item.enabled.toLowerCase()))throw Error('enabled يجب أن يكون true أو false أو 1 أو 0.');
   item.enabled=['1','true'].includes(item.enabled.toLowerCase());return item;
  });
 }
 const api={parse,columns};if(typeof module==='object'&&module.exports)module.exports=api;else root.FazaaVehicleCSV=api;
})(typeof window==='undefined'?globalThis:window);
