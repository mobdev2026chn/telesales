package com.askeva.telesales_monitor

import android.content.ContentUris
import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Looks for the recording the phone's own dialer made of a call (Xiaomi, Samsung, Oppo/Realme,
 * Vivo, Huawei/Honor, Transsion, ... save these to shared storage). Two sources:
 *  1. MediaStore.Audio rows added/modified since (call start - 30 s).
 *  2. A direct listing of well-known call-recorder folders, for files MediaStore has not indexed yet.
 * [RecordingCandidateRanker] decides which one (if any) belongs to the call.
 * Needs READ_MEDIA_AUDIO (API 33+) / READ_EXTERNAL_STORAGE (API <= 32).
 */
object BuiltInRecordingFinder {

    data class Found(
        /** content:// Uri (MediaStore) or "" */
        val uri: String,
        /** absolute path (folder scan) or "" */
        val path: String,
        val displayName: String,
        val durationSeconds: Int,
        val key: String,
    )

    /** Folders (relative to shared storage) that OEM dialers use for call recordings. */
    private val KNOWN_FOLDERS = listOf(
        "MIUI/sound_recorder/call_rec",          // Xiaomi / Redmi / Poco (MIUI)
        "Recordings/Call",                       // Samsung One UI, HyperOS, Honor
        "Recordings/Call recordings",
        "Recordings/Call Recordings",
        "Recordings/Sound records/Call recordings",
        "Music/Recordings/Call Recordings",      // OnePlus / Oppo / Realme (ColorOS)
        "Music/Recordings/Call",
        "Record/Call",                           // Vivo / iQOO
        "Record/PhoneRecord",                    // OnePlus (older), Vivo
        "Sounds/CallRecord",                     // Huawei / Honor (EMUI)
        "Call",                                  // Samsung (older)
        "CallRecord",
        "CallRecordings",
        "Call Recordings",
        "PhoneRecord",
        "Recorder/call",                         // Tecno / Infinix / itel
        "Recorder/Call",
        "Sound Recorder/Call",
        "VoiceRecorder/Call",
        "Voice Recorder/Call",
    )

    /** Second "used" key, so one file reached through MediaStore and through a folder listing is recognised. */
    fun usedKeyFor(displayName: String) = "name:$displayName"

    private val AUDIO_EXTENSIONS = setOf("m4a", "mp3", "amr", "aac", "wav", "ogg", "opus", "3gp", "3gpp", "awb", "mp4", "flac")

    fun find(
        ctx: Context,
        call: RecordingCandidateRanker.CallInfo,
        exclude: Set<String>,
    ): Found? {
        if (!CallMonitorStore.hasMediaPermission(ctx)) return null
        val candidates = ArrayList<RecordingCandidateRanker.Candidate>()
        try { candidates.addAll(queryMediaStore(ctx, call)) } catch (e: Exception) { e.printStackTrace() }
        val indexedNames = candidates.map { it.displayName }.toSet()
        try {
            // A file already seen through MediaStore is kept only in its content:// form
            candidates.addAll(scanKnownFolders(call).filter { it.displayName !in indexedNames })
        } catch (e: Exception) { e.printStackTrace() }
        // Files already uploaded for an earlier call are excluded by key and by name
        val fresh = candidates.filter { usedKeyFor(it.displayName) !in exclude }
        val best = RecordingCandidateRanker.pickBest(fresh, call, exclude) ?: return null

        val isUri = best.key.startsWith("content://")
        if (!isUri) {
            // A file found by listing may still be being written: require a stable size
            val f = File(best.key)
            val size1 = f.length()
            try { Thread.sleep(1500) } catch (_: InterruptedException) {}
            if (f.length() != size1 || size1 == 0L) return null
        }
        return Found(
            uri = if (isUri) best.key else "",
            path = if (isUri) "" else best.key,
            displayName = best.displayName,
            durationSeconds = (best.durationMs / 1000).toInt(),
            key = best.key,
        )
    }

