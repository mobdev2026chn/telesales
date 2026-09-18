package com.askeva.telesales_monitor

import java.util.Locale
import kotlin.math.abs
import kotlin.math.max

/**
 * Picks the phone's own (OEM dialer) call recording for a call that just ended.
 *
 * Pure Kotlin on purpose: no Android types, so the rules are easy to read and to reason about.
 * [BuiltInRecordingFinder] turns MediaStore rows / files into [Candidate]s and calls [pickBest].
 *
 * Rules, in order:
 *  1. Time window. The file must have been touched after (call start - 30 s). When its creation
 *     time is known it must also have been created between (call start - 30 s) and
 *     [CallInfo.createdBeforeMs] (call end + 20 s, or the next call's start if that is earlier):
 *     that rejects the previous call's file (created before this call) and the next call's file.
 *     (MediaStore DATE_ADDED can lag the call end by a few seconds when the file is indexed late.)
 *     Files found by folder listing have no creation time: their last change must be before that cut-off.
 *  2. Score. Known call-recorder folder (+50), file name containing the number's last 10 / 7
 *     digits (+40) or the contact name (+30), "call" in the name (+10), recording length close to
 *     the talk time (+30 / +20 / +5, or -40 when clearly different).
 *  3. Acceptance. A candidate is only taken when it sits in a call-recorder folder, or its name
 *     carries the number / contact name, or it is in a generic recordings folder AND its length
 *     matches the call within 5 s. Anything else (voice memos, music) is never uploaded.
 *  4. Highest score wins; ties go to the file whose last change is closest to the call end.
 */
object RecordingCandidateRanker {

    const val WINDOW_BEFORE_START_MS = 30_000L
    const val CREATED_AFTER_END_SLACK_MS = 20_000L
    const val MIN_SIZE_BYTES = 2_048L

    data class Candidate(
        /** Content Uri or absolute path; used to remember files already uploaded. */
        val key: String,
        val displayName: String,
        /** Folder, e.g. "MIUI/sound_recorder/call_rec/" or "/storage/emulated/0/Recordings/Call". */
        val folderPath: String,
        /** Creation time (MediaStore DATE_ADDED), 0 when unknown. */
        val createdMs: Long,
        /** Last modification time, 0 when unknown. */
        val modifiedMs: Long,
        /** 0 when unknown. */
        val durationMs: Long,
        /** 0 when unknown. */
        val sizeBytes: Long,
    )

    data class CallInfo(
        val startMs: Long,
        val endMs: Long,
        /** Connected talk time from the call log (0 when unknown). */
        val talkSeconds: Int,
        val phoneNumber: String,
        val contactName: String,
        /** Latest acceptable creation time: end + slack, capped by the start of a following call. */
        val createdBeforeMs: Long = endMs + CREATED_AFTER_END_SLACK_MS,
    )

    /**
     * Normalised folder segments that mark a dialer's call-recording folder. A folder matches when
     * any path segment (lower-case, without spaces / "_" / "-") STARTS WITH one of these, e.g.
     * "call_rec" (MIUI/sound_recorder/call_rec), "CallRecord" (Sounds/CallRecord, Huawei),
     * "Call Recordings" (Music/Recordings/Call Recordings, ColorOS / OnePlus), "PhoneRecord"
     * (Record/PhoneRecord, OnePlus / Vivo), "CallRecorder", "VoiceCall".
     */
    private val RECORDER_SEGMENT_PREFIXES = listOf("callrec", "phonerecord", "voicecall", "callaudio")

    /** Segments that mean "call" on their own, e.g. Recordings/Call (Samsung One UI, Honor), Record/Call (Vivo), /Call (older Samsung). */
    private val CALL_SEGMENTS = setOf("call", "calls")

    /** Generic recorder folders (voice recorder apps). Only accepted with a matching length. */
    private val GENERIC_RECORD_WORDS = listOf("record", "recorder", "recording", "soundrecorder")

    fun normalise(s: String): String =
        s.lowercase(Locale.US).replace(" ", "").replace("_", "").replace("-", "")

