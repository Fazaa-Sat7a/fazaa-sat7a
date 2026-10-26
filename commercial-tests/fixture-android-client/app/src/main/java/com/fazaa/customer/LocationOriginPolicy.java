package com.fazaa.customer;

import java.net.URI;
import java.net.URISyntaxException;

/** Compare the origin's components rather than its WebView string formatting. */
final class LocationOriginPolicy {
    private LocationOriginPolicy() {}

    static boolean allows(String origin) {
        if (origin == null) return false;
        try {
            URI uri = new URI(origin);
            String path = uri.getRawPath();
            return "https".equalsIgnoreCase(uri.getScheme())
                && "fazaa-sat7a.github.io".equalsIgnoreCase(uri.getHost())
                && (uri.getPort() == -1 || uri.getPort() == 443)
                && uri.getRawUserInfo() == null
                && uri.getRawQuery() == null
                && uri.getRawFragment() == null
                && (path == null || path.isEmpty() || "/".equals(path));
        } catch (URISyntaxException e) {
            return false;
        }
    }
}
