package com.pianoforparkinson.piano_practice

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class MusicImportBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "piano_training/music_import/v1")
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val epoch = AtomicInteger()
    private var pending: MethodChannel.Result? = null
    private var draft: File? = null
    private var draftCreated = false
    private var draftProtected = false
    private val requestCode = 4281

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickMp3" -> {
                    if (pending != null || draft != null) result.error("E_IMPORT_BUSY", "Finish the current import", null)
                    else {
                        pending = result
                        epoch.incrementAndGet()
                        try {
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "audio/mpeg"
                                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                            }, requestCode)
                        } catch (error: Exception) {
                            pending = null
                            result.error("E_IMPORT_PICKER", error.message, null)
                        }
                    }
                }
                "commitImport" -> { draftProtected = true; result.success(null) }
                "uncommitImport" -> { draftProtected = false; result.success(null) }
                "cancelImport" -> {
                    epoch.incrementAndGet()
                    pending?.success(null); pending = null
                    discardDraft()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(code: Int, status: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val result = pending ?: return true
        val uri = data?.data
        if (status != Activity.RESULT_OK || uri == null) {
            pending = null; result.success(null); return true
        }
        val token = epoch.get()
        var title = "Imported song.mp3"
        runCatching {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) title = it.getString(0) ?: title
            }
        }
        val name = title
        worker.execute {
            val directory = File(activity.noBackupFilesDir, "imports").apply { mkdirs() }
            val temporary = File(directory, ".pending-${UUID.randomUUID()}")
            var destination: File? = null
            var created = false
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                activity.contentResolver.openInputStream(uri)!!.use { input ->
                    temporary.outputStream().use { output ->
                        val buffer = ByteArray(32768)
                        var total = 0L
                        var count = input.read(buffer)
                        while (count >= 0) {
                            check(epoch.get() == token) { "E_IMPORT_CANCELLED" }
                            total += count
                            require(total <= 100L * 1024 * 1024) { "E_IMPORT_TOO_LARGE" }
                            if (count > 0) { digest.update(buffer, 0, count); output.write(buffer, 0, count) }
                            count = input.read(buffer)
                        }
                    }
                }
                val analysis = Mp3Melody.extract(temporary) { epoch.get() != token }
                val hash = digest.digest().joinToString("") { "%02x".format(it) }
                val file = File(directory, "$hash.mp3")
                destination = file
                created = !file.exists()
                if (created || !matchesHash(file, hash)) check(temporary.renameTo(file)) else temporary.delete()
                handler.post {
                    if (epoch.get() != token) {
                        if (created) file.delete()
                    } else {
                        draft = file; draftCreated = created; draftProtected = false; pending = null
                        result.success(analysis + mapOf("title" to name.removeSuffix(".mp3"),
                            "path" to "imports/$hash.mp3", "sha256" to hash))
                    }
                }
            } catch (error: Exception) {
                temporary.delete()
                if (created) destination?.delete()
                handler.post {
                    if (epoch.get() == token) {
                        pending = null
                        result.error(error.message?.takeIf { it.startsWith("E_IMPORT_") } ?: "E_IMPORT_FAILED", error.message, null)
                    }
                }
            }
        }
        return true
    }

    private fun matchesHash(file: File, expected: String): Boolean {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(32768)
            var count = stream.read(buffer)
            while (count >= 0) {
                if (count > 0) digest.update(buffer, 0, count)
                count = stream.read(buffer)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) } == expected
    }

    private fun discardDraft() {
        if (draftCreated && !draftProtected) draft?.delete()
        draft = null; draftCreated = false; draftProtected = false
    }

    fun close() {
        epoch.incrementAndGet()
        pending?.success(null); pending = null
        discardDraft()
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }
}
