package com.askeva.telesales_monitor

import android.Manifest
import android.content.Context
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import java.util.Locale

/**
 * Which SIM slot (1-based, 0 = unknown) a call-log row's PHONE_ACCOUNT_ID belongs to.
 *
 * Phones fill PHONE_ACCOUNT_ID differently: the subscription id, the SIM's ICCID (sometimes with a
 * trailing "F" or cut short), or a telecom phone-account id. All three are resolved here, so a call
 * on the personal SIM is recognised as such instead of being reported as "unknown".
 */
object SimSlots {

    fun activeSubscriptions(ctx: Context): List<SubscriptionInfo> {
        return try {
            if (!CallMonitorStore.hasPermission(ctx, Manifest.permission.READ_PHONE_STATE)) return emptyList()
            val sm = ctx.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            sm?.activeSubscriptionInfoList ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun activeSimCount(ctx: Context): Int = activeSubscriptions(ctx).size

    private fun normIcc(s: String) = s.lowercase(Locale.US).trimEnd('f')

    /** Build once per call-log read (subscription lookups are not free), then call [slotFor] per row. */
    class Resolver(ctx: Context) {
        private val subs = activeSubscriptions(ctx)
        private val onlySlot = if (subs.size == 1) subs[0].simSlotIndex + 1 else 0
        private val bySubId = HashMap<String, Int>()
        private val byIcc = HashMap<String, Int>()
        private val byAccount = HashMap<String, Int>()

        init {
            val slotBySubId = HashMap<Int, Int>()
            for (info in subs) {
                val slot = info.simSlotIndex + 1
                slotBySubId[info.subscriptionId] = slot
                bySubId[info.subscriptionId.toString()] = slot
                try {
                    val icc = info.iccId
                    if (!icc.isNullOrEmpty()) byIcc[normIcc(icc)] = slot
                } catch (_: Exception) {}
            }
            // Telecom phone accounts -> subscription (Android 11+), covers OEM-specific account ids
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && CallMonitorStore.hasPermission(ctx, Manifest.permission.READ_PHONE_STATE)) {
                try {
                    val telecom = ctx.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                    val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                    @Suppress("MissingPermission")
                    val handles = telecom?.callCapablePhoneAccounts ?: emptyList()
                    for (h in handles) {
                        val subId = try { tm?.getSubscriptionId(h) ?: -1 } catch (_: Exception) { -1 }
                        val slot = slotBySubId[subId] ?: continue
                        byAccount[h.id] = slot
                    }
                } catch (_: Exception) {}
            }
        }

        fun slotFor(accountId: String?): Int {
            val id = accountId?.trim().orEmpty()
            if (id.isEmpty()) return onlySlot
            bySubId[id]?.let { return it }
            byAccount[id]?.let { return it }
            val icc = normIcc(id)
            byIcc[icc]?.let { return it }
            // Shortened / padded ICCIDs: same prefix of at least 18 digits
            if (icc.length >= 18) {
                for ((k, slot) in byIcc) {
                    if (k.length >= 18 && (k.startsWith(icc) || icc.startsWith(k))) return slot
                }
            }
            return onlySlot
        }
    }
}
