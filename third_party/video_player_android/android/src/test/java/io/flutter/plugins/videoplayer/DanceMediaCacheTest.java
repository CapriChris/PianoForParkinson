package io.flutter.plugins.videoplayer;

import static org.junit.Assert.*;
import android.net.Uri;
import androidx.media3.datasource.*;
import androidx.media3.datasource.cache.*;
import androidx.media3.database.StandaloneDatabaseProvider;
import androidx.test.core.app.ApplicationProvider;
import java.net.ServerSocket;
import java.net.Socket;
import java.io.*;
import java.net.InetSocketAddress;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class DanceMediaCacheTest {
  private final byte[] media = new byte[128 * 1024];
  private final AtomicLong networkBytes = new AtomicLong();
  private LoopbackServer server;
  private File directory;
  private SimpleCache cache;
  private DanceCacheEvictor evictor;
  private final List<StandaloneDatabaseProvider> databases = new ArrayList<>();
  private StandaloneDatabaseProvider database() { StandaloneDatabaseProvider db = new StandaloneDatabaseProvider(ApplicationProvider.getApplicationContext()); databases.add(db); return db; }
  private DanceMediaCache subject;
  private DanceMediaCache.Resource resource;
  private String mode = "range";

  private interface Handler { void handle(Exchange exchange) throws IOException; }
  private static final class Headers extends TreeMap<String, String> {
    Headers() { super(String.CASE_INSENSITIVE_ORDER); }
    String getFirst(String key) { return get(key); }
    void add(String key, String value) { put(key, value); }
  }
  private static final class Exchange {
    final Socket socket; final Headers request = new Headers(), response = new Headers();
    Exchange(Socket socket) throws IOException {
      this.socket = socket;
      BufferedReader input = new BufferedReader(new InputStreamReader(socket.getInputStream(), java.nio.charset.StandardCharsets.US_ASCII));
      input.readLine(); String line;
      while ((line = input.readLine()) != null && !line.isEmpty()) { int i = line.indexOf(':'); request.put(line.substring(0, i), line.substring(i + 1).trim()); }
    }
    Headers getRequestHeaders() { return request; }
    Headers getResponseHeaders() { return response; }
    OutputStream getResponseBody() throws IOException { return socket.getOutputStream(); }
    void sendResponseHeaders(int code, long length) throws IOException {
      StringBuilder text = new StringBuilder("HTTP/1.1 " + code + " Response\r\nConnection: close\r\nContent-Length: " + Math.max(0, length) + "\r\n");
      response.forEach((k,v) -> text.append(k).append(": ").append(v).append("\r\n"));
      text.append("\r\n"); getResponseBody().write(text.toString().getBytes(java.nio.charset.StandardCharsets.US_ASCII));
    }
    void close() throws IOException { socket.close(); }
  }
  private static final class LoopbackServer {
    final ServerSocket socket = new ServerSocket(0, 16, java.net.InetAddress.getByName("127.0.0.1"));
    Handler handler;
    LoopbackServer() throws IOException {}
    void start() { Thread thread = new Thread(() -> { while (!socket.isClosed()) try { handler.handle(new Exchange(socket.accept())); } catch (IOException ignored) {} }); thread.setDaemon(true); thread.start(); }
    void stop(int ignored) { try { socket.close(); } catch (IOException e) { throw new AssertionError(e); } }
  }
  @Before public void setUp() throws Exception {
    new Random(82).nextBytes(media);
    server = new LoopbackServer();
    server.handler = exchange -> {
      String range = exchange.getRequestHeaders().getFirst("Range");
      assertNull(exchange.getRequestHeaders().getFirst("X-PQ-Dance-Part"));
      int start = 0, end = media.length - 1;
      if (range != null) {
        String[] parts = range.substring(6).split("-", -1);
        start = Integer.parseInt(parts[0]);
        if (!parts[1].isEmpty()) end = Math.min(end, Integer.parseInt(parts[1]));
      }
      if (mode.equals("416")) {
        exchange.getResponseHeaders().add("Content-Range", "bytes */" + media.length);
        exchange.sendResponseHeaders(416, -1); exchange.close(); return;
      }
      boolean partial = range != null && !mode.equals("200");
      if (!partial) { start = 0; end = media.length - 1; }
      if (partial) exchange.getResponseHeaders().add("Content-Range", "bytes " + start + "-" + end + "/" + (mode.equals("wrongLength") ? media.length + 1 : media.length));
      exchange.sendResponseHeaders(partial ? 206 : 200, end - start + 1);
      try { exchange.getResponseBody().write(media, start, end - start + 1); networkBytes.addAndGet(end - start + 1); }
      finally { exchange.close(); }
    };
    server.start();
    directory = Files.createTempDirectory("dance-cache").toFile();
    cache = new SimpleCache(directory, (evictor = new DanceCacheEvictor(1024 * 1024, () -> Long.MAX_VALUE)), database());
    resource = new DanceMediaCache.Resource("course", "part", "v1", "http://127.0.0.1:" + server.socket.getLocalPort() + "/video", media.length, hex(MessageDigest.getInstance("SHA-256").digest(media)));
    subject = new DanceMediaCache(cache, evictor);
  }
  @After public void tearDown() { if (server != null) server.stop(0); cache.release(); for (StandaloneDatabaseProvider db : databases) db.close(); }
  private static String hex(byte[] bytes) { StringBuilder s = new StringBuilder(); for (byte b : bytes) s.append(String.format("%02x", b & 255)); return s.toString(); }
  private byte[] read(long start, int count) throws Exception {
    DataSource source = subject.factory(resource, new DefaultHttpDataSource.Factory().setConnectTimeoutMs(300).setReadTimeoutMs(300)).createDataSource();
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    try {
      source.open(new DataSpec.Builder().setUri(resource.url).setPosition(start).setLength(count).build());
      byte[] buffer = new byte[4096]; int n;
      while ((n = source.read(buffer, 0, Math.min(buffer.length, count - out.size()))) > 0) { out.write(buffer, 0, n); if (out.size() == count) break; }
      return out.toByteArray();
    } finally { source.close(); }
  }
  @Test public void partialReadPersistsAndOfflineReopenUsesNoHttp() throws Exception {
    assertArrayEquals(Arrays.copyOfRange(media, 100, 8100), read(100, 8000));
    assertEquals(8000L, subject.status(resource).get("cachedBytes"));
    assertEquals(false, subject.status(resource).get("complete"));
    cache.release();
    cache = new SimpleCache(directory, (evictor = new DanceCacheEvictor(1024 * 1024, () -> Long.MAX_VALUE)), database());
    subject = new DanceMediaCache(cache, evictor);
    server.stop(0); server = null; long before = networkBytes.get();
    assertArrayEquals(Arrays.copyOfRange(media, 100, 8100), read(100, 8000));
    assertEquals(before, networkBytes.get());
    assertThrows(IOException.class, () -> read(0, 8000));
  }
  @Test public void fullVerifiedCacheReadsOfflineAndCorruptionRevokes() throws Exception {
    assertArrayEquals(media, read(0, media.length));
    assertEquals(true, subject.status(resource).get("complete"));
    server.stop(0); server = null; long before = networkBytes.get();
    assertArrayEquals(media, read(0, media.length));
    assertEquals(before, networkBytes.get());
    CacheSpan span = cache.getCachedSpans(resource.key()).first();
    try (RandomAccessFile f = new RandomAccessFile(span.file, "rw")) { f.seek(3); f.write(42); }
    assertEquals(false, subject.status(resource).get("complete"));
    assertEquals(0L, subject.status(resource).get("cachedBytes"));
  }
  @Test public void missingFileRevokesAndVersionHashChangesDoNotReuse() throws Exception {
    read(0, media.length);
    DanceMediaCache.Resource next = new DanceMediaCache.Resource("course", "part", "v2", resource.url, media.length, resource.sha256);
    assertNotEquals(resource.key(), next.key());
    assertEquals(0L, subject.status(next).get("cachedBytes"));
    assertTrue(cache.getCachedSpans(resource.key()).first().file.delete());
    assertEquals(false, subject.status(resource).get("complete"));
  }
  @Test public void ignoredRangeAndWrongTotalAnd416CannotPoisonCache() throws Exception {
    for (String response : new String[] {"200", "wrongLength", "416"}) {
      mode = response;
      assertThrows(IOException.class, () -> read(100, 8000));
      assertEquals(0L, subject.status(resource).get("cachedBytes"));
    }
  }
  @Test public void lruEvictionRevokesCompleteness() throws Exception {
    cache.release();
    cache = new SimpleCache(directory, (evictor = new DanceCacheEvictor(media.length + 1024, () -> Long.MAX_VALUE)), database());
    subject = new DanceMediaCache(cache, evictor);
    read(0, media.length); assertEquals(true, subject.status(resource).get("complete"));
    DanceMediaCache.Resource first = resource;
    resource = new DanceMediaCache.Resource("course", "other", "v1", first.url, media.length, first.sha256);
    read(0, media.length);
    assertEquals(true, subject.status(resource).get("complete"));
    assertEquals(false, subject.status(first).get("complete"));
    assertTrue(cache.getCacheSpace() <= media.length + 1024);
  }
  @Test public void openingFullResourceCachesOnlyBytesActuallyRead() throws Exception {
    DataSource source = subject.factory(resource, new DefaultHttpDataSource.Factory()).createDataSource();
    try {
      source.open(new DataSpec(Uri.parse(resource.url)));
      byte[] chunk = new byte[1000];
      assertEquals(1000, source.read(chunk, 0, chunk.length));
    } finally { source.close(); }
    long before = networkBytes.get();
    assertEquals(1000L, subject.status(resource).get("cachedBytes"));
    assertEquals(false, subject.status(resource).get("complete"));
    assertEquals(before, networkBytes.get());
  }
  @Test public void wrongDigestInvalidatesFullDataAndHashIsPartOfIdentity() throws Exception {
    DanceMediaCache.Resource original = resource;
    resource = new DanceMediaCache.Resource("course", "part", "v1", original.url, media.length, "0".repeat(64));
    assertNotEquals(original.key(), resource.key());
    read(0, media.length);
    assertEquals(false, subject.status(resource).get("complete"));
    assertEquals(0L, subject.status(resource).get("cachedBytes"));
  }
  @Test public void activeCachedFileIsNotDeletedByLruUntilReaderCloses() throws Exception {
    cache.release();
    cache = new SimpleCache(directory, (evictor = new DanceCacheEvictor(media.length + 1024, () -> Long.MAX_VALUE)), database());
    subject = new DanceMediaCache(cache, evictor);
    read(0, media.length);
    String activeKey = resource.key();
    File active = cache.getCachedSpans(resource.key()).first().file;
    DataSource held = subject.factory(resource, new DefaultHttpDataSource.Factory()).createDataSource();
    held.open(new DataSpec(Uri.parse(resource.url)));
    held.read(new byte[1], 0, 1);
    resource = new DanceMediaCache.Resource("course", "other", "v1", resource.url, media.length, resource.sha256);
    read(0, media.length);
    assertTrue("LRU must preserve an opened cached file", active.isFile());
    assertEquals(media.length, cache.getCachedBytes(activeKey, 0, media.length));
    assertTrue(cache.getCacheSpace() <= media.length + 1024);
    assertEquals(0L, subject.status(resource).get("cachedBytes"));
    held.close();
    assertTrue(cache.getCacheSpace() <= media.length + 1024);
  }
  @Test public void runtimeLowSpaceReducesCacheBudget() throws Exception {
    cache.release();
    AtomicLong usable = new AtomicLong(Long.MAX_VALUE);
    cache = new SimpleCache(directory, (evictor = new DanceCacheEvictor(1024 * 1024, usable::get)), database());
    subject = new DanceMediaCache(cache, evictor);
    read(0, media.length);
    usable.set(1024);
    synchronized (cache) { evictor.trim(cache); }
    assertEquals(0, cache.getCacheSpace());
  }
  @Test public void firstCacheWriteFailureContinuesUncachedAtUnreadPosition() throws Exception {
    DefaultHttpDataSource.Factory http = new DefaultHttpDataSource.Factory();
    DataSource cached = new CacheDataSource.Factory().setCache(cache)
        .setCacheKeyFactory(spec -> resource.key()).setUpstreamDataSourceFactory(http)
        .setCacheWriteDataSinkFactory(() -> new DataSink() {
          public void open(DataSpec spec) {}
          public void write(byte[] bytes, int offset, int length) throws IOException { throw new Cache.CacheException(new IOException("simulated full disk")); }
          public void close() {}
        }).createDataSource();
    DataSource source = new DanceMediaCache.FallbackSource(cached, http);
    ByteArrayOutputStream output = new ByteArrayOutputStream();
    try {
      source.open(new DataSpec.Builder().setUri(resource.url).setLength(media.length).build());
      byte[] buffer = new byte[4096]; int count;
      while ((count = source.read(buffer, 0, buffer.length)) != -1) output.write(buffer, 0, count);
    } finally { source.close(); }
    assertArrayEquals(media, output.toByteArray());
    assertEquals(0L, subject.status(resource).get("cachedBytes"));
  }
  @Test public void validTeachingIdentityRemainsRecognizedWhenCacheStorageFails() throws Exception {
    java.lang.reflect.Field catalogue = DanceMediaCache.class.getDeclaredField("packagedCatalogue");
    catalogue.setAccessible(true); Object previous = catalogue.get(null); catalogue.set(null, null);
    android.content.Context context = org.mockito.Mockito.mock(android.content.Context.class);
    android.content.res.AssetManager assets = org.mockito.Mockito.mock(android.content.res.AssetManager.class);
    org.mockito.Mockito.when(context.getAssets()).thenReturn(assets);
    org.mockito.Mockito.when(context.getApplicationContext()).thenReturn(context);
    org.mockito.Mockito.when(context.getNoBackupFilesDir()).thenThrow(new IllegalStateException("storage unavailable"));
    String url = "https://ccqspace.site/pd-rehab/assets/dance/v1/balance-six-part-1.mp4";
    String json = "{\"schemaVersion\":1,\"items\":[{\"courseId\":\"hkpdf-balance-six\",\"partId\":\"balance-six-1\",\"resourceVersion\":\"v1\",\"url\":\"" + url + "\",\"bytes\":131072,\"sha256\":\"" + resource.sha256 + "\",\"mimeType\":\"video/mp4\"}]}";
    org.mockito.Mockito.when(assets.open("flutter_assets/assets/video/remote_manifest.json"))
        .thenReturn(new ByteArrayInputStream(json.getBytes(java.nio.charset.StandardCharsets.UTF_8)));
    try {
      assertTrue(DanceMediaCache.isKnown(context, url, Collections.singletonMap(DanceMediaCache.HEADER, "balance-six-1")));
      assertFalse(DanceMediaCache.isKnown(context, url + "?token=bad", Collections.singletonMap(DanceMediaCache.HEADER, "balance-six-1")));
      org.mockito.Mockito.verify(context, org.mockito.Mockito.never()).getNoBackupFilesDir();
    } finally { catalogue.set(null, previous); }
  }
  private String catalogueItem(String course, String part, String version, String file) {
    return "{\"schemaVersion\":1,\"items\":[{\"courseId\":\"" + course + "\",\"partId\":\"" + part + "\",\"resourceVersion\":\"" + version + "\",\"url\":\"https://ccqspace.site/pd-rehab/assets/dance/" + version + "/" + file + "\",\"bytes\":131072,\"sha256\":\"" + resource.sha256 + "\",\"mimeType\":\"video/mp4\"}]}";
  }
  @Test public void acceptsTenExplicitIdentitiesAndRejectsCrossVersionAndUnknown() throws Exception {
    for (String course : new String[]{"hkpdf-balance-six", "brain-and-body", "move-and-shout"}) {
      String prefix = course.equals("hkpdf-balance-six") ? "balance-six" : course;
      String version = course.equals("hkpdf-balance-six") ? "v1" : "v2";
      int count = course.equals("brain-and-body") ? 4 : 3;
      for (int i = 1; i <= count; i++) {
        String part = prefix + "-" + i, file = prefix + "-part-" + i + ".mp4";
        assertEquals(1, DanceMediaCache.parseCatalogue(catalogueItem(course, part, version, file)).size());
        assertThrows(IOException.class, () -> DanceMediaCache.parseCatalogue(catalogueItem(course, part, version.equals("v1") ? "v2" : "v1", file)));
        assertThrows(IOException.class, () -> DanceMediaCache.parseCatalogue(catalogueItem(course, part, version, "other.mp4")));
      }
    }
    assertThrows(IOException.class, () -> DanceMediaCache.parseCatalogue(catalogueItem("brain-and-body", "brain-and-body-5", "v2", "brain-and-body-part-5.mp4")));
  }
  @Test public void newEnglishIdentityCachesAndReopensOfflineWithVersionIsolation() throws Exception {
    resource = new DanceMediaCache.Resource("brain-and-body", "brain-and-body-4", "v2", resource.url, media.length, resource.sha256);
    assertArrayEquals(media, read(0, media.length));
    assertEquals(true, subject.status(resource).get("complete"));
    cache.release();
    cache = new SimpleCache(directory, (evictor = new DanceCacheEvictor(1024 * 1024, () -> Long.MAX_VALUE)), database());
    subject = new DanceMediaCache(cache, evictor);
    server.stop(0); server = null;
    assertArrayEquals(media, read(0, media.length));
    DanceMediaCache.Resource old = new DanceMediaCache.Resource(resource.course, resource.part, "v1", resource.url, media.length, resource.sha256);
    assertEquals(0L, subject.status(old).get("cachedBytes"));
  }
  @Test public void internalMarkerIsCaseInsensitiveAndNeverSentUpstream() {
    Map<String, String> headers = new HashMap<>(); headers.put("x-pq-dance-part", "part"); headers.put("Authorization", "test");
    assertEquals(Collections.singletonMap("Authorization", "test"), DanceMediaCache.stripHeader(headers));
    assertEquals(2, headers.size());
  }
}
