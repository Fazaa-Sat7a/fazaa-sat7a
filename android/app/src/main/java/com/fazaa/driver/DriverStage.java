package com.fazaa.driver;

/** Visible request actions follow the server status; no optimistic stage advancement. */
enum DriverStage {
    ACCEPTED("تم قبول الطلب", "وصلت إلى العميل", "arrived"),
    ARRIVED("وصلت إلى العميل", "بدأت نقل السيارة", "in_progress"),
    IN_PROGRESS("نقل المركبة جارٍ", "أنهيت الخدمة", "done"),
    DONE("اكتملت الخدمة", "", ""),
    CLOSED("الطلب ملغى أو منتهي", "", ""),
    UNKNOWN("حالة الطلب غير محدثة", "", "");

    final String caption, nextLabel, nextStatus;
    DriverStage(String caption,String nextLabel,String nextStatus){this.caption=caption;this.nextLabel=nextLabel;this.nextStatus=nextStatus;}

    static DriverStage of(String status){
        if(status==null)return UNKNOWN;
        switch(status){
            case "accepted":return ACCEPTED;
            case "arrived":return ARRIVED;
            case "in_progress":return IN_PROGRESS;
            case "done":return DONE;
            case "cancelled_customer":case "cancelled_driver":case "expired":return CLOSED;
            default:return UNKNOWN;
        }
    }
    boolean pickupRoute(){return this==ACCEPTED;}
    boolean deliveryRoutes(){return this==ARRIVED||this==IN_PROGRESS;}
    boolean contact(){return this==ACCEPTED||this==ARRIVED||this==IN_PROGRESS;}
    boolean cancel(){return contact();}
    boolean hasNext(){return !nextStatus.isEmpty();}
}
