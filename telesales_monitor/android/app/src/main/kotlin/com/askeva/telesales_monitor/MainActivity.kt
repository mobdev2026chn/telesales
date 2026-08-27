package com.askeva.telesales_monitor

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.provider.ContactsContract
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Base64
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.askeva.telesales/telephony"
    private val PERMISSION_REQ_CODE = 2001
    private val NOTIF_CHANNEL_ID = "telesales_call_recording_channel"
    private val NOTIF_ID = 9001

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var methodChannel: MethodChannel? = null

    private var telephonyReceiver: BroadcastReceiver? = null
    private var callLogObserver: ContentObserver? = null
    private var mediaRecorder: MediaRecorder? = null
    private var mediaPlayer: MediaPlayer? = null
    private var pcmAudioRecord: AudioRecord? = null
    private var isPcmRecording = false
    private var pcmRecordThread: Thread? = null
    private var isRecording = false
    private var currentRecordingFile: File? = null
    private var autoRecordEnabled = true

    private var incomingNumber: String = ""
    private var isIncomingCall: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSimCards" -> {
                    val simList = getActiveSimCards()
                    result.success(simList)
                }
                "getCallLogs" -> {
                    val logs = getRealDeviceCallLogs()
                    result.success(logs)
                }
                "checkPermissions" -> {
                    val granted = checkAllPermissions()
                    result.success(granted)
                }
                "requestPermissions" -> {
                    requestSystemPermissions(result)
                }
                "validateSimNumber" -> {
                    val number = call.argument<String>("phoneNumber") ?: ""
                    val slot = call.argument<Int>("slotIndex") ?: 0
                    val valResult = validateSimNumber(number, slot)
                    result.success(valResult)
                }
                "directCall" -> {
                    val phone = call.argument<String>("phoneNumber") ?: ""
                    val slot = call.argument<Int>("slotIndex") ?: 0
                    makeDirectCall(phone, slot)
                    result.success(true)
                }
                "setAutoRecord" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    autoRecordEnabled = enabled
                    result.success(true)
                }
                "isAutoRecordEnabled" -> {
                    result.success(autoRecordEnabled)
                }
                "isRecordingActive" -> {
                    result.success(isRecording)
                }
                "startTestRecording" -> {
                    if (!isRecording) {
                        startCallRecording()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "stopTestRecording" -> {
                    if (isRecording) {
                        stopCallRecording()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "playAudio" -> {
                    val path = call.argument<String>("filePath") ?: ""
                    val url = call.argument<String>("audioUrl") ?: ""
                    val data = call.argument<String>("audioData") ?: ""
                    playRecordedAudio(path, url, data, result)
                }
                "stopAudio" -> {
                    stopAudioPlayback()
                    result.success(true)
                }
                "openSaveContact" -> {
                    val phone = call.argument<String>("phoneNumber") ?: ""
                    val name = call.argument<String>("name") ?: ""
                    openNativeSaveContactIntent(phone, name)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        registerRealtimeCallListener()
        registerCallLogObserver()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID,
                "Call Recording Live Status",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows live status and alert when call recording starts"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 150, 100, 150)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun showToast(message: String) {
        Handler(Looper.getMainLooper()).post {
            try {
                Toast.makeText(applicationContext, message, Toast.LENGTH_LONG).show()
            } catch (_: Exception) {}
        }
    }

    private fun showRecordingNotification(isLive: Boolean, text: String) {
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (isLive) {
                val notif = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.stat_notify_call_mute)
                    .setContentTitle("🔴 CALL RECORDING ACTIVE")
                    .setContentText(text)
                    .setOngoing(true)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .build()
                manager.notify(NOTIF_ID, notif)
            } else {
                manager.cancel(NOTIF_ID)
            }
        } catch (_: Exception) {}
    }

    private fun registerCallLogObserver() {
        try {
            val hasPermission = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED
            if (!hasPermission) return

            callLogObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) {
                    super.onChange(selfChange)
                    methodChannel?.invokeMethod("onCallStateChanged", mapOf("state" to "LOG_UPDATED"))
                }
            }
            contentResolver.registerContentObserver(CallLog.Calls.CONTENT_URI, true, callLogObserver!!)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun registerRealtimeCallListener() {
        try {
            telephonyReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (TelephonyManager.ACTION_PHONE_STATE_CHANGED == intent?.action) {
                        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE)

                        if (TelephonyManager.EXTRA_STATE_RINGING == stateStr) {
                            isIncomingCall = true
                            incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
                        } else if (TelephonyManager.EXTRA_STATE_OFFHOOK == stateStr) {
                            if (autoRecordEnabled && !isRecording) {
                                startCallRecording()
                            }
                        } else if (TelephonyManager.EXTRA_STATE_IDLE == stateStr) {
                            if (isRecording) {
                                stopCallRecording()
                            }
                            isIncomingCall = false
                            incomingNumber = ""

                            Handler(Looper.getMainLooper()).postDelayed({
                                methodChannel?.invokeMethod("onCallStateChanged", mapOf("state" to "IDLE"))
                            }, 1000)
                        }
                    }
                }
            }
            val filter = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
            registerReceiver(telephonyReceiver, filter)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startCallRecording() {
        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQ_CODE)
                showToast("⚠️ Please ALLOW Microphone permission to record audio!")
                return
            }

            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            try {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                audioManager.isMicrophoneMute = false
            } catch (_: Exception) {}

            val dir = File(cacheDir, "call_recordings")
            if (!dir.exists()) {
                dir.mkdirs()
            }

            val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val prefix = if (isIncomingCall) "INC_CALL_REC" else "OUT_CALL_REC"
            currentRecordingFile = File(dir, "${prefix}_${timeStamp}.wav")

            var startedSuccessfully = startPcmAudioRecord(currentRecordingFile!!)

            if (!startedSuccessfully) {
                currentRecordingFile = File(dir, "${prefix}_${timeStamp}.m4a")
                val audioSources = arrayOf(
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    MediaRecorder.AudioSource.MIC,
                    MediaRecorder.AudioSource.DEFAULT,
                    MediaRecorder.AudioSource.CAMCORDER
                )

                for (source in audioSources) {
                    try {
                        val mr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            MediaRecorder(this)
                        } else {
                            @Suppress("DEPRECATION")
                            MediaRecorder()
                        }

                        mr.setAudioSource(source)
                        mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                        mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                        mr.setAudioSamplingRate(16000)
                        mr.setAudioEncodingBitRate(64000)
                        mr.setOutputFile(currentRecordingFile?.absolutePath)
                        mr.prepare()
                        mr.start()
                        mediaRecorder = mr
                        isRecording = true
                        startedSuccessfully = true
                        break
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            } else {
                isRecording = true
            }

            if (startedSuccessfully) {
                val notifText = if (isIncomingCall) "🔴 Recording incoming call audio now..." else "🔴 Recording outgoing call audio now..."
                showRecordingNotification(true, notifText)
                showToast("🔴 Call recording is ACTIVE!")
                methodChannel?.invokeMethod("onCallRecordingStatus", mapOf("isRecording" to true, "isIncoming" to isIncomingCall))
            } else {
                isRecording = false
                showToast("⚠️ Unable to lock audio hardware stream for call recording.")
            }
        } catch (e: Exception) {
            e.printStackTrace()
            isRecording = false
            showRecordingNotification(false, "")
        }
    }

    private fun startPcmAudioRecord(outputWavFile: File): Boolean {
        try {
            val sampleRate = 16000
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val audioFormat = AudioFormat.ENCODING_PCM_16BIT
            val minBufSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
            val bufferSize = Math.max(minBufSize, 4096)

            val sources = intArrayOf(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                MediaRecorder.AudioSource.MIC,
                MediaRecorder.AudioSource.DEFAULT,
                MediaRecorder.AudioSource.CAMCORDER
            )

            var ar: AudioRecord? = null
            for (src in sources) {
                try {
                    val rec = AudioRecord(src, sampleRate, channelConfig, audioFormat, bufferSize)
                    if (rec.state == AudioRecord.STATE_INITIALIZED) {
                        ar = rec
                        break
                    }
                } catch (_: Exception) {}
            }

            if (ar == null) return false

            pcmAudioRecord = ar
            isPcmRecording = true
            ar.startRecording()

            pcmRecordThread = Thread {
                try {
                    val pcmTempFile = File(cacheDir, "temp_buffer_${System.currentTimeMillis()}.pcm")
                    val os = FileOutputStream(pcmTempFile)
                    val buffer = ShortArray(bufferSize / 2)

                    while (isPcmRecording) {
                        val read = ar.read(buffer, 0, buffer.size)
                        if (read > 0) {
                            val byteBuf = java.nio.ByteBuffer.allocate(read * 2).order(java.nio.ByteOrder.LITTLE_ENDIAN)
                            for (i in 0 until read) {
                                // Boost software audio gain 3x so call speech is loud and clear
                                val sample = buffer[i].toInt()
                                val amplified = (sample * 3.0f).toInt().coerceIn(-32768, 32767).toShort()
                                byteBuf.putShort(amplified)
                            }
                            os.write(byteBuf.array())
                        }
                    }
                    os.close()

                    writeWavHeader(pcmTempFile, outputWavFile, sampleRate, 1, 16)
                    pcmTempFile.delete()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            pcmRecordThread?.start()
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    private fun stopPcmAudioRecord() {
        isPcmRecording = false
        try {
            pcmAudioRecord?.stop()
            pcmAudioRecord?.release()
        } catch (_: Exception) {}
        pcmAudioRecord = null
        try {
            pcmRecordThread?.join(1000)
        } catch (_: Exception) {}
    }

    private fun writeWavHeader(pcmFile: File, wavFile: File, sampleRate: Int, channels: Int, bitDepth: Int) {
        try {
            val pcmSize = pcmFile.length().toInt()
            val totalDataLen = pcmSize + 36
            val byteRate = sampleRate * channels * bitDepth / 8

            val header = ByteArray(44)
            header[0] = 'R'.code.toByte(); header[1] = 'I'.code.toByte(); header[2] = 'F'.code.toByte(); header[3] = 'F'.code.toByte()
            header[4] = (totalDataLen and 0xff).toByte()
            header[5] = (totalDataLen shr 8 and 0xff).toByte()
            header[6] = (totalDataLen shr 16 and 0xff).toByte()
            header[7] = (totalDataLen shr 24 and 0xff).toByte()
            header[8] = 'W'.code.toByte(); header[9] = 'A'.code.toByte(); header[10] = 'V'.code.toByte(); header[11] = 'E'.code.toByte()
            header[12] = 'f'.code.toByte(); header[13] = 'm'.code.toByte(); header[14] = 't'.code.toByte(); header[15] = ' '.code.toByte()
            header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0
            header[20] = 1; header[21] = 0
            header[22] = channels.toByte(); header[23] = 0
            header[24] = (sampleRate and 0xff).toByte()
            header[25] = (sampleRate shr 8 and 0xff).toByte()
            header[26] = (sampleRate shr 16 and 0xff).toByte()
            header[27] = (sampleRate shr 24 and 0xff).toByte()
            header[28] = (byteRate and 0xff).toByte()
            header[29] = (byteRate shr 8 and 0xff).toByte()
            header[30] = (byteRate shr 16 and 0xff).toByte()
            header[31] = (byteRate shr 24 and 0xff).toByte()
            header[32] = (channels * bitDepth / 8).toByte(); header[33] = 0
            header[34] = bitDepth.toByte(); header[35] = 0
            header[36] = 'd'.code.toByte(); header[37] = 'a'.code.toByte(); header[38] = 't'.code.toByte(); header[39] = 'a'.code.toByte()
            header[40] = (pcmSize and 0xff).toByte()
            header[41] = (pcmSize shr 8 and 0xff).toByte()
            header[42] = (pcmSize shr 16 and 0xff).toByte()
            header[43] = (pcmSize shr 24 and 0xff).toByte()

            val out = FileOutputStream(wavFile)
            out.write(header)
            val input = FileInputStream(pcmFile)
            input.copyTo(out)
            input.close()
            out.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopCallRecording() {
        try {
            if (isRecording || mediaRecorder != null || isPcmRecording) {
                if (isPcmRecording) {
                    stopPcmAudioRecord()
                }
                try {
                    mediaRecorder?.stop()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                try {
                    mediaRecorder?.release()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                mediaRecorder = null
                isRecording = false

                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                try {
                    audioManager.mode = AudioManager.MODE_NORMAL
                } catch (_: Exception) {}

                showRecordingNotification(false, "")
                methodChannel?.invokeMethod("onCallRecordingStatus", mapOf("isRecording" to false))

                val file = currentRecordingFile
                if (file != null && file.exists() && file.length() > 0) {
                    showToast("✅ Call Audio Saved & Syncing to MongoDB...")
                    var durSec = 1
                    try {
                        val mmr = MediaMetadataRetriever()
                        mmr.setDataSource(file.absolutePath)
                        val durStr = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        val durMs = durStr?.toLongOrNull() ?: 1000L
                        durSec = (durMs / 1000).toInt().coerceAtLeast(1)
                        mmr.release()
                    } catch (_: Exception) {
                        durSec = (file.length() / (16000 * 2)).toInt().coerceAtLeast(1)
                    }

                    val bytes = file.readBytes()
                    val base64Audio = Base64.encodeToString(bytes, Base64.NO_WRAP)

                    methodChannel?.invokeMethod("onRecordingSaved", mapOf(
                        "filePath" to file.absolutePath,
                        "fileName" to file.name,
                        "audioData" to base64Audio,
                        "durationSeconds" to durSec,
                        "timestamp" to System.currentTimeMillis(),
                        "isIncoming" to isIncomingCall
                    ))
                } else {
                    showToast("⚠️ Call ended before audio buffer was written")
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            isRecording = false
            showRecordingNotification(false, "")
        }
    }

    private fun playRecordedAudio(filePath: String, audioUrl: String, audioData: String, result: MethodChannel.Result) {
        try {
            stopAudioPlayback()

            // 1. Try local file path if present and valid
            if (filePath.isNotEmpty()) {
                val f = File(filePath)
                if (f.exists() && f.length() > 0) {
                    playLocalAudioFile(f.absolutePath, result)
                    return
                }
            }

            // 2. Try Base64 audio data if present
            if (audioData.isNotEmpty() && audioData.length > 50) {
                try {
                    val cleanBase64 = audioData.replace(Regex("^data:audio/\\w+;base64,"), "")
                    val bytes = Base64.decode(cleanBase64, Base64.DEFAULT)
                    if (bytes.isNotEmpty()) {
                        val tempFile = File(cacheDir, "temp_b64_play_${System.currentTimeMillis()}.m4a")
                        tempFile.writeBytes(bytes)
                        playLocalAudioFile(tempFile.absolutePath, result)
                        return
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }

            // 3. Try local cache folder by matching filename
            val targetUrl = if (audioUrl.isNotEmpty()) audioUrl else filePath
            if (targetUrl.isNotEmpty()) {
                val fileName = Uri.parse(targetUrl).lastPathSegment ?: ""
                if (fileName.isNotEmpty()) {
                    val localDir = File(cacheDir, "call_recordings")
                    val localFile = File(localDir, fileName)
                    if (localFile.exists() && localFile.length() > 0) {
                        playLocalAudioFile(localFile.absolutePath, result)
                        return
                    }
                }

                // 4. Download or Stream via HTTP
                if (targetUrl.startsWith("http")) {
                    Thread {
                        try {
                            val url = java.net.URL(targetUrl)
                            val conn = url.openConnection()
                            conn.connectTimeout = 4000
                            conn.readTimeout = 6000
                            val bytes = conn.getInputStream().readBytes()
                            val tempFile = File(cacheDir, "temp_play_${System.currentTimeMillis()}.m4a")
                            tempFile.writeBytes(bytes)

                            Handler(Looper.getMainLooper()).post {
                                playLocalAudioFile(tempFile.absolutePath, result)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                playDirectStream(targetUrl, result)
                            }
                        }
                    }.start()
                    return
                }
            }

            showToast("⚠️ Recording audio file not found on device or server.")
            result.success(false)
        } catch (e: Exception) {
            e.printStackTrace()
            result.success(false)
        }
    }

    private fun playLocalAudioFile(filePath: String, result: MethodChannel.Result) {
        try {
            val f = File(filePath)
            if (!f.exists() || f.length() == 0L) {
                showToast("⚠️ Audio file is empty or missing")
                result.success(false)
                return
            }

            stopAudioPlayback()

            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
            try {
                audioManager?.mode = android.media.AudioManager.MODE_NORMAL
                audioManager?.isSpeakerphoneOn = false
                val maxVol = audioManager?.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC) ?: 15
                audioManager?.setStreamVolume(
                    android.media.AudioManager.STREAM_MUSIC,
                    maxVol,
                    android.media.AudioManager.FLAG_SHOW_UI
                )
            } catch (_: Exception) {}

            mediaPlayer = MediaPlayer().apply {
                val attrs = android.media.AudioAttributes.Builder()
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                    .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .build()
                setAudioAttributes(attrs)
                setVolume(1.0f, 1.0f)
                setDataSource(filePath)
                prepare()
                start()
                setOnCompletionListener {
                    methodChannel?.invokeMethod("onPlaybackCompleted", mapOf("path" to filePath))
                }
                setOnErrorListener { _, _, _ ->
                    methodChannel?.invokeMethod("onPlaybackCompleted", mapOf("path" to filePath))
                    true
                }
            }
            showToast("▶️ Playing audio out loud...")
            result.success(true)
        } catch (e: Exception) {
            e.printStackTrace()
            result.success(false)
        }
    }

    private fun playDirectStream(urlPath: String, result: MethodChannel.Result) {
        try {
            stopAudioPlayback()

            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
            try {
                audioManager?.mode = android.media.AudioManager.MODE_NORMAL
                audioManager?.isSpeakerphoneOn = false
                val maxVol = audioManager?.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC) ?: 15
                audioManager?.setStreamVolume(
                    android.media.AudioManager.STREAM_MUSIC,
                    maxVol,
                    android.media.AudioManager.FLAG_SHOW_UI
                )
            } catch (_: Exception) {}

            mediaPlayer = MediaPlayer().apply {
                val attrs = android.media.AudioAttributes.Builder()
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                    .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .build()
                setAudioAttributes(attrs)
                setVolume(1.0f, 1.0f)
                setDataSource(urlPath)
                setOnPreparedListener { mp ->
                    try { mp.start() } catch (_: Exception) {}
                }
                prepareAsync()
                setOnCompletionListener {
                    methodChannel?.invokeMethod("onPlaybackCompleted", mapOf("path" to urlPath))
                }
                setOnErrorListener { _, _, _ ->
                    methodChannel?.invokeMethod("onPlaybackCompleted", mapOf("path" to urlPath))
                    true
                }
            }
            showToast("▶️ Playing audio stream...")
            result.success(true)
        } catch (e: Exception) {
            e.printStackTrace()
            result.success(false)
        }
    }

    private fun stopAudioPlayback() {
        try {
            if (mediaPlayer != null) {
                if (mediaPlayer?.isPlaying == true) {
                    mediaPlayer?.stop()
                }
                mediaPlayer?.release()
                mediaPlayer = null
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            if (telephonyReceiver != null) {
                unregisterReceiver(telephonyReceiver)
            }
            if (callLogObserver != null) {
                contentResolver.unregisterContentObserver(callLogObserver!!)
            }
            if (isRecording) {
                stopCallRecording()
            }
            stopAudioPlayback()
            showRecordingNotification(false, "")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun makeDirectCall(phoneNumber: String, slotIndex: Int) {
        val clean = phoneNumber.trim()
        if (clean.isEmpty()) return

        try {
            val hasCallPermission = ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED
            val intentAction = if (hasCallPermission) Intent.ACTION_CALL else Intent.ACTION_DIAL
            val intent = Intent(intentAction, Uri.parse("tel:${Uri.encode(clean)}"))
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK

            if (slotIndex == 1) {
                intent.putExtra("simSlot", 1)
                intent.putExtra("com.android.phone.extra.slot", 1)
                intent.putExtra("subscription", 2)
            } else {
                intent.putExtra("simSlot", 0)
                intent.putExtra("com.android.phone.extra.slot", 0)
                intent.putExtra("subscription", 1)
            }

            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
            try {
                val fallbackIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:${Uri.encode(clean)}"))
                fallbackIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(fallbackIntent)
            } catch (e2: Exception) {
                e2.printStackTrace()
            }
        }
    }

    private fun getRealDeviceCallLogs(): List<Map<String, Any?>> {
        val logsList = mutableListOf<Map<String, Any?>>()
        val hasPermission = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED
        if (!hasPermission) {
            return logsList
        }

        val subMap = HashMap<String, Int>()
        try {
            val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            val activeList = subscriptionManager?.activeSubscriptionInfoList
            if (activeList != null) {
                for (info in activeList) {
                    val slot = info.simSlotIndex + 1
                    subMap[info.subscriptionId.toString()] = slot
                    if (info.iccId != null && info.iccId.isNotEmpty()) {
                        subMap[info.iccId] = slot
                    }
                }
            }
        } catch (_: Exception) {}

        try {
            val uri = CallLog.Calls.CONTENT_URI
            val projection = arrayOf(
                CallLog.Calls._ID,
                CallLog.Calls.NUMBER,
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.TYPE,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION,
                CallLog.Calls.PHONE_ACCOUNT_ID
            )
            val sortOrder = "${CallLog.Calls.DATE} DESC"

            val cursor = contentResolver.query(uri, projection, null, null, sortOrder)
            cursor?.use {
                val idIdx = it.getColumnIndex(CallLog.Calls._ID)
                val numberIdx = it.getColumnIndex(CallLog.Calls.NUMBER)
                val nameIdx = it.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val typeIdx = it.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = it.getColumnIndex(CallLog.Calls.DATE)
                val durationIdx = it.getColumnIndex(CallLog.Calls.DURATION)
                val accountIdx = it.getColumnIndex(CallLog.Calls.PHONE_ACCOUNT_ID)

                var count = 0
                while (it.moveToNext() && count < 100) {
                    val id = if (idIdx != -1) it.getString(idIdx) ?: "$count" else "$count"
                    val number = if (numberIdx != -1) it.getString(numberIdx) ?: "" else ""
                    val rawName = if (nameIdx != -1) it.getString(nameIdx) else null
                    val contactName = resolveContactName(number, rawName)
                    val typeInt = if (typeIdx != -1) it.getInt(typeIdx) else CallLog.Calls.INCOMING_TYPE
                    val dateLong = if (dateIdx != -1) it.getLong(dateIdx) else System.currentTimeMillis()
                    val durationLong = if (durationIdx != -1) it.getLong(durationIdx) else 0L
                    val phoneAccountId = if (accountIdx != -1) it.getString(accountIdx) ?: "" else ""

                    var simSlot = 1
                    if (phoneAccountId.isNotEmpty()) {
                        if (subMap.containsKey(phoneAccountId)) {
                            simSlot = subMap[phoneAccountId] ?: 1
                        } else if (phoneAccountId.contains("1") || phoneAccountId.endsWith("_1") || phoneAccountId == "1") {
                            simSlot = 2
                        } else if (phoneAccountId.contains("0") || phoneAccountId.endsWith("_0") || phoneAccountId == "0") {
                            simSlot = 1
                        }
                    }

                    val typeStr = when (typeInt) {
                        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                        CallLog.Calls.MISSED_TYPE -> "missed"
                        CallLog.Calls.REJECTED_TYPE -> "rejected"
                        CallLog.Calls.VOICEMAIL_TYPE -> "incoming"
                        CallLog.Calls.ANSWERED_EXTERNALLY_TYPE -> "incoming"
                        else -> "incoming"
                    }

                    val logMap = HashMap<String, Any?>()
                    logMap["id"] = id
                    logMap["contactName"] = contactName
                    logMap["phoneNumber"] = number
                    logMap["type"] = typeStr
                    logMap["timestamp"] = dateLong
                    logMap["duration"] = durationLong.toInt()
                    logMap["simSlot"] = simSlot

                    logsList.add(logMap)
                    count++
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return logsList
    }

    private fun resolveContactName(number: String, cachedName: String?): String {
        if (!cachedName.isNullOrEmpty() && cachedName != "Unknown" && cachedName != number) {
            return cachedName
        }
        if (number.isEmpty()) return "Unknown"
        try {
            val hasPermission = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED
            if (hasPermission) {
                val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
                val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)
                val cursor = contentResolver.query(uri, projection, null, null, null)
                cursor?.use {
                    if (it.moveToFirst()) {
                        val nameIdx = it.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME)
                        if (nameIdx != -1) {
                            val resolved = it.getString(nameIdx)
                            if (!resolved.isNullOrEmpty()) {
                                return resolved
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return if (number.isNotEmpty()) number else "Unknown"
    }

    private fun openNativeSaveContactIntent(phoneNumber: String, name: String) {
        try {
            val intent = Intent(Intent.ACTION_INSERT).apply {
                type = ContactsContract.Contacts.CONTENT_TYPE
                putExtra(ContactsContract.Intents.Insert.PHONE, phoneNumber)
                if (name.isNotEmpty()) {
                    putExtra(ContactsContract.Intents.Insert.NAME, name)
                }
            }
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun validateSimNumber(numberInput: String, targetSlot: Int): Map<String, Any?> {
        val cleanNumber = numberInput.replace(Regex("[^0-9]"), "").takeLast(10)
        val response = HashMap<String, Any?>()

        if (cleanNumber.length != 10) {
            response["isValid"] = false
            response["message"] = "Please enter a valid 10-digit mobile number."
            return response
        }

        val simList = getActiveSimCards()
        var foundSim = simList.find { it["slotIndex"] == targetSlot }
        if (foundSim == null && simList.isNotEmpty()) {
            foundSim = simList[0]
        }

        val simPhone = (foundSim?.get("number") as? String ?: "").replace(Regex("[^0-9]"), "").takeLast(10)
        
        if (simPhone.isNotEmpty()) {
            if (simPhone == cleanNumber) {
                response["isValid"] = true
                response["isHardwareMatch"] = true
                response["slotIndex"] = foundSim?.get("slotIndex") ?: 0
                response["carrierName"] = foundSim?.get("carrierName") ?: "Detected Carrier"
                response["formattedNumber"] = "+91 $cleanNumber"
                return response
            } else {
                response["isValid"] = false
                response["isHardwareMatch"] = false
                response["message"] = "Device SIM Mismatch: Registered SIM (+91 $cleanNumber) was not detected in this device SIM slot."
                return response
            }
        }

        val isStandardIndianNumber = cleanNumber.matches(Regex("^[6-9][0-9]{9}$"))
        if (isStandardIndianNumber) {
            response["isValid"] = true
            response["isHardwareMatch"] = false
            response["slotIndex"] = foundSim?.get("slotIndex") ?: targetSlot
            response["carrierName"] = foundSim?.get("carrierName") ?: "Jio / Airtel"
            response["formattedNumber"] = "+91 $cleanNumber"
            return response
        } else {
            response["isValid"] = false
            response["message"] = "Invalid Indian mobile number format. Must start with 6, 7, 8, or 9."
            return response
        }
    }

    private fun checkAllPermissions(): Boolean {
        val phoneState = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
        val callLog = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED
        val contacts = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED
        val audio = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        return phoneState && callLog && contacts && audio
    }

    private fun requestSystemPermissions(result: MethodChannel.Result) {
        val permissions = mutableListOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.CALL_PHONE,
            Manifest.permission.RECORD_AUDIO
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            permissions.add(Manifest.permission.READ_PHONE_NUMBERS)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        val needed = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (needed.isEmpty()) {
            result.success(true)
        } else {
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), PERMISSION_REQ_CODE)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQ_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(allGranted)
            pendingPermissionResult = null
        }
    }

    private fun getActiveSimCards(): List<Map<String, Any?>> {
        val simList = mutableListOf<Map<String, Any?>>()
        try {
            val hasPhoneState = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
            if (hasPhoneState) {
                val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                val activeList = subscriptionManager?.activeSubscriptionInfoList
                if (activeList != null && activeList.isNotEmpty()) {
                    for (info in activeList) {
                        val simMap = HashMap<String, Any?>()
                        val slot = info.simSlotIndex // 0 for SIM 1, 1 for SIM 2
                        simMap["slotIndex"] = slot
                        simMap["subscriptionId"] = info.subscriptionId
                        
                        val carrier = info.carrierName?.toString()?.trim() ?: ""
                        val display = info.displayName?.toString()?.trim() ?: ""
                        
                        simMap["displayName"] = if (display.isNotEmpty()) display else (if (carrier.isNotEmpty()) carrier else "SIM ${slot + 1}")
                        simMap["carrierName"] = if (carrier.isNotEmpty()) carrier else (if (display.isNotEmpty()) display else "Operator ${slot + 1}")
                        simMap["countryIso"] = info.countryIso ?: ""
                        
                        var phoneNum = ""
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            try {
                                phoneNum = subscriptionManager.getPhoneNumber(info.subscriptionId) ?: ""
                            } catch (_: Exception) {}
                        }
                        if (phoneNum.isEmpty()) {
                            @Suppress("DEPRECATION")
                            phoneNum = info.number ?: ""
                        }
                        simMap["number"] = phoneNum
                        simList.add(simMap)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        if (simList.isEmpty()) {
            val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            val simOp = telephonyManager?.simOperatorName?.trim()
            val netOp = telephonyManager?.networkOperatorName?.trim()
            val detectedCarrier = if (!simOp.isNullOrEmpty()) simOp else if (!netOp.isNullOrEmpty()) netOp else "Jio True5G"

            val primarySim = HashMap<String, Any?>()
            primarySim["slotIndex"] = 0
            primarySim["subscriptionId"] = 1
            primarySim["displayName"] = detectedCarrier
            primarySim["carrierName"] = detectedCarrier
            primarySim["number"] = ""
            primarySim["countryIso"] = "in"
            simList.add(primarySim)
        }

        return simList
    }
}
