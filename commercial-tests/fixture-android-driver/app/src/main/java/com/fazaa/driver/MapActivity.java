package com.fazaa.driver;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.location.Location;
import android.os.SystemClock;
import org.json.JSONArray;
import org.json.JSONObject;

/** Read-only map. No session tokens and no JavaScript bridge in this WebView. */
public final class MapActivity extends Activity {
    private WebView web;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable update = new Runnable() {
        @Override public void run() {
            try {
                JSONArray points = new JSONArray();
                Location location = ((DriverApp) getApplication()).location;
                if (location != null) {
                    boolean stale = SystemClock.elapsedRealtimeNanos() - location.getElapsedRealtimeNanos() > 90_000_000_000L;
                    points.put(Api.object("lat", location.getLatitude(), "lng", location.getLongitude(), "driver", true, "stale", stale));
                }
                if (getIntent().hasExtra("lat")) points.put(Api.object("lat", getIntent().getDoubleExtra("lat", 0), "lng", getIntent().getDoubleExtra("lng", 0), "driver", false));
                web.evaluateJavascript("window.setPoints && window.setPoints(" + points + ")", null);
            } catch (Exception ignored) { }
            handler.postDelayed(this, 5000);
        }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(Color.rgb(247,246,242)); root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        Button back = new Button(this); back.setText("العودة للطلبات"); back.setOnClickListener(v -> finish()); root.addView(back);
        TextView caption = new TextView(this); caption.setText("الأصفر: موقعك · الأزرق: العميل. الخرائط تحتاج إنترنت."); caption.setPadding(20,10,20,10); root.addView(caption);
        web = new WebView(this);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setGeolocationEnabled(false);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                if (!request.isForMainFrame()) return true;
                String scheme = request.getUrl().getScheme();
                if ("https".equals(scheme)) try { startActivity(new Intent(Intent.ACTION_VIEW, request.getUrl())); } catch (android.content.ActivityNotFoundException ignored) { }
                return true;
            }
            @Override public void onPageFinished(WebView view, String url) { handler.removeCallbacks(update); handler.post(update); }
        });
        root.addView(web, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            root.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(), insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets.consumeSystemWindowInsets();
        });
        root.requestApplyInsets();
        web.loadUrl("file:///android_asset/map.html");
    }
    @Override protected void onPause() { handler.removeCallbacks(update); super.onPause(); }
    @Override protected void onResume() { super.onResume(); handler.post(update); }
    @Override protected void onDestroy() { handler.removeCallbacks(update); web.destroy(); super.onDestroy(); }
}
