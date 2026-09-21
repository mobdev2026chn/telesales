package com.askeva.telesales_monitor

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.util.Log
import java.io.File
import java.nio.ByteBuffer

/**
 * Post-processing of call recordings before upload.
 *  - [trimLeading]: drops the ringing before an outgoing call was answered (our recorder starts
 *    at dial time, the call log's duration starts at answer). AAC frames are self-contained, so
 *    this is a lossless remux.
 *  - [transcodeToAac]: converts AMR / AMR-WB recordings (many OEM dialers) into AAC .m4a.
 *    Browsers cannot play AMR, so without this the admin web shows a player that stays silent.
 */
object AudioTools {
    private const val TAG = "AskEvaAudioTools"
    private const val TIMEOUT_US = 10_000L
    private const val AAC_BIT_RATE = 64_000

    /** Audio codecs web browsers cannot decode. */
    private val UNPLAYABLE_MIMES = setOf("audio/3gpp", "audio/amr-wb", "audio/amr", "audio/amr-nb")

    /** Remuxes [file] in place without its first [trimUs] microseconds. False = file unchanged. */
    fun trimLeading(file: File, trimUs: Long): Boolean {
        if (trimUs <= 0) return false
        val tmp = File(file.parentFile, file.name + ".trim.m4a")
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            extractor.setDataSource(file.absolutePath)
            val track = audioTrack(extractor) ?: return false
            val format = extractor.getTrackFormat(track)
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            // Never trim away (nearly) everything: the call log may be wrong
            if (durationUs > 0 && trimUs > durationUs - 2_000_000L) return false
            extractor.selectTrack(track)
            muxer = MediaMuxer(tmp.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val outTrack = muxer.addTrack(format)
            muxer.start()
            muxerStarted = true
            val buf = ByteBuffer.allocate(maxInputSize(format))
            val info = MediaCodec.BufferInfo()
            var wrote = 0
            while (true) {
                val size = extractor.readSampleData(buf, 0)
                if (size < 0) break
                val pts = extractor.sampleTime
                if (pts >= trimUs) {
                    info.set(0, size, pts - trimUs, extractor.sampleFlags and MediaCodec.BUFFER_FLAG_KEY_FRAME)
                    muxer.writeSampleData(outTrack, buf, info)
                    wrote++
                }
                extractor.advance()
            }
            muxer.stop()
            muxerStarted = false
            muxer.release()
            muxer = null
            if (wrote == 0 || tmp.length() < 1024) {
                tmp.delete()
                return false
            }
            if (!tmp.renameTo(file)) {
                tmp.copyTo(file, overwrite = true)
                tmp.delete()
            }
            return true
        } catch (e: Exception) {
            Log.w(TAG, "trim failed: ${e.message}")
            tmp.delete()
            return false
        } finally {
            try { if (muxerStarted) muxer?.stop() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    /** True when the recording's audio codec cannot be played in a browser (AMR). */
    fun needsTranscode(ctx: Context, path: String, uri: String): Boolean {
        val extractor = MediaExtractor()
        return try {
            setSource(ctx, extractor, path, uri)
            val track = audioTrack(extractor) ?: return false
            val mime = extractor.getTrackFormat(track).getString(MediaFormat.KEY_MIME)?.lowercase() ?: ""
            mime in UNPLAYABLE_MIMES
        } catch (_: Exception) {
            false
        } finally {
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    /** Decodes the recording and re-encodes it as mono AAC-LC .m4a into [out]. */
    fun transcodeToAac(ctx: Context, path: String, uri: String, out: File): Boolean {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            setSource(ctx, extractor, path, uri)
            val track = audioTrack(extractor) ?: return false
            val inFormat = extractor.getTrackFormat(track)
            extractor.selectTrack(track)
            val sampleRate = inFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = if (inFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) inFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 1

            val dec = MediaCodec.createDecoderByType(inFormat.getString(MediaFormat.KEY_MIME)!!)
            decoder = dec
            dec.configure(inFormat, null, null, 0)
            dec.start()

            val outFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channels).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, AAC_BIT_RATE)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 64 * 1024)
            }
            val enc = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            encoder = enc
            enc.configure(outFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            enc.start()
            val mux = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = mux

            val info = MediaCodec.BufferInfo()
            val encInfo = MediaCodec.BufferInfo()
            var outTrack = -1
            var extractorDone = false
            var decoderDone = false
            var encoderDone = false
            var totalBytes = 0L // PCM bytes fed to the encoder, for timestamps
            val bytesPerSecond = sampleRate.toLong() * channels * 2

            fun drainEncoder() {
                while (true) {
                    val idx = enc.dequeueOutputBuffer(encInfo, 0)
                    when {
                        idx == MediaCodec.INFO_TRY_AGAIN_LATER -> return
                        idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            outTrack = mux.addTrack(enc.outputFormat)
                            mux.start()
                            muxerStarted = true
                        }
                        idx >= 0 -> {
                            val b = enc.getOutputBuffer(idx)
                            if (encInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) encInfo.size = 0
                            if (encInfo.size > 0 && muxerStarted && b != null) {
                                b.position(encInfo.offset)
                                b.limit(encInfo.offset + encInfo.size)
                                mux.writeSampleData(outTrack, b, encInfo)
                            }
                            enc.releaseOutputBuffer(idx, false)
                            if (encInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                encoderDone = true
                                return
                            }
                        }
                    }
                }
            }

            var guard = 0
            while (!encoderDone && guard++ < 2_000_000) {
                if (!extractorDone) {
                    val inIdx = dec.dequeueInputBuffer(TIMEOUT_US)
                    if (inIdx >= 0) {
                        val inBuf = dec.getInputBuffer(inIdx)!!
                        val size = extractor.readSampleData(inBuf, 0)
                        if (size < 0) {
                            dec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            extractorDone = true
                        } else {
                            dec.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                if (!decoderDone) {
                    val outIdx = dec.dequeueOutputBuffer(info, TIMEOUT_US)
                    if (outIdx >= 0) {
                        val pcm = dec.getOutputBuffer(outIdx)
                        val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        var off = 0
                        val len = if (pcm != null) info.size else 0
                        while (off < len) {
                            val encIn = enc.dequeueInputBuffer(TIMEOUT_US)
                            if (encIn < 0) { drainEncoder(); continue }
                            val dst = enc.getInputBuffer(encIn)!!
                            dst.clear()
                            val chunk = minOf(dst.remaining(), len - off)
                            pcm!!.limit(info.offset + off + chunk)
                            pcm.position(info.offset + off)
                            dst.put(pcm)
                            enc.queueInputBuffer(encIn, 0, chunk, totalBytes * 1_000_000L / bytesPerSecond, 0)
                            totalBytes += chunk
                            off += chunk
                        }
                        dec.releaseOutputBuffer(outIdx, false)
                        if (eos) {
                            decoderDone = true
                            var queued = false
                            for (i in 0 until 100) {
                                val encIn = enc.dequeueInputBuffer(TIMEOUT_US)
                                if (encIn >= 0) {
                                    enc.queueInputBuffer(encIn, 0, 0, totalBytes * 1_000_000L / bytesPerSecond, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                    queued = true
                                    break
                                }
                                drainEncoder()
                            }
                            if (!queued) break
                        }
                    }
                }
                drainEncoder()
            }
            if (muxerStarted) {
                mux.stop()
                muxerStarted = false
            }
            return encoderDone && totalBytes > 0 && out.length() > 1024
        } catch (e: Exception) {
            Log.w(TAG, "transcode failed: ${e.message}")
            return false
        } finally {
            try { decoder?.stop() } catch (_: Exception) {}
            try { decoder?.release() } catch (_: Exception) {}
            try { encoder?.stop() } catch (_: Exception) {}
            try { encoder?.release() } catch (_: Exception) {}
            try { if (muxerStarted) muxer?.stop() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    private fun setSource(ctx: Context, extractor: MediaExtractor, path: String, uri: String) {
        if (uri.isNotEmpty()) extractor.setDataSource(ctx, Uri.parse(uri), null)
        else extractor.setDataSource(path)
    }

    private fun audioTrack(extractor: MediaExtractor): Int? {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) return i
        }
        return null
    }

    private fun maxInputSize(format: MediaFormat): Int =
        if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) maxOf(format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE), 64 * 1024) else 256 * 1024
}
