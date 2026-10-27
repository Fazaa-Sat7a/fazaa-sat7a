package com.fazaa.driver;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.Set;

public final class DriverService extends Service implements LocationListener {
    private static final String TRACKING_CHANNEL = "driver_tracking_v1";
    private static final String OFFERS_CHANNEL = "driver_requests_v1";
    private static final int TRACKING_NOTIFICATION = 10;
    private static final int OFFER_NOTIFICATION = 11;
    private NotificationManager notifications;
    private LocationManager locations;
    private PowerManager.WakeLock wakeLock;
    private DriverApp app;
    private boolean started;

    @Override public void onCreate() {
        super.onCreate();
        app = (DriverApp) getApplication();
        notifications = getSystemService(NotificationManager.class);
        NotificationChannel tracking = new NotificationChannel(TRACKING_CHANNEL, "تشغيل السائق والموقع", NotificationManager.IMPORTANCE_LOW);
        tracking.setDescription("إشعار ظاهر طوال تحديث موقع السائق واستقبال الطلبات.");
        NotificationChannel offers = new NotificationChannel(OFFERS_CHANNEL, "طلبات سطحة قريبة", NotificationManager.IMPORTANCE_HIGH);
        offers.enableVibration(true);
        offers.setDescription("تنبيه صوتي للطلبات الجديدة ضمن ١٥ كم أثناء تشغيل الاستقبال.");
        notifications.createNotificationChannel(tracking);
        notifications.createNotificationChannel(offers);
        PowerManager power = getSystemService(PowerManager.class);
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, getPackageName() + ":driver");
        wakeLock.setReferenceCounted(false);
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (started) return START_NOT_STICKY;
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED && checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            app.worker.execute(() -> app.publish("اسمح بالوصول إلى الموقع ثم فعّل الاستقبال."));
            stopSelf(); return START_NOT_STICKY;
        }
        try {
            Notification notification = ongoing("جاري تشغيل الموقع…");
            if (Build.VERSION.SDK_INT >= 29) startForeground(TRACKING_NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
            else startForeground(TRACKING_NOTIFICATION, notification);
            locations = getSystemService(LocationManager.class);
            boolean provider = false;
            if (locations.isProviderEnabled(LocationManager.GPS_PROVIDER) && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                locations.requestLocationUpdates(LocationManager.GPS_PROVIDER, 5000L, 0f, this, Looper.getMainLooper()); provider = true;
            }
            if (locations.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locations.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 5000L, 0f, this, Looper.getMainLooper()); provider = true;
            }
            if (!provider) throw new IllegalStateException("فعّل الموقع GPS من إعدادات الهاتف ثم حاول مجدداً.");
            started = true;
            app.service = this;
            keepAwake();
            app.serviceStarted();
        } catch (Exception e) {
            app.worker.execute(() -> app.publish(DriverApp.error(e)));
            stopSelf();
        }
        // Deliberately do not restart location from the background after process death.
        return START_NOT_STICKY;
    }

    private PendingIntent openApp() {
        return PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private Notification ongoing(String message) {
        return new Notification.Builder(this, TRACKING_CHANNEL).setSmallIcon(R.drawable.ic_truck)
                .setContentTitle(getString(R.string.app_name)).setContentText(message).setContentIntent(openApp())
                .setStyle(new Notification.BigTextStyle().bigText(message + "\nافتح التطبيق لإدارة الاستقبال والخدمة."))
                .setOngoing(true).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_SERVICE).build();
    }

    void updateNotification(String message) { notifications.notify(TRACKING_NOTIFICATION, ongoing(message)); }
    void keepAwake() { if (wakeLock != null) wakeLock.acquire(60000L); }
    void clearOffers() { notifications.cancel(OFFER_NOTIFICATION); }

    void notifyOffers(JSONArray offers, Set<String> notified) throws Exception {
        if (offers.length() == 0) { clearOffers(); return; }
        boolean hasNew = false;
        for (int i = 0; i < offers.length(); i++) {
            JSONObject offer = offers.getJSONObject(i);
            if (notified.add(offer.getString("id"))) hasNew = true;
        }
        // Only IDs are retained in process memory; customer phone is never in notifications.
        if (hasNew) {
            Notification notification = new Notification.Builder(this, OFFERS_CHANNEL)
                    .setSmallIcon(R.drawable.ic_truck).setContentTitle("طلب سطحة قريب")
                    .setContentText("افتح التطبيق لمراجعة الطلب وقبوله قبل انتهاء مهلته.")
                    .setContentIntent(openApp()).setAutoCancel(true).setTimeoutAfter(60000)
                    .setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(Notification.CATEGORY_EVENT).build();
            notifications.notify(OFFER_NOTIFICATION, notification);
        }
    }

    @Override public void onLocationChanged(Location location) {
        app.location = new Location(location);
    }
    @Override public void onProviderDisabled(String provider) {
        if (locations != null && !locations.isProviderEnabled(LocationManager.GPS_PROVIDER) && !locations.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            app.location = null; app.refresh();
        }
    }
    @Override public void onProviderEnabled(String provider) { }
    @Override public void onStatusChanged(String provider, int status, Bundle extras) { }

    @Override public void onDestroy() {
        try { if (locations != null) locations.removeUpdates(this); }
        catch (SecurityException ignored) { /* Permission may have been revoked in Settings. */ }
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        clearOffers();
        if (app.service == this) {
            app.service = null;
            app.location = null;
            app.worker.execute(app::serviceStopped);
        }
        stopForeground(STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
