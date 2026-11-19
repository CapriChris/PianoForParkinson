package com.pianoforparkinson.piano_practice.updates

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class ApkUpdateFileProvider : FileProvider()

class ApkUpdateBridge(private val activity: Activity) {
    private val directory get() = File(activity.cacheDir, "apk_updates")
    private val packageManager get() = activity.packageManager
    private val packageName get() = activity.packageName

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "piano_companion/apk_updates/v1")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "installed" -> result.success(mapOf(
                            "packageName" to packageName,
                            "versionCode" to versionCode(installed()),
                        ))
                        "downloadDirectory" -> {
                            check(directory.isDirectory || directory.mkdirs())
                            result.success(directory.absolutePath)
                        }
                        "openInstallSettings" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.fromParts("package", packageName, null)))
                            }
                            result.success(null)
                        }
                        "install" -> install(call, result)
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("UPDATE_UNAVAILABLE", null, null)
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun installed(flags: Int = 0) = packageManager.getPackageInfo(packageName, flags)

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else info.signatures
        return signatures.orEmpty().map { signature ->
            hex(MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()))
        }.toSet()
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }

    private fun install(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()) {
            result.success(false)
            return
        }
        val expectedVersion = call.argument<Number>("versionCode")?.toLong()
        val expectedSize = call.argument<Number>("sizeBytes")?.toLong()
        val expectedHash = call.argument<String>("sha256")
        val apk = File(directory, "update.apk")
        Thread {
            val valid = try {
                expectedVersion != null && expectedSize != null && expectedHash != null &&
                    verify(apk, expectedVersion, expectedSize, expectedHash)
            } catch (_: Exception) {
                false
            }
            activity.runOnUiThread {
                if (!valid) {
                    result.error("INVALID_APK", null, null)
                    return@runOnUiThread
                }
                try {
                    check(!activity.isFinishing && !activity.isDestroyed)
                    val uri = FileProvider.getUriForFile(activity, "$packageName.apk_updates", apk)
                    activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    })
                    result.success(true)
                } catch (_: Exception) {
                    result.error("UPDATE_UNAVAILABLE", null, null)
                }
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun verify(apk: File, version: Long, size: Long, hash: String): Boolean {
        if (!apk.isFile || apk.length() != size || size <= 0 || size > 1024L * 1024 * 1024) {
            return false
        }
        val digest = MessageDigest.getInstance("SHA-256")
        apk.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val length = input.read(buffer)
                if (length < 0) break
                digest.update(buffer, 0, length)
            }
        }
        if (hex(digest.digest()) != hash) return false
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else PackageManager.GET_SIGNATURES
        val current = installed(flags)
        val next = packageManager.getPackageArchiveInfo(apk.absolutePath, flags) ?: return false
        val currentSigners = signers(current)
        return next.packageName == packageName &&
            versionCode(next) == version && version > versionCode(current) &&
            currentSigners.isNotEmpty() && currentSigners == signers(next)
    }
}
