package com.askeva.telesales_monitor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Decline / Hang up buttons of the call notifications ([CallUi]). Not exported. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_DECLINE -> CallManager.rejectCall()
            ACTION_HANG_UP -> CallManager.disconnectCall()
        }
    }

    companion object {
        const val ACTION_DECLINE = "com.askeva.telesales_monitor.CALL_DECLINE"
        const val ACTION_HANG_UP = "com.askeva.telesales_monitor.CALL_HANG_UP"
    }
}
