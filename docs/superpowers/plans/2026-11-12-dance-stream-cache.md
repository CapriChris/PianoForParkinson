# Dance streaming and persistent cache implementation plan

> For agentic workers: use executing-plans or subagent-driven-development task by task, with tests and review before release.

**Goal:** Stream the three published balance-six parts while persistently reusing only bytes actually read; keep existing training semantics and Fandango asset.

**Architecture:** Controlled local fork of video_player_android 2.12.2 injects Media3 CacheDataSource for explicitly identified teaching resources only. A single packaged remote_manifest.json supplies resource identity, byte length, hash and HTTPS URL to Dart and Android. Existing controller/UI/PlaybackLedger remains responsible for pause, interruption, saving and capture.

**Tech stack:** Flutter 3.47.7, video_player 2.14.1, Android Media3 1.9.2 (plugin baseline), CacheDataSource/SimpleCache, SHA-256.

**Spec:** User's 2026-11-12-舞蹈视频在线播放与自动缓存交接.md; published resources in PD Web docs/dance-media-20261112/resources-v1.json. This run covers the three MP4s only.

## Constraints and review focus

- No download buttons, download service, full-file prefetch or course prefetch. Never credit buffering/cache work as training.
- Keep IDs, UI, account/authentication, plans, AI and face-video workflow. Do not change training database or server.
- No full-buffer memory copies. Cache is shared, app-private, noBackup, initially <=1 GiB with low-space reduction; no external storage permission.
- Stable key is courseId/partId/resourceVersion/sha256, never token/URL. Media bytes must match expected length/version, never mix Range 200/416/version mismatches.
- Full/offline status requires all expected local bytes plus SHA; no network during completeness verification. Missing/evicted/corrupt spans revoke full status. Do not infer full from playback position.
- Old controller reads stop on dispose/part switch/background. Respect manual resume after network/buffering interruption.
- True native cache tests required, not only Dart mocks; actual Android device checks reported separately if no device available.
- Keep original videos until cache/data-source integration tests pass; Fandango remains bundled. Then remove only the three MP4 pubspec entries.

## Files and interface

- `third_party/video_player_android/`: minimally vendored BSD plugin with license/source provenance. Own HTTP media/cache implementation and tests here. No global Pub cache edits.
- `assets/video/remote_manifest.json`: packaged JSON identical resource fields to published v1 list of three. Native reads `flutter_assets/assets/video/remote_manifest.json` through Android AssetManager.
- `lib/platform/dance_video_source.dart`: validates local manifest, resolves network vs original asset, queries cache status once per selection; never fetches a course API for full-cache offline playback.
- `lib/features/dance_player_page.dart`: use resolved source instead of always asset(), preserve existing controller options and lifecycle; compact metered-data notice only if uncached bytes needed.
- `pubspec.yaml`: override plugin path; add exact JSON asset; remove three MP4 assets only after validation; keep WebM.
- `test/`: resource resolution, controller creation, lifecycle/regression and package assertions.

**Dart/native protocol:** network controller sends internal header `X-PQ-Dance-Part` containing the known partId. Native strips it before all HTTP requests and validates URL/metadata against packaged catalogue. Unknown resources keep original uncached plugin behavior. MethodChannel `piano_training/dance_media_cache/v1`, method `status`, args `{partId: string}` returns `{cachedBytes: int,totalBytes: int,complete: bool,metered: bool}`. Status verification is asynchronous and local-only; incomplete cache must not trigger an upstream request. Complete data must be served offline with no HEAD/manifest request.

## Task 1: native cache

- [x] Vendor current plugin without build/cache/generated artifacts; preserve license and behavior for non-course sources.
- [x] Add failing native tests for streamed partial write/reopen reuse, offline full verified playback, partial cache miss, corruption, eviction and stable identity.
- [x] Implement shared cache, metered status, bounded upstream checks, background local verification and invalidation/recovery; no downloader/cache writer prefill.
- [x] Run actual native cache tests including requests counter; audit read/write/eviction and resource identity races.

## Task 2: Dart source and UI

- [x] Record fresh main baseline and run existing tests before source changes; run the final analyzer and regression suite.
- [x] Add resource/controller tests first, use real packaged JSON; keep Fandango local.
- [x] Resolve/create source inside existing exception and generation guards, update necessary loading/error/traffic text only.
- [x] Verify existing playback/buffering/seek/background/save tests; no algorithm changes.

## Task 3: integrated delivery

- [x] Run full Flutter analyze/test, native tests and actual public range reads.
- [x] Remove three MP4 packaging entries after cache verification. Check built APK member list for no MP4 copies and WebM retained.
- [x] Build same-arm64 isolated QA APK, verify signature/version/SHA and compare archive size.
- [x] Review resource/cache security and lifecycle. Report missing physical Android validation explicitly.
- [x] Local commits and reproducible handoff; no unrequested GitHub push or APK Release.

Automated validation and isolated QA build completed. Physical Android acceptance remains outstanding: no connected device; it is explicitly documented rather than counted as passed. No GitHub push/Release or production App update performed.
