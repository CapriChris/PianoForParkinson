// Copyright 2026 Piano Training contributors. BSD-3-Clause; see LICENSE.
package io.flutter.plugins.videoplayer;

import android.content.Context;
import android.net.Uri;
import androidx.media3.common.C;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.database.StandaloneDatabaseProvider;
import androidx.media3.datasource.*;
import androidx.media3.datasource.cache.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.json.*;

/** Read-through only: no downloader, CacheWriter, prefetch, or persistent completeness flag. */
@UnstableApi
final class DanceMediaCache {
  static final String HEADER = "X-PQ-Dance-Part";
  private static final long MAX_BYTES = 1024L * 1024 * 1024;
  private static DanceMediaCache shared;
  private static Map<String, Resource> packagedCatalogue;
  private final SimpleCache cache;
  private final DanceCacheEvictor evictor;
  final Map<String, Resource> catalogue = new HashMap<>();

  static final class Resource {
    final String course, part, version, url, sha256;
    final long bytes;
    Resource(String course, String part, String version, String url, long bytes, String sha256) {
      this.course = course; this.part = part; this.version = version; this.url = url;
      this.bytes = bytes; this.sha256 = sha256;
    }
    String key() { return course + "/" + part + "/" + version + "/" + sha256; }
  }

  DanceMediaCache(SimpleCache cache, DanceCacheEvictor evictor) { this.cache = cache; this.evictor = evictor; }

  static synchronized DanceMediaCache get(Context context) throws IOException {
    if (shared != null) return shared;
    Context app = context.getApplicationContext();
    Map<String, Resource> entries = loadCatalogue(app);
    File directory = new File(app.getNoBackupFilesDir(), "dance-stream-cache-v1");
    DanceCacheEvictor evictor = new DanceCacheEvictor(MAX_BYTES, app.getNoBackupFilesDir()::getUsableSpace);
    DanceMediaCache result = new DanceMediaCache(new SimpleCache(directory,
        evictor, new StandaloneDatabaseProvider(app)), evictor);
    result.catalogue.putAll(entries);
    shared = result;
    return result;
  }

