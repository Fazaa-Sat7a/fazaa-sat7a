package com.fazaa.customer;
final class PushUuid {
 private PushUuid(){}
 static String parse(String value){return value!=null&&value.matches("(?i)^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$")?value.toLowerCase(java.util.Locale.ROOT):null;}
}
