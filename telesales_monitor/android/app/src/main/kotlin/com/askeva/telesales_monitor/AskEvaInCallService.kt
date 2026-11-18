package com.askeva.telesales_monitor

import android.telecom.Call
import android.telecom.InCallService

/**
 * Native Android InCallService for AskEVA.
 * The Android Telecom framework binds to this service when a cellular phone call
 * is created, received, or disconnected.
 *
 * All state management and Flutter bridging are delegated cleanly to [CallManager].
 *
 * Notice: This service manages call signaling and control (ringing, answer, reject, end).
 * It does NOT grant access to the raw cellular audio stream.
 */
class AskEvaInCallService : InCallService() {

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        CallManager.registerCall(call, this)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        CallManager.unregisterCall(call)
    }

    override fun onDestroy() {
        super.onDestroy()
        CallManager.activeCall?.let {
            CallManager.unregisterCall(it)
        }
    }
}
