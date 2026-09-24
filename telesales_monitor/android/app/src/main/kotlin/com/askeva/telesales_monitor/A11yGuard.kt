package com.askeva.telesales_monitor

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import android.util.Log

/**
 * Keeps the "AskEVA Call Recording" accessibility service on.
 *
 * Phones switch it off when they kill or force-stop the app (battery managers, cleaners, Play
 * Protect). An app cannot switch it back on by itself, except when the one-time permission
 * WRITE_SECURE_SETTINGS was granted from a computer:
 *   adb shell pm grant com.askeva.telesales_monitor android.permission.WRITE_SECURE_SETTINGS
 * With it, [ensureEnabled] turns the service back on; without it, [check] tells the caller.
 */
object A11yGuard {
    private const val TAG = "AskEvaA11yGuard"
    private const val ALERT_EVERY_MS = 60 * 60 * 1000L
    @Volatile private var lastAlertAtMs = 0L

    fun canSelfRepair(ctx: Context): Boolean =
        ctx.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    /** True when the service is on (after switching it back on if we are allowed to). */
    fun ensureEnabled(ctx: Context): Boolean {
        if (CallAccessibilityService.isEnabled(ctx)) return true
        if (!canSelfRepair(ctx)) return false
        return try {
            val me = ComponentName(ctx, CallAccessibilityService::class.java)
            val resolver = ctx.contentResolver
            val current = Settings.Secure.getString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
            // Keep every other enabled service exactly as it is
            val others = current.split(':').filter { entry ->
                if (entry.isBlank()) return@filter false
                val cn = ComponentName.unflattenFromString(entry)
                !(cn != null && cn.packageName == me.packageName && cn.className == me.className)
            }
            Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, (others + me.flattenToString()).joinToString(":"))
            Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
            Log.i(TAG, "accessibility service switched back on")
            CallMonitorStore.cancelNotification(ctx, CallMonitorStore.NOTIF_ID_A11Y)
            CallAccessibilityService.isEnabled(ctx)
        } catch (e: Exception) {
            Log.w(TAG, "could not switch the accessibility service on", e)
            false
        }
    }

    /**
     * Repairs the service if possible; otherwise, when the app itself has to record calls (no
     * trusted built-in recorder), reminds the caller at most once an hour.
     */
    fun check(ctx: Context) {
        try {
            if (ensureEnabled(ctx)) {
                CallMonitorStore.cancelNotification(ctx, CallMonitorStore.NOTIF_ID_A11Y)
                return
            }
            if (CallMonitorStore.recordingSession(ctx) == null) return
            if (CallMonitorStore.nativeRecorderDetected(ctx) && CallMonitorStore.hasMediaPermission(ctx)) return
            val now = System.currentTimeMillis()
            if (now - lastAlertAtMs < ALERT_EVERY_MS) return
            lastAlertAtMs = now
            CallMonitorStore.postAlert(
                ctx, CallMonitorStore.NOTIF_ID_A11Y,
                "Call recording is switched off",
                "Your phone turned off \"AskEVA Call Recording\" in Accessibility, so calls are recorded " +
                    "without sound. Tap, then open Call recording setup and switch it back on."
            )
        } catch (_: Exception) {}
    }
}
