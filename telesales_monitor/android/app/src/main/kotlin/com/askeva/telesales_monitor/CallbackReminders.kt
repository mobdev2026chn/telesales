package com.askeva.telesales_monitor

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import org.json.JSONObject

/**
 * Follow-up reminders: a phone notification when a callback the agent scheduled is due.
 * Set from Dart (MainActivity "scheduleCallbackReminder" / "cancelCallbackReminder" /
 * "cancelAllCallbackReminders"). Kept in a small prefs file so they survive the app being closed and
 * are set again after a reboot ([BootReceiver]). Inexact alarms (no exact-alarm permission needed):
 * Android may deliver one a few minutes late while the phone sleeps.
 */
object CallbackReminders {
    private const val PREFS = "askeva_callback_reminders"
    const val ACTION_FIRE = "com.askeva.telesales_monitor.CALLBACK_REMINDER"
    const val EXTRA_ID = "reminder_id"
    /** A reminder missed while the phone was off is still shown after boot if it is at most this late. */
    private const val SHOW_LATE_UP_TO_MS = 12L * 3600 * 1000

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun notifId(id: String) = 20000 + (id.hashCode() and 0x7FFF)

    private fun pendingIntent(ctx: Context, id: String, create: Boolean): PendingIntent? {
        val intent = Intent(ctx, CallbackReminderReceiver::class.java)
            .setAction(ACTION_FIRE)
            // Distinct data per reminder, so each one can be replaced / cancelled on its own
            .setData(Uri.parse("askeva-reminder://callback/" + Uri.encode(id)))
            .putExtra(EXTRA_ID, id)
        val flags = PendingIntent.FLAG_IMMUTABLE or (if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE)
        return PendingIntent.getBroadcast(ctx.applicationContext, notifId(id), intent, flags)
    }

    private fun setAlarm(ctx: Context, id: String, atMs: Long) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val pi = pendingIntent(ctx, id, create = true) ?: return
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
    }

    fun schedule(ctx: Context, id: String, atMs: Long, title: String, body: String): Boolean {
        if (id.isEmpty() || atMs <= System.currentTimeMillis()) return false
        return try {
            prefs(ctx).edit().putString(id, JSONObject().put("atMs", atMs).put("title", title).put("body", body).toString()).apply()
            setAlarm(ctx, id, atMs)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun cancel(ctx: Context, id: String): Boolean {
        if (id.isEmpty()) return false
        return try {
            prefs(ctx).edit().remove(id).apply()
            pendingIntent(ctx, id, create = false)?.let { pi ->
                (ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager)?.cancel(pi)
                pi.cancel()
            }
            CallMonitorStore.cancelNotification(ctx, notifId(id))
            true
        } catch (_: Exception) {
            false
        }
    }

    fun cancelAll(ctx: Context): Boolean {
        val ids = try { prefs(ctx).all.keys.toList() } catch (_: Exception) { emptyList() }
        ids.forEach { cancel(ctx, it) }
        return true
    }

    /** After a reboot alarms are gone: set them again, and show the ones that fell due while the phone was off. */
    fun rescheduleAll(ctx: Context) {
        val now = System.currentTimeMillis()
        val all = try { prefs(ctx).all } catch (_: Exception) { return }
        for ((id, raw) in all) {
            val o = try { JSONObject(raw as? String ?: continue) } catch (_: Exception) { prefs(ctx).edit().remove(id).apply(); continue }
            val atMs = o.optLong("atMs")
            when {
                atMs > now -> setAlarm(ctx, id, atMs)
                now - atMs <= SHOW_LATE_UP_TO_MS -> fire(ctx, id)
                else -> prefs(ctx).edit().remove(id).apply()
            }
        }
    }

    /** Shows the reminder (only while someone is signed in) and forgets it. */
    fun fire(ctx: Context, id: String) {
        val raw = prefs(ctx).getString(id, null) ?: return
        prefs(ctx).edit().remove(id).apply()
        if (CallMonitorStore.session(ctx) == null) return // signed out since it was set
        val o = try { JSONObject(raw) } catch (_: Exception) { return }
        CallMonitorStore.postAlert(
            ctx, notifId(id),
            o.optString("title").ifEmpty { "Callback due" },
            o.optString("body").ifEmpty { "Open AskEVA to call back." },
        )
    }
}

/** Alarm of a [CallbackReminders] reminder. Not exported: only our own alarms reach it. */
class CallbackReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != CallbackReminders.ACTION_FIRE) return
        val id = intent.getStringExtra(CallbackReminders.EXTRA_ID) ?: return
        CallbackReminders.fire(context, id)
    }
}
