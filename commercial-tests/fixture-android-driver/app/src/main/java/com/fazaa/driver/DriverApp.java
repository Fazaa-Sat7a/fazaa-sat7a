package com.fazaa.driver;

import android.app.Application;
import android.location.Location;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/** Network and session mutations share ONE worker, including service polls. */
public final class DriverApp extends Application {
    final ScheduledExecutorService worker = Executors.newSingleThreadScheduledExecutor();
    final Handler main = new Handler(Looper.getMainLooper());
    Api api;
    volatile DriverService service;
    volatile boolean visible;
    volatile boolean ready;
    volatile boolean busy;
    volatile Location location;
    volatile Snapshot snapshot = new Snapshot(null, null, new JSONArray(), false, "", 0);
    private boolean pendingOnline;
    private boolean needsReconcile = true;
    private long onlineDeadline, lastSent;
    private final Set<String> notified = new HashSet<>();
    private JSONObject profile, current;
    private boolean available;
    private JSONObject finances;
    private long financesAt;
    interface Task { void run() throws Exception; }

    static final class Snapshot {
        final JSONObject profile, current;
        final JSONArray offers;
        final boolean available;
        final String message;
        final long syncedAt;
        Snapshot(JSONObject p, JSONObject c, JSONArray o, boolean a, String m, long at) {
            profile = p; current = c; offers = o; available = a; message = m; syncedAt = at;
        }
    }

    @Override public void onCreate() {
        super.onCreate();
        worker.execute(() -> { api = new Api(this); ready = true; });
        worker.scheduleWithFixedDelay(() -> {
            if (api == null || !api.signedIn() || (!visible && service == null)) return;
            synchronize();
        }, 1, 5, TimeUnit.SECONDS);
    }

    void task(Task task) {
        if (busy) return;
        busy = true;
        worker.execute(() -> {
            try { task.run(); }
            catch (Exception e) { publish(error(e)); }
            finally { busy = false; }
        });
    }

    void login(String email, String password) {
        task(() -> { api.login(email, password); needsReconcile = true; synchronize(); });
    }

    void refresh() { worker.execute(this::synchronize); }

    void publish(String message) {
        snapshot = new Snapshot(profile, current, snapshot.offers, available, message, snapshot.syncedAt);
    }

    void synchronize() {
        if (api == null || !api.signedIn()) return;
        try {
            DriverService running = service;
            if (running != null) running.keepAwake();
            profile = api.profile();
            if (!"active".equals(profile.optString("status"))) {
                pendingOnline = false;
                available = false;
                current = null;
                snapshot = new Snapshot(profile, null, new JSONArray(), false, "حساب السائق موقوف. راجع المدير.", 0);
                stopServiceNow();
                return;
            }
            current = first(api.rpc("driver_current_request", new JSONObject()));
            available = profile.optBoolean("is_available");
            if (needsReconcile && service == null) {
                api.rpc("driver_set_available", Api.object("p_available", false));
                available = false;
                needsReconcile = false;
            }
            Location point = location;
            boolean fresh = point != null && SystemClock.elapsedRealtimeNanos() - point.getElapsedRealtimeNanos() < 90_000_000_000L;
            if (running != null && fresh && (pendingOnline || SystemClock.elapsedRealtime() - lastSent > (current != null ? 10000 : 30000))) {
                api.rpc("driver_update_location", Api.object("p_lat", point.getLatitude(), "p_lng", point.getLongitude()));
                lastSent = SystemClock.elapsedRealtime();
            }
            if (running != null && pendingOnline) {
                if (fresh && lastSent > 0) {
                    api.rpc("driver_set_available", Api.object("p_available", true));
                    available = true;
                    pendingOnline = false;
                } else if (SystemClock.elapsedRealtime() > onlineDeadline) {
                    pendingOnline = false;
                    api.rpc("driver_set_available", Api.object("p_available", false));
                    available = false;
                    if (current == null) stopServiceNow();
                    throw new Exception("تعذّر الحصول على موقع حديث. فعّل GPS ثم حاول مجدداً.");
                }
            }
            // Never advertise this device as available with a stale or disabled GPS.
            if (running != null && available && !fresh && !pendingOnline) {
                api.rpc("driver_set_available", Api.object("p_available", false));
                available = false;
            }
            JSONArray offers = new JSONArray();
            if (running != null && available && fresh && current == null) {
                offers = (JSONArray) api.rpc("driver_open_requests", Api.object("p_radius_km", 15));
            }
            // Fare data is authorized separately, without altering the existing GPS worker.
            JSONArray ids = new JSONArray();
            if (current != null) ids.put(current.optString("id"));
            for (int i=0; i<offers.length(); i++) ids.put(offers.getJSONObject(i).optString("id"));
            if (ids.length()>0) {
                JSONObject cards=(JSONObject)api.rpc("get_fazaa_driver_cards",Api.object("p_ids",ids));
                if(current!=null) current.put("_fazaa",cards.optJSONObject(current.optString("id")));
                for(int i=0;i<offers.length();i++){JSONObject offer=offers.getJSONObject(i);offer.put("_fazaa",cards.optJSONObject(offer.optString("id")));}
            }
            if(finances==null || System.currentTimeMillis()-financesAt>30000){
                finances=(JSONObject)api.rpc("get_fazaa_driver_finances",new JSONObject());financesAt=System.currentTimeMillis();
            }
            profile.put("_fazaa_finances",finances);
            if (running != null) running.notifyOffers(offers, notified);
            String state = pendingOnline ? "جاري تحديد موقعك قبل تفعيل الاستقبال…" : running == null ? (current != null ? "لديك خدمة نشطة. اضغط «استئناف التتبع»." : "الاستقبال متوقف.") : !fresh ? "ننتظر إشارة GPS حديثة. الاستقبال الجديد متوقف." : "آخر تحديث: " + java.text.DateFormat.getTimeInstance().format(new java.util.Date()) + " · دقة الموقع نحو " + Math.round(point.getAccuracy()) + " متر";
            snapshot = new Snapshot(profile, current, offers, available, state, System.currentTimeMillis());
            if (running != null) {
                running.updateNotification(current != null ? "خدمة نشطة — تحديث موقعك مستمر" : pendingOnline ? "جاري تحديد الموقع…" : available ? "متاح — نبحث عن طلبات قريبة" : "الاستقبال متوقف");
                if (!available && current == null && !pendingOnline) stopServiceNow();
            }
        } catch (Exception e) {
            publish(error(e));
            DriverService running = service;
            if (running != null) { running.clearOffers(); running.updateNotification("تعذّر التحديث — افتح التطبيق للتحقق"); }
            if (api != null && !api.signedIn()) {
                profile = null; current = null; available = false; pendingOnline = false;
                snapshot = new Snapshot(null, null, new JSONArray(), false, error(e), 0);
                stopServiceNow();
            }
        }
    }

