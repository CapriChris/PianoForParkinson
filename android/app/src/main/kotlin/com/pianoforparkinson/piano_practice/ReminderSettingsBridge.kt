package com.pianoforparkinson.piano_practice

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Opens user-controlled settings; never writes grants or claims to read OEM auto-start grants. */
class ReminderSettingsBridge(private val activity: Activity) {
    private val family: String
        get() {
            val names = "${Build.MANUFACTURER} ${Build.BRAND}".lowercase(Locale.ROOT)
            return when {
                "vivo" in names || "iqoo" in names -> "vivo"
                "xiaomi" in names || "redmi" in names || "poco" in names -> "xiaomi"
                "honor" in names -> "honor"
                "huawei" in names -> "huawei"
                "oppo" in names || "realme" in names || "oneplus" in names -> "oppo"
                "meizu" in names -> "meizu"
                "samsung" in names -> "samsung"
                listOf("google", "aosp", "motorola", "sony", "nokia", "hmd").any { it in names } -> "standard"
                else -> "other"
            }
        }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "piano_training/reminder_settings/v1")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> {
                        val power = activity.getSystemService(PowerManager::class.java)
                        result.success(mapOf(
                            "family" to family,
                            "manufacturer" to Build.MANUFACTURER,
                            "batteryUnrestricted" to power.isIgnoringBatteryOptimizations(activity.packageName),
                            "startupReviewRecommended" to (family !in setOf("standard", "samsung")),
                            "backgroundReviewRecommended" to (family != "standard"),
                            "autoStartGranted" to null,
                        ))
                    }
                    "openAutoStartSettings" -> result.success(openAutoStart())
                    "openNotificationDisplaySettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                            .putExtra(Settings.EXTRA_CHANNEL_ID, "training_plans_v2")
                        else appDetails()
                        result.success(openFirst(listOf(intent, appDetails()), "training_plans_v2"))
                    }
                    "openBackgroundSettings" -> result.success(openFirst(listOf(appDetails(),
                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))))
                    else -> result.notImplemented()
                }
            }
    }

    private fun appDetails() = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", activity.packageName, null))

    private fun component(pkg: String, name: String) = Intent().setComponent(ComponentName(pkg, name))

    private fun openAutoStart(): Map<String, Any> {
        // OEM destinations are best-effort: system updates can rename or protect them.
        // startActivity is guarded rather than treating package visibility as proof of availability.
        val targets = when (family) {
            "vivo" -> listOf(
                Intent("com.iqoo.secure.BGSTARTUPMANAGER").setPackage("com.vivo.permissionmanager"),
                component("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
                component("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"))
            "xiaomi" -> listOf(component("com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"))
            "huawei" -> listOf(
                component("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                component("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity"))
            "honor" -> listOf(
                component("com.hihonor.systemmanager", "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                component("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"))
            "oppo" -> listOf(
                component("com.oplus.safecenter", "com.oplus.safecenter.startupapp.StartupAppListActivity"),
                component("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
                component("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"))
            "meizu" -> listOf(Intent("com.meizu.safe.security.SHOW_APPSEC").setPackage("com.meizu.safe"))
            else -> emptyList()
        }
        val vendorResult = openFirst(targets)
        if (vendorResult["opened"] == true) return vendorResult + ("destination" to "autoStart")
        return openFirst(listOf(appDetails(), Intent(Settings.ACTION_SETTINGS))) + ("destination" to "appDetails")
    }

    private fun openFirst(targets: List<Intent>, highlightKey: String = activity.packageName): Map<String, Any> {
        for (target in targets) {
            target.putExtra("package_name", activity.packageName)
            target.putExtra("packageName", activity.packageName)
            target.putExtra(Intent.EXTRA_PACKAGE_NAME, activity.packageName)
            target.putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            // Supported Settings fragments can locate/highlight their own row.
            // OEM lists may ignore these hints; never report a verified effect
            // or attempt to manipulate another app's views or toggle its grants.
            target.putExtra(":settings:fragment_args_key", highlightKey)
            target.putExtra(":settings:show_fragment_args", android.os.Bundle().apply {
                putString(":settings:fragment_args_key", highlightKey)
            })
            try {
                activity.startActivity(target)
                return mapOf("opened" to true, "highlightRequested" to true, "highlightVerified" to false)
            } catch (_: android.content.ActivityNotFoundException) {
                // Try the next known destination, then a standard Android settings page.
            } catch (_: SecurityException) {
                // Private OEM activities must not be bypassed.
            }
        }
        return mapOf("opened" to false)
    }
}
