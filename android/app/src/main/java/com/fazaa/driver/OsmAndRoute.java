package com.fazaa.driver;

import java.util.Locale;

/** Only geographic coordinates are handed to OsmAnd, never account/order credentials. */
final class OsmAndRoute {
    static final String[] PACKAGES={"net.osmand","net.osmand.plus"};

    static boolean valid(double lat,double lng){
        return Double.isFinite(lat)&&Double.isFinite(lng)&&Math.abs(lat)<=90&&Math.abs(lng)<=180;
    }

    static String link(double fromLat,double fromLng,double toLat,double toLng){
        if(!valid(fromLat,fromLng)||!valid(toLat,toLng))throw new IllegalArgumentException("Invalid map coordinates");
        return String.format(Locale.ROOT,"https://osmand.net/map/?start=%.7f,%.7f&finish=%.7f,%.7f&profile=car",fromLat,fromLng,toLat,toLng);
    }
}
