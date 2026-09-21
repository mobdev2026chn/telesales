package com.askeva.telesales_monitor

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray

/**
 * Native view of the signed-in session plus the call monitor's own per-device settings.
 *
 * The session is read straight from Flutter's shared_preferences file ("FlutterSharedPreferences",
 * keys prefixed "flutter.") so the service and the upload worker see login / logout / settings
 * changes even when the Flutter engine is not running. Keys written by lib/providers/tele_provider.dart.
 */
object CallMonitorStore {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val NATIVE_PREFS = "askeva_call_monitor"

    const val DEFAULT_BASE_URL = "https://telesales.askeva.io/api"

    private const val KEY_BASE_URL = "base_url"
    private const val KEY_NATIVE_RECORDER = "native_recorder_detected"
    private const val KEY_MISSES = "native_recorder_misses"
    private const val KEY_USED = "used_builtin_files"
    private const val KEY_AUTH_FAILED_TOKEN = "auth_failed_token"

    /** Consecutive connected calls without a built-in file before we record ourselves again. */
    const val MISSES_BEFORE_RESET = 3

    data class Session(
        val token: String,
        val userId: String,
        val callerName: String,
        val callerPhone: String,
        val autoRecord: Boolean,
        /** "sim1Only" | "sim2Only" | "bothSims" (SimTrackingMode.name in Dart). */
        val simMode: String,
        /** A caller, or a manager in caller mode. */
        val isCallerContext: Boolean,
    )

