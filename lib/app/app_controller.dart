import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/content_repository.dart';
import '../data/practice_repository.dart';
import '../domain/contracts.dart';
import '../domain/cognitive_tasks.dart';
import '../domain/intro_lessons.dart';
import '../domain/task_engine.dart';
import '../platform/platform_service.dart';
import 'speech_navigation_observer.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  final content = ContentRepository();
  final PracticeRepository repository;
  final platform = PlatformService();
  final previewInterruptions = ValueNotifier<int>(0);
  final trainingUpdates = ValueNotifier<int>(0);
  final activeSpeech = ValueNotifier<Object?>(null);

  /// Presentation-only intent; never persisted in practice records.
  final homeNavigationRequests = ValueNotifier<int>(0);
  bool _disposed = false;
  int _lastPresentedFrame = 0;
  String? recommendedTask, recommendedSong, recommendationError;
  int _recommendationRevision = 0;
  int _speechEpoch = 0;
  Object? _speechOwner;
  late final speechNavigationObserver = SpeechNavigationObserver(() {
    unawaited(stopSpeech().catchError((_) {}));
  });
  final Clock clock;
  final String clockEpoch = uuid();
  final String? databaseSubdirectory;
  TaskEngine? engine;
  Json capabilities = {};
  bool initialized = false, audioReady = false, busy = false, saved = false;
  bool _backgrounded = false;
  Set<String> _completedIntroLessons = {};
  bool get allIntroLessonsCompleted => IntroLesson.all.every(
    (lesson) => _completedIntroLessons.contains(lesson.id),
  );
  String? error, storageError;
  List<Json> history = [];
  bool historyLoading = false, historyHasMore = false;
  String? historyError;
  int _historyRevision = 0;
  Timer? _ticker, _recorder;
  StreamSubscription<dynamic>? _platformEvents;
  Future<void> _writes = Future.value(), _audioWrites = Future.value();
  Future<void> _audioSettingsWrites = Future.value();
  Future<void> _settingsWrites = Future.value();
  final Map<int, int> _voices = {};
  final Map<int, int> _previewTokens = {};
  int _previewSerial = 0;
  int _generation = 0, _lastFlushSeq = 0;
  Future<void>? _pendingFlush;
  Json? layout;
  bool get hasPendingSave => engine?.ended == true && !saved;
  AppController({
    Clock? clock,
    PracticeRepository? repository,
    this.databaseSubdirectory,
  }) : clock = clock ?? MonotonicClock(),
       repository = repository ?? PracticeRepository() {
    if (databaseSubdirectory != null &&
        !RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(databaseSubdirectory!)) {
      throw ArgumentError('Invalid isolated database directory');
    }
    WidgetsBinding.instance.addObserver(this);
    _platformEvents = PlatformService.events.receiveBroadcastStream().listen(
      (event) {
        if (_disposed) return;
        final kind = (event as Map)['kind'];
        if ({'TTS_START', 'TTS_DONE', 'TTS_STOP', 'TTS_ERROR'}.contains(kind)) {
          if (event['generation'] == _generation &&
              event['speech_epoch'] == _speechEpoch) {
            activeSpeech.value = kind == 'TTS_START' ? _speechOwner : null;
          }
          return;
        }
        interruptPlayback(kind as String);
      },
      onError: (_) {
        interruptPlayback('E_PLATFORM');
      },
    );
  }
  String get locale =>
      initialized ? repository.profile['locale'] as String : 'zh-Hans';
  bool get chinese => locale == 'zh-Hans';
  String text(String zh, String en) => chinese ? zh : en;
  String get mode => repository.profile['mode'] as String;
  Json get settings => repository.settings;
  bool get dualTouchCheckCompleted =>
      settings['dual_touch_check_completed'] == true;
  Future<void> completeDualTouchCheck() async {
    if ((capabilities['max_verified_touch_points'] as int? ?? 0) < 2) {
      throw StateError('E_CAPABILITY_TOUCH2');
    }
    await updateSettings(values: {'dual_touch_check_completed': true});
  }

  bool get soundEnabled =>
      settings['sound_enabled'] == true && settings['gain_permille'] > 0;
  Future<void> refreshCapabilities() async {
    capabilities = await platform.call('getCapabilities');
    notifyListeners();
  }

  Future<void> initialize() async {
    error = null;
    busy = true;
    notifyListeners();
    try {
      capabilities = await platform.call('getCapabilities');
      _generation = capabilities['active_generation'] as int? ?? 0;
      final language =
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      var databasePath = capabilities['storage_path'] as String;
      if (databaseSubdirectory != null) {
        databasePath = '$databasePath/$databaseSubdirectory';
        await Directory(databasePath).create();
      }
      await repository.open(databasePath, language == 'zh' ? 'zh-Hans' : 'en');
      await content.load().timeout(const Duration(seconds: 10));
      content.select(settings['selected_song_id'] as String?);
      await refreshIntroLessonProgress();
      await platform.activate(++_generation);
      try {
        await platform.prepare(content.soundPack);
        audioReady = true;
      } catch (_) {
        audioReady = false;
      }
      capabilities = await platform.call('getCapabilities');
      initialized = true;
      await refreshHistory();
    } catch (e) {
      error = '$e';
    }
    busy = false;
    notifyListeners();
  }

  Future<void> updateSettings({
    String? locale,
    String? mode,
    Json? values,
    bool onboard = false,
  }) async {
    final changes = values == null
        ? null
        : <String, dynamic>{
            for (final entry in values.entries)
              if (!settings.containsKey(entry.key) ||
                  settings[entry.key] != entry.value)
                entry.key: entry.value,
          };
    final next = _settingsWrites.catchError((_) {}).then((_) async {
      await repository.settingsUpdate(
        locale: locale,
        mode: mode,
        settings: changes == null ? null : {...settings, ...changes},
        onboard: onboard,
      );
      notifyListeners();
    });
    _settingsWrites = next;
    await next;
  }

  int? _textScalePreview;

  /// Null follows the system at 100%.
  int? get textScalePercent {
    if (_textScalePreview != null) return _textScalePreview;
    if (!initialized) return null;
    final currentSettings = settings;
    if (currentSettings.containsKey('text_size_percent_v3')) {
      final value = currentSettings['text_size_percent_v3'];
      return value is int && value >= 80 && value <= 120 ? value : null;
    }
    if (currentSettings.containsKey('text_size_percent_v2')) {
      final old = currentSettings['text_size_percent_v2'];
      return old is int && old >= 80 && old <= 120
          ? (old * 100 / 110).round().clamp(80, 120)
          : null;
    }
    final old = currentSettings['text_scale_percent'];
    return old is int && old >= 80 && old <= 200 ? old.clamp(80, 120) : null;
  }

  void previewTextScale(int percent) {
    if (_disposed) return;
    _textScalePreview = percent.clamp(80, 120);
    notifyListeners();
  }

  void clearTextScalePreview() {
    if (_disposed || _textScalePreview == null) return;
    _textScalePreview = null;
    notifyListeners();
  }

  Future<void> saveTextScale(int? percent) async {
    if (percent != null && (percent < 80 || percent > 120)) {
      throw ArgumentError.value(percent, 'percent');
    }
    try {
      await updateSettings(values: {'text_size_percent_v3': percent});
    } finally {
      clearTextScalePreview();
    }
  }

  // Nullable fields allow an existing hot-reload session to initialise them lazily.
  Map<String, (int, int)>? _pendingPieceTempos;
  int? _pieceTempoSerial;

  int pieceTempo(String pieceId, int defaultTempo) {
    final pending = _pendingPieceTempos?[pieceId];
    if (pending != null) return pending.$1;
    final values = settings['piece_tempos'];
    final saved = values is Map ? values[pieceId] : null;
    return saved is int && const {40, 50, 60, 70, 80}.contains(saved)
        ? saved
        : defaultTempo;
  }

  Future<void> savePieceTempo(String pieceId, int tempo) async {
    if (pieceId.isEmpty || !const {40, 50, 60, 70, 80}.contains(tempo)) {
      throw ArgumentError('Invalid piece tempo');
    }
    final serial = (_pieceTempoSerial ?? 0) + 1;
    _pieceTempoSerial = serial;
    (_pendingPieceTempos ??= {})[pieceId] = (tempo, serial);
    final next = _settingsWrites.catchError((_) {}).then((_) async {
      final current = settings;
      final raw = current['piece_tempos'];
      final values = <String, int>{
        if (raw is Map)
          for (final entry in raw.entries)
            if (entry.key is String && entry.value is int)
              entry.key as String: entry.value as int,
        pieceId: tempo,
      };
      await repository.settingsUpdate(
        settings: {...current, 'piece_tempos': values},
      );
      if (!_disposed) notifyListeners();
    });
    _settingsWrites = next;
    try {
      await next;
    } finally {
      if (_pendingPieceTempos?[pieceId]?.$2 == serial) {
        _pendingPieceTempos?.remove(pieceId);
      }
    }
  }

  Future<void> refreshIntroLessonProgress() async {
    try {
      _completedIntroLessons = await repository.completedLessons();
    } catch (_) {
      // Unknown completion state keeps the optional entry available.
      _completedIntroLessons = {};
    }
    notifyListeners();
  }

  Future<void> completeIntroLesson(String lessonId) async {
    await repository.completeLesson(lessonId);
    _completedIntroLessons = {..._completedIntroLessons, lessonId};
    notifyListeners();
  }

  Future<void> clearPracticeRecords() async {
    await repository.clear();
    _completedIntroLessons = {};
    notifyListeners();
    await refreshHistory();
  }

  Future<void> updateAudioGain(String key, int gain) {
    if (!{'gain_permille', 'speech_gain_permille'}.contains(key) ||
        gain < 0 ||
        gain > 1000) {
      throw ArgumentError('Invalid audio gain');
    }
    final next = _audioSettingsWrites.catchError((_) {}).then((_) async {
      await updateSettings(
        values: {
          ...settings,
          key: gain,
          if (key == 'gain_permille') 'sound_enabled': true,
          if (key == 'speech_gain_permille') 'speech_enabled': true,
          'volume_controls_version': 2,
        },
      );
      if (key == 'speech_gain_permille' && gain == 0) {
        await stopSpeech();
      }
      if (key == 'gain_permille' && gain == 0) await stopPreview();
    });
    _audioSettingsWrites = next;
    return next;
  }

  Future<void> refreshHistory() async {
    final revision = ++_historyRevision;
    history = [];
    historyHasMore = false;
    historyLoading = true;
    historyError = null;
    notifyListeners();
    try {
      final page = await repository.historyPage();
      if (revision != _historyRevision) return;
      history = page.records;
      historyHasMore = page.hasMore;
    } catch (e) {
      if (revision != _historyRevision) return;
      historyError = '$e';
    } finally {
      if (revision == _historyRevision) {
        historyLoading = false;
        notifyListeners();
      }
    }
    await refreshRecommendations();
  }

  Future<void> refreshRecommendations() async {
    if (!initialized || engine != null && !engine!.ended) return;
    final revision = ++_recommendationRevision;
    try {
      final result = await repository.recommendations([
        for (final song in content.songs) song['content_id'] as String,
      ]);
      if (revision != _recommendationRevision ||
          engine != null && !engine!.ended) {
        return;
      }
      recommendedTask = result['task_id'] as String;
      recommendedSong = result['song_id'] as String?;
      recommendationError = null;
    } catch (_) {
      if (revision != _recommendationRevision) return;
      recommendationError = text(
        '暂时无法生成推荐，你仍可自由选择练习。',
        'Recommendations unavailable. You can still choose any practice.',
      );
    }
    notifyListeners();
  }

  Future<void> selectSong(String? id) async {
    if (engine != null && !engine!.ended) throw StateError('E_ACTIVE_SESSION');
    content.select(id);
    await updateSettings(
      values: {'selected_song_id': content.song['content_id']},
    );
  }

  void framePresented() => _lastPresentedFrame = clock.now;

  Future<void> loadMoreHistory() async {
    if (historyLoading || !historyHasMore || history.isEmpty) return;
    final revision = _historyRevision;
    historyLoading = true;
    historyError = null;
    notifyListeners();
    try {
      final page = await repository.historyPage(after: history.last);
      if (revision != _historyRevision) return;
      final ids = history.map((r) => r['session_id']).toSet();
      history = [
        ...history,
        ...page.records.where((r) => ids.add(r['session_id'])),
      ];
      historyHasMore = page.hasMore;
    } catch (e) {
      if (revision != _historyRevision) return;
      historyError = '$e';
    } finally {
      if (revision == _historyRevision) {
        historyLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> start(
    String taskId,
    Json keyboardLayout, {
    bool reader = false,
  }) async {
    if (busy || (engine != null && !engine!.ended)) return;
    if (hasPendingSave) {
      await finishSave();
      if (hasPendingSave) throw StateError('E_PENDING_UNSAVED_SESSION');
    }
    if (reader && (isCognitiveTask(taskId) || isBeatTask(taskId))) {
      throw StateError('E_SCREEN_READER');
    }
    if (soundEnabled && !audioReady) throw StateError('E_AUDIO_INIT');
    busy = true;
    notifyListeners();
    try {
      final storage = await platform.call('getStorageStatus');
      if (storage['available_bytes'] <
          content.config.json['recording']['minimum_free_bytes']) {
        throw StateError('E_STORAGE_LOW');
      }
      await platform.activate(++_generation);
      await stopSpeech();
      capabilities = await platform.call('getCapabilities');
      if (isDualTask(taskId) &&
          (keyboardLayout['canvas_width_dp'] < 600 ||
              (!dualTouchCheckCompleted &&
                  (capabilities['max_verified_touch_points'] as int? ?? 0) <
                      2) ||
              reader)) {
        throw StateError('E_CAPABILITY_TOUCH2');
      }
      final task = TaskEngine(
        clockEpochId: clockEpoch,
        config: content.config,
        clock: clock,
        taskId: taskId,
        mode: mode,
        level: await repository.level(taskId, content.config),
        song: content.notes,
        layoutSnapshot: keyboardLayout,
      );
      task.generation = _generation;
      layout = keyboardLayout;
      final environment = normalizeRecordText({
        'schema_version': 1,
        'platform': 'ANDROID',
        'os_version': capabilities['os_version'],
        'app_version': appVersion,
        'build_id': appBuild,
        'device_model': capabilities['device_model'],
        'device_local_id': settings['device_local_id'],
        'window_width_dp': keyboardLayout['canvas_width_dp'],
        'window_height_dp': keyboardLayout['canvas_height_dp'],
        'text_scale_permille': keyboardLayout['text_scale_permille'],
        'layout_id': keyboardLayout['layout_id'],
        'layout_version': 1,
        'layout_snapshot': keyboardLayout,
        'audio_backend': 'SOUNDPOOL',
        'sound_pack_version': content.soundPack['version'],
        'audio_route_category': soundEnabled
            ? capabilities['audio_route_category']
            : 'MUTED',
        'sound_enabled': soundEnabled,
        'app_gain_permille': settings['gain_permille'],
        'screen_reader_active': reader,
        'clock_source': 'DART_RECEIPT',
        'latency_test_id': null,
        'system_volume_steps': null,
        'renderer_policy':
            capabilities['renderer_policy'] ?? 'PLATFORM_DEFAULT',
      }) as Json;
      await repository.create(
        task,
        environment,
        task.cognitive || task.alternate || task.dual ? null : content.song,
        capabilities['timezone'] as String,
      );
      engine = task;
      saved = false;
      storageError = null;
      _lastFlushSeq = task.events.length;
      _lastPresentedFrame = clock.now;
      _ticker?.cancel();
      _recorder?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 20), (_) {
        if (busy ||
            engine == null ||
            engine!.ended ||
            engine!.phase == 'paused') {
          return;
        }
        final oldCompleted = engine!.completed;
        if (!_backgrounded && clock.now - _lastPresentedFrame > 3000000) {
          engine!.pause('E_FRAME_STALLED');
          _drainAudio();
          unawaited(flush());
          unawaited(
            platform
                .call('reportFrameStall', {'locale': locale})
                .catchError((_) => <String, dynamic>{}),
          );
          notifyListeners();
          return;
        }
        engine!.tick();
        _drainAudio();
        if (engine!.completed != oldCompleted) unawaited(flush());
        if (engine!.ended) unawaited(finishSave());
        trainingUpdates.value++;
      });
      _recorder = Timer.periodic(
        Duration(
          milliseconds:
              content.config.json['recording']['flush_interval_ms'] as int,
        ),
        (_) {
          if (engine != null &&
              !engine!.ended &&
              storageError == null &&
              engine!.events.length > _lastFlushSeq) {
            unawaited(flush());
          }
        },
      );
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void down(int pointer, int? key, {bool disabled = false, Json? coordinates}) {
    engine?.down(pointer, key, disabled: disabled, coordinates: coordinates);
    _changed();
  }

  void up(int pointer, {bool cancel = false, Json? coordinates}) {
    engine?.up(pointer, cancel: cancel, coordinates: coordinates);
    _changed();
  }

  void move(int pointer, Json coordinates) {
    engine?.move(pointer, coordinates);
    if (engine?.ended == true) _changed();
  }

  void reconfigureLayout(Json value) {
    layout = value;
    engine?.reconfigure(value);
    _changed();
    unawaited(flush());
  }

  void _changed() {
    _drainAudio();
    if (engine != null &&
        storageError == null &&
        engine!.events.length - _lastFlushSeq >=
            content.config.json['recording']['flush_event_count']) {
      unawaited(flush());
    }
    if (engine?.ended == true) unawaited(finishSave());
    notifyListeners();
  }

  void cue() {
    engine?.cuePresented();
    _changed();
  }

  void pause(String reason) {
    engine?.pause(reason);
    _changed();
    unawaited(flush());
  }

  Future<void> resume({
    bool help = false,
    bool lower = false,
    bool replay = false,
  }) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await flush();
      if (storageError != null) return;
      if (lower) {
        engine?.lower();
      } else {
        engine?.resume(help: help, replay: replay);
      }
      _lastPresentedFrame = clock.now;
      _generation = engine!.generation;
      await platform.activate(_generation);
      _changed();
    } catch (_) {
      pause('E_PLATFORM');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> next() async {
    await flush();
    if (storageError == null) {
      engine?.nextBlock();
      _changed();
    }
  }

  Future<void> exit() async {
    engine?.finish('EXITED');
    _changed();
    await finishSave();
  }

  void _drainAudio() {
    final task = engine;
    if (task == null || task.audio.isEmpty) return;
    final commands = List<Json>.from(task.audio);
    task.audio.clear();
    _audioWrites = _audioWrites.catchError((_) {}).then((_) async {
      for (final command in commands) {
        try {
          if (command['kind'] == 'off') {
            _generation = task.generation;
            await platform.activate(_generation);
            _voices.clear();
            continue;
          }
          if (command['kind'] == 'up') {
            final voice = _voices.remove(command['pointer']);
            if (voice != null) await platform.stop(voice);
            continue;
          }
          if (task.generation != command['generation'] || !soundEnabled) {
            continue;
          }
          final voice = await platform.play(
            command['key_id'] as int,
            settings['gain_permille'] as int,
            owner: command['kind'] == 'down' ? 'USER' : 'DEMO',
          );
          if (task.generation != command['generation']) {
            await platform.stop(voice);
            continue;
          }
          if (command['kind'] == 'down') {
            _voices[command['pointer'] as int] = voice;
          } else {
            final gen = task.generation;
            Timer(Duration(milliseconds: command['duration_ms'] as int), () {
              if (gen == task.generation) unawaited(platform.stop(voice));
            });
          }
          task.emit('AUDIO_REPLY', {
            'voice_id': voice,
            'generation': task.generation,
            'ok': true,
            'request_event_seq': command['request_event_seq'],
          }, context: command['context'] as Json?);
        } catch (_) {
          task.pause('E_AUDIO_PLAY');
          unawaited(flush());
          _drainAudio();
          notifyListeners();
        }
      }
    });
  }

  Future<void> flush() {
    final task = engine;
    if (task == null) return Future.value();
    final pending = _pendingFlush;
    if (pending != null) {
      return pending;
    }
    _writes = _writes.catchError((_) {}).then((_) async {
      try {
        do {
          final capturedSeq = task.events.length;
          await repository.persist(task);
          _lastFlushSeq = capturedSeq;
          storageError = null;
        } while (task.events.length > _lastFlushSeq);
      } catch (e) {
        storageError = '$e';
        task.pause('E_DB_WRITE');
        _drainAudio();
        notifyListeners();
      }
    });
    _pendingFlush = _writes.whenComplete(() => _pendingFlush = null);
    return _pendingFlush!;
  }

  Future<void>? _pendingFinish;
  Future<void> finishSave() {
    if (saved || engine?.ended != true) return Future.value();
    if (_pendingFinish != null) return _pendingFinish!;
    _pendingFinish = _saveFinished().whenComplete(() => _pendingFinish = null);
    return _pendingFinish!;
  }

  Future<void> _saveFinished() async {
    _ticker?.cancel();
    _recorder?.cancel();
    await _audioWrites;
    await flush();
    if (storageError == null) {
      saved = true;
      await refreshHistory();
    }
    notifyListeners();
  }

  Future<void> preview(
    int key,
    bool down, {
    int? pointer,
    int ratePermille = 1000,
  }) async {
    if (!audioReady || !soundEnabled || _backgrounded) return;
    final id = pointer ?? key;
    if (down) {
      final token = ++_previewSerial;
      _previewTokens[id] = token;
      final int voice;
      try {
        voice = await platform.play(
          key,
          settings['gain_permille'] as int,
          owner: 'SANDBOX',
          ratePermille: ratePermille,
        );
      } catch (_) {
        if (_backgrounded || _previewTokens[id] != token) return;
        rethrow;
      }
      if (_previewTokens[id] == token) {
        _voices[id] = voice;
      } else {
        await platform.stop(voice);
      }
    } else {
      _previewTokens.remove(id);
      final voice = _voices.remove(id);
      if (voice != null) await platform.stop(voice);
    }
  }

  Future<void> stopPreview() async {
    _previewTokens.clear();
    _voices.clear();
    await platform.off();
  }

  Future<void> stopAllPlayback() async {
    await Future.wait([stopPreview(), stopSpeech()]);
  }

  void interruptPlayback(String reason) {
    // Invalidate pending sandbox replies before any asynchronous platform work.
    _previewTokens.clear();
    if (engine != null && !engine!.ended) pause(reason);
    previewInterruptions.value++;
    unawaited(stopAllPlayback().catchError((_) {}));
  }

  Future<void> stopSpeech({Object? owner}) async {
    if (owner != null && !identical(owner, _speechOwner)) return;
    _speechOwner = null;
    if (!_disposed) activeSpeech.value = null;
    await platform.call('stopSpeech', {'speech_epoch': ++_speechEpoch});
  }

  Future<void> speak(String text, {Object? owner}) async {
    if (_backgrounded ||
        settings['speech_enabled'] != true ||
        settings['speech_gain_permille'] == 0) {
      return;
    }
    try {
      _speechOwner = owner;
      if (!_disposed) activeSpeech.value = null;
      final epoch = ++_speechEpoch;
      await platform.call('speakLocal', {
        'speech_epoch': epoch,
        'locale': locale,
        'resolved_text': text,
        'gain_permille': settings['speech_gain_permille'],
      });
    } catch (_) {
      /* Text remains visible. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state != AppLifecycleState.resumed;
    if (_backgrounded) {
      interruptPlayback('INTERRUPTED_BACKGROUND');
    } else {
      unawaited(refreshRecommendations());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _historyRevision++;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _recorder?.cancel();
    _platformEvents?.cancel();
    previewInterruptions.dispose();
    trainingUpdates.dispose();
    activeSpeech.dispose();
    homeNavigationRequests.dispose();
    unawaited(stopAllPlayback().catchError((_) {}));
    super.dispose();
  }
}
