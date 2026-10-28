package com.fazaa.customer;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.widget.Toast;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.BooleanSupplier;

/** Foreground-only update notification; never interrupts an active job or installs silently. */
public final class CustomerUpdates {
    private final Activity activity;
    private final BooleanSupplier canPrompt;
    private final SharedPreferences prefs;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private boolean checking,closed,manualRequested;
    private int requestId;
    private Runnable deadline;
    private AlertDialog progress;
    private AlertDialog dialog;
    public CustomerUpdates(Activity activity,BooleanSupplier canPrompt){this.activity=activity;this.canPrompt=canPrompt;prefs=activity.getSharedPreferences("customer_updates",0);}
    public void check(boolean manual){
        if(closed)return;
        if(prefs.getLong("download_id",-1)>0){resumeDownload(manual);return;}
        if(manual){manualRequested=true;showProgress();}
        if(checking)return;
        long now=System.currentTimeMillis();
        if(!manual&&now-prefs.getLong("checked_at",0)<6*60*60*1000L)return;
        checking=true;
        final int id=++requestId;
        deadline=()->{
            if(closed||id!=requestId||!checking)return;
            requestId++;checking=false;
            boolean requested=manualRequested;manualRequested=false;dismissProgress();
            if(requested)resultDialog("تعذّر التحقق", "لم يصل رد خلال 25 ثانية. تأكد من الإنترنت وحاول مجدداً. لم نتمكن من معرفة إن كان تطبيقك أحدث إصدار.");
        };
        main.postDelayed(deadline,25000);
        worker.execute(()->{
            JSONObject result=null;String error=null;HttpURLConnection connection=null;
            try{
                connection=(HttpURLConnection)new URL(UpdatePolicy.MANIFEST).openConnection();connection.setConnectTimeout(10000);connection.setReadTimeout(10000);connection.setUseCaches(false);connection.setRequestProperty("Accept","application/json");
                int status=connection.getResponseCode();if(status!=200)throw new java.io.IOException("HTTP "+status);
                try(InputStream input=connection.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){
                    byte[] bytes=new byte[2048];int count;while((count=input.read(bytes))!=-1){if(out.size()+count>16384)throw new java.io.IOException("Manifest too large");out.write(bytes,0,count);}result=new JSONObject(out.toString("UTF-8"));
                }
            }catch(Exception e){error="تعذّر التحقق حالياً. تأكد من الإنترنت وحاول مجدداً.";}finally{if(connection!=null)connection.disconnect();}
            JSONObject manifest=result;String failure=error;main.post(()->{if(closed||id!=requestId)return;
                checking=false;main.removeCallbacks(deadline);
                boolean requested=manualRequested;manualRequested=false;dismissProgress();
                if(activity.isFinishing()||activity.isDestroyed())return;
                if(failure!=null){if(requested)resultDialog("تعذّر التحقق",failure);return;}handle(manifest,requested);});
        });
    }
    private void handle(JSONObject manifest,boolean manual){
        try{
            PackageInfo info=activity.getPackageManager().getPackageInfo(activity.getPackageName(),0);
            long installed=Build.VERSION.SDK_INT>=28?info.getLongVersionCode():info.versionCode;
            long code=manifest.getLong("versionCode");String name=manifest.getString("versionName"),url=manifest.getString("apkUrl"),pkg=manifest.getString("packageId");
            if(!UpdatePolicy.PACKAGE.equals(pkg)||code<=0||name.length()>40)throw new IllegalArgumentException("Invalid release");
            if(code>installed&&!UpdatePolicy.accepts(activity.getPackageName(),installed,pkg,code,url))throw new IllegalArgumentException("Invalid update target");
            prefs.edit().putLong("checked_at",System.currentTimeMillis()).apply();
            if(!canPrompt.getAsBoolean())return;
            if(code<=installed){state("تطبيقك محدّث · "+info.versionName);if(manual)resultDialog("تطبيقك محدّث", "أنت تستخدم أحدث إصدار متاح لك.\nالإصدار المثبّت: "+info.versionName+"\nرقم البناء: "+installed);return;}
            if(!manual&&prefs.getLong("dismissed_version",0)==code)return;
            if(dialog!=null&&dialog.isShowing())return;
            dialog=new AlertDialog.Builder(activity).setTitle("تحديث جديد لفزعة")
                .setMessage("الإصدار "+name+" متاح الآن.\nهل تريد تحميل التحديث؟")
                .setPositiveButton("تحميل التحديث",(d,w)->{if(canPrompt.getAsBoolean())download(url,code,manifest.optString("sha256"));})
                .setNegativeButton("لاحقاً",(d,w)->prefs.edit().putLong("dismissed_version",code).apply()).create();
            dialog.setOnCancelListener(d->prefs.edit().putLong("dismissed_version",code).apply());dialog.show();
        }catch(Exception e){if(manual)resultDialog("تعذّر التحقق","تعذّر قراءة معلومات الإصدار. حاول لاحقاً.");}
    }
    private void state(String text){if(activity instanceof ClientActivity)((ClientActivity)activity).updateState(text);}
    private boolean verifying;
    private Runnable downloadPoll;
    private boolean promptDownload;
    private void download(String url,long code,String sha){
        if(!sha.matches("[a-fA-F0-9]{64}")){resultDialog("تعذّر التنزيل","معلومات التحديث غير مكتملة. حاول لاحقاً.");return;}
        try{
            android.app.DownloadManager manager=(android.app.DownloadManager)activity.getSystemService(Activity.DOWNLOAD_SERVICE);
            java.io.File target=new java.io.File(activity.getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS),"fazaa-customer-"+code+".apk");
            if(target.exists()&&!target.delete())throw new java.io.IOException();
            android.app.DownloadManager.Request request=new android.app.DownloadManager.Request(Uri.parse(url)).setTitle("تحديث فزعة").setDescription("جاري تنزيل الإصدار الجديد").setMimeType("application/vnd.android.package-archive").setNotificationVisibility(android.app.DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED).setDestinationInExternalFilesDir(activity,android.os.Environment.DIRECTORY_DOWNLOADS,target.getName());
            long id=manager.enqueue(request);prefs.edit().putLong("download_id",id).putLong("download_code",code).putString("download_sha",sha).putString("download_path",target.getAbsolutePath()).apply();
            state("بدأ تنزيل التحديث…");toast("بدأ التنزيل. يمكنك متابعة تقدّمه من الإشعارات.");resumeDownload(true);
        }catch(Exception e){resultDialog("تعذّر بدء التنزيل","تحقّق من مساحة الهاتف والاتصال ثم حاول مجدداً.");}
    }
    public void resumeDownload(boolean prompt){
        if(closed||!canPrompt.getAsBoolean())return;promptDownload|=prompt;
        if(downloadPoll!=null)main.removeCallbacks(downloadPoll);
        long id=prefs.getLong("download_id",-1);if(id<0||verifying)return;
        try{PackageInfo info=activity.getPackageManager().getPackageInfo(activity.getPackageName(),0);long current=Build.VERSION.SDK_INT>=28?info.getLongVersionCode():info.versionCode;
            if(current>=prefs.getLong("download_code",0)){((android.app.DownloadManager)activity.getSystemService(Activity.DOWNLOAD_SERVICE)).remove(id);prefs.edit().remove("download_id").apply();state("تطبيقك محدّث · "+info.versionName);return;}
        }catch(Exception ignored){}
        android.app.DownloadManager manager=(android.app.DownloadManager)activity.getSystemService(Activity.DOWNLOAD_SERVICE);
        try(android.database.Cursor cursor=manager.query(new android.app.DownloadManager.Query().setFilterById(id))){
            if(cursor==null||!cursor.moveToFirst()){prefs.edit().remove("download_id").apply();state("أعد التحقق لتنزيل التحديث");return;}
            int status=cursor.getInt(cursor.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_STATUS));
            if(status==android.app.DownloadManager.STATUS_FAILED){manager.remove(id);prefs.edit().remove("download_id").apply();state("تعذّر التنزيل — حاول مجدداً");resultDialog("تعذّر التنزيل","تحقّق من الإنترنت ومساحة الهاتف، ثم اضغط التحقق من التحديثات.");return;}
            if(status==android.app.DownloadManager.STATUS_SUCCESSFUL){verifyDownload(id,manager);return;}
            long total=cursor.getLong(cursor.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),done=cursor.getLong(cursor.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR));
            state(status==android.app.DownloadManager.STATUS_PAUSED?"التنزيل متوقف مؤقتاً؛ سيُستأنف عند توفر الاتصال":total>0?"جاري التنزيل: "+(done*100/total)+"%":"جاري تنزيل التحديث…");
        }catch(Exception e){state("يمكن متابعة التنزيل من إشعارات الهاتف");}
        downloadPoll=()->resumeDownload(false);main.postDelayed(downloadPoll,1500);
    }
    private void verifyDownload(long id,android.app.DownloadManager manager){
        verifying=true;state("جاري التحقق من ملف التحديث…");
        worker.execute(()->{
            boolean valid=false;long code=prefs.getLong("download_code",0);
            try{
                String path=prefs.getString("download_path","");java.security.MessageDigest digest=java.security.MessageDigest.getInstance("SHA-256");
                try(java.io.InputStream input=new java.io.FileInputStream(path)){byte[] bytes=new byte[32768];int count;while((count=input.read(bytes))!=-1)digest.update(bytes,0,count);}
                StringBuilder hex=new StringBuilder();for(byte b:digest.digest())hex.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
                android.content.pm.PackageManager pm=activity.getPackageManager();
                PackageInfo apk=pm.getPackageArchiveInfo(path,android.content.pm.PackageManager.GET_SIGNATURES),installed=pm.getPackageInfo(activity.getPackageName(),android.content.pm.PackageManager.GET_SIGNATURES);
                long apkCode=apk==null?0:Build.VERSION.SDK_INT>=28?apk.getLongVersionCode():apk.versionCode;
                long current=Build.VERSION.SDK_INT>=28?installed.getLongVersionCode():installed.versionCode;
                valid=apk!=null&&UpdatePolicy.PACKAGE.equals(apk.packageName)&&apkCode==code&&apkCode>current&&hex.toString().equalsIgnoreCase(prefs.getString("download_sha",""))&&apk.signatures!=null&&installed.signatures!=null&&java.util.Arrays.equals(apk.signatures,installed.signatures);
            }catch(Exception ignored){}
            final boolean checked=valid;main.post(()->{verifying=false;if(closed)return;if(!checked){manager.remove(id);prefs.edit().remove("download_id").apply();state("تعذّر التحقق من التحديث");resultDialog("لم يكتمل التحديث","الملف غير صالح للتحديث أو أصبح التطبيق محدّثاً. أعد التحقق من الإصدار.");return;}state("التحديث جاهز — اضغط لتثبيته");if(!canPrompt.getAsBoolean())return;
                if(dialog!=null&&dialog.isShowing())return;
                dialog=new AlertDialog.Builder(activity).setTitle("التحديث جاهز").setMessage("اكتمل التنزيل. ثبّت التحديث مع الاحتفاظ بحسابك وطلباتك.").setPositiveButton("تثبيت التحديث",(d,w)->install(id,manager)).setNegativeButton("لاحقاً",null).create();dialog.show();
            });
        });
    }
    private void install(long id,android.app.DownloadManager manager){
        if(!activity.getPackageManager().canRequestPackageInstalls()){
            new AlertDialog.Builder(activity).setTitle("السماح بتحديث فزعة").setMessage("اسمح لفزعة بتثبيت هذا التحديث، ثم ارجع إلى التطبيق.").setPositiveButton("فتح الإعدادات",(d,w)->activity.startActivity(new Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+activity.getPackageName())))).setNegativeButton("لاحقاً",null).show();return;
        }
        try{Uri uri=manager.getUriForDownloadedFile(id);if(uri==null)throw new IllegalStateException();activity.startActivity(new Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION));}catch(Exception e){resultDialog("تعذّر فتح التحديث","أعد المحاولة من زر تحديث التطبيق.");}
    }
    private void showProgress(){
        if(!canPrompt.getAsBoolean()||activity.isFinishing()||activity.isDestroyed())return;
        if(progress!=null&&progress.isShowing())return;
        progress=new AlertDialog.Builder(activity).setTitle("تحديث تطبيق فزعة")
            .setMessage("جاري التحقق من الإصدار المتاح…\nقد يستغرق ذلك بضع ثوانٍ.")
            .setNegativeButton("إخفاء",(d,w)->{}).create();progress.show();
    }
    private void dismissProgress(){if(progress!=null){progress.dismiss();progress=null;}}
    private void resultDialog(String title,String message){
        if(!canPrompt.getAsBoolean()||activity.isFinishing()||activity.isDestroyed())return;
        if(dialog!=null)dialog.dismiss();
        dialog=new AlertDialog.Builder(activity).setTitle(title).setMessage(message).setPositiveButton("حسناً",(d,w)->{}).create();dialog.show();
    }
    public void hideDuringTrip(){if(downloadPoll!=null)main.removeCallbacks(downloadPoll);dismissProgress();if(dialog!=null&&dialog.isShowing())dialog.dismiss();}
    private void toast(String text){Toast.makeText(activity,text,Toast.LENGTH_LONG).show();}
    public void close(){closed=true;dismissProgress();worker.shutdownNow();main.removeCallbacksAndMessages(null);if(dialog!=null)dialog.dismiss();}
}