    private fun queryMediaStore(ctx: Context, call: RecordingCandidateRanker.CallInfo): List<RecordingCandidateRanker.Candidate> {
        val collection: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }
        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
        )
        @Suppress("DEPRECATION")
        val dataCol = MediaStore.Audio.Media.DATA
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) projection.add(MediaStore.Audio.Media.RELATIVE_PATH)
        else projection.add(dataCol)

        // DATE_ADDED / DATE_MODIFIED are in seconds
        val sinceSec = ((call.startMs - RecordingCandidateRanker.WINDOW_BEFORE_START_MS) / 1000).toString()
        val selection = "${MediaStore.Audio.Media.DATE_ADDED} >= ? OR ${MediaStore.Audio.Media.DATE_MODIFIED} >= ?"
        val out = ArrayList<RecordingCandidateRanker.Candidate>()
        ctx.contentResolver.query(
            collection, projection.toTypedArray(), selection, arrayOf(sinceSec, sinceSec),
            "${MediaStore.Audio.Media.DATE_ADDED} DESC"
        )?.use { c ->
            val idI = c.getColumnIndex(MediaStore.Audio.Media._ID)
            val nameI = c.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
            val addedI = c.getColumnIndex(MediaStore.Audio.Media.DATE_ADDED)
            val modI = c.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)
            val durI = c.getColumnIndex(MediaStore.Audio.Media.DURATION)
            val sizeI = c.getColumnIndex(MediaStore.Audio.Media.SIZE)
            val folderI = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) c.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH) else c.getColumnIndex(dataCol)
            var rows = 0
            while (c.moveToNext() && rows++ < 200) {
                val id = if (idI >= 0) c.getLong(idI) else continue
                val name = if (nameI >= 0) c.getString(nameI) ?: "" else ""
                var folder = if (folderI >= 0) c.getString(folderI) ?: "" else ""
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) folder = File(folder).parent ?: folder
                out.add(
                    RecordingCandidateRanker.Candidate(
                        key = ContentUris.withAppendedId(collection, id).toString(),
                        displayName = name,
                        folderPath = folder,
                        createdMs = if (addedI >= 0) c.getLong(addedI) * 1000 else 0L,
                        modifiedMs = if (modI >= 0) c.getLong(modI) * 1000 else 0L,
                        durationMs = if (durI >= 0) c.getLong(durI) else 0L,
                        sizeBytes = if (sizeI >= 0) c.getLong(sizeI) else 0L,
                    )
                )
            }
        }
        return out
    }

    private fun scanKnownFolders(call: RecordingCandidateRanker.CallInfo): List<RecordingCandidateRanker.Candidate> {
        @Suppress("DEPRECATION")
        val root = Environment.getExternalStorageDirectory() ?: return emptyList()
        val since = call.startMs - RecordingCandidateRanker.WINDOW_BEFORE_START_MS
        val out = ArrayList<RecordingCandidateRanker.Candidate>()
        for (rel in KNOWN_FOLDERS) {
            val dir = File(root, rel)
            val files = try { dir.listFiles() } catch (_: Exception) { null } ?: continue
            for (f in files) {
                if (!f.isFile) continue
                if (f.extension.lowercase() !in AUDIO_EXTENSIONS) continue
                val modified = f.lastModified()
                if (modified < since) continue
                out.add(
                    RecordingCandidateRanker.Candidate(
                        key = f.absolutePath,
                        displayName = f.name,
                        folderPath = rel,
                        createdMs = 0L, // not available from File
                        modifiedMs = modified,
                        durationMs = durationOf(f),
                        sizeBytes = f.length(),
                    )
                )
            }
        }
        return out
    }

    private fun durationOf(f: File): Long {
        return try {
            val mmr = MediaMetadataRetriever()
            try {
                mmr.setDataSource(f.absolutePath)
                mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            } finally {
                mmr.release()
            }
        } catch (_: Exception) {
            0L
        }
    }
}
