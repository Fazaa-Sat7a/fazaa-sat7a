package com.fazaa.driver;

public final class DriverStageChecks {
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    private static void equal(String actual,String expected){check(actual.equals(expected),actual+" != "+expected);}
    public static void main(String[] args){
        DriverStage accepted=DriverStage.of("accepted");
        check(accepted.pickupRoute()&&!accepted.deliveryRoutes(),"Accepted stage must show only pickup routing");
        check(accepted.contact()&&accepted.cancel()&&accepted.hasNext(),"Accepted stage remains actionable");
        equal(accepted.nextLabel,"وصلت إلى العميل");equal(accepted.nextStatus,"arrived");
        DriverStage arrived=DriverStage.of(accepted.nextStatus);
        check(!arrived.pickupRoute()&&arrived.deliveryRoutes(),"Arrival must replace pickup with delivery routing");
        equal(arrived.nextLabel,"بدأت نقل السيارة");equal(arrived.nextStatus,"in_progress");
        check(!arrived.nextStatus.equals("done"),"Service cannot be completed directly from arrival UI");
        DriverStage moving=DriverStage.of(arrived.nextStatus);
        check(!moving.pickupRoute()&&moving.deliveryRoutes()&&moving.contact(),"Transport stage keeps delivery and contact");
        equal(moving.nextLabel,"أنهيت الخدمة");equal(moving.nextStatus,"done");
        for(String state:new String[]{moving.nextStatus,"cancelled_customer","cancelled_driver","expired","new","unknown","null",null}){
            DriverStage stage=DriverStage.of(state);
            check(!stage.pickupRoute()&&!stage.deliveryRoutes()&&!stage.contact()&&!stage.cancel()&&!stage.hasNext(),"Stale/closed/unknown request must expose no active-stage actions: "+state);
        }
        equal(DriverStage.of("done").caption,"اكتملت الخدمة");
        System.out.println("PASS: sequential accepted→arrived→in_progress→done UI; route switching, contact/cancel visibility, no early completion and no actions on closed/unknown requests.");
    }
}
