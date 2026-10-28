package com.fazaa.admin;

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
public final class AdminUpdates {
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
    public AdminUpdates(Activity activity,BooleanSupplier canPrompt){this.activity=activity;this.canPrompt=canPrompt;prefs=activity.getSharedPreferences("admin_updates",0);}
    public void check(boolean manual){
        if(closed)return;
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
            if(code<=installed){if(manual)resultDialog("تطبيقك محدّث", "أنت تستخدم أحدث إصدار متاح لك.\nالإصدار المثبّت: "+info.versionName+"\nرقم البناء: "+installed);return;}
            if(!manual&&prefs.getLong("dismissed_version",0)==code)return;
            if(dialog!=null&&dialog.isShowing())return;
            dialog=new AlertDialog.Builder(activity).setTitle("تحديث جديد لفزعة إدارة")
                .setMessage("الإصدار "+name+" متاح الآن.\nهل تريد تحميل التحديث؟")
                .setPositiveButton("تحميل التحديث",(d,w)->{if(!canPrompt.getAsBoolean())return;try{activity.startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(url)));}catch(android.content.ActivityNotFoundException e){toast("يلزم متصفح لفتح رابط التحديث.");}})
                .setNegativeButton("لاحقاً",(d,w)->prefs.edit().putLong("dismissed_version",code).apply()).create();
            dialog.setOnCancelListener(d->prefs.edit().putLong("dismissed_version",code).apply());dialog.show();
        }catch(Exception e){if(manual)resultDialog("تعذّر التحقق","تعذّر قراءة معلومات الإصدار. حاول لاحقاً.");}
    }
    private void showProgress(){
        if(!canPrompt.getAsBoolean()||activity.isFinishing()||activity.isDestroyed())return;
        if(progress!=null&&progress.isShowing())return;
        progress=new AlertDialog.Builder(activity).setTitle("تحديث تطبيق الإدارة")
            .setMessage("جاري التحقق من الإصدار المتاح…\nقد يستغرق ذلك بضع ثوانٍ.")
            .setNegativeButton("إخفاء",(d,w)->{}).create();progress.show();
    }
    private void dismissProgress(){if(progress!=null){progress.dismiss();progress=null;}}
    private void resultDialog(String title,String message){
        if(!canPrompt.getAsBoolean()||activity.isFinishing()||activity.isDestroyed())return;
        if(dialog!=null)dialog.dismiss();
        dialog=new AlertDialog.Builder(activity).setTitle(title).setMessage(message).setPositiveButton("حسناً",(d,w)->{}).create();dialog.show();
    }
    public void hideDuringTrip(){dismissProgress();if(dialog!=null&&dialog.isShowing())dialog.dismiss();}
    private void toast(String text){Toast.makeText(activity,text,Toast.LENGTH_LONG).show();}
    public void close(){closed=true;dismissProgress();worker.shutdownNow();main.removeCallbacksAndMessages(null);if(dialog!=null)dialog.dismiss();}
}
