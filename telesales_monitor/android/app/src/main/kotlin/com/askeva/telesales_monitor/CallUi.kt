package com.askeva.telesales_monitor

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telecom.Call
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * What the phone shows for a call while AskEVA is the Phone app: the incoming-call notification
 * (full screen when the phone is locked, with Answer / Decline), the ongoing-call notification
 * (timer, Hang up) and AskEVA's call screen (MainActivity → Flutter call screen).
 * Android rings for incoming calls itself (no IN_CALL_SERVICE_RINGING), so the channels are silent.
 */
object CallUi {
    private const val TAG = "AskEvaCallUi"
    const val NOTIF_ID = 4101
    private const val CH_INCOMING = "askeva_incoming_calls"
    private const val CH_ONGOING = "askeva_ongoing_calls"

    /** MainActivity extras: show the call screen (also over the lock screen) / answer the ringing call. */
    const val EXTRA_SHOW_CALL = "askeva_show_call"
    const val EXTRA_ANSWER = "askeva_answer_call"

    private var shownCallId: String? = null

    /** Called by [CallManager] on every change; [call] null = no calls left. */
    fun update(ctx: Context, call: Call?, callId: String?, name: String) {
        if (call == null) {
            cancel(ctx)
            shownCallId = null
            return
        }
        ensureChannels(ctx)
        val number = call.details?.handle?.schemeSpecificPart ?: ""
        val title = name.ifBlank { number.ifBlank { "Unknown number" } }
        val isNew = callId != shownCallId
        shownCallId = callId
        if (call.state == Call.STATE_RINGING) {
            postIncoming(ctx, title)
            // No way to show the full-screen notification: open the call screen directly
            // (an InCallService may start activities from the background)
            if (isNew && !canShowFullScreen(ctx)) showCallScreen(ctx)
        } else {
            postOngoing(ctx, call, title)
            // A call placed from AskEVA or anywhere else: bring up AskEVA's call screen once
            if (isNew && call.state != Call.STATE_DISCONNECTED) showCallScreen(ctx)
        }
    }

    fun showCallScreen(ctx: Context) {
        try {
            ctx.startActivity(callScreenIntent(ctx))
        } catch (e: Exception) {
            Log.w(TAG, "could not open the call screen", e)
        }
    }

    private fun callScreenIntent(ctx: Context, answer: Boolean = false) =
        Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_SHOW_CALL, true)
            .putExtra(EXTRA_ANSWER, answer)

    private fun activityPi(ctx: Context, request: Int, answer: Boolean) = PendingIntent.getActivity(
        ctx, request, callScreenIntent(ctx, answer), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun actionPi(ctx: Context, request: Int, action: String) = PendingIntent.getBroadcast(
        ctx, request, Intent(ctx, CallActionReceiver::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun canShowFullScreen(ctx: Context): Boolean {
        if (!NotificationManagerCompat.from(ctx).areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 34) {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            if (nm != null && !nm.canUseFullScreenIntent()) return false
        }
        return true
    }

    private fun postIncoming(ctx: Context, title: String) {
        val n = NotificationCompat.Builder(ctx, CH_INCOMING)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(title)
            .setContentText("Incoming call")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(activityPi(ctx, 1, answer = false))
            .setFullScreenIntent(activityPi(ctx, 2, answer = false), true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Decline", actionPi(ctx, 3, CallActionReceiver.ACTION_DECLINE))
            .addAction(android.R.drawable.sym_action_call, "Answer", activityPi(ctx, 4, answer = true))
            .build()
        notify(ctx, n)
    }

    private fun postOngoing(ctx: Context, call: Call, title: String) {
        val stateText = when (call.state) {
            Call.STATE_ACTIVE -> "Ongoing call"
            Call.STATE_HOLDING -> "On hold"
            Call.STATE_SELECT_PHONE_ACCOUNT -> "Choose a SIM"
            Call.STATE_DISCONNECTING, Call.STATE_DISCONNECTED -> "Call ended"
            else -> "Calling…"
        }
        val connectedAt = call.details?.connectTimeMillis ?: 0L
        val b = NotificationCompat.Builder(ctx, CH_ONGOING)
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle(title)
            .setContentText(stateText)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(activityPi(ctx, 1, answer = false))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Hang up", actionPi(ctx, 5, CallActionReceiver.ACTION_HANG_UP))
        if (call.state == Call.STATE_ACTIVE && connectedAt > 0) {
            b.setWhen(connectedAt).setShowWhen(true).setUsesChronometer(true)
        }
        notify(ctx, b.build())
    }

    private fun notify(ctx: Context, n: android.app.Notification) {
        try {
            NotificationManagerCompat.from(ctx).notify(NOTIF_ID, n)
        } catch (e: SecurityException) {
            Log.w(TAG, "notifications not allowed", e) // POST_NOTIFICATIONS denied: the call screen still opens
        }
    }

    private fun cancel(ctx: Context) {
        try {
            NotificationManagerCompat.from(ctx).cancel(NOTIF_ID)
        } catch (_: Exception) {}
    }

    private fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CH_INCOMING) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CH_INCOMING, "Incoming calls", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Incoming calls while AskEVA is your Phone app"
                    setSound(null, null) // Android plays the ringtone
                    enableVibration(false)
                },
            )
        }
        if (nm.getNotificationChannel(CH_ONGOING) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CH_ONGOING, "Ongoing calls", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "The call in progress, with Hang up"
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
    }
}
