package com.askeva.telesales_monitor

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telecom.TelecomManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.content.ContextCompat

/**
 * Two jobs, both only for work calls:
 *
 *  1. Exists so Android lets this app capture audio during a phone call. Since Android 10 the system
 *     hands ordinary apps silence while a call is active; apps with an enabled accessibility service
 *     are exempt. Recording itself happens in [CallMonitorService] / [CallRecorder].
 *  2. Loudspeaker fallback ([SpeakerAssist]): on phones whose Phone app saves no readable recording,
 *     the service taps the call screen's Speaker button once, so the microphone hears the other side.
 *     It looks at the screen only while such a request is open (at most 30 s after a work call
 *     connects), only in the phone app's windows, and never types anything.
 *
 * Runs in the ":a11y" process: requests arrive by broadcast, results go back the same way.
 * Only suitable for directly installed (non-Play) builds.
 */
class CallAccessibilityService : AccessibilityService() {

    private val main = Handler(Looper.getMainLooper())
    private var receiver: BroadcastReceiver? = null

    /** Watch the call screen for its Speaker button until this time; 0 = no open request. */
    private var speakerUntilMs = 0L
    /** Id (deadline) of the last speaker request received, so a repeated broadcast is ignored. */
    private var lastRequestUntilMs = 0L
    private var verifyPending = false
    /** When the open request started, and whether the call screen was already brought to the front for it. */
    private var requestOpenedAtMs = 0L
    private var callScreenShown = false
    private val attempt = Runnable { trySpeaker() }
    private val verify = Runnable {
        verifyPending = false
        val on = SpeakerAssist.isSpeakerOn(this)
        report(when (on) { true -> "on"; false -> "tap_no_effect"; null -> "tapped" })
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "accessibility service connected")
        setWatching(false)
        if (receiver == null) {
            val r = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    when (intent?.action) {
                        SpeakerAssist.ACTION_REQUEST -> startSpeakerRequest(intent.getLongExtra(SpeakerAssist.EXTRA_UNTIL_MS, 0L))
                        SpeakerAssist.ACTION_CANCEL -> stopSpeakerRequest()
                        ACTION_DISABLE -> switchOff()
                    }
                }
            }
            val filter = IntentFilter().apply {
                addAction(SpeakerAssist.ACTION_REQUEST)
                addAction(SpeakerAssist.ACTION_CANCEL)
                addAction(ACTION_DISABLE)
            }
            try {
                ContextCompat.registerReceiver(this, r, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
                receiver = r
            } catch (e: Exception) {
                Log.w(TAG, "could not listen for speaker requests", e)
            }
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Events are subscribed to only while a speaker request is open (see setWatching)
        if (speakerUntilMs == 0L || event == null) return
        main.removeCallbacks(attempt)
        main.postDelayed(attempt, 150) // coalesce bursts of content changes
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        stopSpeakerRequest()
        try { receiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        receiver = null
        super.onDestroy()
    }

    /** Not needed on this phone (its own recorder is used): off, so payment apps work. */
    private fun switchOff() {
        if (speakerUntilMs != 0L || verifyPending) return // never in the middle of a call's speaker request
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        Log.i(TAG, "switching off: not needed on this phone")
        try { disableSelf() } catch (e: Exception) { Log.w(TAG, "disableSelf failed", e) }
    }

    // ------------------------------------------------------------------ Loudspeaker fallback

    private fun startSpeakerRequest(untilMs: Long) {
        // The call service repeats its request (this service may still have been starting); one call
        // = one request id (its deadline), handled once, so the speaker is never tapped twice
        if (untilMs != 0L && untilMs == lastRequestUntilMs) return
        lastRequestUntilMs = untilMs
        val now = System.currentTimeMillis()
        speakerUntilMs = if (untilMs > now) untilMs else now + 30_000L
        requestOpenedAtMs = now
        callScreenShown = false
        verifyPending = false
        main.removeCallbacks(verify)
        main.removeCallbacks(attempt)
        setWatching(true)
        // The call screen may not be up yet, and may send no events: also try on a timer
        for (delay in RETRY_DELAYS_MS) main.postDelayed(attempt, delay)
        main.postDelayed(attempt, speakerUntilMs - now + 50)
        Log.i(TAG, "speaker request open")
    }

    private fun stopSpeakerRequest() {
        speakerUntilMs = 0L
        main.removeCallbacks(attempt)
        if (verifyPending) {
            verifyPending = false
            main.removeCallbacks(verify)
        }
        setWatching(false)
    }

    private fun trySpeaker() {
        if (speakerUntilMs == 0L) return
        if (System.currentTimeMillis() > speakerUntilMs) {
            finish("not_found")
            return
        }
        if (SpeakerAssist.isSpeakerOn(this) == true) {
            finish("already_on")
            return
        }
        val found = findSpeakerButton()
        if (found == null) {
            // Not on screen yet: the next attempt retries. Still missing after a moment = the call was
            // answered from the notification, or the caller switched app: bring the call screen up, once.
            if (!callScreenShown && System.currentTimeMillis() - requestOpenedAtMs >= SHOW_CALL_SCREEN_AFTER_MS) {
                callScreenShown = true
                showCallScreen()
            }
            return
        }
        val (label, target) = found
        val checked = checkedState(target) ?: checkedState(label)
        if (checked == true) {
            finish("already_on")
            return
        }
        // One tap per call, so the speaker is never toggled back off
        finish("tapped")
        val ok = tap(target, label)
        Log.i(TAG, "speaker button tapped (ok=$ok)")
        verifyPending = true
        main.postDelayed(verify, 1500)
    }

    /** Brings the phone app's call screen to the front (needs the phone permission AskEVA already has). */
    @android.annotation.SuppressLint("MissingPermission")
    private fun showCallScreen() {
        try {
            val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            if (!telecom.isInCall) return
            telecom.showInCallScreen(false)
            Log.i(TAG, "speaker button not visible: call screen brought to the front")
        } catch (e: Exception) {
            Log.w(TAG, "could not bring the call screen to the front", e)
        }
    }

    private fun finish(result: String) {
        speakerUntilMs = 0L
        main.removeCallbacks(attempt)
        setWatching(false)
        report(result)
    }

    private fun report(result: String) {
        Log.i(TAG, "speaker: $result")
        SpeakerAssist.send(this, Intent(SpeakerAssist.ACTION_RESULT).putExtra(SpeakerAssist.EXTRA_RESULT, result))
    }

    /** Window events are only needed while a request is open; otherwise subscribe to (almost) nothing. */
    private fun setWatching(on: Boolean) {
        try {
            val info = serviceInfo ?: return
            info.eventTypes = if (on) {
                AccessibilityEvent.TYPE_WINDOWS_CHANGED or AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            } else {
                AccessibilityEvent.TYPE_ANNOUNCEMENT
            }
            info.notificationTimeout = if (on) 200L else 1000L
            serviceInfo = info
        } catch (_: Exception) {}
    }

    /** (node whose id / label says "speaker", node to tap) in a phone-app window, or null. */
    private fun findSpeakerButton(): Pair<AccessibilityNodeInfo, AccessibilityNodeInfo>? {
        val dialer = try {
            (getSystemService(Context.TELECOM_SERVICE) as TelecomManager).defaultDialerPackage ?: ""
        } catch (_: Exception) { "" }
        val roots = ArrayList<AccessibilityNodeInfo>()
        try { windows.forEach { w -> w.root?.let { roots.add(it) } } } catch (_: Exception) {}
        if (roots.isEmpty()) rootInActiveWindow?.let { roots.add(it) }
        for (root in roots) {
            val pkg = root.packageName?.toString() ?: continue
            if (!isCallScreen(pkg, dialer)) continue
            val label = findSpeakerNode(root) ?: continue
            return label to (clickableAncestor(label) ?: label)
        }
        return null
    }

    private fun isCallScreen(pkg: String, dialer: String): Boolean {
        if (pkg == packageName) return false
        if (pkg == dialer) return true
        val p = pkg.lowercase()
        return CALL_PACKAGE_HINTS.any { p.contains(it) }
    }

    private fun findSpeakerNode(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        var byLabel: AccessibilityNodeInfo? = null
        while (queue.isNotEmpty() && visited++ < MAX_NODES) {
            val n = queue.removeFirst()
            if (n.isVisibleToUser) {
                val id = n.viewIdResourceName?.lowercase().orEmpty().substringAfter(":id/")
                if (id.contains("speaker") && EXCLUDE_WORDS.none { id.contains(it) }) return n
                if (byLabel == null && (isSpeakerLabel(n.text) || isSpeakerLabel(n.contentDescription))) byLabel = n
            }
            for (i in 0 until n.childCount) n.getChild(i)?.let { queue.add(it) }
        }
        return byLabel
    }

    private fun isSpeakerLabel(cs: CharSequence?): Boolean {
        val s = cs?.toString()?.trim()?.lowercase() ?: return false
        if (s.isEmpty() || s.length > 40) return false
        if (EXCLUDE_WORDS.any { s.contains(it) }) return false
        return s.contains("speaker") || LOCAL_SPEAKER_WORDS.any { s.contains(it) }
    }

    /** true / false when the button says whether it is on, null when it does not. */
    private fun checkedState(n: AccessibilityNodeInfo): Boolean? = when {
        n.isCheckable -> n.isChecked
        n.isSelected -> true
        else -> null
    }

    private fun clickableAncestor(n: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var cur: AccessibilityNodeInfo? = n
        var depth = 0
        while (cur != null && depth++ <= 3) {
            if (cur.isClickable) return cur
            cur = cur.parent
        }
        return null
    }

    private fun tap(target: AccessibilityNodeInfo, label: AccessibilityNodeInfo): Boolean {
        if (target.isClickable && target.isEnabled && target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
        // A custom button that does not take ACTION_CLICK: tap the centre of its label
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val r = Rect()
        label.getBoundsInScreen(r)
        if (r.isEmpty) return false
        val path = Path().apply { moveTo(r.exactCenterX(), r.exactCenterY()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 60))
            .build()
        return try { dispatchGesture(gesture, null, null) } catch (_: Exception) { false }
    }

    companion object {
        private const val TAG = "AskEvaA11y"
        /** Sent by [A11yGuard] when the phone's own recorder makes this service unnecessary. */
        const val ACTION_DISABLE = "com.askeva.telesales_monitor.A11Y_DISABLE"
        private const val MAX_NODES = 600
        private val RETRY_DELAYS_MS = longArrayOf(300, 800, 1500, 2500, 4000, 6000, 9000, 13000, 18000, 24000)
        /** Speaker button still not visible this long after the request: bring the call screen to the front. */
        private const val SHOW_CALL_SCREEN_AFTER_MS = 2_000L

        /** In-call screens: Samsung "com.samsung.android.incallui", AOSP / Xiaomi / Oppo / Vivo "com.android.incallui", Google "...dialer". */
        private val CALL_PACKAGE_HINTS = listOf("incallui", "dialer", "telecom", "contacts", ".phone", "phone.")

        /** Never tap these, even when they mention a speaker. */
        private val EXCLUDE_WORDS = listOf("earpiece", "bluetooth", "headset", "volume", "headphone")

        /** "Speaker" in common phone languages (English is matched by "speaker"). */
        private val LOCAL_SPEAKER_WORDS = listOf(
            "स्पीकर", // Hindi, Marathi
            "ஸ்பீக்கர்", // Tamil
            "స్పీకర్", // Telugu
            "ಸ್ಪೀಕರ್", // Kannada
            "സ്പീക്കർ", // Malayalam
            "স্পিকার", // Bengali
            "સ્પીકર", // Gujarati
            "ਸਪੀਕਰ", // Punjabi
            "ସ୍ପିକର", // Odia
            "اسپیکر", // Urdu
            "مكبر الصوت", // Arabic
            "altavoz", "haut-parleur", "lautsprecher", "alto-falante", "altoparlante", "pengeras suara",
            "loa ngoài", "громкая", "динамик", "hoparlör", "głośnik", "luidspreker",
        )

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
