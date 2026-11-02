import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:piano_practice/domain/dance_training.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bundled WebM initializes plays seeks and pauses on Android', (
    tester,
  ) async {
    final video = VideoPlayerController.asset(
      danceAsset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await video.initialize();
      expect(video.value.isInitialized, true);
      expect(video.value.duration.inSeconds, inInclusiveRange(1250, 1270));
      expect(video.value.size.width, 1920);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AspectRatio(
              aspectRatio: video.value.aspectRatio,
              child: VideoPlayer(video),
            ),
          ),
        ),
      );
      await video.play();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump();
      final position = await video.position;
      expect(position!.inMilliseconds, greaterThan(0));
      await video.seekTo(const Duration(seconds: 20));
      await video.pause();
      expect(video.value.isPlaying, false);
      expect(video.value.hasError, false);
      debugPrint(
        'DANCE_SMOKE duration=${video.value.duration.inMilliseconds}, size=${video.value.size}, playback=${position.inMilliseconds}ms',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await video.dispose();
    }
  });
}
