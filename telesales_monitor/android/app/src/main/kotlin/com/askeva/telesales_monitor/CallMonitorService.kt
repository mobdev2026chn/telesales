package com.askeva.telesales_monitor

import android.Manifest
import org.json.JSONObject
import android.app.Notification
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.CallLog
import android.provider.ContactsContract
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.random.Random

/**
 * Foreground service (type "microphone") that follows every call while a caller is signed in,
 * whether or not the app's UI / Flutter engine is alive.
 *
 * Per connected call:
 *  - OFFHOOK: record the mic ourselves, unless the phone's built-in recorder was detected earlier.
 *  - IDLE: match the call-log row (number, SIM, type, talk time), drop personal-SIM calls, then
 *    look for the dialer's own recording for ~16 s. Built-in file found -> queue it (ours is
 *    discarded) and trust the OEM recorder from now on; none -> queue ours. Three connected calls
 *    in a row without a built-in file switch our own recording back on.
 *  - Queued recordings are uploaded by [RecordingUploader] (WorkManager).
 *
 * Call state comes from the PHONE_STATE broadcast registered here. Unlike TelephonyCallback
 * (API 31+), which only reports the default subscription, the broadcast fires for calls on
 * either SIM and carries the subscription id and (with READ_CALL_LOG) the incoming number.
 */
class CallMonitorService : Service() {

    companion object {
        @Volatile var isRunning = false
            private set

        // Set by MainActivity when the app itself places a call (the broadcast has no outgoing number)
        @Volatile var lastDialedNumber = ""
        @Volatile var lastDialedAtMs = 0L
        @Volatile var lastDialedSlot = 0 // 1-based

        fun noteDialed(number: String, slot1Based: Int) {
            lastDialedNumber = number
            lastDialedAtMs = System.currentTimeMillis()
            lastDialedSlot = slot1Based
        }

        /** Must be called while the app is in the foreground (Android 12+ / 14 FGS rules). */
        fun start(ctx: Context): Boolean {
            if (!CallMonitorStore.hasPermission(ctx, Manifest.permission.RECORD_AUDIO)) return false
            if (!CallMonitorStore.hasPermission(ctx, Manifest.permission.READ_PHONE_STATE)) return false
            return try {
                ContextCompat.startForegroundService(ctx, Intent(ctx, CallMonitorService::class.java))
                true
            } catch (e: Exception) {
                e.printStackTrace()
                false
            }
        }

        fun stop(ctx: Context) {
            try { ctx.stopService(Intent(ctx, CallMonitorService::class.java)) } catch (_: Exception) {}
        }

        private val BUILTIN_POLL_OFFSETS_MS = longArrayOf(4000L, 7000L, 11000L, 16000L)
        private const val MIN_TALK_SECONDS_FOR_MISS = 5
        /** Server marks a user offline after 5 minutes without any request. */
        private const val HEARTBEAT_EVERY_SEC = 120L
    }

    private data class EndedCall(
        val startMs: Long,
        val offhookMs: Long,
        val endMs: Long,
        val number: String,
        val incoming: Boolean,
        val simSlot: Int,
        val recorder: CallRecorder?,
    )

    private data class CallLogRow(val number: String, val name: String, val type: String, val durationSec: Int, val simSlot: Int)

    /** Post-call work runs one call at a time, off the main thread. */
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    /** "Still here" pings, so the admin dashboard shows this caller as online while logged in. */
    private var heartbeat: java.util.concurrent.ScheduledExecutorService? = null
    private var receiver: BroadcastReceiver? = null

