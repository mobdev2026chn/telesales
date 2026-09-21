package com.askeva.telesales_monitor

import android.content.Context
import android.net.Uri
import android.util.Base64
import android.util.Base64OutputStream
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
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id).put("userId", userId).put("source", source).put("path", path).put("uri", uri)
        .put("fileName", fileName).put("callStartedAtMs", callStartedAtMs).put("phoneNumber", phoneNumber)
        .put("contactName", contactName).put("type", type).put("simSlot", simSlot)
        .put("durationSeconds", durationSeconds).put("attempts", attempts).put("createdAtMs", createdAtMs)

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
        )
    }
}

/** Persisted upload queue: a JSON array in filesDir, survives process death and reboots. */
object RecordingQueue {
    private val lock = Any()
    private fun file(ctx: Context) = File(ctx.filesDir, "recording_upload_queue.json")

    fun all(ctx: Context): List<QueuedRecording> = synchronized(lock) { readLocked(ctx) }

    private fun readLocked(ctx: Context): MutableList<QueuedRecording> {
        return try {
            val f = file(ctx)
            if (!f.exists()) return mutableListOf()
            val arr = JSONArray(f.readText())
            (0 until arr.length()).mapNotNull { i -> arr.optJSONObject(i)?.let { QueuedRecording.fromJson(it) } }.toMutableList()
        } catch (_: Exception) {
            mutableListOf()
        }
    }

    private fun writeLocked(ctx: Context, items: List<QueuedRecording>) {
        try {
            val arr = JSONArray()
            items.forEach { arr.put(it.toJson()) }
            val tmp = File(ctx.filesDir, "recording_upload_queue.json.tmp")
            tmp.writeText(arr.toString())
            if (!tmp.renameTo(file(ctx))) {
                file(ctx).writeText(arr.toString())
                tmp.delete()
            }
        } catch (_: Exception) {}
    }

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
    /** Give up on one recording after this many failed attempts (about a week with WorkManager backoff). */
    private const val MAX_ATTEMPTS = 40
    /** Recordings of a user who has not signed in again for this long are discarded. */
    private const val FOREIGN_USER_MAX_AGE_MS = 14L * 24 * 3600 * 1000

    private val draining = AtomicBoolean(false)

    enum class Outcome { OK, AUTH, RETRY, DROP }

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
                when (uploadOne(ctx, base, session, item)) {
                    Outcome.OK -> {
                        RecordingQueue.remove(ctx, item.id)
                        if (item.source == "own" && item.path.isNotEmpty()) deleteQuietly(item.path)
                        uploaded++
                    }
                    Outcome.DROP -> discard(ctx, item)
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
                        val next = item.copy(attempts = item.attempts + 1)
                        if (next.attempts >= MAX_ATTEMPTS) discard(ctx, item) else {
                            RecordingQueue.update(ctx, next)
                            needRetry = true
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
            if (!AudioTools.needsTranscode(ctx, item.path, item.uri)) return null
            val out = File(ctx.cacheDir, "upload_${item.id}.m4a")
            if (AudioTools.transcodeToAac(ctx, item.path, item.uri, out)) out else { out.delete(); null }
        } catch (_: Exception) {
            null
        }
    }

    fun uploadOne(ctx: Context, base: String, session: CallMonitorStore.Session, item: QueuedRecording): Outcome {
        val converted = playableCopy(ctx, item)
        try {
            return uploadStream(ctx, base, session, item, converted)
        } finally {
            converted?.delete()
        }
    }

    private fun uploadStream(ctx: Context, base: String, session: CallMonitorStore.Session, item: QueuedRecording, converted: File?): Outcome {
        val input: InputStream = try {
            if (converted != null) FileInputStream(converted) else openAudio(ctx, item) ?: return Outcome.DROP
        } catch (_: FileNotFoundException) {
            return Outcome.DROP // the file was deleted (e.g. by the user in the recorder app)
        } catch (_: SecurityException) {
            return Outcome.RETRY // media permission revoked: keep it until access is granted again
        } catch (_: Exception) {
            return Outcome.RETRY
        }
        val fileName = if (converted != null) item.fileName.substringBeforeLast('.') + ".m4a" else item.fileName

        val meta = JSONObject()
            .put("callerId", session.userId)
            .put("callerName", session.callerName)
            .put("callerPhone", session.callerPhone)
            .put("contactName", item.contactName.ifEmpty { item.phoneNumber.ifEmpty { "Unknown" } })
            .put("phoneNumber", item.phoneNumber)
            .put("durationSeconds", item.durationSeconds.coerceAtLeast(1))
            .put("fileName", fileName)
            .put("type", item.type)
            .put("callStartedAt", isoUtc(item.callStartedAtMs))
            .put("callLogTimestampMs", item.callStartedAtMs)
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
            try { (if (code < 400) conn.inputStream else conn.errorStream)?.use { it.readBytes() } } catch (_: Exception) {}
            return when {
                code in 200..299 -> Outcome.OK
                code == 401 -> Outcome.AUTH
                code == 408 || code == 429 || code >= 500 -> Outcome.RETRY
                else -> Outcome.DROP // 400 / 403 / 413: the same request will never succeed
            }
        } catch (_: IOException) {
            return Outcome.RETRY
        } catch (_: SecurityException) {
            return Outcome.RETRY
        } catch (_: Exception) {
            return Outcome.RETRY
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
