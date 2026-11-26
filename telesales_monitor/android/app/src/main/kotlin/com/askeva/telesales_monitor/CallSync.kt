package com.askeva.telesales_monitor

import android.Manifest
import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.CallLog
import android.provider.ContactsContract
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/**
 * Call-log work shared by [CallMonitorService] (live, while it runs) and [CallSyncWorker] (every
 * 15 minutes while it does not, e.g. after a reboot or an app update on Android 14+, where the service
 * may only be started by opening the app):
 *  - [pushRecentCalls]: send this session's work-SIM calls to POST /calls/sync.
 *  - [catchUpBuiltInRecordings]: queue the phone's own recordings of calls the service did not see.
 *  - [recoverOrphanedRecordings]: queue AskEVA recordings left behind when the app was killed mid-call.
 */
object CallSync {
    /** Calls per /calls/sync request. */
    const val MAX_PUSH_BATCH = 200
    /** After a new row was sent, recent rows are re-sent for this long: some phones fill in the duration late. */
    private const val RESEND_RECENT_FOR_MS = 15 * 60_000L
    /** A call must have ended this long ago before the catch-up looks for its recording (files are finalised late). */
    private const val CATCH_UP_AFTER_END_MS = 2 * 60_000L
    /** At most this many calls per catch-up run (the next run continues). */
    private const val CATCH_UP_MAX_ROWS = 60
    /** An unqueued AskEVA recording this old is left over from a killed app, not one still being handled. */
    private const val ORPHAN_MIN_AGE_MS = 10 * 60_000L

    private val pushLock = Any()
    private val catchUpLock = Any()

    private fun last10(s: String) = s.filter { it.isDigit() }.takeLast(10)

    fun isoUtc(ms: Long): String {
        val f = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        f.timeZone = TimeZone.getTimeZone("UTC")
        return f.format(Date(ms))
    }

    fun lookupContactName(ctx: Context, number: String): String? {
        if (number.isEmpty() || !CallMonitorStore.hasPermission(ctx, Manifest.permission.READ_CONTACTS)) return null
        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
            ctx.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0)?.ifEmpty { null } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    // ------------------------------------------------------------------ Call sync

    /**
     * Sends this session's work-SIM calls from the call log to POST /calls/sync, so the dashboard is live
     * even when the app is closed. Same rows, timestamps and types as the app's own sync
     * (MainActivity.getCallLogs), so the server's de-duplication (caller + number + exact call-log time)
     * stores every call once whoever sends it first. Missed / rejected calls are included.
     * Returns true when a full batch was sent (more rows are waiting).
     */
    fun pushRecentCalls(ctx: Context): Boolean = synchronized(pushLock) { pushLocked(ctx) }

