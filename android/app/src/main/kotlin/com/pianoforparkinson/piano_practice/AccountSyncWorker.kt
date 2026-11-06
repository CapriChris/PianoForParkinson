package com.pianoforparkinson.piano_practice

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileLock
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Shared OS locks cover the entire account DB lifetime, not an isolate flag. */
private class AccountLease(private val file: RandomAccessFile, private val lock: FileLock) {
    fun close() { try { lock.release() } finally { file.close() } }
    companion object {
        fun acquire(path: File): AccountLease? {
            path.parentFile?.mkdirs()
            val file = RandomAccessFile(path, "rw")
            return try {
                val lock = file.channel.tryLock()
                if (lock == null) { file.close(); null } else AccountLease(file, lock)
            } catch (_: java.nio.channels.OverlappingFileLockException) {
                file.close(); null
            } catch (error: Throwable) {
                file.close(); throw error
            }
        }
    }
}

class AccountSyncBridge(private val context: Context, private val background: Boolean = false) {
    private val main = Handler(Looper.getMainLooper())
    private var global: AccountLease? = null
    private var workspace: AccountLease? = null
    private var workspaceName: String? = null
    private var channel: MethodChannel? = null

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { transport ->
            transport.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "storageRoot" -> result.success(context.noBackupFilesDir.absolutePath)
                        "startForeground" -> {
                            if (background) { result.error("E_CONTEXT", "Background engine cannot become foreground", null); return@setMethodCallHandler }
                            if (global == null) global = AccountLease.acquire(File(context.noBackupFilesDir, ".account-session.lock"))
                            if (global != null) foregroundChannel = transport
                            result.success(global != null)
                        }
                        "acquireWorkspace" -> {
                            val account = call.argument<String>("account")
                            if (account == null || !ACCOUNT.matches(account)) throw IllegalArgumentException("Invalid account workspace")
                            if (!background && global == null) throw IllegalStateException("Foreground session lease required")
                            if (workspaceName == account && workspace != null) { result.success(true); return@setMethodCallHandler }
                            if (workspace != null) throw IllegalStateException("Close previous account database first")
                            val root = File(context.noBackupFilesDir, account)
                            root.mkdirs()
                            workspace = AccountLease.acquire(File(root, ".sync-workspace.lock"))
                            if (workspace != null) workspaceName = account
                            result.success(workspace != null)
                        }
                        "releaseWorkspace" -> {
                            workspace?.close(); workspace = null; workspaceName = null
                            result.success(null)
                        }
                        "schedule" -> {
                            schedule(context)
                            result.success(null)
                        }
                        "cancel" -> {
                            WorkManager.getInstance(context).cancelAllWorkByTag(TAG)
                            result.success(null)
                        }
                        "finished" -> {
                            backgroundCompletion?.invoke(call.argument<Boolean>("ok") == true)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("E_ACCOUNT_SYNC", "Account synchronization operation unavailable", null)
                }
            }
        }
    }

    fun close() {
        if (foregroundChannel === channel) foregroundChannel = null
        channel?.setMethodCallHandler(null); channel = null
        workspace?.close(); workspace = null; workspaceName = null
        global?.close(); global = null
    }

    companion object {
        const val CHANNEL = "piano_training/account_sync/v1"
        private const val TAG = "qin-account-structured-sync"
        private val ACCOUNT = Regex("account-[a-f0-9]{64}")
        @Volatile var foregroundChannel: MethodChannel? = null
        @Volatile var backgroundCompletion: ((Boolean) -> Unit)? = null

        private fun schedule(context: Context) {
            val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
            val manager = WorkManager.getInstance(context)
            manager.enqueueUniqueWork(TAG + "-connected", ExistingWorkPolicy.KEEP,
                OneTimeWorkRequestBuilder<AccountSyncWorker>().setConstraints(constraints).addTag(TAG).build())
            manager.enqueueUniquePeriodicWork(TAG + "-periodic", ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<AccountSyncWorker>(15, TimeUnit.MINUTES)
                    .setConstraints(constraints).addTag(TAG).build())
        }
    }
}

/** WorkManager may delay this job; it never records video or opens an audio engine. */
class AccountSyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var engine: FlutterEngine? = null
    @Volatile private var stopSignal: (() -> Unit)? = null

    override fun onStopped() {
        stopSignal?.invoke()
        super.onStopped()
    }

    override fun doWork(): Result {
        if (isStopped) return Result.retry()
        val foreground = AccountSyncBridge.foregroundChannel
        if (foreground != null) {
            val completed = CountDownLatch(1)
            var okay = false
            main.post {
                if (foreground !== AccountSyncBridge.foregroundChannel) { completed.countDown(); return@post }
                foreground.invokeMethod("runForegroundSync", null, object : MethodChannel.Result {
                    override fun success(result: Any?) { okay = result == true; completed.countDown() }
                    override fun error(code: String, message: String?, details: Any?) { completed.countDown() }
                    override fun notImplemented() { completed.countDown() }
                })
            }
            return if (completed.await(150, TimeUnit.SECONDS) && okay) Result.success() else Result.retry()
        }
        val lease = try { AccountLease.acquire(File(applicationContext.noBackupFilesDir, ".account-session.lock")) }
                    catch (_: Exception) { null } ?: return Result.retry()
        val completed = CountDownLatch(1)
        stopSignal = { completed.countDown() }
        var okay = false
        var bridge: AccountSyncBridge? = null
        AccountSyncBridge.backgroundCompletion = { result -> okay = result; completed.countDown() }
        try {
            main.post {
                try {
                    if (isStopped) { completed.countDown(); return@post }
                    val loader = FlutterInjector.instance().flutterLoader()
                    loader.startInitialization(applicationContext)
                    loader.ensureInitializationComplete(applicationContext, null)
                    val workerEngine = FlutterEngine(applicationContext)
                    engine = workerEngine
                    AccountVault(applicationContext).register(workerEngine.dartExecutor.binaryMessenger)
                    bridge = AccountSyncBridge(applicationContext, background = true).also {
                        it.register(workerEngine.dartExecutor.binaryMessenger)
                    }
                    workerEngine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "package:piano_practice/accounts/background_sync.dart",
                        "accountSyncBackgroundMain"))
                } catch (_: Throwable) { completed.countDown() }
            }
            return if (completed.await(150, TimeUnit.SECONDS) && okay) Result.success() else Result.retry()
        } finally {
            stopSignal = null
            AccountSyncBridge.backgroundCompletion = null
            val released = CountDownLatch(1)
            main.post {
                try { engine?.destroy(); engine = null; bridge?.close() }
                finally { released.countDown() }
            }
            // Do not release the global lease while a headless engine can still write.
            released.await()
            lease.close()
        }
    }
}
