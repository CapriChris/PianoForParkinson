import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piano_piece.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/piece_backing_audio.dart';
import 'package:piano_practice/platform/platform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AppController c;
  late ManualClock clock;
  late PianoPiece piece;
  late List<MethodCall> calls;
  late int errors;
  late PieceBackingAudio backing;
  Completer<void>? prepareGate;
  bool rejectSync = false;

  Future<void> flush() => Future<void>.delayed(Duration.zero);
  List<MethodCall> commands(String name) =>
      calls.where((c) => c.method == name).toList();

  setUp(() {
    calls = [];
    errors = 0;
    prepareGate = null;
    rejectSync = false;
    messenger.setMockMethodCallHandler(
      const MethodChannel('piano_training/platform_events/v1'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(PlatformService.channel, (call) async {
      calls.add(call);
      if (call.method == 'preparePieceBacking' && prepareGate != null) {
        await prepareGate!.future;
      }
      return {
        'request_id': (call.arguments as Map)['request_id'],
        'ok': !(rejectSync && call.method == 'syncPieceBacking'),
        'error_code': 'E_AUDIO_PLAY',
        'data': {'accepted': true, 'prepared': true},
      };
    });
    clock = ManualClock();
    c = AppController(clock: clock)..initialized = true;
    c.audioReady = true;
    c.repository.profile = {
      'locale': 'zh-Hans',
      'mode': 'ASSIST',
      'settings_json': jsonEncode({
        'sound_enabled': true,
        'gain_permille': 600,
      }),
    };
    piece = PianoPiece.fromJson(
      jsonDecode(
        File('assets/content/piece-saints-001.json').readAsStringSync(),
      ) as Json,
    );
    backing = PieceBackingAudio(c, piece, onError: () => errors++);
  });
  tearDown(() async {
    backing.close();
    c.dispose();
    await flush();
  });

  for (final tempo in [40, 50, 60, 70, 80]) {
    test(
      'backing follows lead-in, rests, pause/resume and completion at $tempo',
      () async {
        await backing.prepare(tempo);
        expect(
          commands('preparePieceBacking').single.arguments['tempo_bpm'],
          tempo,
        );
        expect(
          commands('preparePieceBacking').single.arguments['path'],
          endsWith('_$tempo.ogg'),
        );
        final player = ScrollingPiecePlayer(piece, clock, tempo: tempo)
          ..start();
        await backing.start(player);
        backing.sync(player);
        await flush();
        expect(
          commands('syncPieceBacking'),
          hasLength(1),
        ); // native stream includes the silent four-beat preparation
        expect(
          commands('syncPieceBacking').single.arguments['position_us'],
          -player.atTick(4 * piece.ticksPerBeat),
        );
        clock.now = player.atTick(4 * piece.ticksPerBeat);
        player.tick();
        expect(
          player.targetKey,
          0,
        ); // accompaniment continues over melody rests
        backing.sync(player);
        await flush();
        expect(commands('syncPieceBacking'), hasLength(1));
        clock.now += 1234567;
        player.tick();
        backing.sync(player);
        await flush();
        // UI frames must never poll/seek a track that is already playing.
        expect(commands('syncPieceBacking'), hasLength(1));
        player.pause();
        final frozen = player.elapsedUs;
        await backing.stop();
        final count = commands('syncPieceBacking').length;
        clock.now += 10000000;
        backing.sync(player);
        await flush();
        expect(commands('syncPieceBacking').length, count);
        await backing.prepare(tempo);
        player.resume();
        await backing.start(player);
        backing.sync(player);
        await flush();
        expect(
          commands('syncPieceBacking').last.arguments['position_us'],
          frozen,
        );
        clock.now += player.totalUs;
        player.tick();
        backing.sync(player);
        await backing.stop();
        expect(player.mode, ScrollPieceMode.complete);
        expect(errors, 0);
      },
    );
  }

  test('sound disabled sends no backing preparation or playback', () async {
    c.repository.profile['settings_json'] = jsonEncode({
      'sound_enabled': false,
    });
    await backing.prepare(60);
    final player = ScrollingPiecePlayer(piece, clock, tempo: 60)
      ..start(leadBeats: 0);
    backing.sync(player);
    await flush();
    expect(commands('preparePieceBacking'), isEmpty);
    expect(commands('syncPieceBacking'), isEmpty);
  });

  test(
    'cancelling pending prepare cannot restart the old accompaniment',
    () async {
      prepareGate = Completer<void>();
      final pending = backing.prepare(60);
      await flush();
      await backing.stop();
      prepareGate!.complete();
      await pending;
      final player = ScrollingPiecePlayer(piece, clock, tempo: 60)
        ..start(leadBeats: 0);
      await backing.start(player);
      backing.sync(player);
      await flush();
      expect(commands('syncPieceBacking'), isEmpty);
      expect(commands('stopPieceBacking'), isNotEmpty);
      expect(errors, 0);
    },
  );

  test(
    'native playback failure reaches the page interruption handler',
    () async {
      await backing.prepare(60);
      rejectSync = true;
      final player = ScrollingPiecePlayer(piece, clock, tempo: 60)
        ..start(leadBeats: 0);
      await expectLater(backing.start(player), throwsStateError);
    },
  );
}
