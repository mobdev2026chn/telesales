package com.askeva.telesales_monitor

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telecom.TelecomManager

/** Opens OEM settings screens for the "Call recording setup" screen. Every attempt may fail. */
object DeviceSetupHelper {

    private fun tryStart(activity: Activity, intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun component(pkg: String, cls: String) = Intent().setComponent(ComponentName(pkg, cls))

    fun isIgnoringBatteryOptimizations(ctx: Context): Boolean {
        return try {
            val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(ctx.packageName)
        } catch (_: Exception) {
            false
        }
    }

    @SuppressLint("BatteryLife") // a call-tracking app must survive Doze to follow calls all day
    fun requestIgnoreBatteryOptimizations(activity: Activity): Boolean {
        if (isIgnoringBatteryOptimizations(activity)) return true
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${activity.packageName}"))
        return tryStart(activity, direct) || tryStart(activity, Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }

    /** The dialer's call-recording (or call) settings. Falls back to the dialer app, then its app-info page. */
    fun openDialerRecordingSettings(activity: Activity): Boolean {
        val candidates = listOf(
            // Xiaomi / Redmi / Poco (MIUI dialer)
            component("com.android.incallui", "com.android.incallui.settings.CallRecordSetting"),
            component("com.android.phone", "com.android.phone.settings.CallRecordSetting"),
            // Samsung
            component("com.samsung.android.dialer", "com.samsung.android.dialer.callrecording.CallRecordingSettingsActivity"),
            component("com.samsung.android.app.telephonyui", "com.samsung.android.app.telephonyui.callsettings.ui.preference.CallSettingsActivity"),
            // Oppo / Realme / OnePlus (ColorOS)
            component("com.android.contacts", "com.oplus.dialer.setting.CallRecordSettingActivity"),
            component("com.android.contacts", "com.coloros.dialer.setting.CallRecordSettingActivity"),
            // Vivo / iQOO
            component("com.android.dialer", "com.android.dialer.app.settings.CallRecordingSettingsActivity"),
            // Huawei / Honor
            component("com.android.phone", "com.android.phone.MSimCallFeaturesSetting"),
        )
        for (i in candidates) if (tryStart(activity, i)) return true

        // Generic: the default dialer's call settings (handled by most OEM dialers)
        if (tryStart(activity, Intent(TelecomManager.ACTION_SHOW_CALL_SETTINGS))) return true
        if (tryStart(activity, Intent(Intent.ACTION_DIAL))) return true

        val dialerPkg = try {
            (activity.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).defaultDialerPackage
        } catch (_: Exception) { null }
        if (!dialerPkg.isNullOrEmpty()) {
            return tryStart(activity, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$dialerPkg")))
        }
        return false
    }

    /** OEM "autostart" / background-launch managers; falls back to this app's info page. */
    /** Settings > Accessibility, where the user switches on "AskEVA Call Recording". */
    fun openAccessibilitySettings(activity: Activity): Boolean {
        // Android 11+ can deep-link to our own service's page on many builds
        val details = Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS")
            .putExtra(Intent.EXTRA_COMPONENT_NAME, ComponentName(activity, CallAccessibilityService::class.java).flattenToString())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && tryStart(activity, details)) return true
        return tryStart(activity, Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }

    /** App info page (for Android 13+ "Allow restricted settings" when the APK was sideloaded). */
    /** Settings > Apps > Default apps, where the user picks the phone's own dialer as the Phone app. */
    fun openDefaultAppsSettings(activity: Activity): Boolean =
        tryStart(activity, Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)) ||
            tryStart(activity, Intent(Settings.ACTION_SETTINGS))

    fun openAppInfo(activity: Activity): Boolean =
        tryStart(activity, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))

    fun openAutostartSettings(activity: Activity): Boolean {
        val candidates = listOf(
            component("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            component("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            component("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
            component("com.oplus.safecenter", "com.oplus.safecenter.permission.startup.StartupAppListActivity"),
            component("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
            component("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            component("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"),
            component("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),
            component("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
            component("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            component("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
            component("com.hihonor.systemmanager", "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            component("com.transsion.phonemaster", "com.cyin.himgr.autostart.AutoStartActivity"),
        )
        for (i in candidates) if (tryStart(activity, i)) return true
        return tryStart(activity, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
    }

    /** Package of the phone app that handles calls (its recorder decides where recordings are saved). */
    fun defaultDialerPackage(ctx: Context): String = try {
        (ctx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).defaultDialerPackage ?: ""
    } catch (_: Exception) {
        ""
    }

    fun deviceInfo(): Map<String, Any?> = mapOf(
        "manufacturer" to (Build.MANUFACTURER ?: ""),
        "brand" to (Build.BRAND ?: ""),
        "model" to (Build.MODEL ?: ""),
        "sdkInt" to Build.VERSION.SDK_INT,
    )
}
