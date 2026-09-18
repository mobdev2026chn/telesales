package com.askeva.telesales_monitor

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Exists only so Android lets this app capture audio during a phone call.
 *
 * Since Android 10 the system hands ordinary apps silence while a call is active; apps with an
 * enabled accessibility service are exempt. This service reads no screen content, performs no
 * actions and subscribes to no useful events: recording itself still happens in
 * [CallMonitorService] / [CallRecorder]. Only suitable for directly installed (non-Play) builds.
 */
class CallAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Intentionally empty: no screen content is read.
    }

    override fun onInterrupt() {}

    companion object {
        private const val TAG = "AskEvaA11y"

        /** Whether the user has switched this service on in Settings > Accessibility. */
        fun isEnabled(ctx: Context): Boolean {
            return try {
                val enabled = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
                val me = ComponentName(ctx, CallAccessibilityService::class.java)
                enabled.split(':').any { entry ->
                    val cn = ComponentName.unflattenFromString(entry)
                    cn != null && cn.packageName == me.packageName && cn.className == me.className
                }
            } catch (_: Exception) {
                false
            }
        }
    }
}