    void serviceStarted() {
        worker.execute(() -> {
            notified.clear();
            pendingOnline = true; onlineDeadline = SystemClock.elapsedRealtime() + 45000;
            lastSent = 0; needsReconcile = false; synchronize();
        });
    }

    void serviceStopped() {
        pendingOnline = false;
        available = false;
        needsReconcile = true;
        try { if (api != null && api.signedIn()) api.rpc("driver_set_available", Api.object("p_available", false)); }
        catch (Exception ignored) { /* Reconciled on next visible sync; do not claim remote success. */ }
        snapshot = new Snapshot(profile, current, new JSONArray(), false, "التتبع متوقف. افتح التطبيق لتشغيله مجدداً.", 0);
    }

    void stopReceiving() {
        task(() -> {
            api.rpc("driver_set_available", Api.object("p_available", false));
            available = false; pendingOnline = false;
            if (current == null) stopServiceNow();
            synchronize();
        });
    }

    void accept(String id) {
        task(() -> {
            if (service == null || !available) throw new Exception("فعّل استقبال الطلبات أولاً.");
            Object accepted = api.rpc("driver_accept_request", Api.object("p_id", id));
            synchronize();
            if (!Boolean.TRUE.equals(accepted)) publish("لم يُقبل الطلب؛ ربما قبله سائق آخر أو انتهت مهلته.");
        });
    }

    void changeStatus(String id, String status) {
        task(() -> {
            Object changed = api.rpc("driver_set_status", Api.object("p_id", id, "p_status", status));
            synchronize();
            if (!Boolean.TRUE.equals(changed)) publish("تغيّرت حالة الطلب. راجع آخر تحديث.");
        });
    }

    void logout() {
        task(() -> {
            // Re-read the server so stale UI cannot hide an accepted request.
            if (first(api.rpc("driver_current_request", new JSONObject())) != null) throw new Exception("أكمل الطلب الحالي أو ألغِه قبل تسجيل الخروج.");
            api.rpc("driver_set_available", Api.object("p_available", false));
            pendingOnline = false; available = false; stopServiceNow();
            api.clear(); finances=null; financesAt=0; profile = null; current = null; notified.clear(); needsReconcile = true;
            snapshot = new Snapshot(null, null, new JSONArray(), false, "تم تسجيل الخروج.", 0);
        });
    }

    void stopServiceNow() {
        DriverService running = service;
        if (running != null) main.post(running::stopSelf);
    }
    static JSONObject first(Object result) throws Exception {
        return result instanceof JSONArray && ((JSONArray) result).length() > 0 ? ((JSONArray) result).getJSONObject(0) : null;
    }
    static String error(Exception error) {
        String message = error.getMessage();
        if (message == null) return "تعذّر إتمام العملية. حاول مجدداً.";
        if (message.contains("Invalid login credentials")) return "البريد أو كلمة المرور غير صحيحين.";
        if (message.contains("not an active driver")) return "حساب السائق غير مفعّل.";
        if (message.contains("driver already has an active request")) return "لديك طلب نشط بالفعل. حدّث الصفحة.";
        return message;
    }
}
