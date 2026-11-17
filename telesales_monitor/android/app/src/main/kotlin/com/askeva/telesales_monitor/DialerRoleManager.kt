package com.askeva.telesales_monitor

import android.app.Activity
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telecom.TelecomManager

/**
 * Manages checking and requesting the Android Default Dialer role (ROLE_DIALER).
 * Uses RoleManager on Android 10+ (API 29+) with graceful fallback to TelecomManager
 * on older versions.
 *
 * Important note: Being the default dialer does NOT grant cellular call audio recording
 * permissions. Call management is handled separately by [CallManager] and [AskEvaInCallService].
 */
object DialerRoleManager {

    const val REQUEST_CODE_DIALER_ROLE = 4001

    /**
     * Checks if AskEVA is currently the system's default dialer (phone app).
     */
    fun isDefaultDialer(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = context.getSystemService(Context.ROLE_SERVICE) as? RoleManager
                roleManager?.isRoleHeld(RoleManager.ROLE_DIALER) == true
            } else {
                val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                telecomManager?.defaultDialerPackage == context.packageName
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Checks if the default dialer role can be requested on this device.
     */
    fun isRoleAvailable(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = context.getSystemService(Context.ROLE_SERVICE) as? RoleManager
                roleManager?.isRoleAvailable(RoleManager.ROLE_DIALER) == true
            } else {
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * The ".DialerEntry" alias (AndroidManifest) holds the DIAL / tel: filters Android requires of a
     * Phone app. Off by default, so tel: links keep going to the phone's own Phone app; switched on
     * just before asking for the role, and off again whenever AskEVA is not the Phone app.
     */
    private fun dialerEntry(context: Context) =
        ComponentName(context, "${DialerRoleManager::class.java.`package`!!.name}.DialerEntry")

    fun setDialerEntryEnabled(context: Context, enabled: Boolean) {
        try {
            val state = if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            if (context.packageManager.getComponentEnabledSetting(dialerEntry(context)) == state) return
            context.packageManager.setComponentEnabledSetting(dialerEntry(context), state, PackageManager.DONT_KILL_APP)
        } catch (_: Exception) {}
    }

    /** App start / resume / role answer: the DIAL filters are on exactly while AskEVA is the Phone app. */
    fun syncDialerEntry(context: Context) = setDialerEntryEnabled(context, isDefaultDialer(context))

    /**
     * Returns a summary map of dialer status for Flutter.
     */
    fun getStatus(context: Context): Map<String, Any> {
        return mapOf(
            "isDefault" to isDefaultDialer(context),
            "isRoleAvailable" to isRoleAvailable(context)
        )
    }

    /**
     * Creates the Intent to request the default dialer role. Call [setDialerEntryEnabled] (true)
     * first: without the DIAL filters Android does not offer AskEVA as a Phone app.
     * Being the Phone app stops the phone maker's call recorder (Samsung, vivo, ...): the Call recording
     * screen says so and asks first on those phones; on Phone-by-Google-only phones nothing is lost.
     */
    fun createRequestRoleIntent(activity: Activity): Intent? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = activity.getSystemService(Context.ROLE_SERVICE) as? RoleManager
                if (roleManager?.isRoleAvailable(RoleManager.ROLE_DIALER) == true) {
                    roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                } else {
                    null
                }
            } else {
                Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER).apply {
                    putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, activity.packageName)
                }
            }
        } catch (_: Exception) {
            null
        }
    }
}
