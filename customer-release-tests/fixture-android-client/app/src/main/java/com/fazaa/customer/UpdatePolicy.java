package com.fazaa.customer;

import java.net.URI;
/** Only our stable Admin package and immutable versioned release APKs are accepted. */
public final class UpdatePolicy {
    public static final String PACKAGE="com.fazaa.customer.test";
    public static final String MANIFEST="https://github.com/Fazaa-Sat7a/fazaa-sat7a/releases/download/customer-updates/update.json";
    private UpdatePolicy(){}
    public static boolean accepts(String currentPackage,long installed,String publishedPackage,long code,String url){
        if(!PACKAGE.equals(currentPackage)||!PACKAGE.equals(publishedPackage)||code<=installed||code>2100000000L)return false;
        try{URI uri=new URI(url);return "https".equals(uri.getScheme())&&"github.com".equalsIgnoreCase(uri.getHost())&&uri.getPort()==-1&&uri.getUserInfo()==null&&uri.getQuery()==null&&uri.getFragment()==null&&("/Fazaa-Sat7a/fazaa-sat7a/releases/download/customer-v"+code+"/fazaa-customer.apk").equals(uri.getRawPath());}catch(Exception e){return false;}
    }
}