    fun folderSegments(folderPath: String): List<String> =
        folderPath.replace('\\', '/').split('/').map { normalise(it) }.filter { it.isNotEmpty() }

    fun isCallRecorderFolder(folderPath: String): Boolean {
        val segs = folderSegments(folderPath)
        return segs.any { seg -> RECORDER_SEGMENT_PREFIXES.any { seg.startsWith(it) } || seg in CALL_SEGMENTS }
    }

    fun isGenericRecorderFolder(folderPath: String): Boolean {
        val segs = folderSegments(folderPath)
        return segs.any { seg -> GENERIC_RECORD_WORDS.any { seg.contains(it) } }
    }

    fun digitsOnly(s: String): String = s.filter { it.isDigit() }

    /** True when the file name contains the number's last 10 digits, or at least its last 7. */
    fun nameHasNumber(displayName: String, phoneNumber: String): Boolean {
        val num = digitsOnly(phoneNumber)
        if (num.length < 7) return false
        val nameDigits = digitsOnly(displayName)
        if (num.length >= 10 && nameDigits.contains(num.takeLast(10))) return true
        // Names also carry dates (20240518_103012): 7 digits is long enough to rarely collide by chance
        return nameDigits.contains(num.takeLast(7))
    }

    fun nameHasContact(displayName: String, contactName: String): Boolean {
        val c = normalise(contactName).filter { it.isLetterOrDigit() }
        if (c.length < 3 || c.all { it.isDigit() }) return false
        return normalise(displayName).filter { it.isLetterOrDigit() }.contains(c)
    }

    fun inTimeWindow(c: Candidate, call: CallInfo): Boolean {
        val earliest = call.startMs - WINDOW_BEFORE_START_MS
        val touched = max(c.modifiedMs, c.createdMs)
        if (touched <= 0L || touched < earliest) return false
        if (c.createdMs > 0L) {
            if (c.createdMs < earliest) return false
            if (c.createdMs > call.createdBeforeMs) return false
        } else if (c.modifiedMs > call.createdBeforeMs) {
            // Folder-listed file (no creation time) still changing after the cut-off: a later call's
            return false
        }
        return true
    }

    /** Score of a candidate, or null when it must not be used for this call. */
    fun score(c: Candidate, call: CallInfo): Int? {
        if (!inTimeWindow(c, call)) return null
        if (c.sizeBytes in 1 until MIN_SIZE_BYTES) return null

        val recorderFolder = isCallRecorderFolder(c.folderPath)
        val genericFolder = !recorderFolder && isGenericRecorderFolder(c.folderPath)
        val hasNumber = nameHasNumber(c.displayName, call.phoneNumber)
        val hasContact = nameHasContact(c.displayName, call.contactName)

        var s = 0
        if (recorderFolder) s += 50 else if (genericFolder) s += 10
        if (hasNumber) s += 40
        if (hasContact) s += 30
        if (normalise(c.displayName).contains("call")) s += 10

        var durationDiffSec = -1L
        if (call.talkSeconds > 0 && c.durationMs > 0) {
            durationDiffSec = abs(c.durationMs / 1000 - call.talkSeconds)
            s += when {
                durationDiffSec <= 5 -> 30
                durationDiffSec <= 15 -> 20
                durationDiffSec <= 60 -> 5
                else -> 0
            }
            if (durationDiffSec > max(60L, call.talkSeconds / 2L)) s -= 40
        }

        val accepted = recorderFolder || hasNumber || hasContact ||
            (genericFolder && durationDiffSec in 0..5)
        return if (accepted && s > 0) s else null
    }

    fun pickBest(candidates: List<Candidate>, call: CallInfo, exclude: Set<String>): Candidate? {
        var best: Candidate? = null
        var bestScore = Int.MIN_VALUE
        var bestDistance = Long.MAX_VALUE
        for (c in candidates) {
            if (c.key in exclude) continue
            val s = score(c, call) ?: continue
            val distance = abs(max(c.modifiedMs, c.createdMs) - call.endMs)
            if (s > bestScore || (s == bestScore && distance < bestDistance)) {
                best = c
                bestScore = s
                bestDistance = distance
            }
        }
        return best
    }
}
