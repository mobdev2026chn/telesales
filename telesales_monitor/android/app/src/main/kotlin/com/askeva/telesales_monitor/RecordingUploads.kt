package com.askeva.telesales_monitor

import android.content.Context
import android.net.Uri
import android.util.Base64
import android.util.Base64OutputStream
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.FilterOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** One finished call recording waiting for upload. Exactly one of [path] / [uri] is set. */
data class QueuedRecording(
    val id: String,
    val userId: String,
    /** "own" = our mic recording in filesDir (deleted after upload); "builtin" = the OEM dialer's file (never deleted). */
    val source: String,
    val path: String,
    val uri: String,
    val fileName: String,
    val callStartedAtMs: Long,
    val phoneNumber: String,
    val contactName: String,
    /** "INCOMING" | "OUTGOING" */
    val type: String,
    val simSlot: Int,
    val durationSeconds: Int,
    val attempts: Int = 0,
    val createdAtMs: Long = System.currentTimeMillis(),
    /** Own recordings: how the loudspeaker was handled ([SpeakerAssist.Session.result]), "" = not used. */
    val speaker: String = "",
    /**
     * Built-in recordings: AskEVA's own recording of the same call, kept until the built-in file has
     * uploaded. Used instead when the built-in file disappears or is rejected. "" = none.
     */
    val fallbackPath: String = "",
    val fallbackSpeaker: String = "",
    /**
     * Set aside (not deleted) after the server rejected it or after [RecordingUploader] gave up retrying.
     * Parked items are retried once a day and removed only when they are too old. 0 = active.
     */
    val parkedAtMs: Long = 0L,
    /** Why it was parked, e.g. "HTTP 400" (never shown to customers, kept for support). */
    val lastError: String = "",
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id).put("userId", userId).put("source", source).put("path", path).put("uri", uri)
        .put("fileName", fileName).put("callStartedAtMs", callStartedAtMs).put("phoneNumber", phoneNumber)
        .put("contactName", contactName).put("type", type).put("simSlot", simSlot)
        .put("durationSeconds", durationSeconds).put("attempts", attempts).put("createdAtMs", createdAtMs)
        .put("speaker", speaker)
        .put("fallbackPath", fallbackPath).put("fallbackSpeaker", fallbackSpeaker)
        .put("parkedAtMs", parkedAtMs).put("lastError", lastError)

    companion object {
        fun newId(): String = UUID.randomUUID().toString()

        fun fromJson(o: JSONObject) = QueuedRecording(
            id = o.optString("id").ifEmpty { newId() },
            userId = o.optString("userId"),
            source = o.optString("source", "own"),
            path = o.optString("path"),
            uri = o.optString("uri"),
            fileName = o.optString("fileName"),
            callStartedAtMs = o.optLong("callStartedAtMs"),
            phoneNumber = o.optString("phoneNumber"),
            contactName = o.optString("contactName"),
            type = o.optString("type", "OUTGOING"),
            simSlot = o.optInt("simSlot"),
            durationSeconds = o.optInt("durationSeconds"),
            attempts = o.optInt("attempts"),
            createdAtMs = o.optLong("createdAtMs", System.currentTimeMillis()),
            speaker = o.optString("speaker"),
            fallbackPath = o.optString("fallbackPath"),
            fallbackSpeaker = o.optString("fallbackSpeaker"),
            parkedAtMs = o.optLong("parkedAtMs", 0L),
            lastError = o.optString("lastError"),
        )
    }
}

/** Persisted upload queue: a JSON array in filesDir, survives process death and reboots. */
object RecordingQueue {
    private val lock = Any()
    private fun file(ctx: Context) = File(ctx.filesDir, "recording_upload_queue.json")
    /** The previous good copy: read when the main file is missing or damaged, so the queue is never wiped. */
    private fun backupFile(ctx: Context) = File(ctx.filesDir, "recording_upload_queue.json.bak")

    fun all(ctx: Context): List<QueuedRecording> = synchronized(lock) { readLocked(ctx) }

    private fun parse(f: File): MutableList<QueuedRecording> {
        val arr = JSONArray(f.readText())
        return (0 until arr.length()).mapNotNull { i -> arr.optJSONObject(i)?.let { QueuedRecording.fromJson(it) } }.toMutableList()
    }

