package com.askeva.telesales_monitor

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Per-call recording diagnostics (no audio, no phone numbers): which mic source was used, how much
 * speech it heard, whether the accessibility exemption is on, and the phone model / dialer.
 * Queued in a small file and sent to POST /api/diagnostics/recording by the upload worker, so
 * silent-recording problems on a phone can be investigated without a USB cable.
 */
object RecordingDiagnostics {
    private const val MAX_QUEUED = 50
    private val lock = Any()

    private fun file(ctx: Context) = File(ctx.filesDir, "recording_diagnostics.json")

    /** "1.0.6 (7)": lets admins see which phones still run an old build. */
    private fun appVersion(ctx: Context): String = try {
        val pi = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) pi.longVersionCode
        else @Suppress("DEPRECATION") pi.versionCode.toLong()
        "${pi.versionName} ($code)"
    } catch (_: Exception) {
        ""
    }

    private fun readLocked(ctx: Context): JSONArray = try {
        val f = file(ctx)
        if (f.exists()) JSONArray(f.readText()) else JSONArray()
    } catch (_: Exception) {
        JSONArray()
    }

    fun add(ctx: Context, item: JSONObject) = synchronized(lock) {
        try {
            item.put("at", System.currentTimeMillis())
            item.put("manufacturer", Build.MANUFACTURER)
            item.put("brand", Build.BRAND)
            item.put("model", Build.MODEL)
            item.put("sdkInt", Build.VERSION.SDK_INT)
            item.put("appVersion", appVersion(ctx))
            item.put("accessibilityEnabled", CallAccessibilityService.isEnabled(ctx))
            val dialer = DeviceSetupHelper.defaultDialerPackage(ctx)
            item.put("dialerPackage", dialer)
            // Phone by Google: whether switching to the phone's own Phone app would fix recording
            if (dialer == DeviceSetupHelper.GOOGLE_DIALER) item.put("builtInDialer", DeviceSetupHelper.builtInDialer(ctx) != null)
            val arr = readLocked(ctx)
            arr.put(item)
            val trimmed = JSONArray()
            val from = maxOf(0, arr.length() - MAX_QUEUED)
            for (i in from until arr.length()) trimmed.put(arr.get(i))
            file(ctx).writeText(trimmed.toString())
        } catch (_: Exception) {}
    }

    /** Sends queued diagnostics; clears them on success. Never throws. */
    fun send(ctx: Context, base: String, token: String) {
        val items = synchronized(lock) { readLocked(ctx) }
        if (items.length() == 0) return
        var conn: HttpURLConnection? = null
        try {
            conn = (URL("$base/diagnostics/recording").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000
                readTimeout = 20_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
            }
            conn.outputStream.use { it.write(JSONObject().put("items", items).toString().toByteArray()) }
            if (conn.responseCode in 200..299) {
                synchronized(lock) {
                    // Keep anything added while we were sending
                    val now = readLocked(ctx)
                    val rest = JSONArray()
                    for (i in items.length() until now.length()) rest.put(now.get(i))
                    file(ctx).writeText(rest.toString())
                }
            }
        } catch (_: Exception) {
        } finally {
            conn?.disconnect()
        }
    }
}
