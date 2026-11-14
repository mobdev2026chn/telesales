package com.askeva.telesales_monitor

import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Loudspeaker fallback for phones whose own Phone app does not save readable call recordings.
 *
 * Android never gives ordinary apps the call audio, only the microphone, so our own recording holds
 * the caller's voice only - unless the other side comes out of the loudspeaker, where the microphone
 * hears it too. When the app has to record a work call itself, [begin] switches the speaker on for
 * that call and [end] undoes what we changed.
 *
 *  - Android 11 and older: AudioManager.setSpeakerphoneOn routes the call to the speaker directly.
 *  - Android 12+: only the phone app may change a call's route, so [CallAccessibilityService] taps
 *    the Speaker button on the call screen. It runs in its own process, so it is asked by broadcast
 *    and answers with [ACTION_RESULT].
 */
object SpeakerAssist {
    private const val TAG = "AskEvaSpeaker"

    const val ACTION_REQUEST = "com.askeva.telesales_monitor.SPEAKER_REQUEST"
    const val ACTION_CANCEL = "com.askeva.telesales_monitor.SPEAKER_CANCEL"
    const val ACTION_RESULT = "com.askeva.telesales_monitor.SPEAKER_RESULT"
    const val EXTRA_UNTIL_MS = "untilMs"
    const val EXTRA_RESULT = "result"

    /** How long after the call connects the call screen is watched for its Speaker button. */
    private const val REQUEST_WINDOW_MS = 30_000L

    class Session(
        /** setSpeakerphoneOn(true) was called (Android 11 and older): switched off again at the end. */
        val usedSpeakerphoneApi: Boolean,
    ) {
        /**
         * How the speaker was handled, for diagnostics: "requested", then the accessibility service's
         * answer: "on" | "already_on" | "tapped" | "tap_no_effect" | "not_found".
         */
        @Volatile var result: String = "requested"
        /** The call ended: no more repeats of the request. */
        @Volatile var ended = false
    }

    /** Repeats of the request while no answer came: the service may only be starting (just switched on). */
    private val REPEAT_AFTER_MS = longArrayOf(1500L, 3500L)
    private val main = Handler(Looper.getMainLooper())

    private fun audio(ctx: Context) = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    /** A wired, USB or Bluetooth headset is connected: the caller hears the call there, so the route is left alone. */
    fun headsetConnected(ctx: Context): Boolean {
        val am = audio(ctx) ?: return false
        return try {
            am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { d ->
                when (d.type) {
                    AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                    AudioDeviceInfo.TYPE_USB_HEADSET -> true
                    else -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && d.type == AudioDeviceInfo.TYPE_BLE_HEADSET
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    /** Whether the call is playing through the loudspeaker; null when the phone does not say. */
    fun isSpeakerOn(ctx: Context): Boolean? {
        val am = audio(ctx) ?: return null
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val device = am.communicationDevice ?: return null
                device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            } else {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn
            }
        } catch (_: Exception) {
            null
        }
    }

    /** Main thread, right after our own recording of a work call started. */
    fun begin(ctx: Context): Session {
        var usedApi = false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            try {
                val am = audio(ctx)
                @Suppress("DEPRECATION")
                if (am != null && !am.isSpeakerphoneOn) {
                    am.isSpeakerphoneOn = true
                    usedApi = true
                }
            } catch (e: Exception) {
                Log.w(TAG, "setSpeakerphoneOn failed", e)
            }
        }
        // Also on Android 11 and older: the service confirms the route (or taps if the call ignored it).
        // The deadline doubles as the request id: the service handles each id once.
        val untilMs = System.currentTimeMillis() + REQUEST_WINDOW_MS
        val session = Session(usedApi)
        send(ctx, Intent(ACTION_REQUEST).putExtra(EXTRA_UNTIL_MS, untilMs))
        for (delay in REPEAT_AFTER_MS) {
            main.postDelayed({
                if (!session.ended && session.result == "requested") {
                    send(ctx, Intent(ACTION_REQUEST).putExtra(EXTRA_UNTIL_MS, untilMs))
                }
            }, delay)
        }
        Log.i(TAG, "speaker requested (api=$usedApi)")
        return session
    }

    /** Main thread, when the call ends. The phone app resets the route for the next call by itself. */
    fun end(ctx: Context, session: Session) {
        session.ended = true
        send(ctx, Intent(ACTION_CANCEL))
        if (session.usedSpeakerphoneApi) {
            try {
                @Suppress("DEPRECATION")
                audio(ctx)?.isSpeakerphoneOn = false
            } catch (_: Exception) {}
        }
    }

    /** Broadcast inside this app only (the accessibility service runs in the ":a11y" process). */
    fun send(ctx: Context, intent: Intent) {
        try {
            ctx.sendBroadcast(intent.setPackage(ctx.packageName))
        } catch (e: Exception) {
            Log.w(TAG, "broadcast failed", e)
        }
    }
}
