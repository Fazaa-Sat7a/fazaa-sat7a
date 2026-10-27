package com.fazaa.driver;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.NotificationManager;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.location.LocationManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.Locale;

public final class MainActivity extends Activity {
    private static final int INK = Color.rgb(19, 36, 60), YELLOW = Color.rgb(255, 194, 28), PAPER = Color.rgb(244, 246, 250);
    private final Handler handler = new Handler(Looper.getMainLooper());
    private DriverApp app;
    private ScrollView scroll;
    private LinearLayout root;
    private TextView loginMessage;
    private EditText email, password;
    private Button loginButton;
    private DriverApp.Snapshot lastSnapshot;
    private boolean lastBusy;
    private DriverService lastService;
    private String screen = "";
    private CaptainUpdates captainUpdates;
    private boolean automaticUpdateChecked;
    private final Runnable updates = new Runnable() {
        @Override public void run() { render(); handler.postDelayed(this, 750); }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        app = (DriverApp) getApplication();
        captainUpdates = new CaptainUpdates(this, () -> app.visible && app.snapshot.current == null);
        scroll = new ScrollView(this);
        scroll.setBackgroundColor(PAPER);
        scroll.setFillViewport(true);
        scroll.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(24), dp(20), dp(28));
        scroll.addView(root);
        setContentView(scroll);
        scroll.setOnApplyWindowInsetsListener((view, insets) -> {
            scroll.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(), insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets.consumeSystemWindowInsets();
        });
        scroll.requestApplyInsets();
    }

    @Override protected void onResume() { super.onResume(); automaticUpdateChecked=false; app.visible = true; app.refresh(); handler.post(updates); }
    @Override protected void onPause() { handler.removeCallbacks(updates); app.visible = false; super.onPause(); }

    @Override protected void onDestroy() { handler.removeCallbacks(updates); captainUpdates.close(); super.onDestroy(); }

    private void render() {
        if (!app.ready) { if (!screen.equals("loading")) { root.removeAllViews(); brandHeader(); TowSplashView animation=new TowSplashView(this);root.addView(animation,new LinearLayout.LayoutParams(-1,dp(190)));label(root,"جاري فتح فزعة كابتن…",16,false);screen = "loading"; } return; }
        DriverApp.Snapshot state = app.snapshot;
        if(!automaticUpdateChecked && state.current==null){automaticUpdateChecked=true;captainUpdates.check(false);}
        if(state.current!=null)captainUpdates.hideDuringTrip();
        boolean logged = app.api.signedIn() && state.profile != null;
        if (!logged) {
            if (!screen.equals("login")) showLogin();
            loginMessage.setText(state.message);
            loginButton.setEnabled(!app.busy);
            loginButton.setText(app.busy ? "جاري الدخول…" : "دخول الكابتن");
            return;
        }
        if (screen.equals("dashboard") && lastSnapshot == state && lastBusy == app.busy && lastService == app.service) return;
        String priorTrip=lastSnapshot==null||lastSnapshot.current==null?"":lastSnapshot.current.optString("id")+":"+lastSnapshot.current.optString("status");
        String nextTrip=state.current==null?"":state.current.optString("id")+":"+state.current.optString("status");
        int position=priorTrip.equals(nextTrip)?scroll.getScrollY():0;
        screen = "dashboard"; lastSnapshot = state; lastBusy = app.busy; lastService = app.service;
        root.removeAllViews();
        brandHeader();
        if(state.current==null){
        LinearLayout driver = card();
        label(driver, state.profile.optString("name", "السائق"), 22, true);
        label(driver, "اللوحة: " + state.profile.optString("plate", "—") + " · " + state.profile.optString("area", "دمشق"), 14, false);
        JSONObject finance=state.profile.optJSONObject("_fazaa_finances");
        if(finance!=null){
            label(driver,finance.optDouble("commission_pct",0)==0?"عمولة فزعة FREE خلال فترة الإطلاق":"عمولة الطلبات الجديدة: "+finance.optString("commission_pct")+"%",16,true);
            label(driver,"المستحق لفزعة: "+finance.optString("balance","0")+" "+finance.optString("currency_label",""),14,false);
            JSONObject rating=finance.optJSONObject("rating");
            label(driver,rating!=null&&rating.optInt("count")>0?"★ "+rating.optString("average")+" / 5 · "+rating.optInt("count")+" تقييم":"جديد — لم تسجل تقييمات بعد",15,true);
            button(driver,"كشف العمولات والتسديدات",()->showLedger(finance),true);
        }
        boolean activeAccount = "active".equals(state.profile.optString("status"));
        label(driver, !activeAccount ? "الحساب موقوف" : state.available ? (state.current == null ? "متاح لاستقبال الطلبات" : "مشغول بخدمة") : "غير متاح لطلبات جديدة", 17, true);
        label(driver, state.message, 14, false);
        String toggle = state.available ? "إيقاف استقبال الطلبات" : state.current != null && app.service == null ? "استئناف التتبع" : app.service != null ? "تشغيل استقبال الطلبات" : "ابدأ استقبال الطلبات";
        button(driver, toggle, () -> { if (state.available) app.stopReceiving(); else startReceiving(); }, activeAccount && !app.busy);
        label(driver, "عند تشغيل الاستقبال، يستمر تحديث الموقع أثناء استخدام تطبيق آخر أو إطفاء الشاشة، مع إشعار ظاهر. أوقف الاستقبال عند انتهاء دوامك.", 13, false);
        if (app.service != null && !state.available && state.current == null) button(driver, "إيقاف التشغيل", app::stopReceiving, !app.busy);
        button(driver, "تحديث الحالة", app::refresh, !app.busy);
        if (!getSystemService(NotificationManager.class).areNotificationsEnabled()) button(driver, "تفعيل إشعارات الطلبات", this::notificationSettings, true);
        }else{
            label(root,state.message,13,false);
            if(app.service==null)button(root,"استئناف تتبع الموقع",this::startReceiving,!app.busy);
            if(!getSystemService(NotificationManager.class).areNotificationsEnabled())button(root,"تفعيل إشعارات الطلبات",this::notificationSettings,true);
        }
        if (state.current != null) showCurrent(state.current);
        else {
            label(root, "الطلبات القريبة · ضمن ١٥ كم", 22, true);
            if (state.offers.length() == 0) label(root, state.available ? "لا توجد طلبات متاحة حالياً. تتحدّث القائمة تلقائياً." : "فعّل استقبال الطلبات لعرض الطلبات القريبة.", 15, false);
            for (int i = 0; i < state.offers.length(); i++) {
                JSONObject offer = state.offers.optJSONObject(i);
                if (offer != null) showOffer(offer, state.syncedAt);
            }
        }
        if(state.current==null){
        button(root,"التحقق من تحديث التطبيق",()->captainUpdates.check(true),true);
        button(root, "تسجيل الخروج", () -> confirm("تسجيل الخروج؟", "سيُوقف استقبال الطلبات على هذا الهاتف.", app::logout), !app.busy && state.current == null);
        label(root, "التنبيهات تعتمد على اتصال الإنترنت وتشغيل الاستقبال. الكتم ووضع عدم الإزعاج وإيقاف التطبيق من النظام قد يمنعان التنبيه.", 12, false);
        }else button(root,"تحديث الحالة",app::refresh,!app.busy);
        scroll.post(() -> scroll.scrollTo(0, position));
    }

    private void showLogin() {
        screen = "login";
        root.removeAllViews();
        brandHeader();
        LinearLayout form = card();
        label(form, "جاهز للفزعة؟", 27, true);
        label(form, "استخدم حساب السائق الحالي الذي أنشأه المدير.", 15, false);
        label(form, "البريد الإلكتروني", 14, true);
        email = new EditText(this); email.setSingleLine(true); email.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS); email.setTextDirection(View.TEXT_DIRECTION_LTR); email.setHint("driver@example.com"); form.addView(email);
        label(form, "كلمة المرور", 14, true);
        password = new EditText(this); password.setSingleLine(true); password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD); password.setTextDirection(View.TEXT_DIRECTION_LTR); password.setSaveEnabled(false); form.addView(password);
        loginButton = primaryButton(form, "دخول الكابتن", () -> {
            String address = email.getText().toString().trim(), secret = password.getText().toString();
            if (address.isEmpty() || secret.isEmpty()) { toast("أدخل البريد وكلمة المرور."); return; }
            password.setText(""); app.login(address, secret);
        }, true);
        loginMessage = label(form, "", 14, false);
        button(root,"التحقق من تحديث التطبيق",()->captainUpdates.check(true),true);
        label(root, "جلسة الدخول محفوظة مشفّرة على هذا الهاتف. لا تستخدم حساب المدير هنا.", 13, false);
    }

    private void brandHeader(){
        LinearLayout brand=new LinearLayout(this);brand.setOrientation(LinearLayout.HORIZONTAL);brand.setGravity(Gravity.CENTER_VERTICAL);brand.setPadding(dp(16),dp(12),dp(16),dp(12));
        GradientDrawable bg=new GradientDrawable();bg.setColor(INK);bg.setCornerRadius(dp(22));brand.setBackground(bg);
        android.widget.ImageView mark=new android.widget.ImageView(this);mark.setImageResource(R.drawable.captain_mark);mark.setScaleType(android.widget.ImageView.ScaleType.FIT_CENTER);mark.setContentDescription(getString(R.string.app_name));brand.addView(mark,new LinearLayout.LayoutParams(dp(100),dp(88)));
        LinearLayout copy=new LinearLayout(this);copy.setOrientation(LinearLayout.VERTICAL);brand.addView(copy,new LinearLayout.LayoutParams(0,-2,1));
        TextView name=label(copy,getString(R.string.app_name),22,true);name.setTextColor(Color.WHITE);label(copy,"جاهز تفزع؟",14,false).setTextColor(YELLOW);
        root.addView(brand,new LinearLayout.LayoutParams(-1,-2));
    }

    private void showOffer(JSONObject offer, long syncedAt) {
        LinearLayout card = card();
        label(card, problem(offer.optString("problem")) + " · " + car(offer.optString("car_type")), 20, true);
        label(card, String.format(Locale.ROOT, "المسافة المباشرة: %.1f كم", offer.optDouble("distance_km", 0)), 15, false);
        label(card, "وقت الطلب: " + DriverDisplay.time(offer.optString("created_at", "")), 13, false);
        String note = DriverDisplay.text(offer.opt("note"), "");
        if (!note.isEmpty()) label(card, note, 15, false);
        fareDetails(card,offer);
        button(card, "عرض الرحلة", () -> openTrip(offer), true);
        primaryButton(card, "قبول الطلب", () -> app.accept(offer.optString("id")), !app.busy && app.service != null && offer.optJSONObject("_fazaa")!=null && System.currentTimeMillis() - syncedAt < 30000);
    }

    private void showCurrent(JSONObject request) {
        String status = request.optString("status"), id = request.optString("id");
        DriverStage stage=DriverStage.of(status);
        LinearLayout card = card();
        label(card, stage==DriverStage.DONE||stage==DriverStage.CLOSED ? "تفاصيل الطلب" : "طلبك الحالي", 23, true);
        label(card, stage.caption, 17, true);
        label(card, problem(request.optString("problem")) + " · " + car(request.optString("car_type")), 16, false);
        label(card, "مرجع الطلب: " + id.substring(0, Math.min(8, id.length())), 13, false);
        String note = DriverDisplay.text(request.opt("note"), "");
        if (!note.isEmpty()) label(card, note, 15, false);
        fareDetails(card,request);
        if(stage.hasNext())primaryButton(card,stage.nextLabel,()->{
            if(stage==DriverStage.IN_PROGRESS)confirm("إنهاء الخدمة؟","تأكّد من اكتمال الخدمة وتسوية الأجرة الكاش قبل الإنهاء.",()->app.changeStatus(id,stage.nextStatus));
            else app.changeStatus(id,stage.nextStatus);
        },!app.busy);
        if(stage.pickupRoute())button(card,"المسار إلى العميل",()->openRoute(request,-1,"المسار إلى العميل"),true);
        if(stage.deliveryRoutes())deliveryRoutes(card,request);
        String phone=DriverDisplay.text(request.opt("customer_phone"),"").replaceAll("[^0-9+]","");
        if(stage.contact()&&!phone.isEmpty())button(card,"اتصال بالعميل",()->external(new Intent(Intent.ACTION_DIAL,Uri.parse("tel:"+phone))),true);
        if(stage.cancel()){
            Button cancel=button(card,"إلغاء الطلب",()->confirm("إلغاء الطلب الحالي؟","أخبر العميل قبل الإلغاء.",()->app.changeStatus(id,"cancelled_driver")),!app.busy);
            cancel.setBackgroundTintList(android.content.res.ColorStateList.valueOf(Color.rgb(242,243,245)));cancel.setTextColor(Color.rgb(164,38,44));
        }
        label(card, request.optJSONObject("_fazaa")!=null&&request.optJSONObject("_fazaa").optBoolean("priced")?"السعر مثبت؛ لا تضف مبلغاً خارج موافقة العميل في التطبيق.":"طلب قديم سابق لتفعيل التسعير الثابت.", 13, false);
    }

    private void fareDetails(LinearLayout card,JSONObject request){
        JSONObject fare=request.optJSONObject("_fazaa");
        if(fare==null){label(card,"بيانات الأجرة غير متاحة. حدّث الحالة قبل قبول الطلب.",14,true);return;}
        if(!fare.optBoolean("priced")){label(card,"طلب سابق لنظام التسعير الثابت.",14,false);return;}
        String currency=fare.optString("currency_label","");
        String category=DriverDisplay.text(fare.opt("category_label"),"");
        if(!category.isEmpty())label(card,"فئة المركبة: "+category,15,true);
        if(fare.has("enclosed")&&!fare.isNull("enclosed"))label(card,fare.optBoolean("enclosed")?"الخدمة: سطحة مغلقة / VIP":"الخدمة: سطحة عادية",15,false);
        if(fare.has("vehicle_year")&&!fare.isNull("vehicle_year"))label(card,"سنة الصنع: "+fare.optString("vehicle_year"),15,false);
        label(card,"الدفع: كاش من العميل",14,true);
        label(card,"الأجرة الشاملة: "+fare.optString("total")+" "+currency,22,true);
        label(card,fare.optString("vehicle_name")+" · "+fare.optString("truck_name"),15,false);
        double pct=fare.optDouble("commission_pct",0),total=fare.optDouble("total",0),commission=fare.optDouble("commission",0);
        label(card,pct==0?"عمولة فزعة FREE — كامل الأجرة إلك":"عمولة فزعة: "+commission+" · صافي مستحقك: "+(total-commission)+" "+currency,15,true);
        org.json.JSONArray stops=fare.optJSONArray("stops");
        if(stops!=null)for(int i=0;i<stops.length();i++){
            JSONObject stop=stops.optJSONObject(i);if(stop==null)continue;
            label(card,(i+1)+". "+stop.optString("label","الوجهة"),15,true);
        }
    }
    private void deliveryRoutes(LinearLayout card,JSONObject request){
        JSONObject fare=request.optJSONObject("_fazaa");
        org.json.JSONArray stops=fare==null?null:fare.optJSONArray("stops");
        if(stops==null)return;
        for(int i=0;i<stops.length();i++){
            if(stops.optJSONObject(i)==null)continue;
            final int stopIndex=i;String title=DriverDisplay.deliveryButton(i,stops.length());
            button(card,title,()->openRoute(request,stopIndex,title),true);
        }
    }
    private void openTrip(JSONObject request){openRoute(request,-2,"عرض الرحلة");}

    private void showLedger(JSONObject finance){
        StringBuilder text=new StringBuilder();org.json.JSONArray entries=finance.optJSONArray("ledger");
        if(entries!=null)for(int i=0;i<entries.length();i++){
            JSONObject e=entries.optJSONObject(i);if(e!=null)text.append(DriverDisplay.time(e.optString("created_at", ""))).append("\n").append("commission".equals(e.optString("kind"))?"عمولة رحلة: ":"تسديد: ").append(e.optString("amount")).append(" ").append(finance.optString("currency_label")).append("\n\n");
        }
        new AlertDialog.Builder(this).setTitle("كشف حساب فزعة").setMessage(text.length()>0?text.toString():"لا توجد حركات مالية بعد.").setPositiveButton("إغلاق",null).show();
    }

    private boolean locationPermission() {
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED || checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private void startReceiving() {
        if (app.service != null) {
            app.serviceStarted(); return;
        }
        if (!locationPermission()) { requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, 100); return; }
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 101); return;
        }
        if (!getSystemService(NotificationManager.class).areNotificationsEnabled()) {
            new AlertDialog.Builder(this).setTitle("فعّل إشعارات الطلبات").setMessage("نحتاج الإشعارات لتنبيهك عند وصول طلب أثناء إطفاء الشاشة.").setPositiveButton("الإعدادات", (d, w) -> notificationSettings()).setNegativeButton("لاحقاً", null).show(); return;
        }
        LocationManager manager = getSystemService(LocationManager.class);
        if (!manager.isProviderEnabled(LocationManager.GPS_PROVIDER) && !manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            external(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)); toast("فعّل الموقع ثم اضغط استقبال الطلبات."); return;
        }
        try { startForegroundService(new Intent(this, DriverService.class)); }
        catch (Exception e) { toast("تعذّر تشغيل التتبع. أبقِ التطبيق مفتوحاً وحاول مجدداً."); }
    }

    @Override public void onRequestPermissionsResult(int code, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(code, permissions, results);
        if (code == 100) {
            if (locationPermission()) startReceiving();
            else new AlertDialog.Builder(this).setTitle("إذن الموقع مطلوب").setMessage("اسمح بالموقع لعرض الطلبات القريبة وتحديث موقعك أثناء الخدمة.").setPositiveButton("إعدادات التطبيق", (d, w) -> external(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName())))).setNegativeButton("إغلاق", null).show();
        } else if (code == 101) {
            if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) startReceiving();
            else { toast("فعّل الإشعارات ثم اضغط استقبال الطلبات."); notificationSettings(); }
        }
    }

    private void notificationSettings() { external(new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName())); }
    private void openRoute(JSONObject request, int stopIndex, String title) {
        String id = DriverDisplay.text(request.opt("id"), "");
        if (id.isEmpty()) { toast("تعذّر تحديد الطلب. حدّث الحالة وحاول مجدداً."); return; }
        Intent intent = new Intent(this, MapActivity.class);
        intent.putExtra("routeRequest", id).putExtra("routeStop", stopIndex).putExtra("routeTitle", title);
        if (stopIndex < 0 && !request.isNull("lat") && !request.isNull("lng")) {
            intent.putExtra("lat", request.optDouble("lat")).putExtra("lng", request.optDouble("lng"));
        } else if (stopIndex >= 0) {
            JSONObject fare=request.optJSONObject("_fazaa");
            org.json.JSONArray stops=fare==null?null:fare.optJSONArray("stops");
            JSONObject stop=stops==null?null:stops.optJSONObject(stopIndex);
            if (stop!=null&&!stop.isNull("lat")&&!stop.isNull("lng")) intent.putExtra("lat",stop.optDouble("lat")).putExtra("lng",stop.optDouble("lng"));
        }
        if(stopIndex==-2){
            try{
                org.json.JSONArray points=new org.json.JSONArray();
                if(!request.isNull("lat")&&!request.isNull("lng"))points.put(Api.object("lat",request.optDouble("lat"),"lng",request.optDouble("lng"),"label","موقع العميل","delivery",false));
                JSONObject fare=request.optJSONObject("_fazaa");org.json.JSONArray stops=fare==null?null:fare.optJSONArray("stops");
                if(stops!=null)for(int i=0;i<stops.length();i++){JSONObject stop=stops.optJSONObject(i);if(stop!=null&&!stop.isNull("lat")&&!stop.isNull("lng"))points.put(Api.object("lat",stop.optDouble("lat"),"lng",stop.optDouble("lng"),"label",DriverDisplay.text(stop.opt("label"),"وجهة التوصيل"),"delivery",true,"number",i+1));}
                intent.putExtra("tripPoints",points.toString()).putExtra("hasDeliveries",points.length()>1);
            }catch(org.json.JSONException ignored){}
        }
        startActivity(intent);
    }
    private void external(Intent intent) { try { startActivity(intent); } catch (android.content.ActivityNotFoundException e) { toast("لا يوجد تطبيق مناسب لفتح هذا الرابط."); } }
    private void confirm(String title, String message, Runnable action) { new AlertDialog.Builder(this).setTitle(title).setMessage(message).setPositiveButton("تأكيد", (d, w) -> action.run()).setNegativeButton("رجوع", null).show(); }
    private void toast(String message) { Toast.makeText(this, message, Toast.LENGTH_LONG).show(); }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private LinearLayout card() {
        LinearLayout card = new LinearLayout(this); card.setOrientation(LinearLayout.VERTICAL); card.setPadding(dp(18), dp(18), dp(18), dp(18));
        GradientDrawable background = new GradientDrawable(); background.setColor(Color.WHITE); background.setCornerRadius(dp(18)); background.setStroke(dp(1), Color.rgb(222, 223, 220)); card.setBackground(background);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT); params.setMargins(0, dp(16), 0, dp(8)); root.addView(card, params); return card;
    }
    private TextView label(LinearLayout parent, String text, int size, boolean bold) {
        TextView view = new TextView(this); view.setText(text); view.setTextSize(size); view.setTextColor(INK); view.setGravity(Gravity.START); view.setTextDirection(View.TEXT_DIRECTION_FIRST_STRONG); view.setPadding(0, dp(5), 0, dp(6));
        if (bold) view.setTypeface(null, Typeface.BOLD); parent.addView(view); return view;
    }
    private Button primaryButton(LinearLayout parent,String text,Runnable action,boolean enabled){
        Button view=button(parent,text,action,enabled);
        view.setBackgroundTintList(android.content.res.ColorStateList.valueOf(YELLOW));view.setTextColor(INK);view.setTypeface(null,Typeface.BOLD);view.setMinHeight(dp(58));
        return view;
    }
    private Button button(LinearLayout parent, String text, Runnable action, boolean enabled) {
        Button view = new Button(this); view.setText(text); view.setTextSize(15); view.setTextColor(INK); view.setAllCaps(false); view.setMinHeight(dp(50));
        GradientDrawable background = new GradientDrawable(); background.setColor(Color.rgb(232,237,244)); background.setCornerRadius(dp(14)); view.setBackground(background); view.setPadding(dp(10), dp(10), dp(10), dp(10)); view.setEnabled(enabled); view.setAlpha(enabled ? 1f : .5f);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT); params.setMargins(0, dp(10), 0, dp(4)); parent.addView(view, params); view.setOnClickListener(v -> action.run()); return view;
    }
    private static String problem(String value) { switch (value) { case "engine": return "عطل محرك"; case "battery": return "بطارية"; case "tire": return "إطار"; case "accident": return "حادث"; default: return "مساعدة أخرى"; } }
    private static String car(String value) { switch (value) { case "small": return "سيارة صغيرة"; case "suv": return "دفع رباعي"; case "truck": return "بيك أب / فان"; default: return value; } }
}
