package com.fazaa.customer;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.content.SharedPreferences;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.util.Map;

public final class CustomerMessagingService extends FirebaseMessagingService {
    @Override public void onNewToken(String token) {
        PushStore.prefs(this).edit().putString("token",token).apply();
        ClientActivity.pushTokenChanged();
    }
    @Override public void onMessageReceived(RemoteMessage message) {
        PushStore.createChannel(this);
        if (!PushStore.allowed(this)) return;
        if (android.os.Build.VERSION.SDK_INT >= 33
            && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) return;
        Map<String,String> data=message.getData();
        OrderPush parsed=OrderPush.parse(data,System.currentTimeMillis());
        String event=parsed==null?null:parsed.eventId;
        String request=parsed==null?null:parsed.requestId;
        String title=parsed==null?null:parsed.title;
        if(parsed==null){
            if(message.getNotification()==null)return;
            title="إشعار فزعة";event=java.util.UUID.randomUUID().toString();request=null;
        }
        SharedPreferences prefs=PushStore.prefs(this);
        synchronized(CustomerMessagingService.class) {
            String seenKey="seen."+event;
            if(prefs.contains(seenKey)) return;
            Intent open=new Intent(this,ClientActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
            if(request!=null) open.putExtra("request_id",request);
            open.setAction("com.fazaa.customer.OPEN."+event);
            PendingIntent pending=PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
            Notification notification=new Notification.Builder(this,PushStore.CHANNEL)
                .setSmallIcon(R.drawable.ic_notification_tow).setContentTitle(title)
                .setContentText(request==null?"إشعارات فزعة مفعّلة على جهازك.":"اضغط لفتح الطلب والاطلاع على التفاصيل.")
                .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true)
                .setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(Notification.CATEGORY_STATUS).build();
            // A distinct tag preserves every step instead of replacing the previous notification.
            try { getSystemService(NotificationManager.class).notify("fazaa.event."+event,0,notification); }
            catch(SecurityException e) { return; }
            long now=System.currentTimeMillis();
            SharedPreferences.Editor edit=prefs.edit().putLong(seenKey,now);
            for(Map.Entry<String,?> entry:prefs.getAll().entrySet()) {
                if(entry.getKey().startsWith("seen.") && entry.getValue() instanceof Long
                    && now-(Long)entry.getValue()>7L*24*60*60*1000) edit.remove(entry.getKey());
            }
            edit.apply();
        }
    }
}
