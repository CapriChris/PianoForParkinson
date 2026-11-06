package com.pianoforparkinson.piano_practice

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Encrypted refresh credential, excluded from Android backup. Fail closed. */
class AccountSessionVault(private val context: Context) {
    private val file get() = AtomicFile(File(context.noBackupFilesDir, "account-session-v1"))
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = "piano-companion-account-v1"
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }
    @Synchronized private fun read(): String? {
        if (!file.baseFile.exists()) return null
        val bytes = file.readFully()
        require(bytes.size in 29..65536)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        return cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8)
    }
    @Synchronized private fun write(value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        require(bytes.size <= 60000)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val stream = file.startWrite()
        try {
            stream.write(cipher.iv)
            stream.write(cipher.doFinal(bytes))
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "piano_companion/accounts/v1").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> result.success(read())
                    "write" -> { write(call.argument<String>("value")!!); result.success(null) }
                    "clear" -> { file.delete(); result.success(null) }
                    "acquire" -> result.success(AccountDataLease.acquire(context, "ui"))
                    "release" -> { AccountDataLease.release("ui"); result.success(null) }
                    "scheduleSync" -> { AccountBackgroundSync.schedule(context); result.success(null) }
                    "cancelSync" -> { AccountBackgroundSync.cancel(context); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("ACCOUNT_VAULT", "无法访问安全登录存储，请重新登录。", null) }
        }
    }
}
