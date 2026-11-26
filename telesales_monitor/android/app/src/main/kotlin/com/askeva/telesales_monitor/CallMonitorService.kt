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
import android.os.Build
import android.os.IBinder
import android.provider.CallLog
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
 * Foreground service (type "microphone") that follows work calls while a caller or eligible Team
 * Leader is signed in, whether or not the app's UI / Flutter engine is alive.
 *
 * Per connected call:
 *  - OFFHOOK: record the mic ourselves. Once the phone's built-in recorder is trusted this is only a
 *    backup (Android 10+, where two apps may use the mic at once), so a call the dialer did not record
 *    is still uploaded. When the built-in recorder cannot be used, [SpeakerAssist] also puts the call
 *    on the loudspeaker so the mic hears the other side (Android gives apps no call audio).
 *  - IDLE: match the call-log row (number, SIM, type, talk time), drop personal-SIM calls, then
 *    look for the dialer's own recording for ~16 s. Built-in file found -> queue it (ours is
 *    discarded) and trust the OEM recorder from now on; none -> queue ours. Three connected calls
 *    in a row without a built-in file stop trusting the built-in recorder.
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

        /** After the call ends. OEM recorders finalise the file late and the media index lags behind on Android 11+. */
        private val BUILTIN_POLL_OFFSETS_MS = longArrayOf(4000L, 7000L, 11000L, 16000L, 25000L, 40000L)
        private const val MIN_TALK_SECONDS_FOR_MISS = 5
        /** Server marks a user offline after 5 minutes without any request. */
        private const val HEARTBEAT_EVERY_SEC = 120L
        /** The dialer writes the call-log row a moment after the call ends. */
        private const val PUSH_DELAY_MS = 3000L
    }

    private data class EndedCall(
        val startMs: Long,
        val offhookMs: Long,
        val endMs: Long,
        val number: String,
        val incoming: Boolean,
        val simSlot: Int,
        val recorder: CallRecorder?,
        /** Our recording ran only as a backup to the trusted built-in recorder. */
        val backup: Boolean,
        /** Loudspeaker fallback used for this call (its result arrives from the accessibility service). */
        val speaker: SpeakerAssist.Session?,
        /** Why the loudspeaker was not used, when it was not ("" = not needed). */
        val speakerSkipped: String,
    ) {
        fun speakerDiagnostic(): String = speaker?.result ?: speakerSkipped
    }

    private data class CallLogRow(val number: String, val name: String, val type: String, val durationSec: Int, val simSlot: Int)

    /** Post-call work runs one call at a time, off the main thread. */
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    /** Live call sync (separate from [worker], which waits up to ~16 s per call for recordings). */
    private val pusher: ExecutorService = Executors.newSingleThreadExecutor()
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
    private var recorderIsBackup = false
    private var speaker: SpeakerAssist.Session? = null
    /** Latest loudspeaker session, kept after the call ends: its result can arrive a moment later. */
    @Volatile private var speakerForResults: SpeakerAssist.Session? = null
    private var speakerSkipped = ""
    private var speakerReceiver: BroadcastReceiver? = null
    /** Start of the most recent call; read by the worker to bound the previous call's search. */
    @Volatile private var latestCallStartMs = 0L
    /** Number of the most recent call (when known); its recording must not be taken for an earlier call. */
    @Volatile private var latestCallNumber = ""
    /** Recently handled calls (number, end time). Worker thread only. */
    private val recentCalls = ArrayDeque<Pair<String, Long>>()
    /** Catch-up / orphan recovery queued for this service instance. */
    private var startupTasksQueued = false

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
        CallSyncWorker.schedule(this) // takes over call sync whenever this service is not running (e.g. after a reboot)
        if (!startupTasksQueued) {
            startupTasksQueued = true
            val startedAt = System.currentTimeMillis()
            try {
                worker.execute {
                    // Calls made while tracking was off (e.g. after a reboot): the phone's own recordings
                    try { CallSync.catchUpBuiltInRecordings(this, startedAt) } catch (e: Exception) { e.printStackTrace() }
                    // AskEVA recordings left behind when the app was killed after a call
                    try { CallSync.recoverOrphanedRecordings(this, recordingsDir()) } catch (e: Exception) { e.printStackTrace() }
                }
            } catch (_: Exception) {}
        }
        startHeartbeat()
        CallMonitorEvents.emit("onCallMonitorState", mapOf("running" to true))
        return START_STICKY
    }

    private fun startHeartbeat() {
        if (heartbeat != null) return
        heartbeat = Executors.newSingleThreadScheduledExecutor().also {
            // Each ping also retries any call that could not be sent yet (no internet at call end)
            // ...and checks that the phone has not switched the recording accessibility service off
            it.scheduleWithFixedDelay({ sendHeartbeat(); schedulePush(0); A11yGuard.check(this) }, 0, HEARTBEAT_EVERY_SEC, java.util.concurrent.TimeUnit.SECONDS)
        }
    }

    private fun schedulePush(delayMs: Long) {
        try {
            pusher.execute {
                if (delayMs > 0) try { Thread.sleep(delayMs) } catch (_: InterruptedException) { return@execute }
                pushRecentCalls()
            }
        } catch (_: Exception) {}
    }

    /**
     * Sends this session's work-SIM calls from the call log to POST /calls/sync as soon as a call ends,
     * so the dashboard is live even when the app is closed (the app itself only syncs while open).
     * Same rows, timestamps and types as the app's own sync (MainActivity.getCallLogs), so the server's
     * de-duplication (caller + number + exact call-log time) stores every call once whoever sends it first.
     * Missed / rejected calls are included: they never reach [endCall], but they are in the call log.
     */
    private fun pushRecentCalls() {
        // A full batch means more rows are waiting. No internet: the next call end or heartbeat (2 min) retries.
        if (CallSync.pushRecentCalls(this)) schedulePush(0)
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
        if (CallMonitorStore.builtInTrusted(this)) "Uploading your phone's call recordings"
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
        if (speakerReceiver == null) {
            // Answers from the accessibility service (":a11y" process) about the loudspeaker
            val r = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    val result = intent?.getStringExtra(SpeakerAssist.EXTRA_RESULT) ?: return
                    val s = speakerForResults ?: return
                    s.result = if (s.usedSpeakerphoneApi && result == "already_on") "on_api" else result
                }
            }
            try {
                ContextCompat.registerReceiver(
                    this, r, IntentFilter(SpeakerAssist.ACTION_RESULT), ContextCompat.RECEIVER_NOT_EXPORTED
                )
                speakerReceiver = r
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun onPhoneState(intent: Intent) {
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        @Suppress("DEPRECATION")
        val extraNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
        val now = System.currentTimeMillis()

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                if (!inCall && lastState == TelephonyManager.EXTRA_STATE_IDLE) A11yGuard.onCallStarting(this)
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
                    latestCallNumber = callNumber
                    maybeStartOwnRecording()
                } else if (callNumber.isEmpty() && extraNumber.isNotEmpty()) {
                    callNumber = extraNumber
                    latestCallNumber = callNumber
                }
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                // Every call that ends (answered, missed or rejected) goes to the server right away
                if (inCall || lastState == TelephonyManager.EXTRA_STATE_RINGING) {
                    schedulePush(PUSH_DELAY_MS)
                    schedulePush(PUSH_DELAY_MS * 3) // slow dialers write the row late
                }
                if (inCall) {
                    endCall(now)
                } else if (lastState == TelephonyManager.EXTRA_STATE_RINGING) {
                    A11yGuard.onCallFinished(this) // missed / rejected: switched on at ringing, nothing to process
                }
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
        // The SIM of an outgoing call is often unknown at this point: record unless it is positively the
        // personal SIM. The call-log row decides after the call, and a non-work recording is deleted then.
        if (!CallMonitorStore.isWorkSim(callSlot, session.simMode, 1)) return
        val builtInTrusted = CallMonitorStore.builtInTrusted(this)
        // Android 9 and older give the mic to one app at a time: leave it to the phone's own recorder
        if (builtInTrusted && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        if (!CallMonitorStore.hasPermission(this, Manifest.permission.RECORD_AUDIO)) return
        // On only during calls (payment apps block it): switch it on for this one, if allowed
        A11yGuard.onCallStarting(this)
        // Without it Android hands us silence: a backup recording would be thrown away anyway
        if (builtInTrusted && !CallAccessibilityService.isEnabled(this)) return

        val stamp =SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())
        val suffix = Random.nextInt(0x10000).toString(16).padStart(4, '0')
        val prefix = if (incoming) "INC_CALL_REC" else "OUT_CALL_REC"
        val file = File(recordingsDir(), "${prefix}_${stamp}_$suffix.m4a")
        val rec = CallRecorder(this)
        if (rec.start(file)) {
            recorder = rec
            // Trusted built-in recorder: ours is only a backup, and the call stays on the earpiece
            recorderIsBackup = builtInTrusted
            if (!builtInTrusted) startSpeakerIfNeeded()
            updateNotification(if (speaker != null) "Recording this call (loudspeaker)" else "Recording this call")
            CallMonitorEvents.emit("onCallRecordingStatus", mapOf("isRecording" to true, "isIncoming" to incoming))
        }
    }

    /**
     * Our recording hears only this phone's microphone: put the call on the loudspeaker so the other
     * side is captured too, unless the caller is on a headset.
     */
    private fun startSpeakerIfNeeded() {
        speaker = null
        speakerSkipped = ""
        if (!CallMonitorStore.speakerNeeded(this)) return
        if (SpeakerAssist.headsetConnected(this)) {
            speakerSkipped = "headset"
            return
        }
        val s = SpeakerAssist.begin(this)
        // Android 12+ can only be switched by tapping the call screen, which needs the accessibility service
        if (!CallAccessibilityService.isEnabled(this)) s.result = if (s.usedSpeakerphoneApi) "on_api" else "no_accessibility"
        speaker = s
        speakerForResults = s
    }

    private fun endCall(now: Long) {
        val rec = recorder
        recorder = null
        rec?.requestStop() // stop capturing right away; the file is finished on the worker
        val spk = speaker
        speaker = null
        spk?.let { SpeakerAssist.end(this, it) }
        if (rec != null) {
            updateNotification(idleText())
            CallMonitorEvents.emit("onCallRecordingStatus", mapOf("isRecording" to false))
        }
        val ended = EndedCall(callStartMs, offhookMs, now, callNumber, incoming, callSlot, rec, recorderIsBackup, spk, speakerSkipped)
        recorderIsBackup = false
        speakerSkipped = ""
        callNumber = ""
        callSlot = 0
        try {
            worker.execute {
                try {
                    processEndedCall(ended)
                } finally {
                    // Calls up to here are handled: the background catch-up must not look at this one again
                    CallMonitorStore.setLastHandledCallMs(this, ended.endMs)
                    // Call handled: the accessibility service goes off again (payment apps), unless another call started
                    mainHandler.post { if (!inCall) A11yGuard.onCallFinished(this) }
                }
            }
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
        // Calls just before and after this one: a file named after one of them is not this call's recording
        val otherNumbers = (recentCalls.filter { call.startMs - it.second < 5 * 60_000L }.map { it.first } + latestCallNumber)
            .filter { it.isNotEmpty() && last10(it) != last10(number) }
            .distinct()
        recentCalls.addLast(number to call.endMs)
        while (recentCalls.size > 10) recentCalls.removeFirst()
        val slot = if (row != null && row.simSlot > 0) row.simSlot else call.simSlot
        if (!CallMonitorStore.isWorkSim(slot, session.simMode, SimSlots.activeSimCount(this))) {
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

        // Our recording of an outgoing call started at dialling: cut the ringing so it holds the conversation only.
        // Not when a second call joined (call waiting): this row's talk time then does not match the recording,
        // and cutting by it would remove real conversation.
        if (own != null && row != null && row.durationSec > 0 && callLogRowsDuring(call) <= 1) {
            val answeredAtMs = call.endMs - row.durationSec * 1000L
            // Call-log seconds are rounded down, so keep a one second margin before the answer
            val leadInMs = answeredAtMs - call.recorder!!.startedAtMs - 1000L
            if (leadInMs >= 1500L) AudioTools.trimLeading(own.file, leadInMs * 1000L)
        }

        // Built-in recorder: poll a few times, OEM recorders finalise the file late
        var found: BuiltInRecordingFinder.Found? = null
        var foundAfterMs = 0L
        // Without the audio-files permission we cannot look, which says nothing about the phone's recorder
        val searched = CallMonitorStore.hasMediaPermission(this)
        if (searched) {
            val exclude = CallMonitorStore.usedBuiltInFiles(this).toSet()
            for (offset in BUILTIN_POLL_OFFSETS_MS) {
                foundAfterMs = offset
                sleepUntil(call.endMs + offset)
                // A call started since then: its recording must not be taken for this one
                val next = latestCallStartMs
                var createdBefore = call.endMs + RecordingCandidateRanker.CREATED_AFTER_END_SLACK_MS
                if (next > call.endMs && next < createdBefore) createdBefore = next
                val info = RecordingCandidateRanker.CallInfo(call.startMs, call.endMs, talkSec, number, contact, createdBefore, otherNumbers)
                found = try { BuiltInRecordingFinder.find(this, info, exclude) } catch (_: Exception) { null }
                if (found != null) break
            }
        }

        if (found != null) {
            // AskEVA's own recording is kept until the phone's file has uploaded: if that file disappears or
            // is refused, ours is sent instead (RecordingUploader), and it is deleted once one of them is stored
            // The uploaded recording is the phone's own, with both voices: the last call was recorded with sound
            CallMonitorStore.setLastCapture(this, "ok", -1)
            CallMonitorStore.cancelNotification(this, CallMonitorStore.NOTIF_ID_RECORDING)
            RecordingDiagnostics.add(this, JSONObject().put("result", "builtin").put("builtInFound", true).put("talkSeconds", talkSec)
                .put("backup", call.backup).put("speaker", call.speakerDiagnostic())
                // Where and how late this phone's dialer saves its recordings (folder only, never the file name)
                .put("foundIn", found.folder).put("foundAfterSec", foundAfterMs / 1000))
            CallMonitorStore.onBuiltInFound(this, found.key, BuiltInRecordingFinder.usedKeyFor(found.displayName))
            RecordingQueue.add(
                this, QueuedRecording(
                    id = QueuedRecording.newId(), userId = session.userId, source = "builtin",
                    path = found.path, uri = found.uri, fileName = found.displayName,
                    callStartedAtMs = call.startMs, phoneNumber = number, contactName = contact, type = type,
                    simSlot = slot, durationSeconds = if (talkSec > 0) talkSec else found.durationSeconds,
                    fallbackPath = own?.file?.absolutePath ?: "",
                    fallbackSpeaker = if (own != null) call.speakerDiagnostic() else "",
                )
            )
        } else {
            if (talkSec >= MIN_TALK_SECONDS_FOR_MISS && searched) {
                CallMonitorStore.onBuiltInMissing(this)
                // We looked and the phone saved nothing readable: from the next call on, our recording
                // uses the loudspeaker (see CallMonitorStore.speakerNeeded)
                CallMonitorStore.onCallWithoutBuiltIn(this)
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
                put("backup", call.backup)
                put("speaker", call.speakerDiagnostic())
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
                        speaker = call.speakerDiagnostic(),
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

    /** Call-log rows that began during this call. More than one = call waiting joined a second call. */
    private fun callLogRowsDuring(call: EndedCall): Int {
        if (!CallMonitorStore.hasPermission(this, Manifest.permission.READ_CALL_LOG)) return 1
        return try {
            contentResolver.query(
                CallLog.Calls.CONTENT_URI, arrayOf(CallLog.Calls._ID),
                "${CallLog.Calls.DATE} >= ? AND ${CallLog.Calls.DATE} <= ?",
                arrayOf((call.startMs - 5000L).toString(), call.endMs.toString()), null
            )?.use { it.count } ?: 1
        } catch (_: Exception) {
            1 // cannot tell: trim as before
        }
    }

    private fun activeSubscriptions(): List<android.telephony.SubscriptionInfo> = SimSlots.activeSubscriptions(this)

    /** 1-based SIM slot of a call-log PHONE_ACCOUNT_ID (subscription id, ICCID or telecom account). 0 = unknown. */
    private fun slotFromAccountId(accountId: String): Int = SimSlots.Resolver(this).slotFor(accountId)

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

    private fun lookupContactName(number: String): String? = CallSync.lookupContactName(this, number)

    override fun onDestroy() {
        isRunning = false
        heartbeat?.shutdownNow()
        heartbeat = null
        try { receiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        receiver = null
        // Finish (and queue) a call that is still being recorded
        if (inCall) endCall(System.currentTimeMillis())
        inCall = false
        try { speakerReceiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        speakerReceiver = null
        worker.shutdown() // queued post-call work still completes
        pusher.shutdown()
        CallMonitorEvents.emit("onCallMonitorState", mapOf("running" to false))
        super.onDestroy()
    }
}
