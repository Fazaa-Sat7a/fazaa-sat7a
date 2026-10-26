package com.fazaa.driver;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** One serialized session owner. No service-role key, passwords, or session logging. */
final class Api {
    private static final String BASE = "https://gngkiscujlpyuukbwvkv.supabase.co";
    private static final String PUBLIC_KEY = "sb_publishable_fwrKy1b3DfcILKogtOPbCQ_-trexLNR";
    private static final String KEY_ALIAS = "fazaa.driver.session.v1";
    private final SharedPreferences preferences;
    private volatile JSONObject session;

    Api(Context context) {
        preferences = context.getSharedPreferences("private_session", Context.MODE_PRIVATE);
        try {
            String encoded = preferences.getString("sealed", null);
            if (encoded != null) {
                JSONObject sealed = new JSONObject(encoded);
                Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(sealed.getString("iv"), Base64.NO_WRAP)));
                session = new JSONObject(new String(cipher.doFinal(Base64.decode(sealed.getString("data"), Base64.NO_WRAP)), StandardCharsets.UTF_8));
            }
        } catch (Exception ignored) { clear(); }
    }

    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (store.containsAlias(KEY_ALIAS)) return (SecretKey) store.getKey(KEY_ALIAS, null);
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }

    private void save(JSONObject value) throws Exception {
        // Auth responses do not always contain expires_at outside the JS SDK.
        value.put("expires_at", System.currentTimeMillis() / 1000L + value.optLong("expires_in", 3600));
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key());
        byte[] data = cipher.doFinal(value.toString().getBytes(StandardCharsets.UTF_8));
        JSONObject sealed = object("iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP), "data", Base64.encodeToString(data, Base64.NO_WRAP));
        if (!preferences.edit().putString("sealed", sealed.toString()).commit()) throw new Exception("تعذّر حفظ جلسة الدخول على الهاتف.");
        session = value;
    }

    boolean signedIn() { return session != null; }
    String userId() throws Exception { if (session == null) throw new Exception("سجّل الدخول أولاً."); return session.getJSONObject("user").getString("id"); }
    void clear() { session = null; preferences.edit().clear().commit(); }

    void login(String email, String password) throws Exception {
        save((JSONObject) request("POST", "/auth/v1/token?grant_type=password", object("email", email, "password", password), null));
    }

    private String token(boolean force) throws Exception {
        if (session == null) throw new Exception("انتهت الجلسة. سجّل الدخول مجدداً.");
        if (force || session.optLong("expires_at") < System.currentTimeMillis() / 1000L + 90) {
            try {
                save((JSONObject) request("POST", "/auth/v1/token?grant_type=refresh_token", object("refresh_token", session.getString("refresh_token")), null));
            } catch (HttpError e) {
                if (e.code == 400 || e.code == 401 || e.code == 403) { clear(); throw new Exception("انتهت الجلسة. سجّل الدخول مجدداً."); }
                throw e;
            }
        }
        return session.getString("access_token");
    }

    Object authorized(String method, String path, JSONObject body) throws Exception {
        String access = token(false);
        try { return request(method, path, body, access); }
        catch (HttpError e) { if (e.code != 401) throw e; return request(method, path, body, token(true)); }
    }

    Object rpc(String name, JSONObject body) throws Exception { return authorized("POST", "/rest/v1/rpc/" + name, body); }
    JSONObject profile() throws Exception {
        JSONArray rows = (JSONArray) authorized("GET", "/rest/v1/drivers?select=id,name,phone,plate,area,status,is_available&id=eq." + userId(), null);
        if (rows.length() == 0) throw new Exception("هذا الحساب غير مسجّل كسائق. استخدم حساب السائق.");
        return rows.getJSONObject(0);
    }

    private Object request(String method, String path, JSONObject body, String access) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(BASE + path).openConnection();
        connection.setRequestMethod(method);
        connection.setConnectTimeout(12000);
        connection.setReadTimeout(path.equals("/functions/v1/driver-route") ? 25000 : 12000);
        connection.setInstanceFollowRedirects(false);
        connection.setRequestProperty("apikey", PUBLIC_KEY);
        connection.setRequestProperty("Accept", "application/json");
        if (access != null) connection.setRequestProperty("Authorization", "Bearer " + access);
        try {
            if (body != null) {
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
                try (java.io.OutputStream output = connection.getOutputStream()) { output.write(body.toString().getBytes(StandardCharsets.UTF_8)); }
            }
            int status = connection.getResponseCode();
            String text;
            try (InputStream input = status >= 200 && status < 300 ? connection.getInputStream() : connection.getErrorStream()) {
                java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
                if (input != null) { byte[] buffer = new byte[4096]; int count; while ((count = input.read(buffer)) != -1) bytes.write(buffer, 0, count); }
                text = new String(bytes.toByteArray(), StandardCharsets.UTF_8);
            }
            if (status < 200 || status >= 300) {
                String reason = "تعذّر الاتصال بالخادم (" + status + ").";
                try {
                    JSONObject error = new JSONObject(text);
                    reason = error.optString("message", error.optString("msg", error.optString("error_description", error.optString("error", reason))));
                } catch (Exception ignored) { }
                throw new HttpError(status, reason);
            }
            if (text.isEmpty() || text.equals("null")) return JSONObject.NULL;
            return new org.json.JSONTokener(text).nextValue();
        } catch (java.io.IOException e) { throw new Exception("تعذّر الاتصال. تأكّد من الإنترنت؛ سنعيد المحاولة."); }
        finally { connection.disconnect(); }
    }

    static JSONObject object(Object... pairs) throws org.json.JSONException {
        JSONObject value = new JSONObject();
        for (int i = 0; i < pairs.length; i += 2) value.put((String) pairs[i], pairs[i + 1]);
        return value;
    }
    static final class HttpError extends Exception {
        final int code;
        HttpError(int code, String message) { super(message); this.code = code; }
    }
}
