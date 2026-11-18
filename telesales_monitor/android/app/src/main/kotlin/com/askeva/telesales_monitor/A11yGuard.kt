package com.askeva.telesales_monitor

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * Keeps the "AskEVA Call Recording" accessibility service on ONLY while it is needed: during work calls.
 *
 * Payment apps (GPay, PhonePe, bank apps) refuse to run while a third-party accessibility service is on,
 * so the service must not stay on all day. It is needed only while AskEVA records a call itself (in-call
 * microphone + loudspeaker tap); a phone whose own dialer recording AskEVA uploads does not need it at all.
 *
 *  - Switched on when a call starts ([onCallStarting]: Call button in the app, ringing, off-hook) and off
 *    again once the call has been processed ([onCallFinished]). Both need the one-time permission
 *    WRITE_SECURE_SETTINGS, granted from a computer:
 *      adb shell pm grant com.askeva.telesales_monitor android.permission.WRITE_SECURE_SETTINGS
 *  - Without that permission the app cannot switch the service back on, so it only switches itself off
 *    ([CallAccessibilityService.ACTION_DISABLE]) when the phone's own recorder makes it unnecessary.
 *    Otherwise the caller keeps it on and [check] says why payments may be blocked.
 */
object A11yGuard {
    private const val TAG = "AskEvaA11yGuard"
    private const val ALERT_EVERY_MS = 60 * 60 * 1000L
    @Volatile private var lastAlertAtMs = 0L

    fun canSelfRepair(ctx: Context): Boolean =
        ctx.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    /** The phone's own recorder is trusted: AskEVA uploads its files and needs no accessibility service. */
    fun builtInTrusted(ctx: Context): Boolean =
        CallMonitorStore.nativeRecorderDetected(ctx) && CallMonitorStore.hasMediaPermission(ctx)

    /** Recording is covered on this phone without the user keeping the service on all the time. */
    fun managedOrNotNeeded(ctx: Context): Boolean = canSelfRepair(ctx) || builtInTrusted(ctx)

    /** A work call is starting: switch the service on (when allowed) so the call can be recorded. */
    fun onCallStarting(ctx: Context) {
        ensureEnabled(ctx)
    }

    /**
     * A call has been processed and no other call is active: switch the service off again so payment
     * apps work, when the app can switch it back on at the next call or does not need it at all.
     */
    fun onCallFinished(ctx: Context) {
        if (!CallAccessibilityService.isEnabled(ctx)) return
        when {
            canSelfRepair(ctx) -> disable(ctx)
            builtInTrusted(ctx) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N -> {
                // Not needed on this phone and cannot be written from here: the service turns itself off
                Log.i(TAG, "phone's own recorder is used: asking the accessibility service to switch off")
                SpeakerAssist.send(ctx, Intent(CallAccessibilityService.ACTION_DISABLE))
            }
        }
    }

    /** True when the service is on (after switching it on if we are allowed to). */
    fun ensureEnabled(ctx: Context): Boolean {
        if (CallAccessibilityService.isEnabled(ctx)) return true
        if (!canSelfRepair(ctx)) return false
        return try {
            val me = ComponentName(ctx, CallAccessibilityService::class.java)
            val resolver = ctx.contentResolver
            Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, (others(ctx) + me.flattenToString()).joinToString(":"))
            Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
            Log.i(TAG, "accessibility service switched on for a call")
            CallMonitorStore.cancelNotification(ctx, CallMonitorStore.NOTIF_ID_A11Y)
            CallAccessibilityService.isEnabled(ctx)
        } catch (e: Exception) {
            Log.w(TAG, "could not switch the accessibility service on", e)
            false
        }
    }

    /** Removes only our service; every other enabled service stays exactly as it was. */
    private fun disable(ctx: Context) {
        try {
            val resolver = ctx.contentResolver
            val rest = others(ctx)
            Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, rest.joinToString(":"))
            if (rest.isEmpty()) Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0)
            Log.i(TAG, "accessibility service switched off after the call")
        } catch (e: Exception) {
            Log.w(TAG, "could not switch the accessibility service off", e)
        }
    }

    private fun others(ctx: Context): List<String> {
        val me = ComponentName(ctx, CallAccessibilityService::class.java)
        val current = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
        return current.split(':').filter { entry ->
            if (entry.isBlank()) return@filter false
            val cn = ComponentName.unflattenFromString(entry)
            !(cn != null && cn.packageName == me.packageName && cn.className == me.className)
        }
    }

    /**
     * Heartbeat (every 2 minutes). Never switches the service on outside a call (that would block payment
     * apps); only reminds the caller, at most once an hour, when AskEVA records calls itself, cannot switch
     * the service on by itself, and the caller has turned it off.
     */
    fun check(ctx: Context) {
        try {
            if (CallMonitorStore.recordingSession(ctx) == null) return
            if (CallAccessibilityService.isEnabled(ctx) || managedOrNotNeeded(ctx)) {
                CallMonitorStore.cancelNotification(ctx, CallMonitorStore.NOTIF_ID_A11Y)
                return
            }
            val now = System.currentTimeMillis()
            if (now - lastAlertAtMs < ALERT_EVERY_MS) return
            lastAlertAtMs = now
            CallMonitorStore.postAlert(
                ctx, CallMonitorStore.NOTIF_ID_A11Y,
                "Call recording is switched off",
                "\"AskEVA Call Recording\" is off in Accessibility, so calls are recorded without sound. " +
                    "Tap, then turn on recording."
            )
        } catch (_: Exception) {}
    }
}
