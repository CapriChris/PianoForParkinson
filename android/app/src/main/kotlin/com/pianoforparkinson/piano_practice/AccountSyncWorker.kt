package com.pianoforparkinson.piano_practice

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.*
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileLock
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** One DB/credential owner across a headless worker and the interactive app. */
object AccountDataLease {
    private var file: RandomAccessFile? = null
    private var lock: FileLock? = null
    private var owner: String? = null
    @Synchronized fun acquire(context: Context, who: String): Boolean {
        if (owner == who) return true
        if (owner != null) return false
        val opened = RandomAccessFile(File(context.noBackupFilesDir, "account-data.lock"), "rw")
        val held = runCatching { opened.channel.tryLock() }.getOrNull()
        if (held == null) { opened.close(); return false }
        file = opened; lock = held; owner = who
        return true
    }
    @Synchronized fun release(who: String) {
        if (owner != who) return
        lock?.release(); file?.close(); lock = null; file = null; owner = null
    }
}

object AccountBackgroundSync {
    @Volatile var uiEngine: FlutterEngine? = null
    fun schedule(context: Context) {
        val network = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        val manager = WorkManager.getInstance(context)
        manager.enqueueUniqueWork("account-sync-now", ExistingWorkPolicy.KEEP,
            OneTimeWorkRequest.Builder(AccountSyncWorker::class.java).setConstraints(network)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build())
        manager.enqueueUniquePeriodicWork("account-sync-periodic", ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequest.Builder(AccountSyncWorker::class.java, 15, TimeUnit.MINUTES)
                .setConstraints(network).build())
    }
    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork("account-sync-now")
        WorkManager.getInstance(context).cancelUniqueWork("account-sync-periodic")
    }
}

class AccountSyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val main = Handler(Looper.getMainLooper())
        val done = CountDownLatch(1)
        var retry = true
        var headless: FlutterEngine? = null
        var ownsLease = false
        main.post {
            val existing = AccountBackgroundSync.uiEngine
            if (existing != null) {
                MethodChannel(existing.dartExecutor.binaryMessenger, "piano_companion/background-sync/v1")
                    .invokeMethod("sync", null, object : MethodChannel.Result {
                        override fun success(result: Any?) { retry = result != true; done.countDown() }
                        override fun error(code: String, message: String?, details: Any?) { done.countDown() }
                        override fun notImplemented() { done.countDown() }
                    })
            } else {
                ownsLease = AccountDataLease.acquire(applicationContext, "worker")
                if (!ownsLease) { done.countDown(); return@post }
                try {
                    val loader = FlutterInjector.instance().flutterLoader()
                    loader.startInitialization(applicationContext)
                    loader.ensureInitializationComplete(applicationContext, null)
                    val engine = FlutterEngine(applicationContext)
                    headless = engine
                    AccountSessionVault(applicationContext).register(engine.dartExecutor.binaryMessenger)
                    MethodChannel(engine.dartExecutor.binaryMessenger, "piano_companion/background-sync/v1")
                        .setMethodCallHandler { call, result ->
                            when (call.method) {
                                "storage" -> result.success(applicationContext.noBackupFilesDir.absolutePath)
                                "finish" -> { retry = call.argument<Boolean>("retry") == true; result.success(null); done.countDown() }
                                else -> result.notImplemented()
                            }
                        }
                    engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "accountBackgroundMain"))
                } catch (_: Exception) { done.countDown() }
            }
        }
        try { done.await(150, TimeUnit.SECONDS) } catch (_: InterruptedException) { retry = true }
        // Destroy on the main thread and release only after the isolate stops.
        val destroyed = CountDownLatch(1)
        main.post {
            headless?.destroy()
            if (ownsLease) AccountDataLease.release("worker")
            destroyed.countDown()
        }
        try { destroyed.await(10, TimeUnit.SECONDS) } catch (_: InterruptedException) { }
        return if (retry) Result.retry() else Result.success()
    }
}
