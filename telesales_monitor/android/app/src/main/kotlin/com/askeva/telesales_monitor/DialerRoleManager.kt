package com.askeva.telesales_monitor

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
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
     * Returns a summary map of dialer status for Flutter.
     */
    fun getStatus(context: Context): Map<String, Any> {
        return mapOf(
            "isDefault" to isDefaultDialer(context),
            "isRoleAvailable" to isRoleAvailable(context)
        )
    }

    /**
     * Creates the Intent to request the default dialer role.
     * Note: Per project policy, this should only be invoked once the incoming
     * and ongoing call interfaces (Phases 3 and 4) are completed.
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
