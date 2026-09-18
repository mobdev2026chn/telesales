package com.askeva.telesales_monitor

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.provider.ContactsContract
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Base64
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Method-channel plumbing for Flutter. Call tracking / recording / uploads live in
 * [CallMonitorService] + [RecordingUploader] so they keep working without this Activity.
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.askeva.telesales/telephony"
    // Safety cap on rows read per call-log query (the query itself is already limited to the work session)
    private val MAX_CALL_LOGS = 5000
    private val PERMISSION_REQ_CODE = 2001
    private val MEDIA_PERMISSION_REQ_CODE = 2002
    private val CALL_LOG_DEBOUNCE_MS = 1500L

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingMediaPermissionResult: MethodChannel.Result? = null
    private var methodChannel: MethodChannel? = null
    private var eventListener: ((String, Map<String, Any?>) -> Unit)? = null

    // Heavy work (call-log queries, contact lookups, queue file IO) runs here, never on the UI thread
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val contactNameCache = ConcurrentHashMap<String, String>()

    private var callLogObserver: ContentObserver? = null
    private val callLogChanged = Runnable {
        methodChannel?.invokeMethod("onCallStateChanged", mapOf("state" to "LOG_UPDATED"))
    }
    private var mediaPlayer: MediaPlayer? = null
    private var isPlayerPrepared = false
    private var currentTempPlaybackFile: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ioExecutor.execute { cleanupStaleTempFiles() }

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSimCards" -> {
                    val simList = getActiveSimCards()
                    result.success(simList)
                }
                "getCallLogs" -> {
                    val since = (call.argument<Number>("since"))?.toLong() ?: 0L
                    ioExecutor.execute {
                        val logs = try { getRealDeviceCallLogs(since) } catch (e: Exception) { emptyList() }
                        mainHandler.post { result.success(logs) }
                    }
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
                // ---- Call monitor (foreground service) ----
                "startCallMonitor" -> {
                    val baseUrl = call.argument<String>("baseUrl") ?: ""
                    CallMonitorStore.setBaseUrl(this, baseUrl)
                    CallMonitorStore.cancelNotification(this, CallMonitorStore.NOTIF_ID_LOGIN)
                    result.success(CallMonitorService.start(this))
                }
                "stopCallMonitor" -> {
                    // The upload worker is left alone: it only sends a signed-in user's own recordings
                    CallMonitorService.stop(this)
                    CallMonitorStore.cancelNotification(this, CallMonitorStore.NOTIF_ID_RESUME)
                    result.success(true)
                }
                "retryUploads" -> {
                    RecordingUploader.schedule(this)
                    result.success(true)
                }
                "getPendingUploadCount" -> {
                    val userId = call.argument<String>("userId") ?: ""
                    ioExecutor.execute {
                        val n = try { RecordingQueue.countFor(this, userId) } catch (_: Exception) { 0 }
                        mainHandler.post { result.success(n) }
                    }
                }
                "enqueueLegacyUploads" -> {
                    // Recordings the old Dart uploader had not sent yet: hand them to the native queue
                    val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                    ioExecutor.execute {
                        var added = 0
                        for (m in items) {
                            val path = m["filePath"] as? String ?: continue
                            if (!File(path).exists()) continue
                            RecordingQueue.add(this, QueuedRecording(
                                id = QueuedRecording.newId(),
                                userId = m["userId"] as? String ?: continue,
                                source = "own",
                                path = path,
                                uri = "",
                                fileName = (m["fileName"] as? String)?.ifEmpty { null } ?: File(path).name,
                                callStartedAtMs = (m["callStartedAtMs"] as? Number)?.toLong() ?: System.currentTimeMillis(),
                                phoneNumber = m["phoneNumber"] as? String ?: "",
                                contactName = m["contactName"] as? String ?: "",
                                type = m["type"] as? String ?: "OUTGOING",
                                simSlot = (m["simSlot"] as? Number)?.toInt() ?: 0,
                                durationSeconds = (m["durationSeconds"] as? Number)?.toInt() ?: 1,
                            ))
                            added++
                        }
                        if (added > 0) RecordingUploader.schedule(this)
                        mainHandler.post { result.success(added) }
                    }
                }
                "isRecordingActive" -> {
                    result.success(false)
                }
                // ---- Call recording setup screen ----
                "getRecordingSetupStatus" -> {
                    val userId = call.argument<String>("userId") ?: ""
                    ioExecutor.execute {
                        val status = HashMap<String, Any?>(DeviceSetupHelper.deviceInfo())
                        status["serviceRunning"] = CallMonitorService.isRunning
                        status["micPermission"] = CallMonitorStore.hasPermission(this, Manifest.permission.RECORD_AUDIO)
                        status["mediaPermission"] = CallMonitorStore.hasMediaPermission(this)
                        status["batteryOptimizationIgnored"] = DeviceSetupHelper.isIgnoringBatteryOptimizations(this)
                        status["nativeRecorderDetected"] = CallMonitorStore.nativeRecorderDetected(this)
                        status["accessibilityEnabled"] = CallAccessibilityService.isEnabled(this)
                        status["lastCaptureStatus"] = CallMonitorStore.lastCaptureStatus(this)
                        status["lastCaptureAt"] = CallMonitorStore.lastCaptureAt(this)
                        status["pendingUploads"] = try { RecordingQueue.countFor(this, userId) } catch (_: Exception) { 0 }
                        mainHandler.post { result.success(status) }
                    }
                }
                "requestMediaPermission" -> requestMediaPermission(result)
                "requestIgnoreBatteryOptimizations" -> {
                    result.success(DeviceSetupHelper.requestIgnoreBatteryOptimizations(this))
                }
                "openDialerRecordingSettings" -> {
                    result.success(DeviceSetupHelper.openDialerRecordingSettings(this))
                }
                "openAutostartSettings" -> {
                    result.success(DeviceSetupHelper.openAutostartSettings(this))
                }
                "openAccessibilitySettings" -> {
                    result.success(DeviceSetupHelper.openAccessibilitySettings(this))
                }
                "openAppInfo" -> {
                    result.success(DeviceSetupHelper.openAppInfo(this))
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
                "getPlaybackPosition" -> {
                    result.success(getPlaybackPosition())
                }
                "openSaveContact" -> {
                    val phone = call.argument<String>("phoneNumber") ?: ""
                    val name = call.argument<String>("name") ?: ""
                    contactNameCache.remove(phone)
                    openNativeSaveContactIntent(phone, name)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Service / upload events reach Dart while this engine is alive
        val listener: (String, Map<String, Any?>) -> Unit = { method, args ->
            try { methodChannel?.invokeMethod(method, args) } catch (_: Exception) {}
        }
        eventListener = listener
        CallMonitorEvents.listener = listener

        registerCallLogObserver()
    }

    private fun requestMediaPermission(result: MethodChannel.Result) {
        val perm = CallMonitorStore.mediaReadPermission()
        if (CallMonitorStore.hasPermission(this, perm)) {
            result.success(true)
            return
        }
        pendingMediaPermissionResult?.success(false)
        pendingMediaPermissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(perm), MEDIA_PERMISSION_REQ_CODE)
    }

    private fun showToast(message: String) {
        mainHandler.post {
            try {
                Toast.makeText(applicationContext, message, Toast.LENGTH_LONG).show()
            } catch (_: Exception) {}
        }
    }


    private fun registerCallLogObserver() {
        try {
            if (callLogObserver != null) return
            val hasPermission = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED
            if (!hasPermission) return

            callLogObserver = object : ContentObserver(mainHandler) {
                override fun onChange(selfChange: Boolean) {
                    super.onChange(selfChange)
                    // The provider fires several times per call: debounce into one notification
                    mainHandler.removeCallbacks(callLogChanged)
                    mainHandler.postDelayed(callLogChanged, CALL_LOG_DEBOUNCE_MS)
                }
            }
            contentResolver.registerContentObserver(CallLog.Calls.CONTENT_URI, true, callLogObserver!!)
        } catch (e: Exception) {
            callLogObserver = null
            e.printStackTrace()
        }
    }


    private fun activeSubscriptions(): List<SubscriptionInfo> {
        return try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) return emptyList()
            val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            sm?.activeSubscriptionInfoList ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }



    private fun playRecordedAudio(filePath: String, audioUrl: String, audioData: String, result: MethodChannel.Result) {
        try {
            stopAudioPlayback()

            // 1. Try local file path if present and valid
            if (filePath.isNotEmpty()) {
                val f = File(filePath)
                if (f.exists() && f.length() > 0) {
                    playLocalAudioFile(f.absolutePath, result, null)
                    return
                }
            }

            // 2. Try Base64 audio data if present
            if (audioData.isNotEmpty() && audioData.length > 50) {
                try {
                    val cleanBase64 = audioData.replace(Regex("^data:audio/\\w+;base64,"), "")
                    val bytes = Base64.decode(cleanBase64, Base64.DEFAULT)
                    if (bytes.isNotEmpty()) {
                        val isWav = bytes.size > 4 && bytes[0] == 'R'.code.toByte() && bytes[1] == 'I'.code.toByte() && bytes[2] == 'F'.code.toByte()
                        val ext = if (isWav) ".wav" else ".m4a"
                        val tempFile = File(cacheDir, "temp_b64_play_${System.currentTimeMillis()}$ext")
                        tempFile.writeBytes(bytes)
                        playLocalAudioFile(tempFile.absolutePath, result, tempFile)
                        return
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }

            // 3. Download or stream via HTTP(S) (the URL already carries ?token=)
            if (audioUrl.startsWith("http")) {
                ioExecutor.execute {
                    val downloaded = File(cacheDir, "temp_play_${System.currentTimeMillis()}.audio")
                    try {
                        val url = java.net.URL(audioUrl)
                        val conn = url.openConnection()
                        conn.connectTimeout = 8000
                        conn.readTimeout = 20000
                        val bytes = conn.getInputStream().use { it.readBytes() }
                        downloaded.writeBytes(bytes)
                        mainHandler.post { playLocalAudioFile(downloaded.absolutePath, result, downloaded) }
                    } catch (e: Exception) {
                        try { downloaded.delete() } catch (_: Exception) {}
                        mainHandler.post { playDirectStream(audioUrl, result) }
                    }
                }
                return
            }

            showToast("⚠️ Recording audio file not found on device or server.")
            result.success(false)
        } catch (e: Exception) {
            e.printStackTrace()
            result.success(false)
        }
    }

    private fun onPlaybackDone(path: String) {
        deleteTempPlaybackFile()
        isPlayerPrepared = false
        methodChannel?.invokeMethod("onPlaybackCompleted", mapOf("path" to path))
    }

    private fun deleteTempPlaybackFile() {
        val f = currentTempPlaybackFile
        currentTempPlaybackFile = null
        if (f != null) {
            try { f.delete() } catch (_: Exception) {}
        }
    }

    /** [tempFile] is deleted when playback stops or completes. */
    private fun playLocalAudioFile(filePath: String, result: MethodChannel.Result, tempFile: File?) {
        try {
            val f = File(filePath)
            if (!f.exists() || f.length() == 0L) {
                tempFile?.delete()
                showToast("⚠️ Audio file is empty or missing")
                result.success(false)
                return
            }

            stopAudioPlayback()
            currentTempPlaybackFile = tempFile

            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
            try {
                audioManager?.mode = android.media.AudioManager.MODE_NORMAL
                audioManager?.isSpeakerphoneOn = true
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
                isPlayerPrepared = true
                start()
                setOnCompletionListener { onPlaybackDone(filePath) }
                setOnErrorListener { _, _, _ ->
                    onPlaybackDone(filePath)
                    true
                }
            }
            result.success(true)
        } catch (e: Exception) {
            e.printStackTrace()
            deleteTempPlaybackFile()
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
                    isPlayerPrepared = true
                    try { mp.start() } catch (_: Exception) {}
                }
                prepareAsync()
                setOnCompletionListener { onPlaybackDone(urlPath) }
                setOnErrorListener { _, _, _ ->
                    onPlaybackDone(urlPath)
                    true
                }
            }
            result.success(true)
        } catch (e: Exception) {
            e.printStackTrace()
            result.success(false)
        }
    }

    /** Real player position / duration in ms for the progress bar. */
    private fun getPlaybackPosition(): Map<String, Any> {
        val mp = mediaPlayer
        if (mp == null || !isPlayerPrepared) {
            return mapOf("position" to 0, "duration" to 0, "isPlaying" to false)
        }
        return try {
            val dur = mp.duration
            mapOf(
                "position" to mp.currentPosition,
                "duration" to (if (dur > 0) dur else 0),
                "isPlaying" to mp.isPlaying
            )
        } catch (_: Exception) {
            mapOf("position" to 0, "duration" to 0, "isPlaying" to false)
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
        isPlayerPrepared = false
        deleteTempPlaybackFile()
    }

    /** Leftover playback temp files from an earlier run. */
    private fun cleanupStaleTempFiles() {
        try {
            cacheDir.listFiles()?.forEach { f ->
                if (f.isFile && (f.name.startsWith("temp_play_") || f.name.startsWith("temp_b64_play_"))) {
                    f.delete()
                }
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        // The call monitor service keeps running without this Activity; only UI plumbing stops here
        if (CallMonitorEvents.listener === eventListener) CallMonitorEvents.listener = null
        eventListener = null
        try {
            if (callLogObserver != null) {
                contentResolver.unregisterContentObserver(callLogObserver!!)
                callLogObserver = null
            }
            mainHandler.removeCallbacks(callLogChanged)
            stopAudioPlayback()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        ioExecutor.shutdown()
        super.onDestroy()
    }

    /** The call-capable phone account of the SIM in [slotIndex] (0-based), or null. */
    private fun phoneAccountForSlot(slotIndex: Int): PhoneAccountHandle? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) return null
        try {
            val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager ?: return null
            val info = sm.getActiveSubscriptionInfoForSimSlotIndex(slotIndex) ?: return null
            val telecom = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return null
            val telephony = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            val iccId = try { info.iccId } catch (_: Exception) { null }
            for (handle in telecom.callCapablePhoneAccounts) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && telephony != null) {
                    try {
                        if (telephony.getSubscriptionId(handle) == info.subscriptionId) return handle
                    } catch (_: Exception) {}
                }
                val id = handle.id ?: continue
                if (id == info.subscriptionId.toString()) return handle
                if (!iccId.isNullOrEmpty() && id.equals(iccId, ignoreCase = true)) return handle
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return null
    }

    private fun makeDirectCall(phoneNumber: String, slotIndex: Int) {
        val clean = phoneNumber.trim()
        if (clean.isEmpty()) return

        CallMonitorService.noteDialed(clean, slotIndex + 1)

        try {
            val hasCallPermission = ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED
            val intentAction = if (hasCallPermission) Intent.ACTION_CALL else Intent.ACTION_DIAL
            val intent = Intent(intentAction, Uri.parse("tel:${Uri.encode(clean)}"))
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK

            // Standard way to pick the SIM: the phone account of that subscription
            val handle = phoneAccountForSlot(slotIndex)
            if (handle != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                intent.putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
            } else {
                // Vendor dialers that ignore the handle still honour this slot hint
                intent.putExtra("com.android.phone.extra.slot", slotIndex)
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

    // Returns calls made at or after `since` (epoch ms), newest first. Runs on ioExecutor.
    private fun getRealDeviceCallLogs(since: Long = 0L): List<Map<String, Any?>> {
        val logsList = mutableListOf<Map<String, Any?>>()
        val hasPermission = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED
        if (!hasPermission) {
            return logsList
        }

        // PHONE_ACCOUNT_ID holds the subscription id (newer Android) or the SIM's ICCID (older):
        // map by exact equality only. Anything else is reported as 0 = unknown.
        val subIdToSlot = HashMap<String, Int>()
        val iccIdToSlot = HashMap<String, Int>()
        val subs = activeSubscriptions()
        for (info in subs) {
            val slot = info.simSlotIndex + 1
            subIdToSlot[info.subscriptionId.toString()] = slot
            try {
                val icc = info.iccId
                if (!icc.isNullOrEmpty()) iccIdToSlot[icc.lowercase(Locale.US)] = slot
            } catch (_: Exception) {}
        }
        val onlySlot = if (subs.size == 1) subs[0].simSlotIndex + 1 else 0

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
            // Filter by date in the query instead of a fixed row cap, so no work-session call is dropped
            val selection = "${CallLog.Calls.DATE} >= ?"
            val selectionArgs = arrayOf(since.toString())

            val cursor = contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)
            cursor?.use {
                val idIdx = it.getColumnIndex(CallLog.Calls._ID)
                val numberIdx = it.getColumnIndex(CallLog.Calls.NUMBER)
                val nameIdx = it.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val typeIdx = it.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = it.getColumnIndex(CallLog.Calls.DATE)
                val durationIdx = it.getColumnIndex(CallLog.Calls.DURATION)
                val accountIdx = it.getColumnIndex(CallLog.Calls.PHONE_ACCOUNT_ID)

                var count = 0
                while (it.moveToNext() && count < MAX_CALL_LOGS) {
                    val id = if (idIdx != -1) it.getString(idIdx) ?: "$count" else "$count"
                    val number = if (numberIdx != -1) it.getString(numberIdx) ?: "" else ""
                    val rawName = if (nameIdx != -1) it.getString(nameIdx) else null
                    val contactName = resolveContactName(number, rawName)
                    val typeInt = if (typeIdx != -1) it.getInt(typeIdx) else CallLog.Calls.INCOMING_TYPE
                    val dateLong = if (dateIdx != -1) it.getLong(dateIdx) else System.currentTimeMillis()
                    val durationLong = if (durationIdx != -1) it.getLong(durationIdx) else 0L
                    val phoneAccountId = if (accountIdx != -1) it.getString(accountIdx) ?: "" else ""

                    val simSlot = when {
                        phoneAccountId.isEmpty() -> onlySlot
                        subIdToSlot.containsKey(phoneAccountId) -> subIdToSlot[phoneAccountId] ?: 0
                        iccIdToSlot.containsKey(phoneAccountId.lowercase(Locale.US)) -> iccIdToSlot[phoneAccountId.lowercase(Locale.US)] ?: 0
                        else -> onlySlot
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

    /** Contact name for a number; lookups are cached (called for every call-log row). */
    private fun resolveContactName(number: String, cachedName: String?): String {
        if (!cachedName.isNullOrEmpty() && cachedName != "Unknown" && cachedName != number) {
            return cachedName
        }
        if (number.isEmpty()) return "Unknown"
        contactNameCache[number]?.let { return it }
        var resolvedName = number
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
                                resolvedName = resolved
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        contactNameCache[number] = resolvedName
        return resolvedName
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

        val isStandardIndianNumber = cleanNumber.matches(Regex("^[6-9][0-9]{9}$"))
        if (isStandardIndianNumber) {
            response["isValid"] = true
            response["isHardwareMatch"] = false // the number format is valid; ownership is not verified here
            response["slotIndex"] = foundSim?.get("slotIndex") ?: targetSlot
            response["carrierName"] = foundSim?.get("carrierName") ?: ""
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
            // The observer could not be registered at start-up without READ_CALL_LOG: do it now
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED) {
                registerCallLogObserver()
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
                contactNameCache.clear() // earlier lookups ran without contacts access
            }
            pendingPermissionResult?.success(allGranted)
            pendingPermissionResult = null
        } else if (requestCode == MEDIA_PERMISSION_REQ_CODE) {
            val granted = CallMonitorStore.hasMediaPermission(this)
            pendingMediaPermissionResult?.success(granted)
            pendingMediaPermissionResult = null
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
                        simMap["carrierName"] = if (carrier.isNotEmpty()) carrier else (if (display.isNotEmpty()) display else "SIM ${slot + 1}")
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
            val detectedCarrier = if (!simOp.isNullOrEmpty()) simOp else if (!netOp.isNullOrEmpty()) netOp else "SIM 1"

            val primarySim = HashMap<String, Any?>()
            primarySim["slotIndex"] = 0
            primarySim["subscriptionId"] = -1
            primarySim["displayName"] = detectedCarrier
            primarySim["carrierName"] = detectedCarrier
            primarySim["number"] = ""
            primarySim["countryIso"] = ""
            simList.add(primarySim)
        }

        return simList
    }
}
