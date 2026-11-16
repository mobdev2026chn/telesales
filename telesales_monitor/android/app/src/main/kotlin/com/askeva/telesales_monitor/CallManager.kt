package com.askeva.telesales_monitor

import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.telecom.VideoProfile
import io.flutter.plugin.common.EventChannel

/**
 * Singleton managing cellular SIM call state and lifecycle.
 * Coordinates between [AskEvaInCallService], [MainActivity], and Flutter via EventChannel.
 *
 * Keeps all call management logic clean and strictly separate from MainActivity.
 */
object CallManager {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    // Reference to the active cellular call
    var activeCall: Call? = null
        private set

    // Reference to the InCallService for audio route controls
    private var inCallService: InCallService? = null

    private val callCallback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            super.onStateChanged(call, state)
            dispatchCallState(call, state)
        }

        override fun onDetailsChanged(call: Call, details: Call.Details) {
            super.onDetailsChanged(call, details)
            dispatchCallDetails(call, details)
        }
    }

    /**
     * Attaches the Flutter EventSink for streaming real-time call events.
     */
    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        // If there's an ongoing call when the channel attaches, notify Flutter
        activeCall?.let {
            dispatchCallState(it, it.state)
        }
    }

    /**
     * Called by AskEvaInCallService when a new cellular call is registered.
     */
    fun registerCall(call: Call, service: InCallService) {
        inCallService = service
        activeCall?.unregisterCallback(callCallback)
        activeCall = call
        call.registerCallback(callCallback)
        dispatchCallState(call, call.state)
    }

    /**
     * Called by AskEvaInCallService when a cellular call is terminated.
     */
    fun unregisterCall(call: Call) {
        if (activeCall == call) {
            dispatchCallState(call, Call.STATE_DISCONNECTED)
            call.unregisterCallback(callCallback)
            activeCall = null
            inCallService = null
        }
    }

    /**
     * Answers an incoming cellular call.
     */
    fun answerCall(): Boolean {
        val call = activeCall ?: return false
        return try {
            call.answer(VideoProfile.STATE_AUDIO_ONLY)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Rejects an incoming cellular call.
     */
    fun rejectCall(): Boolean {
        val call = activeCall ?: return false
        return try {
            call.reject(false, null)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Disconnects / ends an ongoing cellular call.
     */
    fun disconnectCall(): Boolean {
        val call = activeCall ?: return false
        return try {
            call.disconnect()
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Toggles mute state via InCallService.
     */
    fun setMuted(muted: Boolean): Boolean {
        val service = inCallService ?: return false
        return try {
            service.setMuted(muted)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Toggles speakerphone audio route via InCallService.
     */
    fun setSpeaker(speaker: Boolean): Boolean {
        val service = inCallService ?: return false
        return try {
            val route = if (speaker) CallAudioState.ROUTE_SPEAKER else CallAudioState.ROUTE_EARPIECE
            service.setAudioRoute(route)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun dispatchCallState(call: Call, stateInt: Int) {
        val stateString = mapStateToString(stateInt)
        val handle = call.details?.handle?.schemeSpecificPart ?: ""
        val callerName = call.details?.callerDisplayName ?: ""
        val isIncoming = (stateInt == Call.STATE_RINGING) ||
            (call.details?.hasProperty(Call.Details.PROPERTY_IS_EXTERNAL_CALL) == true)

        val payload = mapOf(
            "event" to "callStateChanged",
            "state" to stateString,
            "phoneNumber" to handle,
            "displayName" to callerName,
            "isIncoming" to isIncoming,
            "timestamp" to System.currentTimeMillis()
        )

        sendEvent(payload)
    }

    private fun dispatchCallDetails(call: Call, details: Call.Details) {
        val handle = details.handle?.schemeSpecificPart ?: ""
        val callerName = details.callerDisplayName ?: ""

        val payload = mapOf(
            "event" to "callDetailsChanged",
            "state" to mapStateToString(call.state),
            "phoneNumber" to handle,
            "displayName" to callerName,
            "timestamp" to System.currentTimeMillis()
        )

        sendEvent(payload)
    }

    private fun sendEvent(data: Map<String, Any?>) {
        mainHandler.post {
            try {
                eventSink?.success(data)
            } catch (_: Exception) {
                // EventSink was detached or cancelled
            }
        }
    }

    private fun mapStateToString(state: Int): String {
        return when (state) {
            Call.STATE_NEW -> "NEW"
            Call.STATE_RINGING -> "RINGING"
            Call.STATE_DIALING -> "DIALING"
            Call.STATE_CONNECTING -> "CONNECTING"
            Call.STATE_ACTIVE -> "ACTIVE"
            Call.STATE_HOLDING -> "HOLDING"
            Call.STATE_DISCONNECTING -> "DISCONNECTING"
            Call.STATE_DISCONNECTED -> "DISCONNECTED"
            else -> "UNKNOWN"
        }
    }
}
