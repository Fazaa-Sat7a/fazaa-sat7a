package com.fazaa.customer;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONObject;
import java.util.UUID;

final class PushStore {
    static final String CHANNEL = "fazaa_customer_order_updates";
    private PushStore() {}
    static SharedPreferences prefs(Context c) { return c.getSharedPreferences("fazaa_push", Context.MODE_PRIVATE); }
    static synchronized String installation(Context c) {
        String id = prefs(c).getString("installation_id", null);
        if (id == null) { id = UUID.randomUUID().toString(); prefs(c).edit().putString("installation_id", id).apply(); }
        return id;
    }
    static void createChannel(Context c) {
        NotificationChannel channel = new NotificationChannel(CHANNEL,"تحديثات طلب السطحة",NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("قبول السائق والوصول وبدء الخدمة والإكمال والإلغاء");
        channel.enableVibration(true);
        c.getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }
    static boolean allowed(Context c) {
        NotificationManager manager = c.getSystemService(NotificationManager.class);
        if (!manager.areNotificationsEnabled()) return false;
        NotificationChannel channel = manager.getNotificationChannel(CHANNEL);
        return channel == null || channel.getImportance() != NotificationManager.IMPORTANCE_NONE;
    }
    static String requestId(String value) {
        return PushUuid.parse(value);
    }
    static JSONObject device(Context c) {
        JSONObject data = new JSONObject();
        try {
            data.put("installation_id",installation(c));
            data.put("token",prefs(c).getString("token", ""));
            data.put("permission",allowed(c));
        } catch (org.json.JSONException ignored) { /* All values are strings or booleans. */ }
        return data;
    }
}
