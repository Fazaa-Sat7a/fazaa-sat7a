package com.fazaa.driver;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

/** Formatting only; no session, GPS or fare mutations. */
final class DriverDisplay {
    static String text(Object value, String fallback) {
        if (value == null) return fallback;
        String result = value.toString().trim();
        return result.isEmpty() || "null".equalsIgnoreCase(result) ? fallback : result;
    }

    static String time(String value) { return time(value, ZoneId.systemDefault()); }

    static String time(String value, ZoneId zone) {
        String clean = text(value, "");
        if (clean.isEmpty()) return "—";
        try {
            return OffsetDateTime.parse(clean).atZoneSameInstant(zone)
                    .format(DateTimeFormatter.ofPattern("dd/MM/yyyy · HH:mm", Locale.forLanguageTag("ar-SY")));
        } catch (RuntimeException ignored) { return "—"; }
    }

    static String deliveryButton(int index, int count, String name) {
        String label = count > 1 ? "المسار إلى وجهة توصيل المركبة " + (index + 1) : "المسار إلى وجهة توصيل المركبة";
        String clean = text(name, "");
        return clean.isEmpty() ? label : label + " — " + clean;
    }
}
