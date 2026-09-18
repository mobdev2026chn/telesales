package com.askeva.telesales_monitor

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Records one call from the microphone into an .m4a (AAC) file. Used only while the phone's own
 * dialer recorder has not been detected. On Android 10+ only the agent's side is captured
 * (the far end is audible only on speakerphone).
 *
 * Primary path: AudioRecord (VOICE_COMMUNICATION -> VOICE_RECOGNITION -> MIC) with a 3x software
 * gain, encoded to AAC with MediaCodec + MediaMuxer. Fallback: MediaRecorder AAC.
 * [requestStop] is cheap (main thread); [awaitResult] joins the encoder (worker thread).
 */
class CallRecorder(private val ctx: Context) {

    data class Result(val file: File, val durationSeconds: Int)

    private companion object {
        const val SAMPLE_RATE = 16_000
        const val BIT_RATE = 48_000
        const val GAIN = 3.0f
        const val TIMEOUT_US = 10_000L
        /** RMS (16-bit, before gain) above which a chunk counts as speech: about -40 dBFS. */
        const val SPEECH_RMS = 330.0
        /** Less than this much speech in the whole call means the mic was muted by Android. */
        const val MIN_VOICED_SECONDS = 1.0
        const val TAG = "AskEvaRecorder"
    }

    private var outFile: File? = null
    @Volatile private var running = false
    private var thread: Thread? = null
    private var mediaRecorder: MediaRecorder? = null
    private var startedAtMs = 0L

    // Written by the encoder thread
    @Volatile private var totalSamples = 0L
    @Volatile private var peak = 0
    @Volatile private var wroteSamples = false
    /** Samples in read chunks whose RMS is above the speech threshold. */
    @Volatile private var voicedSamples = 0L

    /** True when the last [awaitResult] threw the file away because Android fed us silence. */
    var discardedAsSilent = false
        private set

    val isRecording: Boolean get() = running || mediaRecorder != null

    fun start(file: File): Boolean {
        outFile = file
        startedAtMs = System.currentTimeMillis()
        if (startEncoder(file)) return true
        return startMediaRecorder(file)
    }

    /**
     * Source order. Android mutes the mic for ordinary apps during a call; with our accessibility
     * service enabled the app is exempt, and VOICE_RECOGNITION (no echo cancellation, so the
     * earpiece audio is not removed) usually picks up the most of the far end.
     * CallMonitorStore.forcedAudioSource (debug experiments) overrides the order.
     */
    private fun sourceOrder(): IntArray {
        // Calibrated / trial source first; the others only if it cannot be opened at all
        val (primary, mode) = CallMonitorStore.chooseSource(ctx)
        sourceMode = mode
        if (mode == "forced") return intArrayOf(primary)
        return intArrayOf(primary) + CallMonitorStore.SOURCE_CANDIDATES.filter { it != primary }
    }

    /** "forced" | "locked" | "trial" — how the source was chosen (for diagnostics). */
    var sourceMode = ""
        private set

    /** Seconds of speech heard in the last recording (for diagnostics / calibration). */
    val voicedSeconds: Double get() = voicedSamples.toDouble() / SAMPLE_RATE
    val recordedSeconds: Int get() = (totalSamples / SAMPLE_RATE).toInt()
    val peakLevel: Int get() = peak

    /** The AudioSource actually used (-1 before start / MediaRecorder fallback). */
    var usedSource = -1
        private set

    private fun createAudioRecord(bufferSize: Int): AudioRecord? {
        for (src in sourceOrder()) {
            try {
                val rec = AudioRecord(src, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufferSize)
                if (rec.state == AudioRecord.STATE_INITIALIZED) {
                    usedSource = src
                    return rec
                }
                rec.release()
            } catch (_: Exception) {}
        }
        return null
    }

    private fun startEncoder(file: File): Boolean {
        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuf <= 0) return false
        val bufferSize = max(minBuf, 8192)
        val rec = createAudioRecord(bufferSize) ?: return false