  private static synchronized Map<String, Resource> loadCatalogue(Context app) throws IOException {
    if (packagedCatalogue != null) return packagedCatalogue;
    Map<String, Resource> entries;
    try (InputStream stream = app.getAssets().open("flutter_assets/assets/video/remote_manifest.json")) {
      ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] buffer = new byte[4096]; int read;
      while ((read = stream.read(buffer)) != -1) {
        if (out.size() + read > 64 * 1024) throw new IOException("Oversized teaching catalogue");
        out.write(buffer, 0, read);
      }
      entries = parseCatalogue(out.toString(StandardCharsets.UTF_8.name()));
    }
    packagedCatalogue = Collections.unmodifiableMap(entries);
    return packagedCatalogue;
  }

  static Map<String, Resource> parseCatalogue(String json) throws IOException {
    try {
      JSONObject root = new JSONObject(json);
      if (root.getInt("schemaVersion") != 1) throw new IOException("Unknown catalogue schema");
      JSONArray items = root.getJSONArray("items");
      Map<String, Resource> entries = new HashMap<>();
      for (int i = 0; i < items.length(); i++) {
        JSONObject item = items.getJSONObject(i);
        Resource r = new Resource(item.getString("courseId"), item.getString("partId"),
            item.getString("resourceVersion"), item.getString("url"), item.getLong("bytes"), item.getString("sha256"));
        Uri uri = Uri.parse(r.url);
        boolean chinese = r.course.equals("hkpdf-balance-six") && r.part.matches("balance-six-[123]");
        boolean english = (r.course.equals("brain-and-body") && r.part.matches("brain-and-body-[1234]"))
            || (r.course.equals("move-and-shout") && r.part.matches("move-and-shout-[123]"));
        if (!chinese && !english) throw new IOException("Unknown teaching resource");
        String version = chinese ? "v1" : "v2";
        String file = r.part.substring(0, r.part.lastIndexOf('-')) + "-part-" + r.part.substring(r.part.lastIndexOf('-') + 1) + ".mp4";
        if ((!chinese && !english) || !r.version.equals(version)
            || !r.url.equals("https://ccqspace.site/pd-rehab/assets/dance/" + version + "/" + file) || r.bytes <= 0 || r.bytes > MAX_BYTES
            || !r.sha256.matches("[0-9a-f]{64}") || !"https".equals(uri.getScheme())
            || uri.getHost() == null || uri.getQuery() != null || uri.getFragment() != null
            || !"video/mp4".equals(item.getString("mimeType")) || entries.put(r.part, r) != null) {
          throw new IOException("Invalid teaching resource identity");
        }
      }
      return entries;
    } catch (JSONException e) { throw new IOException("Invalid teaching catalogue", e); }
  }

  static Map<String, String> stripHeader(Map<String, String> headers) {
    Map<String, String> clean = new HashMap<>();
    for (Map.Entry<String, String> item : headers.entrySet()) {
      if (!HEADER.equalsIgnoreCase(item.getKey())) clean.put(item.getKey(), item.getValue());
    }
    return clean;
  }

  static boolean isKnown(Context context, String url, Map<String, String> headers) {
    String part = null;
    for (Map.Entry<String, String> item : headers.entrySet()) {
      if (HEADER.equalsIgnoreCase(item.getKey())) part = item.getValue();
    }
    if (part == null) return false;
    try {
      Resource resource = loadCatalogue(context).get(part);
      return resource != null && resource.url.equals(url);
    } catch (IOException | RuntimeException e) { return false; }
  }

  static DataSource.Factory maybeFactory(Context context, String url, Map<String, String> headers,
      DataSource.Factory upstream) {
    String part = null;
    for (Map.Entry<String, String> item : headers.entrySet()) {
      if (HEADER.equalsIgnoreCase(item.getKey())) part = item.getValue();
    }
    if (part == null) return upstream;
    try {
      DanceMediaCache manager = get(context);
      Resource r = manager.catalogue.get(part);
      return r != null && r.url.equals(url) ? manager.factory(r, upstream) : upstream;
    } catch (IOException | RuntimeException e) { return upstream; } // Fail closed to uncached playback.
  }

  DataSource.Factory factory(Resource resource, DataSource.Factory upstream) {
    DataSource.Factory checked = () -> new CheckedSource(resource, upstream.createDataSource());
    CacheDataSource.Factory cached = new CacheDataSource.Factory().setCache(cache)
        .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
        .setCacheKeyFactory(spec -> resource.key())
        .setCacheReadDataSourceFactory(() -> new PinnedFileSource())
        .setUpstreamDataSourceFactory(checked);
    return () -> {
      synchronized (cache) {
        evictor.trim(cache);
        return evictor.isInvalid(resource.key()) ? checked.createDataSource()
            : new FallbackSource(cached.createDataSource(), checked);
      }
    };
  }

  /** Synchronized on SimpleCache to prevent concurrent LRU eviction/commit while hashing files. */
  Map<String, Object> status(Resource r) {
    synchronized (cache) {
      long bytes = 0; long position = 0; boolean contiguous = true;
      TreeSet<CacheSpan> spans = new TreeSet<>(cache.getCachedSpans(r.key()));
      for (CacheSpan span : spans) {
        if (span.file == null || !span.file.isFile() || span.file.length() != span.length) {
          evictor.invalidate(cache, r.key()); spans.clear(); bytes = 0; contiguous = false; break;
        }
        bytes += Math.max(0, Math.min(span.length, r.bytes - span.position));
        if (span.position != position) contiguous = false;
        position = span.position + span.length;
      }
      boolean complete = !evictor.isInvalid(r.key()) && contiguous && position == r.bytes && bytes == r.bytes;
      if (complete) {
        try {
          MessageDigest digest = MessageDigest.getInstance("SHA-256"); byte[] buffer = new byte[64 * 1024];
          for (CacheSpan span : spans) {
            try (InputStream file = new FileInputStream(span.file)) {
              int read; while ((read = file.read(buffer)) != -1) digest.update(buffer, 0, read);
            }
          }
          StringBuilder hash = new StringBuilder();
          for (byte value : digest.digest()) hash.append(String.format(Locale.ROOT, "%02x", value & 255));
          complete = r.sha256.equals(hash.toString());
        } catch (Exception e) { complete = false; }
        if (!complete) { evictor.invalidate(cache, r.key()); bytes = 0; }
      }
      Map<String, Object> result = new HashMap<>();
      result.put("cachedBytes", bytes); result.put("totalBytes", r.bytes);
      result.put("complete", complete); return result;
    }
  }

  /** Continue at the first undelivered byte if private cache IO fails; HTTP errors retain normal handling. */
  static final class FallbackSource implements DataSource {
    private DataSource source;
    private final DataSource.Factory direct;
    private final List<TransferListener> listeners = new ArrayList<>();
    private DataSpec spec;
    private long delivered;
    private boolean bypassed;
    FallbackSource(DataSource primary, DataSource.Factory direct) { source = primary; this.direct = direct; }
    @Override public void addTransferListener(TransferListener listener) { listeners.add(listener); source.addTransferListener(listener); }
    @Override public long open(DataSpec spec) throws IOException {
      this.spec = spec; delivered = 0;
      try { return source.open(spec); }
      catch (IOException error) { return bypass(error); }
    }
    private long bypass(IOException error) throws IOException {
      boolean cacheError = false;
      for (Throwable cause = error; cause != null; cause = cause.getCause()) {
        if (cause instanceof Cache.CacheException || cause instanceof FileDataSource.FileDataSourceException) { cacheError = true; break; }
      }
      if (bypassed || !cacheError) throw error;
      bypassed = true;
      try { source.close(); } catch (IOException ignored) {}
      source = direct.createDataSource();
      for (TransferListener listener : listeners) source.addTransferListener(listener);
      return source.open(spec.subrange(delivered));
    }
    @Override public int read(byte[] buffer, int offset, int length) throws IOException {
      int read;
      try { read = source.read(buffer, offset, length); }
      catch (IOException error) { bypass(error); read = source.read(buffer, offset, length); }
      if (read > 0) delivered += read;
      return read;
    }
    @Override public Uri getUri() { return source.getUri(); }
    @Override public Map<String, List<String>> getResponseHeaders() { return source.getResponseHeaders(); }
    @Override public void close() throws IOException { source.close(); }
  }

  private final class PinnedFileSource implements DataSource {
    private final FileDataSource source = new FileDataSource();
    private File file;
    @Override public void addTransferListener(TransferListener listener) { source.addTransferListener(listener); }
    @Override public long open(DataSpec spec) throws IOException {
      synchronized (cache) {
        file = new File(Objects.requireNonNull(spec.uri.getPath()));
        evictor.pin(file);
        try { return source.open(spec); }
        catch (IOException e) { evictor.unpin(file, cache); file = null; throw e; }
      }
    }
    @Override public int read(byte[] buffer, int offset, int length) throws IOException { return source.read(buffer, offset, length); }
    @Override public Uri getUri() { return source.getUri(); }
    @Override public void close() throws IOException {
      try { source.close(); }
      finally { synchronized (cache) { if (file != null) { evictor.unpin(file, cache); file = null; } } }
    }
  }

  /** Reject ignored Range, changed object size and malformed range headers before any cache write. */
  private static final class CheckedSource implements DataSource {
    private static final Pattern RANGE = Pattern.compile("bytes ([0-9]+)-([0-9]+)/([0-9]+)");
    private final Resource resource;
    private final DataSource upstream;
    private long remaining;
    CheckedSource(Resource resource, DataSource upstream) { this.resource = resource; this.upstream = upstream; }
    @Override public void addTransferListener(TransferListener listener) { upstream.addTransferListener(listener); }
    @Override public long open(DataSpec spec) throws IOException {
      if (!resource.url.equals(spec.uri.toString()) || spec.position < 0 || spec.position >= resource.bytes)
        throw new IOException("Teaching resource range outside identity");
      remaining = Math.min(resource.bytes - spec.position, spec.length == C.LENGTH_UNSET ? Long.MAX_VALUE : spec.length);
      DataSpec bounded = spec.buildUpon().setLength(remaining).setHttpRequestHeaders(stripHeader(spec.httpRequestHeaders)).build();
      try {
        long actual = upstream.open(bounded);
        Map<String, List<String>> headers = upstream.getResponseHeaders();
        String range = header(headers, "Content-Range"), length = header(headers, "Content-Length");
        if (range != null) {
          if (length != null && Long.parseLong(length) != remaining) throw new IOException("Teaching range length mismatch");
          if (upstream instanceof HttpDataSource && ((HttpDataSource) upstream).getResponseCode() != 206) throw new IOException("Teaching range response code mismatch");
          Matcher match = RANGE.matcher(range);
          if (!match.matches() || Long.parseLong(match.group(1)) != spec.position
              || Long.parseLong(match.group(3)) != resource.bytes
              || Long.parseLong(match.group(2)) != spec.position + remaining - 1)
            throw new IOException("Teaching resource Range/identity mismatch");
        } else if (spec.position != 0 || length == null || Long.parseLong(length) != resource.bytes) {
          throw new IOException("Teaching resource ignored Range or length changed");
        }
        if (actual != C.LENGTH_UNSET && actual != remaining) throw new IOException("Teaching response length mismatch");
        return remaining;
      } catch (IOException | RuntimeException e) {
        try { upstream.close(); } catch (IOException ignored) {}
        if (e instanceof IOException) throw (IOException) e;
        throw new IOException("Invalid teaching response headers", e);
      }
    }
    private static String header(Map<String, List<String>> headers, String key) {
      for (Map.Entry<String, List<String>> header : headers.entrySet()) {
        if (key.equalsIgnoreCase(header.getKey()) && !header.getValue().isEmpty()) return header.getValue().get(0);
      }
      return null;
    }
    @Override public int read(byte[] buffer, int offset, int length) throws IOException {
      if (length == 0) return 0;
      if (remaining == 0) return C.RESULT_END_OF_INPUT;
      int read = upstream.read(buffer, offset, (int)Math.min(length, remaining));
      if (read == C.RESULT_END_OF_INPUT) throw new EOFException("Truncated teaching resource");
      remaining -= read; return read;
    }
    @Override public Uri getUri() { return upstream.getUri(); }
    @Override public Map<String, List<String>> getResponseHeaders() { return upstream.getResponseHeaders(); }
    @Override public void close() throws IOException { upstream.close(); }
  }
}
