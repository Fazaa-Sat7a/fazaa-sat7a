package com.fazaa.driver;

import android.app.Activity;
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
        TextView caption=new TextView(this);caption.setText("الأصفر: موقعك · الأزرق: الموقع المقصود · المسار تقديري ويحتاج إنترنت.");caption.setPadding(20,4,20,8);root.addView(caption);
        status=new TextView(this);status.setText("عرض المسار داخل التطبيق دون توجيه صوتي.");status.setPadding(20,4,20,8);root.addView(status);
        refresh=new Button(this);refresh.setText("تحديث المسار من موقعي");refresh.setVisibility(hasRoute()?View.VISIBLE:View.GONE);refresh.setOnClickListener(v->loadRoute());root.addView(refresh);
        web=new WebView(this);WebSettings settings=web.getSettings();settings.setUserAgentString(settings.getUserAgentString()+" FazaaDriver/0.2.1 (+https://fazaa-sat7a.github.io/fazaa-sat7a/)");settings.setJavaScriptEnabled(true);settings.setAllowFileAccess(false);settings.setAllowContentAccess(false);settings.setAllowFileAccessFromFileURLs(false);settings.setAllowUniversalAccessFromFileURLs(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);settings.setGeolocationEnabled(false);
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
            JSONObject target=route==null?null:route.optJSONObject("target");
            if(target!=null)points.put(Api.object("lat",target.optDouble("lat"),"lng",target.optDouble("lng"),"driver",false,"delivery",hasRoute()&&getIntent().getIntExtra("routeStop",-1)>=0,"label",DriverDisplay.text(target.opt("label"),"الموقع المقصود")));
            else if(getIntent().hasExtra("lat"))points.put(Api.object("lat",getIntent().getDoubleExtra("lat",0),"lng",getIntent().getDoubleExtra("lng",0),"driver",false,"delivery",hasRoute()&&getIntent().getIntExtra("routeStop",-1)>=0,"label",hasRoute()&&getIntent().getIntExtra("routeStop",-1)>=0?"وجهة توصيل المركبة":"موقع العميل"));
            JSONObject state=Api.object("points",points,"route",route==null?JSONObject.NULL:route);
            web.evaluateJavascript("window.setMapState && window.setMapState("+state+")",null);
        }catch(Exception ignored){}
    }
    @Override protected void onResume(){super.onResume();app.visible=true;handler.removeCallbacks(update);handler.post(update);}
    @Override protected void onPause(){app.visible=false;handler.removeCallbacks(update);super.onPause();}
    @Override protected void onDestroy(){destroyed=true;generation++;handler.removeCallbacks(update);web.destroy();super.onDestroy();}
}
