package com.askeva.telesales_monitor

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.util.IdentityHashMap

/**
 * The SIM calls Android hands to AskEVA while it is the phone's Phone app ([AskEvaInCallService]).
 * Keeps every call, picks the one the call screen shows, streams it to Flutter (EventChannel
 * "com.askeva.telesales/call_events"), keeps the call notification ([CallUi]) up to date and runs
 * the call screen's buttons.
 *
 * The call shown ("primary"): a ringing one first (call waiting), else the active one, else one being
 * dialled, else one on hold. Being the Phone app gives call control only: Android still gives AskEVA
 * just the microphone, never the call audio (see CallRecorder / SpeakerAssist).
 */
object CallManager {
    private const val TAG = "AskEvaCalls"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    /** Every call Android gave us, oldest first. */
    private val calls = ArrayList<Call>()
    private val ids = IdentityHashMap<Call, String>()
    private val incoming = IdentityHashMap<Call, Boolean>()
    private val contactNames = HashMap<String, String>()
    private var nextId = 1

    private var inCallService: InCallService? = null
    private var appContext: Context? = null
    private var audioState: CallAudioState? = null

    /** Whether any call is going on, for the activity's show-over-lock-screen flags. */
    var onCallsChanged: ((hasCalls: Boolean) -> Unit)? = null

    /** The call the call screen shows (kept for older callers). */
    val activeCall: Call? get() = primaryCall()

    val hasCalls: Boolean get() = calls.isNotEmpty()

