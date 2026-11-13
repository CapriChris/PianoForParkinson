import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player/video_player.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/dance_training.dart';
import 'package:piano_practice/features/dance_page.dart';
import 'package:piano_practice/features/dance_player_page.dart';
import 'package:piano_practice/features/dance_result_page.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import 'cognitive_pages_test.dart' show mocks;

class FakeDanceVideo extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final sources = <String>[];
  final dataSources = <DataSource>[];
  final positions = <int, Duration>{};
  final playing = <int>{};
  final volumes = <int, double>{};
  final disposed = <int>{};
  bool deferInitialization = false;
  VideoPlayerOptions? options;
  int next = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++next;
    this.options = options.videoPlayerOptions;
    dataSources.add(options.dataSource);
    sources.add(options.dataSource.asset ?? options.dataSource.uri!);
    streams[id] = StreamController<VideoEvent>();
    positions[id] = Duration.zero;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) {
    if (deferInitialization) return streams[id]!.stream;
    streams[id]!.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 30),
        size: const Size(1280, 720),
      ),
    );
    return streams[id]!.stream;
  }

  @override
  Future<void> dispose(int id) async {
    disposed.add(id);
    playing.remove(id);
    unawaited(streams[id]!.close());
  }

  @override
  Future<void> play(int id) async {
    playing.add(id);
  }

  @override
  Future<void> pause(int id) async {
    playing.remove(id);
  }

  @override
  Future<void> setLooping(int id, bool looping) async {}
  @override
  Future<void> setVolume(int id, double volume) async {
    volumes[id] = volume;
  }

  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mix) async {}
  @override
  Future<void> seekTo(int id, Duration position) async {
    positions[id] = position;
  }

  @override
  Future<Duration> getPosition(int id) async => positions[id]!;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.blueGrey);
  void end() {
    positions[next] = const Duration(seconds: 30);
    streams[next]!.add(VideoEvent(eventType: VideoEventType.completed));
  }

  void buffering(bool loading) {
    streams[next]!.add(
      VideoEvent(
        eventType: loading
            ? VideoEventType.bufferingStart
            : VideoEventType.bufferingEnd,
      ),
    );
    streams[next]!.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: !loading && playing.contains(next),
      ),
    );
  }
}

Future<void> advance(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 1)),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
}

