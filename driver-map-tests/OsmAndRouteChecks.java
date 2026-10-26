package com.fazaa.driver;

import java.net.URI;
import java.util.Locale;

public final class OsmAndRouteChecks {
    private static void require(boolean ok){if(!ok)throw new AssertionError("OsmAnd navigation target mismatch");}
    private static void rejected(double a,double b,double c,double d){
        try{OsmAndRoute.link(a,b,c,d);throw new AssertionError("Invalid coordinates accepted");}
        catch(IllegalArgumentException expected){}
    }
    public static void main(String[] args){
        Locale previous=Locale.getDefault();
        try{
            Locale.setDefault(Locale.forLanguageTag("ar-SY"));
            String link=OsmAndRoute.link(33.5,36.3,33.52,36.32);
            require(link.equals("https://osmand.net/map/?start=33.5000000,36.3000000&finish=33.5200000,36.3200000&profile=car"));
            URI uri=URI.create(link);require("https".equals(uri.getScheme()));require("osmand.net".equals(uri.getHost()));
            require(!link.contains("token")&&!link.contains("request")&&!link.contains("phone"));
            require(OsmAndRoute.valid(0,0));require(OsmAndRoute.valid(-90,-180));
            rejected(Double.NaN,36,33,36);rejected(33,Double.POSITIVE_INFINITY,33,36);rejected(33,36,91,36);rejected(33,36,33,-181);
            require(OsmAndRoute.PACKAGES.length==2);require("net.osmand".equals(OsmAndRoute.PACKAGES[0]));require("net.osmand.plus".equals(OsmAndRoute.PACKAGES[1]));
            System.out.println("PASS: official OsmAnd route URL, lat/lon order, locale-independent coordinates, supported packages, invalid location rejection and coordinate-only payload.");
        }finally{Locale.setDefault(previous);}
    }
}