    private fun pushLocked(ctx: Context): Boolean {
        val session = CallMonitorStore.session(ctx) ?: return false
        if (!session.isCallerContext) return false
        if (session.token == CallMonitorStore.authFailedToken(ctx)) return false
        if (!CallMonitorStore.hasPermission(ctx, Manifest.permission.READ_CALL_LOG)) return false
        val loginMs = CallMonitorStore.loginSessionMs(ctx) ?: return false
        val ack = CallMonitorStore.callPushAck(ctx, session.userId)
        val ackId = CallMonitorStore.callPushAckId(ctx, session.userId)
        // Calls before the work session started are personal and never sent
        val floor = loginMs - 5000L
        // Re-send the last 10 minutes too: rows can be updated after they were first sent
        val since = maxOf(floor, ack - 10 * 60_000L)
        val now = System.currentTimeMillis()
        if (ackId > 0 && !hasRowsAfter(ctx, floor, ackId) &&
            now - CallMonitorStore.callPushNewRowsAt(ctx, session.userId) > RESEND_RECENT_FOR_MS
        ) {
            // Nothing new, and the last new call is long finished: the same rows are not sent again
            return false
        }
        val selection: String
        val args: Array<String>
        if (ackId > 0) {
            // ...plus every row written since the last accepted sync, however early its call began: a long
            // call is logged when it ends, after shorter calls that started later
            selection = "${CallLog.Calls.DATE} >= ? AND (${CallLog.Calls.DATE} >= ? OR ${CallLog.Calls._ID} > ?)"
            args = arrayOf(floor.toString(), since.toString(), ackId.toString())
        } else {
            // First sync of this build: as before, then row ids are tracked from here on
            selection = "${CallLog.Calls.DATE} >= ?"
            args = arrayOf(since.toString())
        }

        val calls = JSONArray()
        var newest = ack
        var newestId = ackId
        try {
            val projection = arrayOf(
                CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME, CallLog.Calls.TYPE,
                CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.PHONE_ACCOUNT_ID, CallLog.Calls._ID
            )
            val sims = SimSlots.Resolver(ctx)
            val simCount = SimSlots.activeSimCount(ctx)
            ctx.contentResolver.query(
                CallLog.Calls.CONTENT_URI, projection, selection, args, "${CallLog.Calls.DATE} ASC"
            )?.use { c ->
                while (c.moveToNext() && calls.length() < MAX_PUSH_BATCH) {
                    val id = c.getLong(6)
                    if (id > newestId) newestId = id
                    val slot = sims.slotFor(c.getString(5))
                    if (!CallMonitorStore.isWorkSim(slot, session.simMode, simCount)) continue // personal SIM: never leaves the phone
                    val number = c.getString(0) ?: ""
                    val date = c.getLong(3)
                    val type = when (c.getInt(2)) {
                        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                        CallLog.Calls.MISSED_TYPE -> "missed"
                        CallLog.Calls.REJECTED_TYPE, CallLog.Calls.BLOCKED_TYPE -> "rejected"
                        else -> "incoming"
                    }
                    val cached = c.getString(1)
                    val name = if (!cached.isNullOrEmpty() && cached != number) cached else (lookupContactName(ctx, number) ?: number.ifEmpty { "Unknown" })
                    calls.put(
                        JSONObject()
                            .put("contactName", name)
                            .put("phoneNumber", number)
                            .put("type", type)
                            .put("timestamp", isoUtc(date))
                            .put("durationSeconds", c.getInt(4).coerceAtLeast(0))
                            .put("simSlot", slot)
                            .put("note", "")
                    )
                    if (date > newest) newest = date
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
        if (calls.length() == 0) {
            // Only personal-SIM rows were new: remember them so they are not looked at again
            if (newestId > ackId) CallMonitorStore.setCallPushAckId(ctx, session.userId, newestId)
            return false
        }

        val body = JSONObject()
            .put("callerId", session.userId)
            .put("callerName", session.callerName)
            .put("callerPhone", session.callerPhone)
            .put("calls", calls)
        var conn: java.net.HttpURLConnection? = null
        try {
            conn = (java.net.URL("${CallMonitorStore.baseUrl(ctx)}/calls/sync").openConnection() as java.net.HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000
                readTimeout = 30_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer ${session.token}")
            }
            conn.outputStream.use { it.write(body.toString().toByteArray()) }
            val code = conn.responseCode
            if (code in 200..299) {
                CallMonitorStore.setCallPushAck(ctx, session.userId, newest)
                if (newestId > ackId) {
                    CallMonitorStore.setCallPushAckId(ctx, session.userId, newestId)
                    CallMonitorStore.setCallPushNewRowsAt(ctx, session.userId, now)
                }
                CallMonitorEvents.emit("onCallsPushed", mapOf("count" to calls.length()))
                return calls.length() >= MAX_PUSH_BATCH
            }
        } catch (_: Exception) {
            // No internet: the next call end, heartbeat or background sync retries
        } finally {
            conn?.disconnect()
        }
        return false
    }

    /** Whether a call-log row (since [floor]) was written after row [afterId]. */
    private fun hasRowsAfter(ctx: Context, floor: Long, afterId: Long): Boolean = try {
        ctx.contentResolver.query(
            CallLog.Calls.CONTENT_URI, arrayOf(CallLog.Calls._ID),
            "${CallLog.Calls.DATE} >= ? AND ${CallLog.Calls._ID} > ?",
            arrayOf(floor.toString(), afterId.toString()), null
        )?.use { it.moveToFirst() } ?: false
    } catch (_: Exception) {
        true // cannot tell: send as before
    }

    // ------------------------------------------------------------------ Catch-up of built-in recordings

    private data class Row(
        val number: String, val name: String, val type: Int, val date: Long, val durationSec: Int, val accountId: String,
    )

    /**
     * Queues the phone's own (OEM dialer) recordings of calls that ended while the call monitor was not
     * running, e.g. after a reboot before the app was opened. Calls after [CallMonitorStore.lastHandledCallMs]
     * and before [beforeMs] are looked at once. Nothing is back-filled on the first run.
     * Same matching rules as the live service ([RecordingCandidateRanker]). Returns the number queued.
     */
    fun catchUpBuiltInRecordings(ctx: Context, beforeMs: Long): Int = synchronized(catchUpLock) { catchUpLocked(ctx, beforeMs) }

    private fun catchUpLocked(ctx: Context, beforeMs: Long): Int {
        val session = CallMonitorStore.recordingSession(ctx) ?: return 0
        if (!CallMonitorStore.hasPermission(ctx, Manifest.permission.READ_CALL_LOG)) return 0
        if (!CallMonitorStore.hasMediaPermission(ctx)) return 0
        val loginMs = CallMonitorStore.loginSessionMs(ctx) ?: return 0
        val last = CallMonitorStore.lastHandledCallMs(ctx)
        if (last <= 0L) {
            CallMonitorStore.setLastHandledCallMs(ctx, beforeMs) // first run of this build: start from now
            return 0
        }
        val from = maxOf(last + 1, loginMs - 5000L)
        if (from >= beforeMs) return 0

        val rows = ArrayList<Row>()
        try {
            ctx.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME, CallLog.Calls.TYPE,
                    CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.PHONE_ACCOUNT_ID
                ),
                "${CallLog.Calls.DATE} >= ?", arrayOf(from.toString()), "${CallLog.Calls.DATE} ASC"
            )?.use { c ->
                while (c.moveToNext() && rows.size <= CATCH_UP_MAX_ROWS) {
                    rows.add(Row(c.getString(0) ?: "", c.getString(1) ?: "", c.getInt(2), c.getLong(3), c.getInt(4), c.getString(5) ?: ""))
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            return 0
        }

        val now = System.currentTimeMillis()
        val sims = SimSlots.Resolver(ctx)
        val simCount = SimSlots.activeSimCount(ctx)
        val exclude = CallMonitorStore.usedBuiltInFiles(ctx).toMutableSet()
        var handledUpTo = last
        var queued = 0
        for ((i, r) in rows.withIndex()) {
            if (i >= CATCH_UP_MAX_ROWS || r.date >= beforeMs) break
            val endEst = r.date + r.durationSec * 1000L
            // Still going, or ended too recently for the dialer to have finished its file: the next run
            if (endEst + CATCH_UP_AFTER_END_MS > now) break
            handledUpTo = maxOf(handledUpTo, r.date)
            if (r.durationSec <= 0) continue // not connected
            val slot = sims.slotFor(r.accountId)
            if (!CallMonitorStore.isWorkSim(slot, session.simMode, simCount)) continue
            val nextStart = rows.getOrNull(i + 1)?.date?.takeIf { it > r.date } ?: Long.MAX_VALUE
            // The call-log time is when the call began (ringing included): allow for the ringing and late indexing
            val createdBefore = minOf(nextStart, endEst + 2 * 60_000L)
            val contact = r.name.ifEmpty { lookupContactName(ctx, r.number) ?: r.number.ifEmpty { "Unknown" } }
            val others = listOfNotNull(rows.getOrNull(i - 1)?.number, rows.getOrNull(i + 1)?.number)
                .filter { it.isNotEmpty() && last10(it) != last10(r.number) }
            val info = RecordingCandidateRanker.CallInfo(r.date, endEst, r.durationSec, r.number, contact, createdBefore, others)
            val found = try { BuiltInRecordingFinder.find(ctx, info, exclude) } catch (_: Exception) { null } ?: continue
            val usedName = BuiltInRecordingFinder.usedKeyFor(found.displayName)
            CallMonitorStore.onBuiltInFound(ctx, found.key, usedName)
            exclude.add(found.key)
            exclude.add(usedName)
            RecordingQueue.add(
                ctx, QueuedRecording(
                    id = QueuedRecording.newId(), userId = session.userId, source = "builtin",
                    path = found.path, uri = found.uri, fileName = found.displayName,
                    callStartedAtMs = r.date, phoneNumber = r.number, contactName = contact,
                    type = if (r.type == CallLog.Calls.OUTGOING_TYPE) "OUTGOING" else "INCOMING",
                    simSlot = slot, durationSeconds = if (r.durationSec > 0) r.durationSec else found.durationSeconds,
                )
            )
            queued++
        }
        CallMonitorStore.setLastHandledCallMs(ctx, handledUpTo)
        if (queued > 0) {
            CallMonitorEvents.emit("onUploadQueueChanged")
            RecordingUploader.schedule(ctx)
        }
        return queued
    }

    // ------------------------------------------------------------------ Recordings left by a killed app

    /** AskEVA's own recording names: INC_CALL_REC_20261124_101530_123_ab12.m4a (see CallMonitorService). */
    private val OWN_NAME = Regex("^(INC|OUT)_CALL_REC_(\\d{8}_\\d{6}_\\d{3})_[0-9a-f]{4}\\.m4a$")

    /**
     * Files in [dir] (AskEVA's call recordings) that no queue item refers to were left behind when the app
     * was killed after a call. A playable one of a connected work call in this session is queued with that
     * call's details; the rest (unfinished files, personal calls, calls before sign-in) are deleted, as the
     * call monitor would have done.
     */
    fun recoverOrphanedRecordings(ctx: Context, dir: File): Int {
        val files = try { dir.listFiles() } catch (_: Exception) { null } ?: return 0
        if (files.isEmpty()) return 0
        val session = CallMonitorStore.recordingSession(ctx)
        val loginMs = CallMonitorStore.loginSessionMs(ctx)
        val referenced = RecordingQueue.referencedPaths(ctx)
        val now = System.currentTimeMillis()
        var recovered = 0
        for (f in files) {
            if (!f.isFile || f.absolutePath in referenced) continue
            if (now - f.lastModified() < ORPHAN_MIN_AGE_MS) continue // may still belong to a call being handled
            val m = OWN_NAME.find(f.name)
            val startedMs = m?.let { parseStamp(it.groupValues[2]) } ?: 0L
            val incoming = m?.groupValues?.get(1) == "INC"
            var row: Row? = null
            var durationSec = 0
            if (session != null && loginMs != null && startedMs >= loginMs - 5000L) {
                durationSec = playableSeconds(f)
                if (durationSec > 0) row = rowNear(ctx, startedMs, incoming)
            }
            if (session == null || row == null || row.durationSec <= 0) {
                try { f.delete() } catch (_: Exception) {}
                continue
            }
            val slot = SimSlots.Resolver(ctx).slotFor(row.accountId)
            if (!CallMonitorStore.isWorkSim(slot, session.simMode, SimSlots.activeSimCount(ctx))) {
                try { f.delete() } catch (_: Exception) {}
                continue
            }
            val contact = row.name.ifEmpty { lookupContactName(ctx, row.number) ?: row.number.ifEmpty { "Unknown" } }
            RecordingQueue.add(
                ctx, QueuedRecording(
                    id = QueuedRecording.newId(), userId = session.userId, source = "own",
                    path = f.absolutePath, uri = "", fileName = f.name,
                    callStartedAtMs = row.date, phoneNumber = row.number, contactName = contact,
                    type = if (row.type == CallLog.Calls.OUTGOING_TYPE) "OUTGOING" else "INCOMING",
                    simSlot = slot, durationSeconds = row.durationSec,
                )
            )
            recovered++
        }
        if (recovered > 0) {
            CallMonitorEvents.emit("onUploadQueueChanged")
            RecordingUploader.schedule(ctx)
        }
        return recovered
    }

    private fun parseStamp(stamp: String): Long? = try {
        SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).parse(stamp)?.time
    } catch (_: Exception) {
        null
    }

    /** Length of a finished audio file in seconds; 0 when it cannot be read (unfinished recording). */
    private fun playableSeconds(f: File): Int {
        if (f.length() < 1024) return 0
        return try {
            val mmr = MediaMetadataRetriever()
            try {
                mmr.setDataSource(f.absolutePath)
                ((mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) / 1000).toInt()
            } finally {
                mmr.release()
            }
        } catch (_: Exception) {
            0
        }
    }

    /**
     * The call-log row of a call whose recording started at [startedMs]: same direction, began up to
     * 2 minutes earlier (ringing) or a few seconds later, closest wins.
     */
    private fun rowNear(ctx: Context, startedMs: Long, incoming: Boolean): Row? {
        if (!CallMonitorStore.hasPermission(ctx, Manifest.permission.READ_CALL_LOG)) return null
        return try {
            var best: Row? = null
            var bestDiff = Long.MAX_VALUE
            ctx.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME, CallLog.Calls.TYPE,
                    CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.PHONE_ACCOUNT_ID
                ),
                "${CallLog.Calls.DATE} >= ? AND ${CallLog.Calls.DATE} <= ?",
                arrayOf((startedMs - 120_000L).toString(), (startedMs + 10_000L).toString()), null
            )?.use { c ->
                while (c.moveToNext()) {
                    val type = c.getInt(2)
                    if ((type == CallLog.Calls.OUTGOING_TYPE) == incoming) continue
                    if (c.getInt(4) <= 0) continue // not connected (missed / rejected): not this recording's call
                    val date = c.getLong(3)
                    val diff = abs(date - startedMs)
                    if (diff < bestDiff) {
                        bestDiff = diff
                        best = Row(c.getString(0) ?: "", c.getString(1) ?: "", type, date, c.getInt(4), c.getString(5) ?: "")
                    }
                }
            }
            best
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Every 15 minutes, while the call monitor is NOT running (after a reboot or app update on Android 14+
 * the service can only be restarted by opening the app): keeps the dashboard's call list up to date and
 * queues the phone's own recordings of those calls. Does nothing while the service runs.
 */
class CallSyncWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        try {
            if (CallMonitorService.isRunning) return Result.success() // the service does this live
            val ctx = applicationContext
            if (CallMonitorStore.session(ctx) == null) return Result.success()
            var batches = 0
            while (!isStopped && batches++ < 5 && CallSync.pushRecentCalls(ctx)) { /* full batch: send the next */ }
            if (!isStopped) CallSync.catchUpBuiltInRecordings(ctx, System.currentTimeMillis())
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return Result.success()
    }

    companion object {
        private const val WORK_NAME = "askeva_call_sync"

        fun schedule(ctx: Context) {
            try {
                val request = PeriodicWorkRequestBuilder<CallSyncWorker>(15, TimeUnit.MINUTES).build()
                WorkManager.getInstance(ctx.applicationContext)
                    .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
