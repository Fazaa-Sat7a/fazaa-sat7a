package com.fazaa.customer;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.GeolocationPermissions;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

/** Separate customer app. Hosted UI keeps the browser and app behavior aligned. */
public final class ClientActivity extends Activity {
    private static final String ORIGIN = "https://fazaa-sat7a.github.io";
    private static final String URL = ORIGIN + "/fazaa-sat7a/?app=1";
    private WebView web;
    private LinearLayout cover;
    private TextView message;
    private Button retry;
    private ProgressBar progress;
    private GeolocationPermissions.Callback locationCallback;
    private String locationOrigin;
    private boolean failed;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.rgb(247,246,242));
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        root.addView(progress, new LinearLayout.LayoutParams(-1, dp(3)));
        FrameLayout frame = new FrameLayout(this);
        root.addView(frame, new LinearLayout.LayoutParams(-1, 0, 1));
        web = new WebView(this);
        web.setBackgroundColor(Color.rgb(247,246,242));
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setGeolocationEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSafeBrowsingEnabled(true);
        settings.setSupportMultipleWindows(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setUserAgentString(settings.getUserAgentString() + " FazaaCustomer/0.1");
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);
        frame.addView(web, new FrameLayout.LayoutParams(-1,-1));

        cover = new LinearLayout(this);
        cover.setOrientation(LinearLayout.VERTICAL);
        cover.setGravity(Gravity.CENTER);
        cover.setPadding(dp(26),dp(26),dp(26),dp(26));
        cover.setBackgroundColor(Color.rgb(247,246,242));
        ImageView icon = new ImageView(this);
        icon.setImageResource(R.drawable.app_icon);
        icon.setContentDescription("سطحة تحمل سيارة");
        cover.addView(icon, new LinearLayout.LayoutParams(dp(125),dp(125)));
        TextView title = new TextView(this);
        title.setText("فزعة"); title.setTextSize(32); title.setTextColor(Color.rgb(31,41,51)); title.setTypeface(null, Typeface.BOLD);
        cover.addView(title);
        message = new TextView(this);
        message.setTextSize(16); message.setGravity(Gravity.CENTER); message.setPadding(0,dp(12),0,dp(12));
        message.setTextColor(Color.rgb(65,77,85));
        cover.addView(message);
        retry = new Button(this);
        retry.setText("إعادة المحاولة"); retry.setOnClickListener(v -> load());
        cover.addView(retry);
        frame.addView(cover, new FrameLayout.LayoutParams(-1,-1));

        web.setWebChromeClient(new WebChromeClient() {
            @Override public void onProgressChanged(WebView view, int value) {
                progress.setProgress(value);
                progress.setVisibility(value < 100 ? View.VISIBLE : View.GONE);
            }
            @Override public void onGeolocationPermissionsShowPrompt(String origin, GeolocationPermissions.Callback callback) {
                if (!ORIGIN.equals(origin) || !trustedPage(Uri.parse(web.getUrl() == null ? "" : web.getUrl()))) {
                    callback.invoke(origin,false,false); return;
                }
                if (locationPermission()) { callback.invoke(origin,true,false); return; }
                clearLocationPrompt();
                locationOrigin = origin; locationCallback = callback;
                requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION}, 101);
            }
            @Override public void onGeolocationPermissionsHidePrompt() { clearLocationPrompt(); }
        });
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                if (!request.isForMainFrame()) return true;
                if (trustedPage(request.getUrl())) return false;
                openExternal(request.getUrl()); return true;
            }
            @Override public void onPageFinished(WebView view, String url) {
                if (!failed && trustedPage(Uri.parse(url))) cover.setVisibility(View.GONE);
            }
            @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) showFailure();
            }
            @Override public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
                if (request.isForMainFrame()) showFailure();
            }
        });
        setContentView(root);
        root.setOnApplyWindowInsetsListener((view,insets) -> {
            root.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());
            return insets.consumeSystemWindowInsets();
        });
        root.requestApplyInsets();
        load();
    }

    private void load() {
        failed = false;
        clearLocationPrompt();
        cover.setVisibility(View.VISIBLE);
        retry.setVisibility(View.GONE);
        message.setText("جاري فتح فزعة…");
        progress.setVisibility(View.VISIBLE);
        web.loadUrl(URL);
    }
    private void showFailure() {
        failed = true;
        message.setText("تعذّر الاتصال. تحقّق من الإنترنت ثم حاول مجدداً.");
        retry.setVisibility(View.VISIBLE); cover.setVisibility(View.VISIBLE); progress.setVisibility(View.GONE);
    }
    private static boolean trustedPage(Uri uri) {
        String path = uri.getPath();
        return "https".equalsIgnoreCase(uri.getScheme()) && "fazaa-sat7a.github.io".equalsIgnoreCase(uri.getHost())
            && (uri.getPort() == -1 || uri.getPort() == 443) && uri.getUserInfo() == null
            && ("/fazaa-sat7a/".equals(path) || "/fazaa-sat7a/index.html".equals(path));
    }
    private boolean locationPermission() {
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            || checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }
    @Override public void onRequestPermissionsResult(int code,String[] permissions,int[] results) {
        super.onRequestPermissionsResult(code,permissions,results);
        if (code == 101 && locationCallback != null) {
            GeolocationPermissions.Callback callback = locationCallback;
            String origin = locationOrigin;
            locationCallback = null; locationOrigin = null;
            boolean granted = locationPermission();
            callback.invoke(origin,granted,false);
            if (!granted) Toast.makeText(this,"يمكنك اختيار موقع السيارة بتحريك الخريطة.",Toast.LENGTH_LONG).show();
        }
    }
    private void clearLocationPrompt() {
        if (locationCallback != null) locationCallback.invoke(locationOrigin,false,false);
        locationCallback = null; locationOrigin = null;
    }
    private void openExternal(Uri uri) {
        String scheme = uri.getScheme(); Intent intent;
        if ("https".equalsIgnoreCase(scheme)) intent = new Intent(Intent.ACTION_VIEW,uri);
        else if ("tel".equalsIgnoreCase(scheme)) intent = new Intent(Intent.ACTION_DIAL,uri);
        else return;
        try { startActivity(intent); }
        catch (android.content.ActivityNotFoundException e) { Toast.makeText(this,"لا يوجد تطبيق مناسب لفتح الرابط.",Toast.LENGTH_LONG).show(); }
    }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    @Override protected void onResume() { super.onResume(); web.onResume(); }
    @Override protected void onPause() { web.onPause(); super.onPause(); }
    @Override protected void onDestroy() {
        clearLocationPrompt(); web.stopLoading(); web.setWebChromeClient(null);
        ((android.view.ViewGroup)web.getParent()).removeView(web); web.destroy(); super.onDestroy();
    }
}
