package com.askeva.telesales_monitor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * After a reboot or an app update the call monitor is not running, and Android 14+ forbids
 * starting a microphone foreground service from the background. So we only remind the caller
 * to open the app (which restarts tracking) and resume any pending uploads.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (CallMonitorStore.session(context) == null) return
        RecordingUploader.schedule(context)
        if (CallMonitorStore.recordingSession(context) != null && !CallMonitorService.isRunning) {
            CallMonitorStore.postAlert(
                context, CallMonitorStore.NOTIF_ID_RESUME,
                "Open AskEVA to resume call tracking",
                "Tap to open AskEVA so your work calls are tracked and their recordings uploaded."
            )
        }
    }
}
