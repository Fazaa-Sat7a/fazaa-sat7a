package com.fazaa.driver;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

/** Hosted admin UI with its own web session; no driver token or native JS bridge. */
public final class AdminActivity extends Activity {
    private static final String ADMIN_URL = "https://fazaa-sat7a.github.io/fazaa-sat7a/admin.html";
    private WebView web;
    private ProgressBar progress;
    private TextView notice;
    private boolean mainFailed;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        root.setBackgroundColor(Color.rgb(247, 246, 242));

        LinearLayout toolbar = new LinearLayout(this);
        Button back = new Button(this); back.setText("العودة للتطبيق"); back.setOnClickListener(v -> finish());
        Button refresh = new Button(this); refresh.setText("إعادة تحميل"); refresh.setOnClickListener(v -> loadAdmin());
        toolbar.addView(back, new LinearLayout.LayoutParams(0, -2, 1));
        toolbar.addView(refresh, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(toolbar);
        notice = new TextView(this);
        notice.setText("لوحة المدير — سجّل الدخول بحساب الإدارة.");
        notice.setTextColor(Color.rgb(31, 41, 51));
        int padding = Math.round(12 * getResources().getDisplayMetrics().density);
        notice.setPadding(padding, padding / 2, padding, padding / 2);
        root.addView(notice);
        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        root.addView(progress, new LinearLayout.LayoutParams(-1, padding / 3));

        web = new WebView(this);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        // Supabase's existing admin storageKey persists only in this WebView's web storage.
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setGeolocationEnabled(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSafeBrowsingEnabled(true);
        settings.setSupportMultipleWindows(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);
        // Enables the existing page's confirmation dialogs for driver edits and suspension.
        web.setWebChromeClient(new WebChromeClient() {
            @Override public void onProgressChanged(WebView view, int value) {
                progress.setProgress(value);
                progress.setVisibility(value < 100 ? View.VISIBLE : View.GONE);
            }
        });
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                if (!request.isForMainFrame()) return true;
                if (isAdminUrl(request.getUrl())) return false;
                openExternal(request.getUrl());
                return true;
            }
            @Override public void onPageFinished(WebView view, String url) {
                if (!mainFailed) notice.setText("لوحة المدير");
            }
            @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) fail();
            }
            @Override public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
                if (request.isForMainFrame()) fail();
            }
        });
        root.addView(web, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            root.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(), insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets.consumeSystemWindowInsets();
        });
        root.requestApplyInsets();
        loadAdmin();
    }

    private static boolean isAdminUrl(Uri uri) {
        return "https".equalsIgnoreCase(uri.getScheme()) && "fazaa-sat7a.github.io".equalsIgnoreCase(uri.getHost())
                && (uri.getPort() == -1 || uri.getPort() == 443) && uri.getUserInfo() == null
                && "/fazaa-sat7a/admin.html".equals(uri.getPath());
    }
    private void loadAdmin() {
        mainFailed = false;
        notice.setText("جاري تحميل لوحة المدير…");
        progress.setVisibility(View.VISIBLE);
        web.loadUrl(ADMIN_URL);
    }
    private void fail() {
        mainFailed = true;
        notice.setText("تعذّر تحميل لوحة المدير. تحقّق من الإنترنت ثم اضغط «إعادة تحميل». ");
        progress.setVisibility(View.GONE);
    }
    private void openExternal(Uri uri) {
        String scheme = uri.getScheme();
        Intent intent;
        if ("https".equalsIgnoreCase(scheme)) intent = new Intent(Intent.ACTION_VIEW, uri);
        else if ("tel".equalsIgnoreCase(scheme)) intent = new Intent(Intent.ACTION_DIAL, uri);
        else return;
        try { startActivity(intent); }
        catch (android.content.ActivityNotFoundException e) { Toast.makeText(this, "لا يوجد تطبيق مناسب لفتح الرابط.", Toast.LENGTH_LONG).show(); }
    }
    @Override protected void onPause() { web.onPause(); super.onPause(); }
    @Override protected void onResume() { super.onResume(); web.onResume(); }
    @Override protected void onDestroy() {
        web.stopLoading();
        web.setWebChromeClient(null);
        web.setWebViewClient(new WebViewClient());
        ((android.view.ViewGroup) web.getParent()).removeView(web);
        web.destroy();
        super.onDestroy();
    }
}
