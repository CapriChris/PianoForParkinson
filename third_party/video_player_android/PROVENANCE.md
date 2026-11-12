# Controlled Android video-player fork

Source: Flutter `video_player_android` **2.12.2**, copied unchanged from the hosted Pub
package on 2026-11-12 before the modifications below. Upstream repository:
https://github.com/flutter/packages/tree/main/packages/video_player/video_player_android
The original AUTHORS and BSD LICENSE are retained. Dart/Pigeon code remains upstream. The only player lifecycle change is identified
teaching sources: pause stops the Media3 loader, and a later play prepares the same
media item again, retaining the current seek position. Other sources keep the
upstream pause/play behavior. Android Media3 remains **1.9.2**.

Local changes: `HttpVideoAsset` strips the internal `X-PQ-Dance-Part` header and selects
`DanceMediaCache` only when that marker and URL match the packaged teaching catalogue.
`VideoPlayerPlugin` registers/unregisters the local asynchronous `DanceCacheChannel`.
Assets and all other remote sources retain upstream data-source behavior.

The authoritative catalogue is the app asset
`flutter_assets/assets/video/remote_manifest.json`. Cache keys contain course, part,
resource version and SHA-256, never URLs or credentials. A process-wide SimpleCache
uses private noBackup storage, LRU eviction and a budget of min(1 GiB, available
space / 5), checked at source creation, writes and reader close. Open cached files
hold leases: LRU skips them and drops a new committed span if accepting it would
exceed the budget. Active files are removed only after their last reader closes. Only bytes returned through player reads enter the
cache. No downloader, background service, prefetch or file preallocation is added.
The app's existing controller disposal and playback ledger remain responsible for
lifecycle and training duration. Cache IO failures continue through a checked
uncached HTTP stream at the first undelivered byte; ordinary HTTP errors retain
normal handling. Teaching recognition is independent of cache storage, so
stop-on-pause remains active when storage fails.

`status` runs on one background executor, reads only local committed spans and hashes
with a 64 KiB buffer while holding SimpleCache's monitor against commit/eviction.
It never probes the network and never persists a completeness bit. Missing files,
length mismatch, eviction, version/hash changes or failed SHA validation revoke full
status. The verification monitor can pause loader cache operations during hashing;
it does not perform hashing on the UI thread. Metered status uses Android's existing
network-state permission; if unavailable it conservatively returns true.

The native tests use actual Media3 CacheDataSource/SimpleCache and a loopback HTTP
server with byte counters, not Dart mocks. `native-cache-tests` is a small standalone
Android test harness compiling the exact same Java source and test files, useful
without configuring every unrelated Flutter plugin/NDK. Configure its ignored
`local.properties` SDK path, use JDK 17+, then run Gradle 9.3.1:

```
gradle -p native-cache-tests testDebugUnitTest
```

The normal Flutter Android build also runs the suite with:

```
gradle -p ../../android :video_player_android:testDebugUnitTest
```

Native tests additionally cover actual LRU pressure with an open reader, bounded
committed bytes while pinned, and reduced available space at runtime.

Physical Android playback, airplane-mode interaction and actual metered-network UI
are device acceptance checks and are not implied by Robolectric tests.

The upstream example app and its 2.4 MB demonstration MP4 are omitted from this fork; no media binaries or generated build/cache files belong in Git.
