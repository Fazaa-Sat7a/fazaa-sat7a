package com.fazaa.customer;
import java.util.Map;
final class OrderPush {
 final String eventId,requestId,title;
 private OrderPush(String event,String request,String title){this.eventId=event;this.requestId=request;this.title=title;}
 static OrderPush parse(Map<String,String> data,long now){
  String event=PushUuid.parse(data.get("event_id")),request=PushUuid.parse(data.get("request_id")),title=titleFor(data.get("status"));
  if(event==null||request==null||title==null)return null;
  try{if(Long.parseLong(data.get("expires_at_ms"))<=now)return null;}catch(RuntimeException e){return null;}
  return new OrderPush(event,request,title);
 }
    private static String titleFor(String status) {
        if(status==null) return null;
        switch(status) {
            case "new": return "تم إرسال طلب السطحة";
            case "accepted": return "قبل السائق طلبك";
            case "arrived": return "وصل السائق إلى موقع السيارة";
            case "in_progress": return "بدأت خدمة نقل السيارة";
            case "done": return "اكتملت الخدمة — قيّم تجربتك";
            case "cancelled_driver": return "ألغى السائق طلبك";
            case "cancelled_customer": return "تم إلغاء طلبك";
            case "expired": return "انتهى الانتظار دون قبول سائق";
            default: return null;
        }
    }
}
