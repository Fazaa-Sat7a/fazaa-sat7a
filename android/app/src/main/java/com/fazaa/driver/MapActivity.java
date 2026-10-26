package com.fazaa.driver;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.location.Location;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.View;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import org.json.JSONArray;
import org.json.JSONObject;

/** The native session owner fetches routes; the read-only map receives geometry only. */
public final class MapActivity extends Activity {
    private static final String ASSET="file:///android_asset/map.html";
    private final Handler handler=new Handler(Looper.getMainLooper());
    private DriverApp app;
    private WebView web;
    private TextView status;
    private Button refresh;
    private JSONObject route;
    private boolean loaded, destroyed, fetching;
    private int generation;
    private final Runnable update=new Runnable(){
        @Override public void run(){paint();handler.postDelayed(this,5000);}
    };

    @Override public void onCreate(Bundle saved){
        super.onCreate(saved);app=(DriverApp)getApplication();
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(Color.rgb(247,246,242));root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        Button back=new Button(this);back.setText("العودة للطلبات");back.setOnClickListener(v->finish());root.addView(back);
        TextView title=new TextView(this);title.setText(DriverDisplay.text(getIntent().getStringExtra("routeTitle"),"خريطة العميل والسائق"));title.setTextSize(21);title.setTextColor(Color.rgb(31,41,51));title.setPadding(20,12,20,8);root.addView(title);
        TextView caption=new TextView(this);caption.setText(isOverview()?(getIntent().getBooleanExtra("hasDeliveries",false)?"الأصفر: موقعك · الأزرق: العميل · الأخضر: وجهات التوصيل بالترتيب.":"الأصفر: موقعك · الأزرق: العميل — لا توجد وجهة توصيل محفوظة في هذا الطلب."):"الأصفر: موقعك · الأزرق: الموقع المقصود · المسار تقديري ويحتاج إنترنت.");caption.setPadding(20,4,20,8);root.addView(caption);
        status=new TextView(this);status.setText(isOverview()?(getIntent().getBooleanExtra("hasDeliveries",false)?"يشمل الوصول إلى العميل ثم التوصيل. الأجرة المعروضة ثابتة.":"يعرض هذا الطلب الطريق إلى العميل فقط."):"للتوجيه أثناء القيادة، اضغط بدء الملاحة عبر OsmAnd.");status.setPadding(20,4,20,8);root.addView(status);
        refresh=new Button(this);refresh.setText(isOverview()?"تحديث عرض الرحلة":"تحديث المسار من موقعي");refresh.setVisibility(hasRoute()?View.VISIBLE:View.GONE);refresh.setOnClickListener(v->loadRoute());root.addView(refresh);
        Button navigation=new Button(this);navigation.setText("بدء الملاحة عبر OsmAnd");navigation.setTextColor(Color.rgb(31,41,51));navigation.setBackgroundTintList(android.content.res.ColorStateList.valueOf(Color.rgb(255,180,0)));navigation.setVisibility(hasRoute()&&!isOverview()?View.VISIBLE:View.GONE);navigation.setOnClickListener(v->openOsmAnd());root.addView(navigation);
        web=new WebView(this);WebSettings settings=web.getSettings();settings.setUserAgentString(settings.getUserAgentString()+" FazaaDriver/0.2.3 (+https://fazaa-sat7a.github.io/fazaa-sat7a/)");settings.setJavaScriptEnabled(true);settings.setAllowFileAccess(false);settings.setAllowContentAccess(false);settings.setAllowFileAccessFromFileURLs(false);settings.setAllowUniversalAccessFromFileURLs(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);settings.setGeolocationEnabled(false);
        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                // Only explicit attribution links may leave the local map.
                String host=request.getUrl().getHost();
                if(request.isForMainFrame()&&request.hasGesture()&&"https".equals(request.getUrl().getScheme())&&("www.openstreetmap.org".equals(host)||"openrouteservice.org".equals(host)))try{startActivity(new Intent(Intent.ACTION_VIEW,request.getUrl()));}catch(android.content.ActivityNotFoundException ignored){}
                return true;
            }
            @Override public void onPageFinished(WebView view,String url){if(ASSET.equals(url)){loaded=true;paint();}}
        });
        root.addView(web,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);
        root.setOnApplyWindowInsetsListener((view,insets)->{root.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets.consumeSystemWindowInsets();});root.requestApplyInsets();
        web.loadUrl(ASSET);if(hasRoute())loadRoute();
    }

    private boolean isOverview(){return getIntent().getIntExtra("routeStop",-1)==-2;}
    private boolean hasRoute(){return !DriverDisplay.text(getIntent().getStringExtra("routeRequest"),"").isEmpty();}

    private void loadRoute(){
        if(fetching||destroyed||!hasRoute())return;
        Location point=app.location;
        if(point==null||SystemClock.elapsedRealtimeNanos()-point.getElapsedRealtimeNanos()>90_000_000_000L){status.setText("موقعك غير محدّث. ارجع للطلبات وفعّل استقبال الطلبات وGPS، ثم حاول مجدداً.");return;}
        fetching=true;refresh.setEnabled(false);route=null;status.setText("جاري حساب المسار…");paint();final int version=++generation;
        app.worker.execute(()->{
            JSONObject result=null;String error=null;
            try{result=(JSONObject)app.api.authorized("POST","/functions/v1/driver-route",Api.object("request_id",getIntent().getStringExtra("routeRequest"),"stop_index",getIntent().getIntExtra("routeStop",-1)));}
            catch(Exception e){error=e.getMessage();}
            final JSONObject data=result;final String reason=error;
            app.main.post(()->{
                if(destroyed||version!=generation)return;fetching=false;refresh.setEnabled(true);
                if(data!=null){route=data;status.setText(String.format(java.util.Locale.forLanguageTag("ar-SY"),"%.2f كم · نحو %.0f دقيقة · أُعدّ %s",data.optDouble("metres")/1000,Math.ceil(data.optDouble("seconds")/60),DriverDisplay.time(data.optString("calculated_at",""))));}
                else status.setText(routeError(reason));
                paint();
            });
        });
    }

    private void openOsmAnd(){
        if(isOverview())return;
        double lat=getIntent().getDoubleExtra("lat",Double.NaN),lng=getIntent().getDoubleExtra("lng",Double.NaN);
        JSONObject target=route==null?null:route.optJSONObject("target");
        if(target!=null){lat=target.optDouble("lat",Double.NaN);lng=target.optDouble("lng",Double.NaN);}
        if(!OsmAndRoute.valid(lat,lng)){toast("الموقع المقصود غير متاح. ارجع للطلب وحدّث الحالة.");return;}
        Location own=app.location;
        if(own==null||SystemClock.elapsedRealtimeNanos()-own.getElapsedRealtimeNanos()>90_000_000_000L||!OsmAndRoute.valid(own.getLatitude(),own.getLongitude())){toast("فعّل GPS وانتظر تحديث موقعك ثم اضغط بدء الملاحة.");return;}
        android.net.Uri uri=android.net.Uri.parse(OsmAndRoute.link(own.getLatitude(),own.getLongitude(),lat,lng));
        // Package-specific intents prevent another map application from taking this action.
        for(String packageName:OsmAndRoute.PACKAGES){
            try{startActivity(new Intent(Intent.ACTION_VIEW,uri).setPackage(packageName));return;}
            catch(android.content.ActivityNotFoundException ignored){}
            catch(SecurityException ignored){}
        }
        new AlertDialog.Builder(this).setTitle("تثبيت OsmAnd").setMessage("ثبّت OsmAnd وحمّل خريطة سوريا، ثم ارجع إلى فزعة واضغط بدء الملاحة مجدداً.").setPositiveButton("فتح صفحة التثبيت",(dialog,which)->installOsmAnd()).setNegativeButton("لاحقاً",null).show();
    }

    private void installOsmAnd(){
        try{startActivity(new Intent(Intent.ACTION_VIEW,android.net.Uri.parse("market://details?id=net.osmand")).setPackage("com.android.vending"));}
        catch(android.content.ActivityNotFoundException e){
            try{startActivity(new Intent(Intent.ACTION_VIEW,android.net.Uri.parse("https://osmand.net/")));}
            catch(android.content.ActivityNotFoundException missing){toast("افتح متجر التطبيقات وابحث عن OsmAnd.");}
        }
    }
    private void toast(String value){Toast.makeText(this,value,Toast.LENGTH_LONG).show();}

    private static String routeError(String reason){
        String value=reason==null?"":reason;
        if(value.contains("DRIVER_LOCATION_STALE"))return "موقع السائق على الخادم غير محدّث. ارجع للطلبات وحدّث الحالة ثم حاول مجدداً.";
        if(value.contains("REQUEST_NOT_AVAILABLE")||value.contains("INVALID_STOP"))return "تغيّرت حالة الطلب أو وجهاته. ارجع للطلبات وحدّث الحالة.";
        if(value.contains("ROUTER_NOT_CONFIGURED"))return "عرض المسار قيد الإعداد. راجع المدير.";
        if(value.contains("ROUTE_RATE_LIMIT"))return "انتظر بضع ثوانٍ ثم أعد تحديث المسار.";
        return "تعذّر تحميل المسار. تحقّق من الإنترنت والموقعين ثم حاول مجدداً.";
    }

    private void paint(){
        if(!loaded||destroyed||web==null)return;
        try{
            JSONArray points=new JSONArray();Location location=app.location;
            if(location!=null){boolean stale=SystemClock.elapsedRealtimeNanos()-location.getElapsedRealtimeNanos()>90_000_000_000L;points.put(Api.object("lat",location.getLatitude(),"lng",location.getLongitude(),"driver",true,"stale",stale,"label","موقع السائق"));}
            if(isOverview()){
                JSONArray targets=route==null?null:route.optJSONArray("targets");
                if(targets==null)try{targets=new JSONArray(getIntent().getStringExtra("tripPoints"));}catch(Exception ignored){}
                if(targets!=null)for(int i=0;i<targets.length();i++){JSONObject target=targets.optJSONObject(i);if(target!=null)points.put(target.put("preview",true));}
            }else{
            JSONObject target=route==null?null:route.optJSONObject("target");
            if(target!=null)points.put(Api.object("lat",target.optDouble("lat"),"lng",target.optDouble("lng"),"driver",false,"delivery",hasRoute()&&getIntent().getIntExtra("routeStop",-1)>=0,"label",DriverDisplay.text(target.opt("label"),"الموقع المقصود")));
            else if(getIntent().hasExtra("lat"))points.put(Api.object("lat",getIntent().getDoubleExtra("lat",0),"lng",getIntent().getDoubleExtra("lng",0),"driver",false,"delivery",hasRoute()&&getIntent().getIntExtra("routeStop",-1)>=0,"label",hasRoute()&&getIntent().getIntExtra("routeStop",-1)>=0?"وجهة توصيل المركبة":"موقع العميل"));
            }
            JSONObject state=Api.object("points",points,"route",route==null?JSONObject.NULL:route);
            web.evaluateJavascript("window.setMapState && window.setMapState("+state+")",null);
        }catch(Exception ignored){}
    }
    @Override protected void onResume(){super.onResume();app.visible=true;handler.removeCallbacks(update);handler.post(update);}
    @Override protected void onPause(){app.visible=false;handler.removeCallbacks(update);super.onPause();}
    @Override protected void onDestroy(){destroyed=true;generation++;handler.removeCallbacks(update);web.destroy();super.onDestroy();}
}
