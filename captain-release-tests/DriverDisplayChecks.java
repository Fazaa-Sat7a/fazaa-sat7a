package com.fazaa.driver;
import java.time.ZoneId;
public final class DriverDisplayChecks {
    private static void equal(String actual,String expected){if(!actual.equals(expected))throw new AssertionError(actual+" != "+expected);}
    public static void main(String[] args){
        equal(DriverDisplay.text(null,""),"");equal(DriverDisplay.text("null",""),"");equal(DriverDisplay.text(" NULL ",""),"");equal(DriverDisplay.text(" ملاحظة ",""),"ملاحظة");
        equal(DriverDisplay.time("2026-10-26T09:38:33.705948+00:00",ZoneId.of("Asia/Damascus")),"26/10/2026 · 12:38");
        equal(DriverDisplay.time("2026-10-26T23:38:33Z",ZoneId.of("Asia/Damascus")),"27/10/2026 · 02:38");
        equal(DriverDisplay.time("2026-10-26T09:38:33+00:00",ZoneId.of("UTC")),"26/10/2026 · 09:38");
        equal(DriverDisplay.time("null",ZoneId.of("UTC")),"—");equal(DriverDisplay.time("broken",ZoneId.of("UTC")),"—");
        equal(DriverDisplay.deliveryButton(0,1),"مسار التوصيل");
        equal(DriverDisplay.deliveryButton(1,3),"مسار التوصيل 2");
        System.out.println("PASS: JSON-null text, UTC microseconds, device zone, day rollover, invalid date and clear single/multiple destination labels.");
    }
}
