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
            require(link.equals("osmand.api://navigate?start_lat=33.5000000&start_lon=36.3000000&dest_lat=33.5200000&dest_lon=36.3200000&profile=car&force=false&location_permission=true"));
            URI uri=URI.create(link);require("osmand.api".equals(uri.getScheme()));require("navigate".equals(uri.getHost()));
            java.util.Map<String,String> params=new java.util.HashMap<>();for(String pair:uri.getQuery().split("&")){String[] kv=pair.split("=",2);params.put(kv[0],kv[1]);}
            require(Double.parseDouble(params.get("start_lat"))==33.5);require(Double.parseDouble(params.get("start_lon"))==36.3);require(Double.parseDouble(params.get("dest_lat"))==33.52);require(Double.parseDouble(params.get("dest_lon"))==36.32);require("false".equals(params.get("force")));require("true".equals(params.get("location_permission")));
            require(!link.contains("token")&&!link.contains("request")&&!link.contains("phone"));
            require(OsmAndRoute.valid(0,0));require(OsmAndRoute.valid(-90,-180));
            rejected(Double.NaN,36,33,36);rejected(33,Double.POSITIVE_INFINITY,33,36);rejected(33,36,91,36);rejected(33,36,33,-181);
            require(OsmAndRoute.PACKAGES.length==2);require("net.osmand".equals(OsmAndRoute.PACKAGES[0]));require("net.osmand.plus".equals(OsmAndRoute.PACKAGES[1]));
            System.out.println("PASS: native OsmAnd navigate command, lat/lon order, locale-independent coordinates, supported packages, invalid location rejection and coordinate-only payload.");
        }finally{Locale.setDefault(previous);}
    }
}
