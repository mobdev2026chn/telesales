package com.askeva.telesales_monitor

import android.content.Context
import android.os.Build
import android.telecom.TelecomManager
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
            item.put("accessibilityEnabled", CallAccessibilityService.isEnabled(ctx))
            item.put("dialerPackage", try {
                (ctx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).defaultDialerPackage ?: ""
            } catch (_: Exception) { "" })
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