    private fun readLocked(ctx: Context): MutableList<QueuedRecording> {
        val f = file(ctx)
        if (f.exists()) {
            try {
                return parse(f)
            } catch (_: Exception) {
                // Damaged: keep it aside for support instead of overwriting it with an empty list
                try {
                    val bad = File(ctx.filesDir, "recording_upload_queue.json.corrupt")
                    bad.delete()
                    if (!f.renameTo(bad)) f.delete()
                } catch (_: Exception) {}
            }
        }
        val bak = backupFile(ctx)
        if (bak.exists()) {
            try { return parse(bak) } catch (_: Exception) {}
        }
        return mutableListOf()
    }

    private fun writeLocked(ctx: Context, items: List<QueuedRecording>) {
        try {
            val arr = JSONArray()
            items.forEach { arr.put(it.toJson()) }
            val text = arr.toString()
            val tmp = File(ctx.filesDir, "recording_upload_queue.json.tmp")
            tmp.writeText(text)
            val main = file(ctx)
            val bak = backupFile(ctx)
            if (main.exists()) {
                bak.delete()
                if (!main.renameTo(bak)) main.delete()
            }
            if (!tmp.renameTo(main)) {
                main.writeText(text)
                tmp.delete()
            }
        } catch (_: Exception) {}
    }

    /** Files that belong to a queued item (its own file or the kept fallback). */
    fun referencedPaths(ctx: Context): Set<String> =
        all(ctx).flatMap { listOf(it.path, it.fallbackPath) }.filter { it.isNotEmpty() }.toSet()

    fun add(ctx: Context, item: QueuedRecording) = synchronized(lock) {
        val items = readLocked(ctx)
        // Same file queued twice (e.g. legacy migration run again): keep one
        items.removeAll { (it.path.isNotEmpty() && it.path == item.path) || (it.uri.isNotEmpty() && it.uri == item.uri) }
        items.add(item)
        writeLocked(ctx, items)
    }

    fun remove(ctx: Context, id: String) = synchronized(lock) {
        val items = readLocked(ctx)
        if (items.removeAll { it.id == id }) writeLocked(ctx, items)
    }

    fun update(ctx: Context, item: QueuedRecording) = synchronized(lock) {
        val items = readLocked(ctx)
        val i = items.indexOfFirst { it.id == item.id }
        if (i >= 0) {
            items[i] = item
            writeLocked(ctx, items)
        }
    }

    fun countFor(ctx: Context, userId: String): Int = all(ctx).count { it.userId == userId }
}

object RecordingUploader {
    private const val WORK_NAME = "askeva_recording_upload"
    /** Stop retrying one recording after this many failed attempts (about a week with WorkManager backoff); it is then parked. */
    private const val MAX_ATTEMPTS = 40
    /** Logcat tag of every upload result: adb logcat -s AskEvaUpload */
    private const val UPLOAD_TAG = "AskEvaUpload"
    /** Recordings of a user who has not signed in again for this long are discarded. */
    private const val FOREIGN_USER_MAX_AGE_MS = 14L * 24 * 3600 * 1000
    /** A parked recording (rejected by the server / gave up retrying) is tried again this often... */
    private const val PARKED_RETRY_EVERY_MS = 24L * 3600 * 1000
    /** ...and removed once the call is this old. */
    private const val PARKED_MAX_AGE_MS = 30L * 24 * 3600 * 1000
    /** Uncompressed (WAV) recordings above this size exceed the server's upload limit: compress them first. */
    private const val LARGE_UNCOMPRESSED_BYTES = 40L * 1024 * 1024

    private val draining = AtomicBoolean(false)

    /**
     * OK = stored on the server. AUTH = token rejected. RETRY = temporary problem (network, 5xx, 408, 429).
     * MISSING = the audio file is gone or empty. REJECTED = the server refused this request (other 4xx).
     */
    enum class Outcome { OK, AUTH, RETRY, MISSING, REJECTED }