void main() {
  late FakeDanceVideo platform;
  setUp(() {
    rootBundle.evict('assets/video/remote_manifest.json');
    platform = FakeDanceVideo();
    VideoPlayerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/dance_media_cache/v1'),
          (_) async => {
            'complete': false,
            'cachedBytes': 0,
            'totalBytes': 34614645,
            'metered': false,
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform_events/v1'),
          (_) async => null,
        );
  });
  AppController setup(
    WidgetTester tester, {
    String locale = 'zh-Hans',
    double scale = 1,
  }) {
    final c = AppController();
    addTearDown(c.dispose);
    mocks(tester, const Size(320, 640), locale, scale, c);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform_events/v1'),
          (_) async => null,
        );
    return c;
  }

  Widget app(Widget child) =>
      MaterialApp(theme: qinTheme(highContrast: false), home: child);
  Future<void> open(
    WidgetTester tester,
    AppController c,
    List<Json> writes,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DancePlayerPage(
                    c: c,
                    nowMilliseconds: () =>
                        tester.binding.clock.now().millisecondsSinceEpoch,
                    saveRecord: (r) async {
                      writes.add(r);
                    },
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await advance(tester);
  }

  testWidgets(
    'Chinese dance streams the chosen resource without prefetching another part',
    (tester) async {
      final c = setup(tester);
      await open(tester, c, []);
      expect(platform.dataSources, hasLength(1));
      final source = platform.dataSources.single;
      expect(source.sourceType, DataSourceType.network);
      expect(
        source.uri,
        'https://ccqspace.site/pd-rehab/assets/dance/v1/balance-six-part-1.mp4',
      );
      expect(source.httpHeaders['X-PQ-Dance-Part'], 'balance-six-1');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('leaving during cache lookup cannot create a late player', (
    tester,
  ) async {
    final pending = Completer<Map<String, Object>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/dance_media_cache/v1'),
          (_) => pending.future,
        );
    final c = setup(tester);
    final writes = <Json>[];
    await open(tester, c, writes);
    expect(platform.dataSources, isEmpty);
    await tester.pumpWidget(const SizedBox());
    pending.complete({
      'complete': false,
      'cachedBytes': 0,
      'totalBytes': 34614645,
      'metered': true,
    });
    await advance(tester);
    expect(platform.dataSources, isEmpty);
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'English dance streams the same default course without locale selection',
    (tester) async {
      final c = setup(tester, locale: 'en');
      await open(tester, c, <Json>[]);
      expect(platform.dataSources.single.sourceType, DataSourceType.network);
      expect(
        platform.sources.single,
        'https://ccqspace.site/pd-rehab/assets/dance/v1/balance-six-part-1.mp4',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('leaving disposes a network player still initializing', (
    tester,
  ) async {
    platform.deferInitialization = true;
    final c = setup(tester);
    await open(tester, c, <Json>[]);
    expect(platform.dataSources, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await advance(tester);
    expect(platform.disposed, contains(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'backgrounding cancels pending network initialization without auto resume',
    (tester) async {
      platform.deferInitialization = true;
      final c = setup(tester);
      await open(tester, c, <Json>[]);
      final observer =
          tester.state(find.byType(DancePlayerPage)) as WidgetsBindingObserver;
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await advance(tester);
      expect(platform.disposed, contains(1));
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await advance(tester);
      expect(platform.dataSources, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'dance ignores notification duck and waits for manual resume after takeover',
    (tester) async {
      final c = setup(tester);
      await open(tester, c, []);
      final id = platform.next;
      expect(platform.playing, contains(id));
      expect(platform.options!.mixWithOthers, isTrue);
      expect(platform.options!.allowBackgroundPlayback, isTrue);
      final observer =
          tester.state(find.byType(DancePlayerPage)) as WidgetsBindingObserver;
      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
      c.handlePlaybackEvent('AUDIO_FOCUS_DUCK');
      await advance(tester);
      expect(platform.playing, contains(id));
      expect(platform.volumes[id], .25);
      c.handlePlaybackEvent('AUDIO_FOCUS_GAIN');
      await advance(tester);
      expect(platform.volumes[id], 1);
      tester
          .widget<DanceVideoSurface>(find.byType(DanceVideoSurface))
          .onVolume!(.6);
      await advance(tester);
      c.handlePlaybackEvent('AUDIO_FOCUS_DUCK');
      await advance(tester);
      expect(platform.volumes[id], closeTo(.15, .001));
      c.handlePlaybackEvent('AUDIO_FOCUS_GAIN');
      await advance(tester);
      expect(platform.volumes[id], .6);
      c.handlePlaybackEvent('WINDOW_FOCUS_LOST');
      await advance(tester);
      expect(platform.playing, isNot(contains(id)));
      c.handlePlaybackEvent('WINDOW_FOCUS_GAIN');
      c.handlePlaybackEvent('AUDIO_FOCUS_GAIN');
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await advance(tester);
      expect(platform.playing, isNot(contains(id)));
      tester
          .widget<DanceVideoSurface>(find.byType(DanceVideoSurface))
          .onToggle();
      await advance(tester);
      expect(platform.playing, contains(id));
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await advance(tester);
      expect(platform.playing, isNot(contains(id)));
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await advance(tester);
      expect(platform.playing, isNot(contains(id)));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'late dance focus grant cannot restart after a second interruption',
    (tester) async {
      final c = setup(tester);
      await open(tester, c, []);
      final id = platform.next;
      c.handlePlaybackEvent('AUDIO_FOCUS_LOST');
      await advance(tester);
      final grant = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('piano_training/platform/v1'),
            (call) async {
              if (call.method == 'requestTrainingAudioFocus') {
                await grant.future;
              }
              return {
                'ok': true,
                'request_id': (call.arguments as Map)['request_id'],
                'data': {'granted': true},
              };
            },
          );
      tester
          .widget<DanceVideoSurface>(find.byType(DanceVideoSurface))
          .onToggle();
      await tester.pump();
      c.handlePlaybackEvent('WINDOW_FOCUS_LOST');
      grant.complete();
      await advance(tester);
      expect(platform.playing, isNot(contains(id)));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('dance buffering shows loading and resumes without pausing', (
    tester,
  ) async {
    final c = setup(tester);
    final writes = <Json>[];
    await open(tester, c, writes);
    final id = platform.next;
    platform.buffering(true);
    await advance(tester);
    expect(platform.playing, contains(id));
    expect(find.byKey(const ValueKey('dance-loading')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dance-play')),
        matching: find.byIcon(Icons.pause),
      ),
      findsOneWidget,
    );
    // Position polling can still report a changed position while buffering;
    // none of that interval may count as active training.
    platform.positions[id] = const Duration(seconds: 1);
    await advance(tester);
    platform.positions[id] = const Duration(seconds: 2);
    await advance(tester);
    platform.buffering(false);
    await advance(tester);
    expect(platform.playing, contains(id));
    expect(find.byKey(const ValueKey('dance-loading')), findsNothing);
    final controller = tester
        .widget<VideoPlayer>(find.byType(VideoPlayer))
        .controller;
    expect(controller.value.isPlaying, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('finish-dance')));
    await tester.tap(find.byKey(const ValueKey('finish-dance')));
    await advance(tester);
    expect(writes.single['active_ms'], 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final interruption in ['pause', 'background', 'audio focus']) {
    testWidgets('buffering does not resume after $interruption', (
      tester,
    ) async {
      final c = setup(tester);
      await open(tester, c, []);
      final id = platform.next;
      platform.buffering(true);
      await advance(tester);
      expect(find.byKey(const ValueKey('dance-loading')), findsOneWidget);
      if (interruption == 'pause') {
        tester
            .widget<DanceVideoSurface>(find.byType(DanceVideoSurface))
            .onToggle();
      } else if (interruption == 'background') {
        final observer = tester.state(
          find.byType(DancePlayerPage),
        ) as WidgetsBindingObserver;
        observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
        observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      } else {
        c.handlePlaybackEvent('AUDIO_FOCUS_LOST');
        c.handlePlaybackEvent('AUDIO_FOCUS_GAIN');
      }
      await advance(tester);
      expect(platform.playing, isNot(contains(id)));
      expect(find.byKey(const ValueKey('dance-loading')), findsNothing);
      platform.buffering(false);
      await advance(tester);
      expect(platform.playing, isNot(contains(id)));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  testWidgets('preparation is concise and shows three independent courses', (
    tester,
  ) async {
    final c = setup(tester);
    await tester.pumpWidget(app(DancePage(c: c)));
    await tester.pumpAndSettle();
    expect(find.text('新平衡舞步六式'), findsOneWidget);
    expect(find.text('身心协调'), findsOneWidget);
    expect(find.text('律动与发声'), findsOneWidget);
    expect(find.text('舞蹈记录'), findsNothing);
    expect(find.text('来源与许可'), findsNothing);
    expect(
      find
          .byType(Icon)
          .evaluate()
          .where((e) => (e.widget as Icon).icon == Icons.accessibility_new),
      isEmpty,
    );
    expect(find.textContaining('待审课程'), findsNothing);
    expect(danceCourseFor(false).id, chineseDanceCourse.id);
    expect(danceCourseFor(true).parts.length, 3);
  });
  testWidgets('new course result repeats its saved course', (tester) async {
    final c = setup(tester);
    await tester.pumpWidget(
      app(
        DanceResultPage(
          c: c,
          alreadySaved: true,
          record: {
            'session_id': 'brain-old',
            'content_id': brainAndBodyCourse.id,
            'title': brainAndBodyCourse.title,
            'active_ms': 1000,
            'parts': <Json>[],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dance-practise-again')));
    await advance(tester);
    expect(
      platform.dataSources.single.httpHeaders['X-PQ-Dance-Part'],
      'brain-and-body-1',
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final locale in ['zh-Hans', 'en']) {
    for (final course in [brainAndBodyCourse, moveAndShoutCourse]) {
      testWidgets(
        'catalog selection streams only selected parts $locale ${course.id}',
        (tester) async {
          final c = setup(tester, locale: locale);
          await tester.pumpWidget(app(DancePage(c: c)));
          await tester.pumpAndSettle();
          for (final item in danceCourses) {
            final entry = find.byKey(ValueKey('dance-course-${item.id}'));
            await tester.scrollUntilVisible(entry, 100);
            await tester.ensureVisible(entry);
            await tester.pumpAndSettle();
            expect(find.text(item.localizedTitle(c.chinese)), findsOneWidget);
          }
          expect(find.textContaining('Fandango'), findsNothing);
          expect(platform.dataSources, isEmpty);
          final selection = find.byKey(ValueKey('dance-course-${course.id}'));
          await tester.scrollUntilVisible(selection, -100);
          await tester.ensureVisible(selection);
          await tester.pumpAndSettle();
          await tester.tap(selection);
          await tester.pumpAndSettle();
          expect(platform.dataSources, isEmpty);
          await tester.tap(find.byKey(const ValueKey('start-dance')));
          await advance(tester);
          expect(platform.dataSources, hasLength(1));
          expect(
            platform.dataSources.single.httpHeaders['X-PQ-Dance-Part'],
            course.parts.first.id,
          );
          expect(
            platform.dataSources.single.sourceType,
            DataSourceType.network,
          );
          final lastPart = find.byKey(
            ValueKey('dance-part-${course.parts.length - 1}'),
          );
          await tester.ensureVisible(lastPart);
          await tester.pumpAndSettle();
          await tester.tap(lastPart);
          await advance(tester);
          expect(platform.dataSources, hasLength(2));
          expect(
            platform.dataSources.last.httpHeaders['X-PQ-Dance-Part'],
            course.parts.last.id,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets('parts switch, resume position, and controls stay inside video', (
    tester,
  ) async {
    final c = setup(tester);
    final writes = <Json>[];
    await open(tester, c, writes);
    expect(
      platform.sources.last,
      'https://ccqspace.site/pd-rehab/assets/dance/v1/balance-six-part-1.mp4',
    );
    platform.positions[platform.next] = const Duration(seconds: 2);
    await advance(tester);
    await tester.tap(find.byKey(const ValueKey('dance-part-1')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

    await advance(tester);
    expect(
      platform.sources.last,
      'https://ccqspace.site/pd-rehab/assets/dance/v1/balance-six-part-2.mp4',
    );
    await tester.tap(find.byKey(const ValueKey('dance-part-0')));
    await advance(tester);
    expect(platform.positions[platform.next], const Duration(seconds: 2));
    final surface = find.byType(DanceVideoSurface);
    expect(
      find.descendant(
        of: surface,
        matching: find.byKey(const ValueKey('dance-play')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: surface,
        matching: find.byKey(const ValueKey('dance-progress')),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await advance(tester);
    expect(writes, isEmpty);
  });
  testWidgets('video completion prompts next part and exit discards record', (
    tester,
  ) async {
    final c = setup(tester);
    final writes = <Json>[];
    await open(tester, c, writes);
    platform.end();
    await advance(tester);
    expect(find.text('第一部分已播放结束'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dance-next-part')));
    await advance(tester);
    expect(
      platform.sources.last,
      'https://ccqspace.site/pd-rehab/assets/dance/v1/balance-six-part-2.mp4',
    );
    await tester.tap(find.byType(BackButton));
    await advance(tester);
    expect(find.text('退出不会保存本次训练记录。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-exit-dance')));
    await advance(tester);
    expect(find.text('open'), findsOneWidget);
    expect(writes, isEmpty);
  });
  testWidgets(
    'finish directly opens result and persists one multipart record',
    (tester) async {
      final c = setup(tester);
      final writes = <Json>[];
      await open(tester, c, writes);
      // Advance native positions in small increments so only observed playback is counted.
      for (var i = 1; i <= 6; i++) {
        platform.positions[platform.next] = Duration(milliseconds: i * 250);
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.tap(find.byKey(const ValueKey('finish-dance')));
      await advance(tester);
      expect(find.byType(DanceResultPage), findsOneWidget);
      expect(find.text('保存本次记录'), findsNothing);
      expect(find.text('已保存训练记录'), findsOneWidget);
      expect(writes.length, 1);
      expect(writes.single['content_id'], chineseDanceCourse.id);
      expect(writes.single['parts'], hasLength(3));
      expect(writes.single['active_ms'], greaterThan(0));
      final firstSession = writes.single['session_id'];
      await tester.tap(find.byKey(const ValueKey('dance-practise-again')));
      await advance(tester);
      expect(find.byType(DanceResultPage), findsNothing);
      expect(find.byType(DancePlayerPage), findsOneWidget);
      expect(platform.positions[platform.next], Duration.zero);
      await tester.tap(find.byKey(const ValueKey('finish-dance')));
      await advance(tester);
      expect(writes.length, 2);
      expect(writes.last['session_id'], isNot(firstSession));
      expect(writes.last['active_ms'], 0);
      await tester.tap(find.byKey(const ValueKey('dance-home')));
      await advance(tester);
      expect(find.text('open'), findsOneWidget);
      expect(c.homeNavigationRequests.value, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await advance(tester);
    },
  );
  testWidgets(
    'result retry keeps same record and shows save failure honestly',
    (tester) async {
      final c = setup(tester);
      var calls = 0;
      final record = <String, dynamic>{
        'session_id': 'same',
        'title': '新平衡舞步六式',
        'active_ms': 2000,
        'parts': <Json>[],
      };
      await tester.pumpWidget(
        app(
          DanceResultPage(
            c: c,
            record: record,
            saveRecord: (r) async {
              expect(identical(record, r), isTrue);
              if (++calls == 1) throw StateError('offline');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('保存失败，请重试。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dance-home')));
      await tester.pumpAndSettle();
      expect(find.text('记录尚未保存'), findsOneWidget);
      await tester.tap(find.text('返回重试'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试保存'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('已保存训练记录'), findsOneWidget);
    },
  );
  testWidgets(
    'scrubbing pauses throughout drag and restores the previous play state',
    (tester) async {
      final c = setup(tester);
      await open(tester, c, <Json>[]);
      final controller = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      expect(controller.value.isPlaying, isTrue);
      var slider = tester.widget<Slider>(
        find.byKey(const ValueKey('dance-progress')),
      );
      slider.onChangeStart!(1000);
      slider.onChanged!(3000);
      await advance(tester);
      expect(controller.value.isPlaying, isFalse);
      expect(platform.playing, isEmpty);
      slider.onChanged!(5000);
      await advance(tester);
      expect(controller.value.isPlaying, isFalse);
      slider.onChangeEnd!(5000);
      await advance(tester);
      expect(controller.value.position, const Duration(seconds: 5));
      expect(controller.value.isPlaying, isTrue);
      await controller.pause();
      await advance(tester);
      slider = tester.widget<Slider>(
        find.byKey(const ValueKey('dance-progress')),
      );
      slider.onChangeStart!(5000);
      slider.onChanged!(7000);
      await advance(tester);
      slider.onChangeEnd!(7000);
      await advance(tester);
      expect(controller.value.position, const Duration(seconds: 7));
      expect(controller.value.isPlaying, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await advance(tester);
    },
  );
  testWidgets('speed menu, vertical volume and fullscreen back control', (
    tester,
  ) async {
    final c = setup(tester);
    await open(tester, c, <Json>[]);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.text('1.0x'), findsOneWidget);
    final rateRect = tester.getRect(find.byKey(const ValueKey('dance-rate')));
    final volume = find.byTooltip('Volume');
    final volumeRect = tester.getRect(volume);
    expect(rateRect.center.dx, lessThan(volumeRect.center.dx));
    await tester.tap(volume);
    await advance(tester);
    final panelRect = tester.getRect(
      find.byKey(const ValueKey('dance-volume-panel')),
    );
    expect(panelRect.center.dx, closeTo(volumeRect.center.dx, 1));
    expect(panelRect.bottom, lessThan(volumeRect.top));
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('dance-volume-slider')),
        matching: find.byType(RotatedBox),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('dance-rate')));
    await advance(tester);
    expect(find.text('0.75x'), findsOneWidget);
    expect(find.text('1.25x'), findsOneWidget);
    expect(find.textContaining('10'), findsNothing);
    await tester.tap(find.text('1.25x'));
    await advance(tester);
    expect(
      tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller
          .value
          .playbackSpeed,
      1.25,
    );
    expect(find.text('1.25x'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dance-fullscreen')));
    await advance(tester);
    expect(find.byKey(const ValueKey('dance-fullscreen-back')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dance-fullscreen-back')));
    await advance(tester);
    expect(find.byKey(const ValueKey('dance-part-0')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await advance(tester);
  });
  testWidgets(
    'exit buttons share one row at large text and video keeps its ratio',
    (tester) async {
      final c = setup(tester, scale: 2);
      await open(tester, c, <Json>[]);
      final size = tester.getSize(find.byType(DanceVideoSurface));
      expect(size.width / size.height, closeTo(16 / 9, 0.01));
      await tester.tap(find.byType(BackButton));
      await advance(tester);
      final left = tester.getRect(find.byKey(const ValueKey('continue-dance')));
      final right = tester.getRect(
        find.byKey(const ValueKey('confirm-exit-dance')),
      );
      expect(left.center.dy, closeTo(right.center.dy, 1));
      expect(left.right, lessThan(right.left));
      expect(find.text('退出'), findsOneWidget);
      expect(find.text('退出且不保存'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('confirm-exit-dance')));
      await advance(tester);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets('player controls fit 320dp at text scale $scale', (
      tester,
    ) async {
      final c = setup(tester, scale: scale);
      await open(tester, c, <Json>[]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await advance(tester);
    });
  }
}