    private fun flutterPrefs(ctx: Context) = ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
    private fun prefs(ctx: Context) = ctx.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)

    private fun readString(all: Map<String, *>, key: String, def: String = ""): String =
        (all["flutter.$key"] as? String) ?: def

    private fun readBool(all: Map<String, *>, key: String, def: Boolean): Boolean =
        (all["flutter.$key"] as? Boolean) ?: def

    /** The signed-in user (any role), or null when nobody is signed in with a real token. */
    fun session(ctx: Context): Session? {
        return try {
            val all = flutterPrefs(ctx).all
            if (!readBool(all, "is_logged_in", false)) return null
            val token = readString(all, "auth_token")
            val userId = readString(all, "current_user_id")
            if (token.isEmpty() || token.startsWith("jwt_") || userId.isEmpty()) return null
            val role = readString(all, "user_role", "caller")
            Session(
                token = token,
                userId = userId,
                callerName = readString(all, "caller_name"),
                callerPhone = readString(all, "verified_tracking_number"),
                autoRecord = readBool(all, "auto_record_enabled", true),
                simMode = readString(all, "sim_tracking_mode", "bothSims"),
                isCallerContext = role == "caller" || readBool(all, "manager_caller_mode", false),
            )
        } catch (_: Exception) {
            null
        }
    }

    /** Session in which calls are recorded / uploaded: a caller context with auto-record on. */
    fun recordingSession(ctx: Context): Session? {
        val s = session(ctx) ?: return null
        return if (s.isCallerContext && s.autoRecord) s else null
    }

    /**
     * Only calls on the registered (work) SIM are tracked, recorded and uploaded.
     * Slot 0 = the phone could not tell which SIM carried the call: kept only when both SIMs are
     * tracked or the phone has a single SIM; on a dual-SIM phone it may be the personal SIM, so it is
     * dropped (same rule as the Dart code).
     */
    fun isWorkSim(slot: Int, simMode: String, activeSimCount: Int): Boolean {
        if (slot <= 0) return simMode == "bothSims" || activeSimCount <= 1
        return when (simMode) {
            "sim1Only" -> slot == 1
            "sim2Only" -> slot == 2
            else -> true
        }
    }

    fun baseUrl(ctx: Context): String =
        prefs(ctx).getString(KEY_BASE_URL, null)?.takeIf { it.startsWith("http") } ?: DEFAULT_BASE_URL

    fun setBaseUrl(ctx: Context, url: String) {
        if (url.startsWith("http")) prefs(ctx).edit().putString(KEY_BASE_URL, url.trimEnd('/')).apply()
    }

    fun nativeRecorderDetected(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_NATIVE_RECORDER, false)

    /**
     * Test override for the recorder's AudioSource (MediaRecorder.AudioSource constant; -1 = automatic).
     * Set on a debug build with:
     *   adb shell run-as com.askeva.telesales_monitor ... (edit shared_prefs/askeva_call_monitor.xml)
     */
    fun forcedAudioSource(ctx: Context): Int = prefs(ctx).getInt("forced_audio_source", -1)

    // ---- Mic source calibration ------------------------------------------------------------------
    // Phones differ in which AudioSource still hears a call. Until one produces real speech, each
    // connected work call tries the next candidate; the first that works is kept for this phone.

    /** MediaRecorder.AudioSource values: VOICE_RECOGNITION, VOICE_COMMUNICATION, MIC, UNPROCESSED, CAMCORDER. */
    val SOURCE_CANDIDATES = intArrayOf(6, 7, 1, 9, 5)

    fun sourceName(source: Int): String = when (source) {
        1 -> "MIC"; 5 -> "CAMCORDER"; 6 -> "VOICE_RECOGNITION"; 7 -> "VOICE_COMMUNICATION"
        9 -> "UNPROCESSED"; -1 -> "NONE"; else -> "SOURCE_$source"
    }

    fun lockedSource(ctx: Context): Int = prefs(ctx).getInt("locked_audio_source", -1)

    /** Source to use for the next call, and whether it is "forced" / "locked" / "trial". */
    fun chooseSource(ctx: Context): Pair<Int, String> {
        val forced = forcedAudioSource(ctx)
        if (forced >= 0) return forced to "forced"
        val locked = lockedSource(ctx)
        if (locked >= 0) return locked to "locked"
        val i = prefs(ctx).getInt("source_trial_index", 0)
        return SOURCE_CANDIDATES[Math.floorMod(i, SOURCE_CANDIDATES.size)] to "trial"
    }

    /** Result of one connected call recorded with [source]. */
    fun reportSourceResult(ctx: Context, source: Int, heardSpeech: Boolean) {
        if (forcedAudioSource(ctx) >= 0 || source < 0) return
        val p = prefs(ctx)
        if (heardSpeech) {
            p.edit().putInt("locked_audio_source", source).putInt("locked_source_silent_calls", 0).apply()
            return
        }
        if (lockedSource(ctx) == source) {
            // A source that worked went silent twice in a row (e.g. OS update): calibrate again
            val silent = p.getInt("locked_source_silent_calls", 0) + 1
            if (silent >= 2) {
                p.edit().remove("locked_audio_source").putInt("locked_source_silent_calls", 0).apply()
            } else {
                p.edit().putInt("locked_source_silent_calls", silent).apply()
            }
            return
        }
        val idx = SOURCE_CANDIDATES.indexOf(source)
        p.edit().putInt("source_trial_index", if (idx >= 0) idx + 1 else p.getInt("source_trial_index", 0) + 1).apply()
    }

    /** Outcome of our own recording for the last connected work call: "ok" | "silent". */
    fun setLastCapture(ctx: Context, status: String, source: Int) {
        prefs(ctx).edit()
            .putString("last_capture_status", status)
            .putInt("last_capture_source", source)
            .putLong("last_capture_at", System.currentTimeMillis())
            .apply()
    }

    fun lastCaptureStatus(ctx: Context): String = prefs(ctx).getString("last_capture_status", "") ?: ""
    fun lastCaptureAt(ctx: Context): Long = prefs(ctx).getLong("last_capture_at", 0L)

    /** A built-in file was found for a call: trust the OEM recorder from now on. */
    fun onBuiltInFound(ctx: Context, vararg keys: String) {
        val used = usedBuiltInFiles(ctx).toMutableList()
        for (key in keys) {
            used.remove(key)
            used.add(key)
        }
        while (used.size > 200) used.removeAt(0)
        prefs(ctx).edit()
            .putBoolean(KEY_NATIVE_RECORDER, true)
            .putInt(KEY_MISSES, 0)
            .putString(KEY_USED, JSONArray(used).toString())
            .apply()
    }

    /** A connected call ended without a built-in file. Returns true when the flag was just reset. */
    fun onBuiltInMissing(ctx: Context): Boolean {
        val p = prefs(ctx)
        if (!p.getBoolean(KEY_NATIVE_RECORDER, false)) return false
        val misses = p.getInt(KEY_MISSES, 0) + 1
        return if (misses >= MISSES_BEFORE_RESET) {
            p.edit().putBoolean(KEY_NATIVE_RECORDER, false).putInt(KEY_MISSES, 0).apply()
            true
        } else {
            p.edit().putInt(KEY_MISSES, misses).apply()
            false
        }
    }

    fun usedBuiltInFiles(ctx: Context): List<String> {
        return try {
            val arr = JSONArray(prefs(ctx).getString(KEY_USED, "[]"))
            (0 until arr.length()).map { arr.getString(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** The token the server rejected with 401: uploads pause until a new login replaces it. */
    /** Start of the signed-in work session (calls before it are personal and never sent). Null = unknown. */
    fun loginSessionMs(ctx: Context): Long? = try {
        (flutterPrefs(ctx).all["flutter.login_session_timestamp_ms"] as? Number)?.toLong()?.takeIf { it > 0 }
    } catch (_: Exception) { null }

    /** Newest call-log time the server accepted from the call monitor, per user. */
    fun callPushAck(ctx: Context, userId: String): Long = prefs(ctx).getLong("call_push_ack_ms_$userId", 0L)
    fun setCallPushAck(ctx: Context, userId: String, ms: Long) {
        prefs(ctx).edit().putLong("call_push_ack_ms_$userId", ms).apply()
    }

    fun authFailedToken(ctx: Context): String = prefs(ctx).getString(KEY_AUTH_FAILED_TOKEN, "") ?: ""
    fun setAuthFailedToken(ctx: Context, token: String) {
        prefs(ctx).edit().putString(KEY_AUTH_FAILED_TOKEN, token).apply()
    }

    fun hasPermission(ctx: Context, perm: String): Boolean =
        ContextCompat.checkSelfPermission(ctx, perm) == PackageManager.PERMISSION_GRANTED

    fun mediaReadPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    fun hasMediaPermission(ctx: Context): Boolean = hasPermission(ctx, mediaReadPermission())

    // ------------------------------------------------------------------ Notifications

    const val CHANNEL_TRACKING = "askeva_call_tracking"
    const val CHANNEL_ALERTS = "askeva_call_alerts"
    const val NOTIF_ID_SERVICE = 9101
    const val NOTIF_ID_LOGIN = 9102
    const val NOTIF_ID_RESUME = 9103
    const val NOTIF_ID_RECORDING = 9104

    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_TRACKING, "Call tracking", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while AskEVA tracks and uploads work call recordings"
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ALERTS, "Call tracking alerts", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Problems that stop call recordings from being uploaded"
            }
        )
    }

    fun openAppIntent(ctx: Context): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(ctx, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    fun postAlert(ctx: Context, id: Int, title: String, text: String) {
        try {
            ensureChannels(ctx)
            if (Build.VERSION.SDK_INT >= 33 && !hasPermission(ctx, Manifest.permission.POST_NOTIFICATIONS)) return
            val n = NotificationCompat.Builder(ctx, CHANNEL_ALERTS)
                .setSmallIcon(android.R.drawable.stat_notify_error)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setContentIntent(openAppIntent(ctx))
                .setAutoCancel(true)
                .build()
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(id, n)
        } catch (_: Exception) {}
    }

    fun cancelNotification(ctx: Context, id: Int) {
        try {
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(id)
        } catch (_: Exception) {}
    }
}

/**
 * Events from the service / upload worker to Dart. [MainActivity] installs [listener] while its
 * Flutter engine is alive; with no listener events are dropped (Dart re-reads state on resume).
 */
object CallMonitorEvents {
    @Volatile var listener: ((String, Map<String, Any?>) -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())

    fun emit(method: String, args: Map<String, Any?> = emptyMap()) {
        main.post {
            try { listener?.invoke(method, args) } catch (_: Exception) {}
        }
    }
}