    /** Release builds never write file names (often a contact name or number) or server replies to the log. */
    private fun isDebuggable(ctx: Context): Boolean =
        (ctx.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun logLabel(ctx: Context, item: QueuedRecording): String =
        if (isDebuggable(ctx)) item.fileName else "${item.source} recording ${item.id.take(8)}"

    /** Starts (or restarts) the upload worker. Runs whenever the network is available, app alive or not. */
    fun schedule(ctx: Context) {
        try {
            val request = OneTimeWorkRequestBuilder<RecordingUploadWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            // While a drain runs, queue another pass after it (it may have missed the new item);
            // otherwise REPLACE, so a worker waiting out a long backoff is retried immediately.
            val policy = if (draining.get()) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.REPLACE
            WorkManager.getInstance(ctx.applicationContext).enqueueUniqueWork(WORK_NAME, policy, request)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /** Uploads every queued recording of the signed-in user. Returns true when something must be retried. */
    fun drain(ctx: Context, isStopped: () -> Boolean): Boolean {
        if (!draining.compareAndSet(false, true)) return false
        try {
            val session = CallMonitorStore.session(ctx) ?: return false // nothing can be sent without a token
            if (session.token == CallMonitorStore.authFailedToken(ctx)) return false
            val base = CallMonitorStore.baseUrl(ctx)
            RecordingDiagnostics.send(ctx, base, session.token)
            var needRetry = false
            var uploaded = 0
            val now = System.currentTimeMillis()

            for (item in RecordingQueue.all(ctx)) {
                if (isStopped()) return true
                if (item.userId != session.userId) {
                    if (now - item.createdAtMs > FOREIGN_USER_MAX_AGE_MS) discard(ctx, item)
                    continue
                }
                val parked = item.parkedAtMs > 0L
                if (parked) {
                    if (now - item.createdAtMs > PARKED_MAX_AGE_MS) {
                        Log.w(UPLOAD_TAG, "removing ${logLabel(ctx, item)}: still not accepted after 30 days (${item.lastError})")
                        discard(ctx, item)
                        continue
                    }
                    // Too big for the server: re-sending it daily would only waste mobile data
                    val retryEvery = if (item.lastError == "HTTP 413") 7 * PARKED_RETRY_EVERY_MS else PARKED_RETRY_EVERY_MS
                    if (now - item.parkedAtMs < retryEvery) continue
                }
                val result = uploadOne(ctx, base, session, item)
                when (result.outcome) {
                    Outcome.OK -> {
                        RecordingQueue.remove(ctx, item.id)
                        if (item.source == "own" && item.path.isNotEmpty()) deleteQuietly(item.path)
                        if (item.fallbackPath.isNotEmpty()) deleteQuietly(item.fallbackPath)
                        uploaded++
                    }
                    Outcome.MISSING, Outcome.REJECTED -> {
                        val fallback = fallbackItem(item)
                        when {
                            // The phone's own file is gone or refused: send AskEVA's recording of the call instead
                            fallback != null -> {
                                RecordingQueue.update(ctx, fallback)
                                needRetry = true
                            }
                            // Nothing left to send
                            result.outcome == Outcome.MISSING -> discard(ctx, item)
                            // Refused: keep the file and try again tomorrow (e.g. after a server fix)
                            else -> park(ctx, item, now, result.error)
                        }
                    }
                    Outcome.AUTH -> {
                        CallMonitorStore.setAuthFailedToken(ctx, session.token)
                        CallMonitorStore.postAlert(
                            ctx, CallMonitorStore.NOTIF_ID_LOGIN,
                            "Please log in again",
                            "Your AskEVA session has expired. Open the app and sign in so your call recordings can upload."
                        )
                        CallMonitorEvents.emit("onUploadAuthFailed")
                        return false // stop retrying until a new login
                    }
                    Outcome.RETRY -> {
                        if (parked) {
                            // Already set aside: the next try is tomorrow, not with the fast retries
                            park(ctx, item, now, item.lastError)
                        } else {
                            val next = item.copy(attempts = item.attempts + 1)
                            if (next.attempts >= MAX_ATTEMPTS) park(ctx, item, now, result.error.ifEmpty { "too many attempts" }) else {
                                RecordingQueue.update(ctx, next)
                                needRetry = true
                            }
                        }
                    }
                }
            }
            if (uploaded > 0) {
                CallMonitorStore.cancelNotification(ctx, CallMonitorStore.NOTIF_ID_LOGIN)
                CallMonitorEvents.emit("onRecordingUploaded", mapOf("count" to uploaded))
            }
            return needRetry
        } finally {
            draining.set(false)
            CallMonitorEvents.emit("onUploadQueueChanged")
        }
    }

    private fun discard(ctx: Context, item: QueuedRecording) {
        RecordingQueue.remove(ctx, item.id)
        if (item.source == "own" && item.path.isNotEmpty()) deleteQuietly(item.path)
        if (item.fallbackPath.isNotEmpty()) deleteQuietly(item.fallbackPath)
    }

    /** Sets a recording aside without deleting its file; it is tried again after [PARKED_RETRY_EVERY_MS]. */
    private fun park(ctx: Context, item: QueuedRecording, now: Long, error: String) {
        if (item.parkedAtMs == 0L) Log.w(UPLOAD_TAG, "keeping ${logLabel(ctx, item)} on the phone, will try again tomorrow ($error)")
        RecordingQueue.update(ctx, item.copy(parkedAtMs = now, lastError = error.take(80)))
    }

    /** The same call as AskEVA's own recording, when one was kept for a built-in recording. */
    private fun fallbackItem(item: QueuedRecording): QueuedRecording? {
        if (item.source != "builtin" || item.fallbackPath.isEmpty()) return null
        val f = File(item.fallbackPath)
        if (!f.exists() || f.length() == 0L) return null
        return item.copy(
            source = "own", path = item.fallbackPath, uri = "", fileName = f.name,
            speaker = item.fallbackSpeaker, fallbackPath = "", fallbackSpeaker = "",
            attempts = 0, parkedAtMs = 0L, lastError = "",
        )
    }

    private fun deleteQuietly(path: String) {
        try { File(path).delete() } catch (_: Exception) {}
    }

    private fun isoUtc(ms: Long): String {
        val f = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        f.timeZone = TimeZone.getTimeZone("UTC")
        return f.format(Date(ms))
    }

    private fun openAudio(ctx: Context, item: QueuedRecording): InputStream? {
        return if (item.uri.isNotEmpty()) {
            ctx.contentResolver.openInputStream(Uri.parse(item.uri))
        } else {
            val f = File(item.path)
            if (!f.exists() || f.length() == 0L) null else FileInputStream(f)
        }
    }

    /** Keeps the connection's stream open when the Base64 encoder is closed (closing flushes the padding). */
    private class NonClosingStream(out: OutputStream) : FilterOutputStream(out) {
        override fun write(b: ByteArray, off: Int, len: Int) { out.write(b, off, len) }
        override fun close() { flush() }
    }

    /**
     * POST <base>/recordings. The JSON body is streamed: metadata prefix, the audio file
     * base64-encoded on the fly, then the closing quote/brace, so long calls never sit in memory.
     * The server de-duplicates by caller + fileName, so a retry after a lost response is harmless.
     */
    /**
     * AMR recordings (many OEM dialers) cannot be played by browsers: upload an AAC copy instead.
     * The copy's name is derived from the original, so the server's caller + fileName de-duplication
     * still recognises a retry. Null = upload the original.
     */
    private fun playableCopy(ctx: Context, item: QueuedRecording): File? {
        if (item.source != "builtin") return null // our own recordings are already AAC
        return try {
            // AMR (browsers cannot play it), or a WAV too big for the server's upload limit
            val needs = AudioTools.needsTranscode(ctx, item.path, item.uri) ||
                (sizeOf(ctx, item) > LARGE_UNCOMPRESSED_BYTES && AudioTools.isPcm16(ctx, item.path, item.uri))
            if (!needs) return null
            val out = File(ctx.cacheDir, "upload_${item.id}.m4a")
            if (AudioTools.transcodeToAac(ctx, item.path, item.uri, out)) out else { out.delete(); null }
        } catch (_: Exception) {
            null
        }
    }

    /** Size of the recording in bytes, 0 when unknown. */
    private fun sizeOf(ctx: Context, item: QueuedRecording): Long = try {
        if (item.uri.isNotEmpty()) {
            ctx.contentResolver.openAssetFileDescriptor(Uri.parse(item.uri), "r")?.use { it.length.coerceAtLeast(0L) } ?: 0L
        } else {
            File(item.path).length()
        }
    } catch (_: Exception) {
        0L
    }

    data class UploadResult(val outcome: Outcome, val error: String = "")

    fun uploadOne(ctx: Context, base: String, session: CallMonitorStore.Session, item: QueuedRecording): UploadResult {
        val converted = playableCopy(ctx, item)
        try {
            return uploadStream(ctx, base, session, item, converted)
        } finally {
            converted?.delete()
        }
    }

    private fun uploadStream(ctx: Context, base: String, session: CallMonitorStore.Session, item: QueuedRecording, converted: File?): UploadResult {
        val input: InputStream = try {
            if (converted != null) FileInputStream(converted) else openAudio(ctx, item) ?: return UploadResult(Outcome.MISSING, "file missing")
        } catch (_: FileNotFoundException) {
            return UploadResult(Outcome.MISSING, "file missing") // the file was deleted (e.g. by the user in the recorder app)
        } catch (_: SecurityException) {
            return UploadResult(Outcome.RETRY, "no media permission") // permission revoked: keep it until access is granted again
        } catch (_: Exception) {
            return UploadResult(Outcome.RETRY, "could not open file")
        }
        val fileName = if (converted != null) item.fileName.substringBeforeLast('.') + ".m4a" else item.fileName

        val meta = JSONObject()
            .put("callerId", session.userId)
            .put("callerName", session.callerName)
            .put("callerPhone", session.callerPhone)
            .put("contactName", item.contactName.ifEmpty { item.phoneNumber.ifEmpty { "Unknown" } })
            // Hidden-number calls have no number; the server requires one (it never links "Unknown" to a lead)
            .put("phoneNumber", item.phoneNumber.ifBlank { "Unknown" })
            .put("durationSeconds", item.durationSeconds.coerceAtLeast(1))
            .put("fileName", fileName)
            .put("type", item.type)
            .put("callStartedAt", isoUtc(item.callStartedAtMs))
            .put("callLogTimestampMs", item.callStartedAtMs)
            // "builtin" = the phone's own recording (both voices); "mic" = AskEVA's microphone recording,
            // where the customer is heard only if the loudspeaker was on ("speaker")
            .put("captureSource", if (item.source == "builtin") "builtin" else "mic")
            .put("speaker", item.speaker)
        if (item.simSlot > 0) meta.put("simSlot", item.simSlot)
        val metaJson = meta.toString()
        val prefix = metaJson.substring(0, metaJson.length - 1) + ",\"audioData\":\""

        var conn: HttpURLConnection? = null
        try {
            conn = (URL("$base/recordings").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 20_000
                readTimeout = 180_000
                setChunkedStreamingMode(64 * 1024)
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Authorization", "Bearer ${session.token}")
            }
            conn.outputStream.use { raw ->
                val out = raw.buffered(64 * 1024)
                out.write(prefix.toByteArray(Charsets.UTF_8))
                Base64OutputStream(NonClosingStream(out), Base64.NO_WRAP).use { b64 ->
                    input.use { it.copyTo(b64, 32 * 1024) }
                }
                out.write("\"}".toByteArray(Charsets.UTF_8))
                out.flush()
            }
            val code = conn.responseCode
            val reply = try {
                (if (code < 400) conn.inputStream else conn.errorStream)?.use { String(it.readBytes(), Charsets.UTF_8) }
            } catch (_: Exception) { null }
            // Every result is logged (file names and server replies only in debug builds)
            val label = logLabel(ctx, item)
            if (code in 200..299) {
                Log.i(UPLOAD_TAG, "uploaded $label to $base: HTTP $code")
            } else {
                val detail = if (isDebuggable(ctx)) " ${reply?.take(300).orEmpty()}" else ""
                Log.w(UPLOAD_TAG, "upload of $label to $base failed: HTTP $code$detail")
            }
            return when {
                code in 200..299 -> UploadResult(Outcome.OK)
                code == 401 -> UploadResult(Outcome.AUTH, "HTTP 401")
                code == 408 || code == 429 || code >= 500 -> UploadResult(Outcome.RETRY, "HTTP $code")
                else -> UploadResult(Outcome.REJECTED, "HTTP $code") // 400 / 403 / 413: this request will not succeed as is
            }
        } catch (e: IOException) {
            val why = if (isDebuggable(ctx)) e.toString() else e.javaClass.simpleName
            Log.w(UPLOAD_TAG, "upload of ${logLabel(ctx, item)} to $base could not connect, will retry: $why")
            return UploadResult(Outcome.RETRY, "no connection")
        } catch (_: SecurityException) {
            return UploadResult(Outcome.RETRY, "no media permission")
        } catch (_: Exception) {
            return UploadResult(Outcome.RETRY, "upload error")
        } finally {
            try { input.close() } catch (_: Exception) {}
            conn?.disconnect()
        }
    }
}

class RecordingUploadWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        val retry = RecordingUploader.drain(applicationContext) { isStopped }
        return if (retry) Result.retry() else Result.success()
    }
}
