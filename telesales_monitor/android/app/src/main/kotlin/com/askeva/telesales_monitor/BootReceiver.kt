package com.askeva.telesales_monitor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * After a reboot or an app update the call monitor is not running, and Android 14+ forbids
 * starting a microphone foreground service from the background. So we remind the caller to open
 * the app (which restarts tracking), resume any pending uploads, and let [CallSyncWorker] keep the
 * call list and the phone's own recordings flowing until then. Follow-up reminders are set again.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        // Alarms do not survive a reboot
        try { CallbackReminders.rescheduleAll(context) } catch (_: Exception) {}
        if (CallMonitorStore.session(context) == null) return
        RecordingUploader.schedule(context)
        CallSyncWorker.schedule(context)
        if (CallMonitorStore.recordingSession(context) != null && !CallMonitorService.isRunning) {
            CallMonitorStore.postAlert(
                context, CallMonitorStore.NOTIF_ID_RESUME,
                "Open AskEVA to resume call tracking",
                "Tap to open AskEVA so your work calls are tracked and their recordings uploaded."
            )
        }
    }
}