    private val callback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) = changed()
        override fun onDetailsChanged(call: Call, details: Call.Details) = changed()
    }

    /** Attaches the Flutter EventSink; a call already going on is sent right away. */
    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink != null && calls.isNotEmpty()) sendEvent(snapshot())
    }

    /** AskEvaInCallService.onCallAdded */
    fun registerCall(call: Call, service: InCallService) {
        inCallService = service
        appContext = service.applicationContext
        if (calls.none { it === call }) {
            calls.add(call)
            ids[call] = "c${nextId++}"
            incoming[call] = isIncoming(call)
            call.registerCallback(callback)
        }
        changed()
    }

    /** AskEvaInCallService.onCallRemoved */
    fun unregisterCall(call: Call) {
        try { call.unregisterCallback(callback) } catch (_: Exception) {}
        calls.removeAll { it === call }
        ids.remove(call)
        incoming.remove(call)
        if (calls.isEmpty()) {
            inCallService = null
            audioState = null
            contactNames.clear()
        }
        changed()
    }

    /** The service was unbound (no calls left, or AskEVA stopped being the Phone app). */
    fun clearAll() {
        for (c in calls.toList()) unregisterCall(c)
    }

    /** AskEvaInCallService.onCallAudioStateChanged: mute and speaker / earpiece / headset. */
    fun onAudioStateChanged(state: CallAudioState?) {
        audioState = state
        if (calls.isNotEmpty()) changed()
    }

    fun primaryCall(): Call? =
        calls.firstOrNull { it.state == Call.STATE_RINGING }
            ?: calls.firstOrNull { it.state == Call.STATE_ACTIVE }
            ?: calls.firstOrNull { it.state in DIALLING_STATES }
            ?: calls.firstOrNull { it.state == Call.STATE_HOLDING }
            ?: calls.lastOrNull()

    // ---- Call screen buttons -------------------------------------------------------------------

    fun answerCall(): Boolean {
        val call = calls.firstOrNull { it.state == Call.STATE_RINGING } ?: return false
        return attempt("answer") { call.answer(VideoProfile.STATE_AUDIO_ONLY) }
    }

    fun rejectCall(): Boolean {
        val call = calls.firstOrNull { it.state == Call.STATE_RINGING } ?: return false
        return attempt("reject") { call.reject(false, null) }
    }

    /** Ends the call on screen (a ringing one is declined). */
    fun disconnectCall(): Boolean {
        val call = primaryCall() ?: return false
        return attempt("disconnect") { call.disconnect() }
    }

    fun holdCall(): Boolean {
        val call = calls.firstOrNull { it.state == Call.STATE_ACTIVE } ?: return false
        return attempt("hold") { call.hold() }
    }

    fun unholdCall(): Boolean {
        val call = calls.firstOrNull { it.state == Call.STATE_HOLDING } ?: return false
        return attempt("unhold") { call.unhold() }
    }

    /** With one call active and one on hold: resume the held one (Android holds the other). */
    fun swapCalls(): Boolean = unholdCall()

    fun playDtmf(digit: Char): Boolean {
        val call = calls.firstOrNull { it.state == Call.STATE_ACTIVE } ?: return false
        return attempt("dtmf") { call.playDtmfTone(digit) }
    }

    fun stopDtmf(): Boolean {
        val call = calls.firstOrNull { it.state == Call.STATE_ACTIVE } ?: return false
        return attempt("dtmf stop") { call.stopDtmfTone() }
    }

    fun setMuted(muted: Boolean): Boolean {
        val service = inCallService ?: return false
        return attempt("mute") { service.setMuted(muted) }
    }

    /** Loudspeaker on, or back to the earpiece (or the wired headset when one is plugged in). */
    fun setSpeaker(speaker: Boolean): Boolean {
        val service = inCallService ?: return false
        val route = if (speaker) CallAudioState.ROUTE_SPEAKER else CallAudioState.ROUTE_WIRED_OR_EARPIECE
        return attempt("audio route") { service.setAudioRoute(route) }
    }

    /** A dual-SIM phone asked which SIM to call with: [index] into the call's "simChoices". */
    fun selectSim(index: Int): Boolean {
        val call = calls.firstOrNull { it.state == Call.STATE_SELECT_PHONE_ACCOUNT } ?: return false
        val handle = simHandles(call).getOrNull(index) ?: return false
        return attempt("select SIM") { call.phoneAccountSelected(handle, false) }
    }

    private inline fun attempt(what: String, block: () -> Unit): Boolean = try {
        block()
        true
    } catch (e: Exception) {
        Log.w(TAG, "$what failed", e)
        false
    }

    // ---- State -----------------------------------------------------------------------------------

    private fun changed() {
        val primary = primaryCall()
        sendEvent(snapshot())
        appContext?.let { ctx ->
            CallUi.update(ctx, primary, primary?.let { ids[it] }, primary?.let { nameOf(ctx, it) } ?: "")
        }
        val has = calls.isNotEmpty()
        mainHandler.post { onCallsChanged?.invoke(has) }
    }

    private fun isIncoming(call: Call): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            call.details?.callDirection == Call.Details.DIRECTION_INCOMING
        } else {
            call.state == Call.STATE_RINGING
        }

    private fun numberOf(call: Call): String = call.details?.handle?.schemeSpecificPart ?: ""

    /** Network-provided name, else the phone's contact name, else "". */
    private fun nameOf(ctx: Context, call: Call): String {
        val shown = call.details?.callerDisplayName
        if (!shown.isNullOrBlank()) return shown
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val contact = call.details?.contactDisplayName
            if (!contact.isNullOrBlank()) return contact
        }
        val number = numberOf(call)
        if (number.isEmpty()) return ""
        return contactNames.getOrPut(number) { lookupContact(ctx, number) }
    }

    private fun lookupContact(ctx: Context, number: String): String {
        if (ctx.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return ""
        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
            ctx.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) ?: "" else ""
            } ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun simHandles(call: Call): List<PhoneAccountHandle> {
        val extras = call.details?.intentExtras ?: return emptyList()
        return try {
            @Suppress("DEPRECATION")
            extras.getParcelableArrayList<PhoneAccountHandle>(Call.AVAILABLE_PHONE_ACCOUNTS) ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** "SIM 1 · Jio", for the SIM picker on dual-SIM phones. */
    private fun simChoices(call: Call): List<String> {
        if (call.state != Call.STATE_SELECT_PHONE_ACCOUNT) return emptyList()
        val ctx = appContext ?: return emptyList()
        val telecom = ctx.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
        return simHandles(call).mapIndexed { i, handle ->
            val label = try { telecom?.getPhoneAccount(handle)?.label?.toString() } catch (_: Exception) { null }
            if (label.isNullOrBlank()) "SIM ${i + 1}" else "SIM ${i + 1} · $label"
        }
    }

    private fun routeName(route: Int?): String = when (route) {
        CallAudioState.ROUTE_SPEAKER -> "speaker"
        CallAudioState.ROUTE_BLUETOOTH -> "bluetooth"
        CallAudioState.ROUTE_WIRED_HEADSET -> "wired"
        CallAudioState.ROUTE_EARPIECE -> "earpiece"
        else -> ""
    }

    private fun snapshot(): Map<String, Any?> {
        val call = primaryCall()
            ?: return mapOf("event" to "callStateChanged", "state" to "DISCONNECTED", "timestamp" to System.currentTimeMillis())
        val details = call.details
        val ctx = appContext
        return mapOf(
            "event" to "callStateChanged",
            "callId" to ids[call],
            "state" to mapStateToString(call.state),
            "phoneNumber" to numberOf(call),
            "displayName" to (if (ctx != null) nameOf(ctx, call) else ""),
            "isIncoming" to (incoming[call] == true),
            "connectTimeMillis" to (details?.connectTimeMillis ?: 0L),
            "canHold" to (details?.can(Call.Details.CAPABILITY_HOLD) == true),
            "muted" to (audioState?.isMuted == true),
            "audioRoute" to routeName(audioState?.route),
            "otherCalls" to (calls.size - 1),
            "heldCalls" to calls.count { it !== call && it.state == Call.STATE_HOLDING },
            "simChoices" to simChoices(call),
            "timestamp" to System.currentTimeMillis(),
        )
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

    private val DIALLING_STATES = setOf(
        Call.STATE_NEW, Call.STATE_DIALING, Call.STATE_CONNECTING, Call.STATE_PULLING_CALL, Call.STATE_SELECT_PHONE_ACCOUNT,
    )

    private fun mapStateToString(state: Int): String = when (state) {
        Call.STATE_NEW -> "NEW"
        Call.STATE_RINGING -> "RINGING"
        Call.STATE_DIALING -> "DIALING"
        Call.STATE_CONNECTING -> "CONNECTING"
        Call.STATE_SELECT_PHONE_ACCOUNT -> "SELECT_SIM"
        Call.STATE_ACTIVE -> "ACTIVE"
        Call.STATE_HOLDING -> "HOLDING"
        Call.STATE_DISCONNECTING -> "DISCONNECTING"
        Call.STATE_DISCONNECTED -> "DISCONNECTED"
        else -> "UNKNOWN"
    }
}