        var codec: MediaCodec? = null
        var muxer: MediaMuxer? = null
        try {
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, bufferSize)
            }
            codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            muxer = MediaMuxer(file.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            rec.startRecording()
            if (rec.recordingState != AudioRecord.RECORDSTATE_RECORDING) throw IllegalStateException("mic busy")
        } catch (e: Exception) {
            e.printStackTrace()
            try { rec.release() } catch (_: Exception) {}
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
            file.delete()
            return false
        }

        running = true
        totalSamples = 0L
        peak = 0
        voicedSamples = 0L
        wroteSamples = false
        Log.i(TAG, "recording started, source=$usedSource a11y=${CallAccessibilityService.isEnabled(ctx)}")
        val c = codec
        val m = muxer
        thread = Thread({ encodeLoop(rec, c, m, bufferSize) }, "askeva-call-recorder").also { it.start() }
        return true
    }

    private fun encodeLoop(rec: AudioRecord, codec: MediaCodec, muxer: MediaMuxer, bufferSize: Int) {
        val pcm = ShortArray(bufferSize / 2)
        val bytes = ByteArray(bufferSize)
        val info = MediaCodec.BufferInfo()
        var track = -1
        var muxerStarted = false

        fun drain(endOfStream: Boolean) {
            var idleLoops = 0
            while (true) {
                val idx = codec.dequeueOutputBuffer(info, if (endOfStream) TIMEOUT_US else 0L)
                when {
                    idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        if (!endOfStream || ++idleLoops > 200) return
                    }
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        if (!muxerStarted) {
                            track = muxer.addTrack(codec.outputFormat)
                            muxer.start()
                            muxerStarted = true
                        }
                    }
                    idx >= 0 -> {
                        val buf = codec.getOutputBuffer(idx)
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && muxerStarted && buf != null) {
                            buf.position(info.offset)
                            buf.limit(info.offset + info.size)
                            muxer.writeSampleData(track, buf, info)
                            wroteSamples = true
                        }
                        codec.releaseOutputBuffer(idx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                    }
                }
            }
        }

        fun ptsUs(samples: Long) = samples * 1_000_000L / SAMPLE_RATE

        try {
            while (running) {
                val n = rec.read(pcm, 0, pcm.size)
                if (n < 0) break // mic lost
                if (n == 0) continue
                var p = peak
                var sumSq = 0.0
                for (i in 0 until n) {
                    val s = pcm[i].toInt()
                    if (abs(s) > p) p = abs(s)
                    sumSq += s.toDouble() * s
                    val v = (s * GAIN).toInt().coerceIn(-32768, 32767)
                    bytes[2 * i] = (v and 0xff).toByte()
                    bytes[2 * i + 1] = (v shr 8 and 0xff).toByte()
                }
                peak = p
                if (kotlin.math.sqrt(sumSq / n) > SPEECH_RMS) voicedSamples += n
                val len = n * 2
                var off = 0
                while (off < len) {
                    val inIdx = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (inIdx < 0) {
                        drain(false)
                        continue
                    }
                    val inBuf = codec.getInputBuffer(inIdx) ?: continue
                    inBuf.clear()
                    val chunk = min(inBuf.remaining(), len - off)
                    inBuf.put(bytes, off, chunk)
                    codec.queueInputBuffer(inIdx, 0, chunk, ptsUs(totalSamples + off / 2), 0)
                    off += chunk
                }
                totalSamples += n
                drain(false)
            }
            // End of stream
            var eosQueued = false
            for (i in 0 until 50) {
                val inIdx = codec.dequeueInputBuffer(TIMEOUT_US)
                if (inIdx >= 0) {
                    codec.queueInputBuffer(inIdx, 0, 0, ptsUs(totalSamples), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    eosQueued = true
                    break
                }
                drain(false)
            }
            if (eosQueued) drain(true)
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            try { rec.stop() } catch (_: Exception) {}
            try { rec.release() } catch (_: Exception) {}
            try { codec.stop() } catch (_: Exception) {}
            try { codec.release() } catch (_: Exception) {}
            try { if (muxerStarted) muxer.stop() } catch (_: Exception) { wroteSamples = false }
            try { muxer.release() } catch (_: Exception) {}
        }
    }

    private fun startMediaRecorder(file: File): Boolean {
        val sources = intArrayOf(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            MediaRecorder.AudioSource.MIC,
        )
        for (source in sources) {
            try {
                val mr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(ctx) else {
                    @Suppress("DEPRECATION") MediaRecorder()
                }
                mr.setAudioSource(source)
                mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                mr.setAudioSamplingRate(SAMPLE_RATE)
                mr.setAudioEncodingBitRate(BIT_RATE)
                mr.setOutputFile(file.absolutePath)
                try {
                    mr.prepare()
                    mr.start()
                } catch (e: Exception) {
                    mr.release()
                    throw e
                }
                mediaRecorder = mr
                return true
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        file.delete()
        return false
    }

    /** Stops capturing. Non-blocking for the encoder path. */
    fun requestStop() {
        running = false
        val mr = mediaRecorder ?: return
        mediaRecorder = null
        try { mr.stop() } catch (_: Exception) { outFile?.delete() }
        try { mr.release() } catch (_: Exception) {}
    }

    /**
     * Waits for the file to be finalised. Returns null (and deletes the file) when nothing usable
     * was captured, including a mic that Android silenced because another app held it.
     */
    fun awaitResult(): Result? {
        requestStop()
        val t = thread
        thread = null
        val usedEncoder = t != null
        try { t?.join(15_000) } catch (_: Exception) {}
        val file = outFile ?: return null
        if (!file.exists() || file.length() < 1024) {
            file.delete()
            return null
        }
        if (usedEncoder) {
            val voicedSec = voicedSamples.toDouble() / SAMPLE_RATE
            Log.i(TAG, "recording finished: source=$usedSource seconds=${totalSamples / SAMPLE_RATE} " +
                "voicedSeconds=${"%.1f".format(voicedSec)} peak=$peak")
            if (!wroteSamples || peak == 0 || voicedSec < MIN_VOICED_SECONDS) {
                // Android muted the microphone for this call (or nothing was said): never upload silence
                discardedAsSilent = wroteSamples && totalSamples > SAMPLE_RATE * 3
                file.delete()
                return null
            }
            return Result(file, (totalSamples / SAMPLE_RATE).toInt().coerceAtLeast(1))
        }
        var sec = 0
        try {
            val mmr = MediaMetadataRetriever()
            mmr.setDataSource(file.absolutePath)
            sec = ((mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) / 1000).toInt()
            mmr.release()
        } catch (_: Exception) {}
        if (sec <= 0) sec = ((System.currentTimeMillis() - startedAtMs) / 1000).toInt()
        return Result(file, sec.coerceAtLeast(1))
    }
}
