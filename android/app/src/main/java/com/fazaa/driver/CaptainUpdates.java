package com.fazaa.driver;

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
public final class CaptainUpdates {
    private final Activity activity;
    private final BooleanSupplier canPrompt;
    private final SharedPreferences prefs;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private boolean checking,closed;
    private AlertDialog dialog;
    public CaptainUpdates(Activity activity,BooleanSupplier canPrompt){this.activity=activity;this.canPrompt=canPrompt;prefs=activity.getSharedPreferences("captain_updates",0);}
    public void check(boolean manual){
        if(closed||checking)return;
        long now=System.currentTimeMillis();
        if(!manual&&now-prefs.getLong("checked_at",0)<6*60*60*1000L)return;
        checking=true;if(manual)toast("جاري التحقق من تحديث التطبيق…");
        worker.execute(()->{
            JSONObject result=null;String error=null;HttpURLConnection connection=null;
            try{
                connection=(HttpURLConnection)new URL(UpdatePolicy.MANIFEST).openConnection();connection.setConnectTimeout(10000);connection.setReadTimeout(10000);connection.setUseCaches(false);connection.setRequestProperty("Accept","application/json");
                int status=connection.getResponseCode();if(status!=200)throw new java.io.IOException("HTTP "+status);
                try(InputStream input=connection.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){
                    byte[] bytes=new byte[2048];int count;while((count=input.read(bytes))!=-1){if(out.size()+count>16384)throw new java.io.IOException("Manifest too large");out.write(bytes,0,count);}result=new JSONObject(out.toString("UTF-8"));
                }
            }catch(Exception e){error="تعذّر التحقق حالياً. تأكد من الإنترنت وحاول مجدداً.";}finally{if(connection!=null)connection.disconnect();}
            JSONObject manifest=result;String failure=error;main.post(()->{checking=false;if(closed||activity.isFinishing()||activity.isDestroyed())return;if(failure!=null){if(manual&&canPrompt.getAsBoolean())toast(failure);return;}handle(manifest,manual);});
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
            if(code<=installed){if(manual)toast("تطبيقك محدّث — الإصدار "+info.versionName);return;}
            if(!manual&&prefs.getLong("dismissed_version",0)==code)return;
            if(dialog!=null&&dialog.isShowing())return;
            String notes=manifest.optString("notes","");if(notes.length()>1000)notes=notes.substring(0,1000);
            dialog=new AlertDialog.Builder(activity).setTitle("تحديث جديد لفزعة كابتن")
                .setMessage("الإصدار "+name+" متاح الآن.\n"+notes+"\n\nحمّل التحديث وافتحه ثم اختر تحديث. لا تحذف التطبيق الحالي؛ سيبقى حسابك محفوظاً.")
                .setPositiveButton("تحميل التحديث",(d,w)->{if(!canPrompt.getAsBoolean())return;try{activity.startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(url)));}catch(android.content.ActivityNotFoundException e){toast("يلزم متصفح لفتح رابط التحديث.");}})
                .setNegativeButton("لاحقاً",(d,w)->prefs.edit().putLong("dismissed_version",code).apply()).create();
            dialog.setOnCancelListener(d->prefs.edit().putLong("dismissed_version",code).apply());dialog.show();
        }catch(Exception e){if(manual&&canPrompt.getAsBoolean())toast("تعذّر قراءة معلومات الإصدار. حاول لاحقاً.");}
    }
    public void hideDuringTrip(){if(dialog!=null&&dialog.isShowing())dialog.dismiss();}
    private void toast(String text){Toast.makeText(activity,text,Toast.LENGTH_LONG).show();}
    public void close(){closed=true;worker.shutdownNow();main.removeCallbacksAndMessages(null);if(dialog!=null)dialog.dismiss();}
}
