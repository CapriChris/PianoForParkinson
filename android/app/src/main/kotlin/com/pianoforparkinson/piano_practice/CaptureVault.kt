package com.pianoforparkinson.piano_practice

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Private, authenticated encrypted chunks. No key or plaintext survives in Dart/SQLite. */
class CaptureVault(private val context: Context) {
    companion object {
        private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "CaptureVault").apply { isDaemon = true } }
    }
    private val main = Handler(Looper.getMainLooper())
    private fun root(scope: Any?): File {
        val base = File(context.filesDir, "capture_vault").apply { mkdirs() }
        if (scope == null) return base
        require(scope is String && Regex("account-[a-f0-9]{64}").matches(scope))
        return File(base, scope).apply { mkdirs() }
    }
    private val blockSize = 4 * 1024 * 1024
    private fun id(raw: Any?): String = UUID.fromString(raw as String).toString()
    private fun folder(root: File, capture: Any?, file: Any?) = File(File(root, id(capture)), id(file))
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("qin-training-video-v1", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder("qin-training-video-v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
            generateKey()
        }
    }
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "qin/capture-vault/v1").setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val root = root(args["owner_scope"])
                    val value: Any? = when (call.method) {
                        "claimLegacy" -> CaptureNamespaceMigration.claim(
                            File(context.filesDir, "capture_vault"),
                            args["owner_scope"] as? String,
                            args["capture_id"] as? String)
                        "cleanup" -> {
                            val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
                            context.cacheDir.listFiles()?.filter { it.name.startsWith("REC") && it.extension == "mp4" && it.lastModified() < cutoff }?.forEach { it.delete() }
                            val known = (args["known_ids"] as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet()
                            // Another signed-in account has a separate metadata DB.
                            // Preserve its recordings for the full retention period.
                            val retentionCutoff = System.currentTimeMillis() - 7 * 24 * 60 * 60 * 1000L
                            root.listFiles()?.filter { it.isDirectory && it.name !in known && it.lastModified() < retentionCutoff }?.forEach {
                                if (runCatching { id(it.name) }.isSuccess) it.deleteRecursively()
                            }
                            null
                        }
                        "budget" -> mapOf("free_bytes" to StatFs(context.filesDir.path).availableBytes,
                            "recording_bytes" to (context.cacheDir.listFiles()?.filter { it.name.startsWith("REC") && it.extension == "mp4" }?.sumOf { it.length() } ?: 0L))
                        "metered" -> (context.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager).isActiveNetworkMetered
                        "space" -> mapOf("free_bytes" to StatFs(context.filesDir.path).availableBytes,
                            "used_bytes" to root.walkTopDown().filter { it.isFile }.sumOf { it.length() })
                        "seal" -> {
                            val source = File(args["path"] as String).canonicalFile
                            require(source.toPath().startsWith(context.cacheDir.canonicalFile.toPath()))
                            require(source.length() in 1..(400L * 1024 * 1024))
                            val destination = folder(root, args["capture_id"], args["file_id"])
                            require(!destination.exists())
                            destination.mkdirs()
                            try {
                                val metadata = MediaMetadataRetriever()
                                val duration = try {
                                    metadata.setDataSource(source.path)
                                    metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L
                                } finally { metadata.release() }
                                require(duration > 0)
                                val digest = MessageDigest.getInstance("SHA-256")
                                val secret = key()
                                var index = 0
                                var size = 0L
                                source.inputStream().use { input ->
                                    val buffer = ByteArray(blockSize)
                                    while (true) {
                                        var count = 0
                                        while (count < buffer.size) {
                                            val n = input.read(buffer, count, buffer.size - count)
                                            if (n < 0) break
                                            count += n
                                        }
                                        if (count == 0) break
                                        digest.update(buffer, 0, count)
                                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                        cipher.init(Cipher.ENCRYPT_MODE, secret)
                                        cipher.updateAAD("${args["capture_id"]}/${args["file_id"]}/$index".toByteArray())
                                        File(destination, "$index.bin").outputStream().use {
                                            it.write(cipher.iv); it.write(cipher.doFinal(buffer, 0, count))
                                        }
                                        size += count; index++
                                    }
                                }
                                source.delete()
                                mapOf("file_id" to args["file_id"], "size_bytes" to size,
                                    "sha256" to digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) },
                                    "duration_ms" to duration, "chunk_count" to index, "mime_type" to "video/mp4")
                            } catch (e: Exception) { destination.deleteRecursively(); throw e }
                        }
                        "readChunk" -> {
                            val index = (args["index"] as Number).toInt()
                            require(index in 0..100)
                            val bytes = File(folder(root, args["capture_id"], args["file_id"]), "$index.bin").readBytes()
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                            cipher.updateAAD("${args["capture_id"]}/${args["file_id"]}/$index".toByteArray())
                            cipher.doFinal(bytes, 12, bytes.size - 12)
                        }
                        "delete" -> { File(root, id(args["capture_id"])).deleteRecursively(); null }
                        else -> throw IllegalArgumentException("Unsupported vault operation")
                    }
                    main.post { result.success(value) }
                } catch (_: Exception) {
                    main.post { result.error("CAPTURE_STORAGE", "视频存储暂不可用，请检查剩余空间后重试。", null) }
                }
            }
        }
    }
}
