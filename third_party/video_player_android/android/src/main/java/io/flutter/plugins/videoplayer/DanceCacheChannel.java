// Copyright 2026 Piano Training contributors. BSD-3-Clause; see LICENSE.
package io.flutter.plugins.videoplayer;
import android.content.Context;
import android.net.ConnectivityManager;
import android.os.Handler;
import android.os.Looper;
import androidx.media3.common.util.UnstableApi;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@UnstableApi
final class DanceCacheChannel {
  private static final ExecutorService VERIFY = Executors.newSingleThreadExecutor(r -> {
    Thread thread = new Thread(r, "dance-cache-verification"); thread.setDaemon(true); return thread;
  });
  static MethodChannel attach(Context context, BinaryMessenger messenger) {
    MethodChannel channel = new MethodChannel(messenger, "piano_training/dance_media_cache/v1");
    Handler main = new Handler(Looper.getMainLooper());
    channel.setMethodCallHandler((call, reply) -> {
      if (!"status".equals(call.method)) { reply.notImplemented(); return; }
      String part = call.argument("partId");
      VERIFY.execute(() -> {
        try {
          DanceMediaCache manager = DanceMediaCache.get(context);
          DanceMediaCache.Resource resource = manager.catalogue.get(part);
          if (resource == null) throw new IOException("Unknown teaching part");
          Map<String, Object> result = manager.status(resource);
          ConnectivityManager connection = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
          // Without ACCESS_NETWORK_STATE, conservatively show the metered warning.
          boolean metered = true;
          try { if (connection != null) metered = connection.isActiveNetworkMetered(); } catch (SecurityException ignored) {}
          result.put("metered", metered);
          main.post(() -> reply.success(result));
        } catch (Exception e) { main.post(() -> reply.error("cache_unavailable", "Local media cache unavailable", null)); }
      });
    });
    return channel;
  }

}
