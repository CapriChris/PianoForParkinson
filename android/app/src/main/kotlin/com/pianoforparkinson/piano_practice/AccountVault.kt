package com.pianoforparkinson.piano_practice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Separate key from capture encryption; no credentials enter backup or SQLite. */
class AccountVault(private val context: Context) {
    companion object {
        private const val alias = "qin-account-session-v1"
        private val executor = Executors.newSingleThreadExecutor { r ->
            Thread(r, "AccountVault").apply { isDaemon = true }
        }
    }
    private val main = Handler(Looper.getMainLooper())
    private val root get() = File(context.noBackupFilesDir, "account-vault-v1").apply { mkdirs() }
    private fun file(raw: Any?): AtomicFile {
        val name = raw as? String ?: error("Missing slot")
        require(name == "session" || name == "pending-revocations")
        return AtomicFile(File(root, "$name.aesgcm"))
    }
    private fun secret(): SecretKey {
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keys.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
            generateKey()
        }
    }
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "qin/account-vault/v1").setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    val args = call.arguments as? Map<*, *> ?: error("Missing arguments")
                    val slot = args["key"] as? String ?: error("Missing slot")
                    val target = file(slot)
                    val value: Any? = when (call.method) {
                        "read" -> {
                            if (!target.baseFile.exists() && !File(target.baseFile.path + ".bak").exists()) null
                            else {
                                val bytes = target.openRead().use { it.readBytes() }
                                require(bytes.size in 29..(1024 * 1024))
                                val buffer = ByteBuffer.wrap(bytes)
                                require(buffer.get().toInt() == 1)
                                val iv = ByteArray(12).also { buffer.get(it) }
                                val payload = ByteArray(buffer.remaining()).also { buffer.get(it) }
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.DECRYPT_MODE, secret(), GCMParameterSpec(128, iv))
                                cipher.updateAAD(slot.toByteArray(Charsets.UTF_8))
                                cipher.doFinal(payload).toString(Charsets.UTF_8)
                            }
                        }
                        "write" -> {
                            val raw = (args["value"] as? String ?: error("Missing value")).toByteArray(Charsets.UTF_8)
                            require(raw.size <= 512 * 1024)
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, secret())
                            cipher.updateAAD(slot.toByteArray(Charsets.UTF_8))
                            require(cipher.iv.size == 12)
                            val encrypted = byteArrayOf(1) + cipher.iv + cipher.doFinal(raw)
                            val stream = target.startWrite()
                            try {
                                stream.write(encrypted)
                                target.finishWrite(stream)
                            } catch (failure: Throwable) {
                                target.failWrite(stream)
                                throw failure
                            }
                            null
                        }
                        "delete" -> { target.delete(); null }
                        else -> error("Unsupported account vault method")
                    }
                    main.post { result.success(value) }
                } catch (_: Throwable) {
                    // Never include plaintext, provider exception detail or token in errors.
                    main.post { result.error("ACCOUNT_VAULT_ERROR", "安全登录存储不可用，请重新登录。", null) }
                }
            }
        }
    }
}