    // Current call
    private var lastState = TelephonyManager.EXTRA_STATE_IDLE
    private var inCall = false
    private var incoming = false
    private var ringingAtMs = 0L
    private var incomingNumber = ""
    private var callNumber = ""
    private var callStartMs = 0L
    private var offhookMs = 0L
    private var callSlot = 0
    private var recorder: CallRecorder? = null
    /** Start of the most recent call; read by the worker to bound the previous call's search. */
    @Volatile private var latestCallStartMs = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!goForeground()) {
            // Typically a sticky restart from the background on Android 14+: mic FGS not allowed.
            if (CallMonitorStore.recordingSession(this) != null) {
                CallMonitorStore.postAlert(
                    this, CallMonitorStore.NOTIF_ID_RESUME,
                    "Open AskEVA to resume call tracking",
                    "Call tracking stopped in the background. Tap to open AskEVA and resume it."
                )
            }
            stopSelf()
            return START_NOT_STICKY
        }
        if (CallMonitorStore.recordingSession(this) == null) {
            // Signed out (or auto-record off) while we were not running: nothing to track
            stopSelf()
            return START_NOT_STICKY
        }
        CallMonitorStore.cancelNotification(this, CallMonitorStore.NOTIF_ID_RESUME)
        registerCallReceiver()
        isRunning = true
        RecordingUploader.schedule(this) // retry anything left from earlier
        startHeartbeat()
        CallMonitorEvents.emit("onCallMonitorState", mapOf("running" to true))
        return START_STICKY
    }

    private fun startHeartbeat() {
        if (heartbeat != null) return
        heartbeat = Executors.newSingleThreadScheduledExecutor().also {
            it.scheduleWithFixedDelay({ sendHeartbeat() }, 0, HEARTBEAT_EVERY_SEC, java.util.concurrent.TimeUnit.SECONDS)
        }
    }

    /** POST <base>/auth/heartbeat with the session token. Failures are ignored (next ping retries). */
    private fun sendHeartbeat() {
        val session = CallMonitorStore.session(this) ?: return
        if (session.token.isEmpty() || session.token == CallMonitorStore.authFailedToken(this)) return
        var conn: java.net.HttpURLConnection? = null
        try {
            conn = (java.net.URL("${CallMonitorStore.baseUrl(this)}/auth/heartbeat").openConnection() as java.net.HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000
                readTimeout = 15_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer ${session.token}")
            }
            conn.outputStream.use { it.write("{}".toByteArray()) }
            conn.responseCode
        } catch (_: Exception) {
        } finally {
            conn?.disconnect()
        }
    }

    private fun buildNotification(text: String): Notification {
        CallMonitorStore.ensureChannels(this)
        return NotificationCompat.Builder(this, CallMonitorStore.CHANNEL_TRACKING)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("AskEVA · Call tracking active")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(CallMonitorStore.openAppIntent(this))
            .build()
    }

    private fun idleText(): String =
        if (CallMonitorStore.nativeRecorderDetected(this)) "Uploading your phone's call recordings"
        else "Work calls are recorded and uploaded"

    private fun goForeground(): Boolean {
        return try {
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
            ServiceCompat.startForeground(this, CallMonitorStore.NOTIF_ID_SERVICE, buildNotification(idleText()), type)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun updateNotification(text: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            nm.notify(CallMonitorStore.NOTIF_ID_SERVICE, buildNotification(text))
        } catch (_: Exception) {}
    }

    private fun registerCallReceiver() {
        if (receiver != null) return
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == TelephonyManager.ACTION_PHONE_STATE_CHANGED) onPhoneState(intent)
            }
        }
        try {
            ContextCompat.registerReceiver(
                this, receiver, IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED),
                ContextCompat.RECEIVER_EXPORTED // system broadcast
            )
        } catch (e: Exception) {
            e.printStackTrace()
            receiver = null
        }
    }

    private fun onPhoneState(intent: Intent) {
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        @Suppress("DEPRECATION")
        val extraNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
        val now = System.currentTimeMillis()

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                if (!inCall) {
                    if (lastState == TelephonyManager.EXTRA_STATE_IDLE) {
                        incoming = true
                        ringingAtMs = now
                    }
                    if (extraNumber.isNotEmpty()) incomingNumber = extraNumber
                }
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                if (!inCall) {
                    inCall = true
                    offhookMs = now
                    if (incoming) {
                        callNumber = incomingNumber.ifEmpty { extraNumber }
                        callStartMs = if (ringingAtMs > 0) ringingAtMs else now
                        callSlot = slotFromIntent(intent)
                    } else {
                        val recentDial = now - lastDialedAtMs < 120_000L
                        callNumber = extraNumber.ifEmpty { if (recentDial) lastDialedNumber else "" }
                        callStartMs = now
                        val slot = slotFromIntent(intent)
                        callSlot = if (slot > 0) slot else if (recentDial) lastDialedSlot else 0
                    }
                    latestCallStartMs = callStartMs
                    maybeStartOwnRecording()
                } else if (callNumber.isEmpty() && extraNumber.isNotEmpty()) {
                    callNumber = extraNumber
                }
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                if (inCall) endCall(now)
                inCall = false
                incoming = false
                ringingAtMs = 0L
                incomingNumber = ""
                CallMonitorEvents.emit("onCallStateChanged", mapOf("state" to "LOG_UPDATED"))
            }
        }
        lastState = state
    }

    private fun maybeStartOwnRecording() {
        val session = CallMonitorStore.recordingSession(this) ?: return
        if (!CallMonitorStore.isWorkSim(callSlot, session.simMode)) return
        // The phone's own recorder handles it: do not compete with it for the microphone
        if (CallMonitorStore.nativeRecorderDetected(this) && CallMonitorStore.hasMediaPermission(this)) return
        if (!CallMonitorStore.hasPermission(this, Manifest.permission.RECORD_AUDIO)) return

        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())
        val suffix = Random.nextInt(0x10000).toString(16).padStart(4, '0')
        val prefix = if (incoming) "INC_CALL_REC" else "OUT_CALL_REC"
        val file = File(recordingsDir(), "${prefix}_${stamp}_$suffix.m4a")
        val rec = CallRecorder(this)
        if (rec.start(file)) {
            recorder = rec
            updateNotification("Recording this call")
            CallMonitorEvents.emit("onCallRecordingStatus", mapOf("isRecording" to true, "isIncoming" to incoming))
        }
    }

    private fun endCall(now: Long) {
        val rec = recorder
        recorder = null
        rec?.requestStop() // stop capturing right away; the file is finished on the worker
        if (rec != null) {
            updateNotification(idleText())
            CallMonitorEvents.emit("onCallRecordingStatus", mapOf("isRecording" to false))
        }
        val ended = EndedCall(callStartMs, offhookMs, now, callNumber, incoming, callSlot, rec)
        callNumber = ""
        callSlot = 0
        try {
            worker.execute { processEndedCall(ended) }
        } catch (_: Exception) {
            rec?.awaitResult()?.file?.delete()
        }
    }

    private fun recordingsDir(): File = File(filesDir, "call_recordings").apply { if (!exists()) mkdirs() }

    private fun sleepUntil(targetMs: Long) {
        val wait = targetMs - System.currentTimeMillis()
        if (wait > 0) try { Thread.sleep(wait) } catch (_: InterruptedException) {}
    }

    /** Worker thread. */
    private fun processEndedCall(call: EndedCall) {
        val own = call.recorder?.awaitResult()
        val session = CallMonitorStore.recordingSession(this)
        if (session == null) {
            own?.file?.delete() // never keep or upload anything without a caller session
            return
        }

        // The call-log row is written around the end of the call
        sleepUntil(call.endMs + 2500)
        var row = findCallLogRow(call)
        if (row == null) {
            sleepUntil(call.endMs + 5500)
            row = findCallLogRow(call)
        }
        val number = row?.number?.ifEmpty { null } ?: call.number
        val slot = if (row != null && row.simSlot > 0) row.simSlot else call.simSlot
        if (!CallMonitorStore.isWorkSim(slot, session.simMode)) {
            own?.file?.delete()
            return
        }
        if (row != null && row.durationSec <= 0) {
            own?.file?.delete() // not connected (missed / rejected / unanswered): nothing to upload
            return
        }
        val type = row?.type ?: if (call.incoming) "INCOMING" else "OUTGOING"
        // Talk time = the call log's duration, which starts when the call is answered. OFFHOOK -> IDLE
        // is only a fallback: for an outgoing call OFFHOOK is the moment of dialling, so it includes the ringing.
        val offhookSec = if (call.offhookMs > 0) ((call.endMs - call.offhookMs) / 1000).toInt().coerceAtLeast(0) else 0
        val talkSec = if (row != null && row.durationSec > 0) row.durationSec else offhookSec
        val contact = row?.name?.ifEmpty { null } ?: lookupContactName(number) ?: number.ifEmpty { "Unknown" }

        // Our recording of an outgoing call started at dialling: cut the ringing so it holds the conversation only
        if (own != null && row != null && row.durationSec > 0) {
            val answeredAtMs = call.endMs - row.durationSec * 1000L
            // Call-log seconds are rounded down, so keep a one second margin before the answer
            val leadInMs = answeredAtMs - call.recorder!!.startedAtMs - 1000L
            if (leadInMs >= 1500L) AudioTools.trimLeading(own.file, leadInMs * 1000L)
        }

        // Built-in recorder: poll a few times, OEM recorders finalise the file late
        var found: BuiltInRecordingFinder.Found? = null
        if (CallMonitorStore.hasMediaPermission(this)) {
            val exclude = CallMonitorStore.usedBuiltInFiles(this).toSet()
            for (offset in BUILTIN_POLL_OFFSETS_MS) {
                sleepUntil(call.endMs + offset)
                // A call started since then: its recording must not be taken for this one
                val next = latestCallStartMs
                var createdBefore = call.endMs + RecordingCandidateRanker.CREATED_AFTER_END_SLACK_MS
                if (next > call.endMs && next < createdBefore) createdBefore = next
                val info = RecordingCandidateRanker.CallInfo(call.startMs, call.endMs, talkSec, number, contact, createdBefore)
                found = try { BuiltInRecordingFinder.find(this, info, exclude) } catch (_: Exception) { null }
                if (found != null) break
            }
        }

        if (found != null) {
            own?.file?.delete()
            CallMonitorStore.cancelNotification(this, CallMonitorStore.NOTIF_ID_RECORDING)
            RecordingDiagnostics.add(this, JSONObject().put("result", "builtin").put("builtInFound", true).put("talkSeconds", talkSec))
            CallMonitorStore.onBuiltInFound(this, found.key, BuiltInRecordingFinder.usedKeyFor(found.displayName))
            RecordingQueue.add(
                this, QueuedRecording(
                    id = QueuedRecording.newId(), userId = session.userId, source = "builtin",
                    path = found.path, uri = found.uri, fileName = found.displayName,
                    callStartedAtMs = call.startMs, phoneNumber = number, contactName = contact, type = type,
                    simSlot = slot, durationSeconds = if (talkSec > 0) talkSec else found.durationSeconds,
                )
            )
        } else {
            if (talkSec >= MIN_TALK_SECONDS_FOR_MISS && CallMonitorStore.hasMediaPermission(this)) {
                CallMonitorStore.onBuiltInMissing(this)
            }
            val recorderUsed = call.recorder
            if (own != null) {
                CallMonitorStore.setLastCapture(this, "ok", recorderUsed?.usedSource ?: -1)
                CallMonitorStore.cancelNotification(this, CallMonitorStore.NOTIF_ID_RECORDING)
            } else if (recorderUsed?.discardedAsSilent == true) {
                // Android muted the mic for this call: nothing worth uploading
                CallMonitorStore.setLastCapture(this, "silent", recorderUsed.usedSource)
                if (!CallAccessibilityService.isEnabled(this)) {
                    CallMonitorStore.postAlert(
                        this, CallMonitorStore.NOTIF_ID_RECORDING,
                        "Call was not recorded",
                        "Android muted the microphone. Open AskEVA → More → Call recording setup and turn on " +
                            "\"AskEVA Call Recording\" in Accessibility so calls are recorded with sound."
                    )
                }
            }
            if (recorderUsed != null && recorderUsed.usedSource >= 0) {
                CallMonitorStore.reportSourceResult(this, recorderUsed.usedSource, heardSpeech = own != null)
            }
            RecordingDiagnostics.add(this, JSONObject().apply {
                put("talkSeconds", talkSec)
                put("builtInFound", false)
                put("uploadedOwn", own != null)
                if (recorderUsed == null) {
                    put("result", "not_recorded")
                    put("note", when {
                        CallMonitorStore.nativeRecorderDetected(this@CallMonitorService) -> "skipped: built-in recorder trusted"
                        !CallMonitorStore.hasPermission(this@CallMonitorService, Manifest.permission.RECORD_AUDIO) -> "no mic permission"
                        else -> "recorder did not start"
                    })
                } else {
                    put("result", if (own != null) "ok" else if (recorderUsed.discardedAsSilent) "silent" else "empty")
                    put("source", recorderUsed.usedSource)
                    put("sourceName", CallMonitorStore.sourceName(recorderUsed.usedSource))
                    put("sourceMode", recorderUsed.sourceMode)
                    put("recordedSeconds", recorderUsed.recordedSeconds)
                    put("voicedSeconds", Math.round(recorderUsed.voicedSeconds * 10) / 10.0)
                    put("peak", recorderUsed.peakLevel)
                }
            })
            if (own != null) {
                RecordingQueue.add(
                    this, QueuedRecording(
                        id = QueuedRecording.newId(), userId = session.userId, source = "own",
                        path = own.file.absolutePath, uri = "", fileName = own.file.name,
                        callStartedAtMs = call.startMs, phoneNumber = number, contactName = contact, type = type,
                        simSlot = slot, durationSeconds = if (talkSec > 0) talkSec else own.durationSeconds,
                    )
                )
            }
        }
        updateNotification(idleText())
        CallMonitorEvents.emit("onUploadQueueChanged")
        RecordingUploader.schedule(this)
    }

    private fun last10(s: String) = s.filter { it.isDigit() }.takeLast(10)

    /** The call-log row of this call: same number (when known), closest start time within 2 minutes. */
    private fun findCallLogRow(call: EndedCall): CallLogRow? {
        if (!CallMonitorStore.hasPermission(this, Manifest.permission.READ_CALL_LOG)) return null
        try {
            val from = call.startMs - 120_000L
            val to = call.endMs + 60_000L
            val projection = arrayOf(
                CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME, CallLog.Calls.TYPE,
                CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.PHONE_ACCOUNT_ID
            )
            val want = last10(call.number)
            var best: CallLogRow? = null
            var bestDiff = Long.MAX_VALUE
            contentResolver.query(
                CallLog.Calls.CONTENT_URI, projection,
                "${CallLog.Calls.DATE} >= ? AND ${CallLog.Calls.DATE} <= ?",
                arrayOf(from.toString(), to.toString()), "${CallLog.Calls.DATE} DESC"
            )?.use { c ->
                while (c.moveToNext()) {
                    val number = c.getString(0) ?: ""
                    if (want.length == 10 && last10(number) != want) continue
                    val date = c.getLong(3)
                    val diff = abs(date - call.startMs)
                    if (diff >= bestDiff) continue
                    val type = when (c.getInt(2)) {
                        CallLog.Calls.OUTGOING_TYPE -> "OUTGOING"
                        else -> "INCOMING"
                    }
                    bestDiff = diff
                    best = CallLogRow(number, c.getString(1) ?: "", type, c.getInt(4), slotFromAccountId(c.getString(5) ?: ""))
                }
            }
            return best
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    private fun activeSubscriptions(): List<android.telephony.SubscriptionInfo> {
        return try {
            if (!CallMonitorStore.hasPermission(this, Manifest.permission.READ_PHONE_STATE)) return emptyList()
            val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            sm?.activeSubscriptionInfoList ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** PHONE_ACCOUNT_ID is the subscription id (newer Android) or the ICCID (older). 0 = unknown. */
    private fun slotFromAccountId(accountId: String): Int {
        val subs = activeSubscriptions()
        val only = if (subs.size == 1) subs[0].simSlotIndex + 1 else 0
        if (accountId.isEmpty()) return only
        for (info in subs) {
            if (info.subscriptionId.toString() == accountId) return info.simSlotIndex + 1
            try {
                if (!info.iccId.isNullOrEmpty() && info.iccId.equals(accountId, ignoreCase = true)) return info.simSlotIndex + 1
            } catch (_: Exception) {}
        }
        return only
    }

    /** 1-based SIM slot of the subscription named in a PHONE_STATE broadcast, 0 when unknown. */
    private fun slotFromIntent(intent: Intent): Int {
        try {
            var subId = intent.getIntExtra("android.telephony.extra.SUBSCRIPTION_INDEX", -1)
            if (subId < 0) subId = intent.getIntExtra("subscription", -1)
            if (subId >= 0 && CallMonitorStore.hasPermission(this, Manifest.permission.READ_PHONE_STATE)) {
                val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                val info = sm?.getActiveSubscriptionInfo(subId)
                if (info != null) return info.simSlotIndex + 1
            }
        } catch (_: Exception) {}
        val subs = activeSubscriptions()
        return if (subs.size == 1) subs[0].simSlotIndex + 1 else 0
    }

    private fun lookupContactName(number: String): String? {
        if (number.isEmpty() || !CallMonitorStore.hasPermission(this, Manifest.permission.READ_CONTACTS)) return null
        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
            contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0)?.ifEmpty { null } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    override fun onDestroy() {
        isRunning = false
        heartbeat?.shutdownNow()
        heartbeat = null
        try { receiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        receiver = null
        // Finish (and queue) a call that is still being recorded
        if (inCall) endCall(System.currentTimeMillis())
        inCall = false
        worker.shutdown() // queued post-call work still completes
        CallMonitorEvents.emit("onCallMonitorState", mapOf("running" to false))
        super.onDestroy()
    }
}
