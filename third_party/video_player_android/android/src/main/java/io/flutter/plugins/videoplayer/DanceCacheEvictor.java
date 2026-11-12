// Copyright 2026 Piano Training contributors. BSD-3-Clause; see LICENSE.
package io.flutter.plugins.videoplayer;

import androidx.media3.common.C;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.cache.*;
import java.io.File;
import java.util.*;
import java.util.function.LongSupplier;

/** All calls are made under SimpleCache's monitor. Open readers hold file leases. */
@UnstableApi
final class DanceCacheEvictor implements CacheEvictor {
  private final long maximum;
  private final LongSupplier usableSpace;
  private final TreeSet<CacheSpan> lru = new TreeSet<>(Comparator
      .comparingLong((CacheSpan span) -> span.lastTouchTimestamp)
      .thenComparing(span -> span.key).thenComparingLong(span -> span.position));
  private final Map<File, Integer> pins = new HashMap<>();
  private final Set<String> invalid = new HashSet<>();
  private long bytes;

  DanceCacheEvictor(long maximum, LongSupplier usableSpace) {
    this.maximum = maximum; this.usableSpace = usableSpace;
  }
  void pin(File file) { pins.put(file, pins.getOrDefault(file, 0) + 1); }
  void unpin(File file, Cache cache) {
    int count = pins.getOrDefault(file, 0);
    if (count <= 1) pins.remove(file); else pins.put(file, count - 1);
    for (String key : new HashSet<>(invalid)) invalidate(cache, key);
    trim(cache);
  }
  boolean isInvalid(String key) { return invalid.contains(key); }
  void invalidate(Cache cache, String key) {
    invalid.add(key);
    for (CacheSpan span : new TreeSet<>(cache.getCachedSpans(key))) {
      if (!pins.containsKey(span.file)) cache.removeSpan(span);
    }
    if (cache.getCachedSpans(key).isEmpty()) invalid.remove(key);
  }
  void trim(Cache cache) { evict(cache, 0); }
  private void evict(Cache cache, long incoming) {
    long budget = Math.min(maximum, Math.max(0, usableSpace.getAsLong() / 5));
    while (bytes + incoming > budget) {
      CacheSpan candidate = null;
      for (CacheSpan span : lru) { if (!pins.containsKey(span.file)) { candidate = span; break; } }
      if (candidate == null) return;
      cache.removeSpan(candidate);
    }
  }
  @Override public boolean requiresCacheSpanTouches() { return true; }
  @Override public void onCacheInitialized() {}
  @Override public void onStartFile(Cache cache, String key, long position, long length) {
    evict(cache, length == C.LENGTH_UNSET ? 0 : length);
  }
  @Override public void onSpanAdded(Cache cache, CacheSpan span) {
    lru.add(span); bytes += span.length;
    // If existing bytes are all pinned, discard the newly committed span instead of exceeding quota.
    evict(cache, 0);
  }
  @Override public void onSpanRemoved(Cache cache, CacheSpan span) { if (lru.remove(span)) bytes -= span.length; }
  @Override public void onSpanTouched(Cache cache, CacheSpan oldSpan, CacheSpan newSpan) {
    lru.remove(oldSpan); lru.add(newSpan);
  }
}
