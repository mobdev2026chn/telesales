package com.askeva.telesales_monitor

import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService

/**
 * Android binds this while AskEVA is the phone's Phone app (default dialer) and a call exists.
 * Everything is delegated to [CallManager] (state, Flutter call screen, notifications).
 *
 * It manages call signalling and control (ringing, answer, reject, end, hold, mute, speaker).
 * It does NOT grant access to the call audio.
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

    @Deprecated("Deprecated in Java")
    override fun onCallAudioStateChanged(audioState: CallAudioState?) {
        @Suppress("DEPRECATION")
        super.onCallAudioStateChanged(audioState)
        CallManager.onAudioStateChanged(audioState)
    }

    override fun onDestroy() {
        CallManager.clearAll()
        super.onDestroy()
    }
}
