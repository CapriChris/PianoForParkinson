import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/dance_training.dart';
import 'package:piano_practice/platform/dance_video_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('piano_training/dance_media_cache/v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => rootBundle.evict(danceRemoteManifestAsset));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('all ten catalogued parts are remote and resolve only their own cache status', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add((call.arguments as Map)['partId'] as String);
      return null;
    });
    expect(danceCourses.map((c) => c.parts.length), [3, 4, 3]);
    for (final course in danceCourses) {
      for (final part in course.parts) {
        final before = calls.length;
        final source = await resolveDanceVideoSource(part);
        expect(source.isRemote, true);
        expect(
          source.uri!.path,
          '/pd-rehab/assets/dance/${course.id == chineseDanceCourse.id ? "v1" : "v2"}/${part.asset.split('/').last}',
        );
        expect(calls.skip(before).toList(), [part.id]);
      }
    }
    expect(calls, hasLength(10));
  });
  test(
    'unknown and retired resources cannot fall back to a bundled video',
    () async {
      expect(
        () => resolveDanceVideoSource(
          const DancePart('fandango-4', 'Fandango', danceAsset),
        ),
        throwsFormatException,
      );
      expect(
        () => resolveDanceVideoSource(
          const DancePart(
            'brain-and-body-1',
            'Invalid',
            'assets/video/wrong.mp4',
          ),
        ),
        throwsFormatException,
      );
    },
  );

  for (final complete in [false, true]) {
    test('metered notice respects verified completeness $complete', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'status');
        expect(call.arguments, {'partId': 'balance-six-1'});
        return {
          'complete': complete,
          'cachedBytes': complete ? 34614645 : 100,
          'totalBytes': 34614645,
          'metered': true,
        };
      });
      final source = await resolveDanceVideoSource(
        chineseDanceCourse.parts.first,
      );
      expect(source.isRemote, true);
      expect(source.needsNetworkNotice, !complete);
      expect(
        source.uri.toString(),
        'https://ccqspace.site/pd-rehab/assets/dance/v1/balance-six-part-1.mp4',
      );
    });
  }

  test('inconsistent complete status cannot hide the traffic notice', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'complete': true,
        'cachedBytes': 100,
        'totalBytes': 34614645,
        'metered': true,
      },
    );
    expect(
      (await resolveDanceVideoSource(chineseDanceCourse.parts.first))
          .needsNetworkNotice,
      true,
    );
  });

  test(
    'native storage failure leaves normal online playback available',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'cache'),
      );
      final source = await resolveDanceVideoSource(
        chineseDanceCourse.parts.first,
      );
      expect(source.isRemote, true);
      expect(source.needsNetworkNotice, true);
    },
  );
}
