import 'dart:math';

import 'contracts.dart';
import 'error_recovery.dart';
import 'practice_metrics.dart';
import 'cognitive_tasks.dart';

class TaskEngine {
  TaskEngine({
    required this.config,
    required this.clock,
    required this.taskId,
    required this.mode,
    required this.level,
    required List<int> song,
    this.layoutSnapshot = const {},
    String? clockEpochId,
    int? seed,
  }) : song = taskId == 'M1_ALTERNATE'
           ? List<int>.generate(
               config.task(taskId)['planned_trial_count_per_block'] as int,
               (i) => (config.task(taskId)['pool'] as List)[i % 2] as int,
             )
           : song,
       id = uuid(),
       epoch = clockEpochId ?? uuid(),
       rng = Lcg(seed ?? Random.secure().nextInt(0xfffffffe) + 1),
       base = clock.now {
    policy = AdaptivePolicy(config, taskId);
    planned = config.blocks * trialCount;
    emit('SESSION_CREATED', {'task_id': taskId});
    _block();
  }
  final PracticeConfig config;
  final Clock clock;
  final String taskId, mode, id, epoch;
  final int base;
  final Lcg rng;
  final List<int> song;
  late final AdaptivePolicy policy;
  final errors = ErrorRecovery();
  int level, completed = 0, slot = 0, trialIndex = 0, generation = 0;
  late int planned;
  Json layoutSnapshot;
  int _seq = 0, _last = 0, _quietSince = 0, _demoIndex = 0;
  int? _deadline, _responseAnchor, _cueRequested, _highlightOff;
  String phase = 'waiting';
  String pauseReason = 'USER';
  String? finishStatus;
  int? finishedAt;
  String? _pausedPhase;
  int? _pausedAt, _pausedHighlight;
  int _responsePausedUs = 0, _userPauseCount = 0;
  bool _skipNextDemo = false;
  bool _timeout = false, _policyHint = false, _replaySong = false;
  String? _hintTrial;
  bool get showAnswer => trials.isNotEmpty && _hintTrial == trial['trial_id'];
  int? highlighted;
  int get demonstrationStep => _demoIndex;
  final Map<int, ({int? key, int down})> pointers = {};
  final List<Json> events = [],
      blocks = [],
      trials = [],
      attempts = [],
      decisions = [];
  final List<Json> audio = [];
  Json? _attempt;
  final List<int> _consumed = [];
  final Map<int, int> _dualDowns = {};
  bool get dual => isDualTask(taskId);
  bool resourceLimited = false;
  bool _enforceBudget() {
    if (ended) return true;
    if (events.length < 24000 && attempts.length < 512 && blocks.length < 64) {
      return false;
    }
    resourceLimited = true;
    emit('ERROR', {'reason_code': 'SESSION_RESOURCE_LIMIT'});
    finish('EXITED');
    return true;
  }

  int get dualToleranceUs =>
      (config.task(taskId)['gap_tolerance_ms_by_level'][block['level'] - 1]
          as int) *
      1000;
  int _actions = 0,
      _outside = 0,
      _disabled = 0,
      _overlap = 0,
      _extra = 0,
      _wrong = 0;
  int? _first;
  bool _correctSong = false;
  int? _firstResponseUs, _lastWindowEnd;
  bool get requiresHold =>
      !dual && config.json['performance']?['hold_policy'] == 'HOLD_400_V1';
  bool get responsiveControls =>
      config.json['performance']?['interaction_policy'] == 'RESPONSIVE_HOLD_V1';
  int _short = 0;
  int? _firstHoldPointer, _firstHoldUs, _rhythmWindowEnd;
  ({int pointer, int key, int down})? _pendingNote;
  ({int key, int duration})? _pausedRelease;
  int? _shortKey, _shortUntil;
  int _shortDuration = 0;
  int? _leadStart;
  int? _demoStart;
  bool _demoAfterLeadIn = false;
  bool get hasDemoLeadIn =>
      rhythm && config.task(taskId)['demo_lead_in_beats'] == 4;
  bool get preparingDemo => phase == 'countdown' && _demoAfterLeadIn;
  int _leadBeatSent = -1;
  bool finishingPhrase = false;
  int _phrasePauseRemainingUs = 0;
  int get phraseEndUs =>
      _beatOrigin! +
      ((block['targets']['trials'] as List).first['target_time_us'] as int) +
      trialCount * 60000000 ~/ bpm;

  int get beatIntervalUs => 60000000 ~/ bpm;
  bool get durationTooShort =>
      requiresHold &&
      (responsiveControls
          ? _shortKey != null && responding
          : _shortUntil != null && visualNow < _shortUntil!);
  bool get inputLocked =>
      finishingPhrase ||
      responsiveControls &&
          windowed &&
          phase == 'response' &&
          _firstHoldUs != null &&
          _firstHoldUs! < noteDurationUs &&
          _consumed.isNotEmpty;
  int? get responseRemainingUs =>
      (memory || windowed) && phase == 'response' && _deadline != null
      ? max(0, _deadline! - visualNow)
      : null;
  double get responseFraction => responseRemainingUs == null
      ? 0
      : (responseRemainingUs! /
                (windowed
                    ? responseWindowUs
                    : config.ms(
                        config.task(taskId),
                        'response_per_position_timeout_ms',
                      )))
            .clamp(0.0, 1.0);

  /// Visuals use the sounding beat, independent of the next matching window.
  double? get rhythmPulse {
    if (!rhythm) return null;
    final visiblePhase = phase == 'paused' ? _pausedPhase : phase;
    if (visiblePhase == 'demo' && _demoStart != null) {
      return _pulseAt(_demoStart!);
    }
    if (_beatOrigin != null &&
        {
          'cue',
          'beatPrepare',
          'response',
          'holdTail',
          'phraseEnd',
        }.contains(visiblePhase)) {
      final first =
          (block['targets']['trials'] as List).first['target_time_us'] as int;
      return _pulseAt(_beatOrigin! + first);
    }
    return null;
  }

  double _pulseAt(int origin) {
    final elapsed = visualNow - origin;
    if (elapsed < 0) return elapsed * bpm / 60000000;
    var index = elapsed * bpm ~/ 60000000;
    // The schedule floors fractional microseconds; match those exact boundaries.
    if (elapsed >= (index + 1) * 60000000 ~/ bpm) index++;
    final start = index * 60000000 ~/ bpm;
    final end = (index + 1) * 60000000 ~/ bpm;
    return index + (elapsed - start) / (end - start);
  }

  int? get soundingNoteIndex {
    final pulse = rhythmPulse;
    return pulse == null || pulse < 0
        ? null
        : pulse.floor().clamp(0, song.length - 1);
  }

  int? get leadInBeat => phase == 'countdown' && _leadStart != null
      ? (leadInProgress.floor() + 1).clamp(1, 4)
      : null;
  double get leadInProgress => _leadStart == null
      ? 0
      : responsiveControls
      ? _pulseAt(_leadStart!)
      : (visualNow - _leadStart!) / beatIntervalUs;
  double get phraseProgress {
    if (responsiveControls && rhythm) {
      final visiblePhase = phase == 'paused' ? _pausedPhase : phase;
      if (visiblePhase == 'gap' ||
          !finishingPhrase && block['status'] == 'COMPLETED') {
        return 1;
      }
      // Demo, playing, highlighting and pendulum share the same beat fraction.
      // The response window opens early; it must not advance phrase progress.
      final pulse = rhythmPulse;
      return pulse == null ? 0 : (pulse / song.length).clamp(0.0, 1.0);
    }
    return _beatOrigin == null
        ? 0
        : ((visualNow - _beatOrigin!) /
                  ((block['targets']['trials'] as List).last['target_time_us'] +
                      beatAfterUs))
              .clamp(0.0, 1.0);
  }

  // Beat targets use a block-relative active timeline. USER pause moves its
  // origin, never the immutable target table or an already sealed result.
  int? _beatOrigin;
  int? _beatSoundIndex;
  bool get alternate => taskId == 'M1_ALTERNATE';
  bool get rhythm => isBeatTask(taskId);
  int get bpm => config.task(taskId)['bpm_by_level'][block['level'] - 1] as int;
  int get beatBeforeUs =>
      config.ms(config.task(taskId), 'window_before_target_ms');
  int get beatAfterUs =>
      config.ms(config.task(taskId), 'window_after_target_ms');
  int get beatTargetUs => target['target_time_us'] as int;
  int get scheduledBeatUs => _beatOrigin! + beatTargetUs;
  int get beatRemainingUs =>
      _beatOrigin == null ? 0 : scheduledBeatUs - visualNow;
  int? get currentBeatErrorUs => rhythm && _firstResponseUs != null
      ? _firstResponseUs! - beatBeforeUs
      : null;
  int get visualNow => _pausedAt ?? now;
  bool get hasDurationGuide =>
      !dual && (requiresHold || memory || taskId == 'S1_GUIDED' || rhythm);
  int get noteDurationUs => requiresHold
      ? 400000
      : rhythm
      ? config.ms(config.task(taskId), 'note_duration_ms')
      : config.ms(config.task(taskId), 'demo_note_duration_ms');
  ({int key, double progress})? get durationGuide {
    if (responsiveControls && phase == 'paused') return null;
    final visiblePhase = phase == 'paused' ? _pausedPhase : phase;
    final lit = phase == 'paused' ? _pausedHighlight : highlighted;
    if (visiblePhase == 'demo' && lit != null && _highlightOff != null) {
      return (
        key: lit,
        progress: (1 - (_highlightOff! - visualNow) / noteDurationUs).clamp(
          0.0,
          1.0,
        ),
      );
    }
    if (requiresHold &&
        {
          'response',
          'release',
          'tail',
          'holdTail',
          'cue',
          'beatPrepare',
        }.contains(visiblePhase)) {
      if (!responsiveControls &&
          taskId == 'G2_INHIBITION' &&
          target['trial_type'] == 'NO_GO') {
        return null;
      }
      final held = pointers.values.where(
        (p) =>
            p.key != null &&
            p.key! <
                (alternate
                    ? 2
                    : cognitive
                    ? 3
                    : 5) &&
            _responseAnchor != null &&
            p.down >= _responseAnchor!,
      );
      if (held.isNotEmpty) {
        return (
          key: held.first.key!,
          progress: ((visualNow - held.first.down) / noteDurationUs).clamp(
            0.0,
            1.0,
          ),
        );
      }
      if (durationTooShort && _shortKey != null) {
        return (
          key: _shortKey!,
          progress: (_shortDuration / noteDurationUs).clamp(0.0, 1.0),
        );
      }
      if (memory || taskId == 'G3_SWITCH') return null;
      if (responsiveControls && rhythm && visualNow < scheduledBeatUs) {
        return null;
      }
      if (taskId == 'G2_INHIBITION' && target['trial_type'] == 'NO_GO') {
        return null;
      }
      return (key: expected.single, progress: 0);
    }
    if ((taskId == 'S1_GUIDED' || rhythm) &&
        {'cue', 'beatPrepare', 'response', 'release'}.contains(visiblePhase)) {
      final matches = pointers.values.where(
        (p) =>
            p.key == expected.single &&
            _responseAnchor != null &&
            p.down >= _responseAnchor!,
      );
      final elapsed = matches.isEmpty
          ? 0
          : max(0, visualNow - matches.first.down);
      return (
        key: expected.single,
        progress: (elapsed / noteDurationUs).clamp(0.0, 1.0),
      );
    }
    return null;
  }

  int? _operationAt;
  int get now => _operationAt ?? clock.now - base;
  T _atReceipt<T>(T Function() action) {
    if (_operationAt != null) return action();
    _operationAt = clock.now - base;
    try {
      return action();
    } finally {
      _operationAt = null;
    }
  }

  bool get memory => taskId == 'G1_MEMORY';
  bool get windowed => dual || isWindowedTask(taskId);
  bool get cognitive => isCognitiveTask(taskId);
  int get responseWindowUs => windowUsAt(level);
  int windowUsAt(int atLevel) => dual
      ? config.ms(config.task(taskId), 'response_window_ms')
      : taskId == 'G2_INHIBITION'
      ? (config.task(
                  taskId,
                )['modes'][mode]['response_window_ms_by_level'][atLevel - 1]
                as int) *
            1000
      : config.ms(
          Map<String, dynamic>.from(config.task(taskId)['modes'][mode]),
          'response_window_ms',
        );
  int get trialCount => cognitive || dual
      ? config.task(taskId)['planned_trial_count_per_block'] as int
      : song.length;
  Json get block => blocks.last;
  Json get trial => trials
      .where((t) => t['block_id'] == block['block_id'])
      .elementAt(trialIndex);
  Json get target => Map<String, dynamic>.from(trial['target']);
  String? get displayedRule => taskId != 'G3_SWITCH'
      ? null
      : phase == 'intertrial' && trialIndex > 0
      ? (block['targets']['trials'] as List)[trialIndex - 1]['rule_id']
            as String
      : target['rule_id'] as String;
  List<int> get expected => List<int>.from(target['expected_keys']);
  int get countdown =>
      phase == 'countdown' ? max(1, ((_deadline! - now) / 1000000).ceil()) : 0;
  bool get ended => finishStatus != null;

  /// Presentation only: gaps describe the sealed item, not the advanced trial.
  /// Beat windows open before the sounding beat, so their logical index cannot
  /// drive the number shown alongside the timeline.
  int get currentItemNumber {
    final visiblePhase = phase == 'paused' ? _pausedPhase : phase;
    if ({
      'trialFeedback',
      'intertrial',
      'feedback',
      'phraseEnd',
      'finished',
    }.contains(visiblePhase)) {
      return completed.clamp(1, planned);
    }
    if (rhythm &&
        responsiveControls &&
        {'cue', 'beatPrepare', 'response', 'holdTail'}.contains(visiblePhase)) {
      final blockOffset = completed - (block['valid_trial_count'] as int);
      return (blockOffset + (soundingNoteIndex ?? 0) + 1).clamp(1, planned);
    }
    return (completed + (trial['status'] == 'COMPLETED' ? 0 : 1)).clamp(
      1,
      planned,
    );
  }

  /// Input receipt feedback can precede the tail observation's final scoring.
  bool get memoryResponseCollected =>
      memory &&
      (phase == 'tail' || phase == 'release') &&
      _consumed.length == expected.length;

  bool get responding =>
      phase == 'response' || phase == 'tail' || phase == 'release';
  bool get heldHint => pointers.values.any(
    (p) => now - p.down >= config.ms(config.input, 'held_touch_hint_ms'),
  );
  String get sessionStatus => ended
      ? 'FINISHING'
      : switch (phase) {
          'paused' => errors.code == pauseReason ? 'PAUSED_ERROR' : 'PAUSED',
          'feedback' => 'BLOCK_FEEDBACK',
          'waiting' => 'WAIT_ALL_UP',
          'countdown' => 'COUNTDOWN',
          'demo' || 'gap' => 'DEMONSTRATING',
          _ => 'ACTIVE',
        };
  int get validDuration => attempts
      .where((a) => a['validity'] == 'VALID')
      .fold(0, (v, a) => v + (a['active_duration_us'] as int));
  int get interruptedDuration => attempts
      .where(
        (a) => a['validity'] == 'INTERRUPTED' || a['validity'] == 'INVALID',
      )
      .fold(0, (v, a) => v + (a['active_duration_us'] as int));
  Json get parameters => parametersAt(level);
  Json parametersAt(int atLevel) {
    final task = config.task(taskId);
    return {
      'task': task,
      'mode': mode,
      'level': atLevel,
      'sequence_length': memory
          ? task['sequence_length_by_level'][atLevel - 1]
          : null,
      'layout': config.json['layout'],
      'layout_snapshot': layoutSnapshot,
      'pause_policy': 'CONTINUE_IN_PLACE_V1',
      if (requiresHold) ...{
        'hold_policy': 'HOLD_400_V1',
        'hold_duration_us': noteDurationUs,
        if (responsiveControls) 'interaction_policy': 'RESPONSIVE_HOLD_V1',
      },
      if (windowed) 'response_window_ms': windowUsAt(atLevel) ~/ 1000,
      if (dual)
        'gap_tolerance_us':
            (task['gap_tolerance_ms_by_level'][atLevel - 1] as int) * 1000,
      if (taskId == 'G3_SWITCH')
        'run_length': task['run_length_by_level'][atLevel - 1],
      if (rhythm) ...{
        'bpm': task['bpm_by_level'][atLevel - 1],
        'beat_reference': task['beat_reference'],
        'target_time_reference': 'BLOCK_ACTIVE_BEAT_TIMELINE_V1',
        'duration_guide_policy': requiresHold
            ? 'REQUIRED_400_V1'
            : 'ADVISORY_V1',
      },
    };
  }

  void emit(String kind, Json payload, {Json? context}) {
    events.add({
      'session_id': id,
      'seq': ++_seq,
      'offset_us': now,
      'clock_epoch_id': epoch,
      'kind': kind,
      'block_id': blocks.isEmpty ? null : block['block_id'],
      'trial_id': trials.isEmpty || trialIndex >= trialCount
          ? null
          : trial['trial_id'],
      'attempt_id': _attempt?['attempt_id'],
      'payload_version': 1,
      'source_event_seq': payload['source_event_seq'],
      'payload': payload,
      ...?context,
    });
  }

  void _block() {
    _beatOrigin = null;
    _beatSoundIndex = null;
    _leadStart = null;
    _demoStart = null;
    _demoAfterLeadIn = false;
    final blockId = uuid(), before = rng.state;
    final task = config.task(taskId);
    final pool = memory ? List<int>.from(task['pool']) : <int>[];
    final targets = <Json>[];
    final generated = dual
        ? dualTargets(task)
        : windowed
        ? cognitiveTargets(taskId, task, level, rng)
        : null;
    for (var i = 0; i < trialCount; i++) {
      final keys = windowed
          ? List<int>.from(generated![i]['expected_keys'])
          : memory
          ? List<int>.generate(
              task['sequence_length_by_level'][level - 1] as int,
              (_) => pool[rng.index(pool.length)],
            )
          : [song[i]];
      final t =
          generated?[i] ??
          {
            'schema_version': 1,
            'logical_index': i,
            'trial_type': memory ? 'SEQUENCE' : 'NOTE',
            'expected_keys': keys,
            'rule_id': null,
            'target_time_us': null,
            if (rhythm) ...{
              'target_time_us':
                  config.ms(task, 'first_target_delay_ms') +
                  i * 60000000 ~/ (task['bpm_by_level'][level - 1] as int),
              'target_key': keys.single,
              'duration_ms': task['note_duration_ms'],
            },
          };
      targets.add(t);
      trials.add({
        'trial_id': uuid(),
        'session_id': id,
        'block_id': blockId,
        'logical_index': i,
        'status': 'PLANNED',
        'target': t,
        if (taskId == 'G3_SWITCH') ...{
          'rule_id': t['rule_id'],
          'switch_flag': t['switch_flag'] == null
              ? null
              : t['switch_flag'] == true
              ? 1
              : 0,
        },
        'assisted': 0,
        'help_count': 0,
        'policy_hint_count': 0,
        'interrupted_retry_count': 0,
      });
    }
    blocks.add({
      'block_id': blockId,
      'session_id': id,
      'ordinal': blocks.length,
      'slot_index': slot,
      'commit_id': uuid(),
      'level': level,
      'status': 'ACTIVE',
      'planned_trial_count': trialCount,
      'valid_trial_count': 0,
      'started_offset_us': now,
      'ended_offset_us': null,
      'ended_utc_ms': null,
      'parameters': parameters,
      'targets': {
        'schema_version': 1,
        'rng_algorithm': 'rng-lcg32-1',
        'rng_state_before': before,
        'rng_state_after': rng.state,
        'trials': targets,
      },
      'active_duration_us': 0,
    });
    trialIndex = 0;
    emit('BLOCK_CREATED', {'slot_index': slot, 'level': level});
  }

  void tick() => _atReceipt(_tick);
  void _tick() {
    if (_enforceBudget()) return;
    if (now < _last) {
      pause('E_CLOCK');
      return;
    }
    _last = now;
    if (phase == 'paused') return;
    if (!dual &&
        responsiveControls &&
        windowed &&
        phase == 'response' &&
        target['trial_type'] != 'NO_GO' &&
        _consumed.isNotEmpty &&
        (_firstHoldUs == null && pointers.containsKey(_firstHoldPointer) ||
            _firstHoldUs != null && _firstHoldUs! >= noteDurationUs)) {
      final fullAt =
          (pointers[_firstHoldPointer]?.down ??
              (_responseAnchor! + _firstResponseUs! + _responsePausedUs)) +
          noteDurationUs;
      if (now >= fullAt && fullAt <= _deadline!) {
        _complete(responseEnd: fullAt);
        return;
      }
    }
    if (phase == 'demo' &&
        highlighted != null &&
        _highlightOff != null &&
        now >= _highlightOff!) {
      highlighted = null;
    }
    if (phase != 'paused' &&
        pointers.values.any(
          (p) => now - p.down > config.ms(config.input, 'held_touch_pause_ms'),
        )) {
      pause('INTERRUPTED_TOUCH_HELD');
      return;
    }
    if (phase == 'waiting' &&
        pointers.isEmpty &&
        now - _quietSince >= config.ms(config.input, 'release_quiet_ms')) {
      if (rhythm && !_skipNextDemo && _beatOrigin == null) {
        if (hasDemoLeadIn && _demoStart == null) {
          _startLeadIn(demo: true);
          return;
        }
        if (hasDemoLeadIn && _demoStart != null) {
          _startLeadIn();
          return;
        }
        _begin();
        return;
      }
      if (rhythm && requiresHold) {
        _startLeadIn();
        return;
      }
      phase = 'countdown';
      _deadline =
          now +
          (config.input['countdown_steps'] as int) *
              config.ms(config.input, 'countdown_step_ms');
    }
    if (rhythm && requiresHold && phase == 'countdown' && _leadStart != null) {
      final beat =
          (responsiveControls
                  ? _pulseAt(_leadStart!).floor()
                  : (now - _leadStart!) ~/ beatIntervalUs)
              .clamp(0, 3);
      if (beat > _leadBeatSent) {
        _leadBeatSent = beat;
        _clickBeat(
          _demoAfterLeadIn ? 'DEMO_LEAD_IN' : 'LEAD_IN',
          beat,
          _leadStart! +
              (responsiveControls
                  ? beat * 60000000 ~/ bpm
                  : beat * beatIntervalUs),
        );
      }
    }
    if (rhythm &&
        phase == 'response' &&
        _beatSoundIndex != trialIndex &&
        now >= scheduledBeatUs &&
        now < scheduledBeatUs + beatAfterUs) {
      _beatSoundIndex = trialIndex;
      if (responsiveControls) highlighted = expected.single;
      emit('BEAT_REFERENCE', {
        'target_time_us': beatTargetUs,
        'scheduled_offset_us': scheduledBeatUs,
      });
      audio.add({
        'kind': 'beat',
        'key_id': requiresHold ? 7 : expected.single,
        'generation': generation,
        'duration_ms': requiresHold
            ? 90
            : config.task(taskId)['note_duration_ms'],
        'request_event_seq': _seq + 1,
        'context': _eventContext,
      });
      emit('AUDIO_REQUEST', {
        'owner': 'BEAT_REFERENCE',
        'key_id': requiresHold ? 7 : expected.single,
      });
    }
    if (phase == 'response' &&
        taskId == 'S1_GUIDED' &&
        !responsiveControls &&
        !_policyHint &&
        now - _responseAnchor! - _responsePausedUs >=
            (config.task(taskId)['policy_hint_delay_ms_by_level'][level - 1]
                    as int) *
                1000) {
      _policyHint = true;
      highlighted = expected.single;
      trial['assisted'] = 1;
      trial['policy_hint_count'] = (trial['policy_hint_count'] as int) + 1;
      emit('POLICY_HINT', {'key_id': highlighted});
    }
    if (_deadline == null || now < _deadline!) return;
    final boundary = _deadline!;
    _deadline = null;
    switch (phase) {
      case 'countdown':
        if (pointers.isNotEmpty) {
          phase = 'waiting';
          return;
        }
        if (rhythm) {
          if (_demoAfterLeadIn) {
            _demoAfterLeadIn = false;
            _leadStart = null;
            _begin(demoOrigin: boundary);
            return;
          }
          _beatOrigin =
              (requiresHold ? boundary : now) -
              beatTargetUs +
              config.ms(config.task(taskId), 'first_target_delay_ms');
          emit('BEAT_SCHEDULED', {
            'origin_offset_us': _beatOrigin,
            'from_logical_index': trialIndex,
            'bpm': bpm,
            'beat_reference': 'PLANNED_BEAT_REFERENCE',
          });
          if (_attempt == null) {
            _begin();
          } else {
            _cue();
          }
          return;
        }
        _begin();
      case 'demo':
        final notes = memory ? expected : song;
        if (_demoIndex < notes.length) {
          final demoNote = _demoIndex;
          highlighted = notes[_demoIndex++];
          _highlightOff = now + noteDurationUs;
          audio.add({
            'kind': 'demo',
            'key_id': highlighted,
            'generation': generation,
            'duration_ms': noteDurationUs ~/ 1000,
          });
          emit('AUDIO_REQUEST', {'owner': 'DEMO', 'key_id': highlighted});
          audio.last.addAll({
            'request_event_seq': _seq,
            'context': _eventContext,
          });
          if (responsiveControls && rhythm) {
            _clickBeat(
              'DEMO',
              demoNote,
              _demoStart! + demoNote * 60000000 ~/ bpm,
            );
          }
          _deadline = responsiveControls && rhythm
              ? _demoStart! + _demoIndex * 60000000 ~/ bpm
              : now +
                    (rhythm && _demoIndex == notes.length
                        ? noteDurationUs +
                              config.ms(
                                config.task('S1_GUIDED'),
                                'demo_end_gap_ms',
                              )
                        : _demoInterval);
        } else {
          highlighted = null;
          phase = 'gap';
          final interval = _demoInterval;
          final duration = noteDurationUs;
          _deadline =
              now +
              max(
                0,
                duration +
                    config.ms(
                      config.task(rhythm ? 'S1_GUIDED' : taskId),
                      'demo_end_gap_ms',
                    ) -
                    interval,
              );
        }
      case 'gap':
        if (pointers.isNotEmpty ||
            now - _quietSince < config.ms(config.input, 'release_quiet_ms')) {
          _deadline = now + 20000;
        } else {
          if (rhythm) {
            if (requiresHold) {
              _startLeadIn();
              return;
            }
            phase = 'countdown';
            _deadline =
                now +
                (config.input['countdown_steps'] as int) *
                    config.ms(config.input, 'countdown_step_ms');
          } else {
            _cue();
          }
        }
      case 'beatPrepare':
        _responseAnchor = boundary;
        _attempt!['cue_anchor_us'] = boundary;
        phase = 'response';
        _deadline = scheduledBeatUs + beatAfterUs;
        emit('BEAT_WINDOW_OPENED', {
          'start_us': boundary,
          'target_time_us': beatTargetUs,
        });
        tick();
      case 'response':
        if (rhythm && requiresHold && _canExtendHold(boundary)) {
          phase = 'holdTail';
          _rhythmWindowEnd = boundary;
          final nextStart = trialIndex + 1 < trialCount
              ? _beatOrigin! +
                    ((block['targets']['trials'] as List)[trialIndex +
                            1]['target_time_us']
                        as int) -
                    beatBeforeUs
              : boundary + noteDurationUs;
          _deadline = min(
            pointers[_firstHoldPointer]!.down + noteDurationUs,
            nextStart,
          );
          tick();
          return;
        }
        if (windowed || rhythm) {
          _complete(responseEnd: boundary);
          return;
        }
        _timeout = true;
        if (responsiveControls && memory) {
          if (_pendingNote != null) {
            final pending = _pendingNote!;
            _finishHeldNote(pending.key, max(0, boundary - pending.down));
          }
          _complete(responseEnd: boundary);
          return;
        }
        phase = 'release';
        if (pointers.isEmpty) _complete();
      case 'phraseEnd':
        _afterBlock();
      case 'holdTail':
        _complete(responseEnd: _rhythmWindowEnd!, holdEnd: boundary);
      case 'tail':
        phase = 'release';
        if (pointers.isEmpty) _complete();
      case 'trialFeedback':
        _begin();
      case 'intertrial':
        if (pointers.isNotEmpty ||
            now - _quietSince < config.ms(config.input, 'release_quiet_ms')) {
          _deadline = now + 20000;
        } else {
          _begin();
        }
      case 'ruleHeader':
        if (pointers.isNotEmpty ||
            now - _quietSince < config.ms(config.input, 'release_quiet_ms')) {
          _deadline = now + 20000;
        } else {
          _cue();
        }
      default:
        break;
    }
  }

  bool _canExtendHold(int end) =>
      _consumed.length == 1 &&
      _consumed.first == expected.single &&
      _actions == 1 &&
      _firstHoldUs == null &&
      pointers.containsKey(_firstHoldPointer) &&
      end - pointers[_firstHoldPointer]!.down < noteDurationUs;

  void _startLeadIn({bool demo = false}) {
    phase = 'countdown';
    _demoAfterLeadIn = demo;
    _leadStart = now;
    _leadBeatSent = -1;
    _deadline =
        now +
        (responsiveControls ? 4 * 60000000 ~/ bpm : 4 * beatIntervalUs) -
        (demo ? 0 : config.ms(config.task(taskId), 'first_target_delay_ms'));
    tick();
  }

  void _clickBeat(String owner, int index, int plannedAt) {
    emit('METRONOME_TICK', {
      'owner': owner,
      'beat_index': index,
      'scheduled_offset_us': plannedAt,
    });
    audio.add({
      'kind': 'beat',
      'key_id': 7,
      'generation': generation,
      'duration_ms': 90,
      'request_event_seq': _seq + 1,
      'context': _eventContext,
    });
    emit('AUDIO_REQUEST', {'owner': 'METRONOME', 'key_id': 7});
  }

  int get _demoInterval => rhythm
      ? 60000000 ~/ bpm
      : memory
      ? config.ms(
          Map<String, dynamic>.from(config.task(taskId)['modes'][mode]),
          'demo_onset_interval_ms',
        )
      : config.ms(config.task(taskId), 'demo_onset_interval_ms');
  void _begin({int? demoOrigin}) {
    _responsePausedUs = _userPauseCount = 0;
    trial['status'] = 'ACTIVE';
    _consumed.clear();
    _actions = _outside = _disabled = _overlap = _extra = _wrong = 0;
    _first = null;
    _short = 0;
    _dualDowns.clear();
    _firstHoldPointer = _firstHoldUs = _rhythmWindowEnd = null;
    _pendingNote = null;
    _pausedRelease = null;
    if (responsiveControls ||
        !requiresHold ||
        !(windowed || rhythm) ||
        !durationTooShort) {
      _shortKey = _shortUntil = null;
    }
    _firstResponseUs = null;
    _responseAnchor = null;
    _timeout = _correctSong = _policyHint = false;
    highlighted = null;
    _attempt = {
      'attempt_id': uuid(),
      'session_id': id,
      'block_id': block['block_id'],
      'trial_id': trial['trial_id'],
      'ordinal': attempts
          .where((a) => a['trial_id'] == trial['trial_id'])
          .length,
      'validity': 'OPEN',
      'started_offset_us': now,
      'ended_offset_us': null,
      'cue_anchor_us': null,
      'cue_confidence': 'FRAME_CALLBACK_ESTIMATE',
      'response_end_us': null,
      'active_duration_us': 0,
      'outcome': null,
      'reason_code': null,
      'result_version': config.json['metric_version'],
      'result': null,
    };
    attempts.add(_attempt!);
    emit('ATTEMPT_STARTED', {'attempt_id': _attempt!['attempt_id']});
    if (rhythm && _beatOrigin != null) {
      _skipNextDemo = false;
      _cue();
    } else if (windowed) {
      if (taskId == 'G3_SWITCH' && (target['switch_flag'] != false)) {
        phase = 'ruleHeader';
        _deadline = now + config.ms(config.task(taskId), 'rule_header_ms');
        emit('RULE_HEADER', {'rule_id': target['rule_id']});
      } else {
        _cue();
      }
    } else if (!_skipNextDemo && (memory || trialIndex == 0 || _replaySong)) {
      _replaySong = false;
      phase = 'demo';
      _demoIndex = 0;
      _demoStart = demoOrigin ?? now;
      _deadline = _demoStart;
      tick();
    } else {
      _skipNextDemo = false;
      _cue();
    }
  }

  void _cue() {
    phase = 'cue';
    _cueRequested = now;
    if (rhythm && !responsiveControls) highlighted = expected.single;
    if (responsiveControls && taskId == 'S1_GUIDED') {
      highlighted = expected.single;
    }
    if (responsiveControls && memory && showAnswer) {
      highlighted = expected.first;
    }
    if (windowed && (taskId == 'G2_INHIBITION' || showAnswer)) {
      highlighted = target['target_key'] as int?;
    }
    emit('CUE_REQUESTED', {
      'target': expected,
      if (windowed) 'trial_type': target['trial_type'],
      if (taskId == 'G3_SWITCH') 'rule_id': target['rule_id'],
      if (windowed && _lastWindowEnd != null)
        'actual_interval_us': _cueRequested! - _lastWindowEnd!,
    });
  }

  void cuePresented() {
    if (phase != 'cue') return;
    final presentedAt = now;
    if (presentedAt - _cueRequested! >
            config.ms(config.timing, 'frame_callback_max_delay_ms') ||
        rhythm &&
            presentedAt >
                scheduledBeatUs -
                    beatBeforeUs +
                    config.ms(config.timing, 'frame_callback_max_delay_ms')) {
      pause('INVALID_FRAME_LATE');
      return;
    }
    if (rhythm) {
      phase = 'beatPrepare';
      _deadline = scheduledBeatUs - beatBeforeUs;
      emit('CUE_PRESENTED', {
        'anchor_us': presentedAt,
        'confidence': 'FRAME_CALLBACK_ESTIMATE',
      });
      tick();
      return;
    }
    _responseAnchor = presentedAt;
    _attempt!['cue_anchor_us'] = presentedAt;
    phase = 'response';
    _deadline = windowed
        ? presentedAt + responseWindowUs
        : memory
        ? presentedAt +
              config.ms(config.task(taskId), 'response_per_position_timeout_ms')
        : null;
    emit('CUE_PRESENTED', {
      'anchor_us': presentedAt,
      'confidence': 'FRAME_CALLBACK_ESTIMATE',
    });
    tick();
  }

  void down(
    int pointer,
    int? key, {
    bool disabled = false,
    Json? coordinates,
  }) => _atReceipt(
    () => _down(pointer, key, disabled: disabled, coordinates: coordinates),
  );
  void _down(
    int pointer,
    int? key, {
    bool disabled = false,
    Json? coordinates,
  }) {
    tick();
    if (ended) return;
    if (inputLocked) return;
    emit('POINTER_DOWN', {
      'pointer_id': pointer,
      'key_id': key,
      ...?coordinates,
    }, context: _inputContext);
    final rawSequence = _seq;
    if (pointers.containsKey(pointer)) {
      pause('E_INPUT_PROTOCOL');
      return;
    }
    final overlap = pointers.isNotEmpty;
    pointers[pointer] = (key: key, down: now);
    if (pointers.length > config.input['max_pointers']) {
      pause('E_INPUT_LIMIT');
      return;
    }
    if (!responding) {
      if (rhythm &&
          _beatOrigin != null &&
          {'beatPrepare', 'cue', 'holdTail'}.contains(phase)) {
        emit('OUT_OF_WINDOW', {
          'pointer_id': pointer,
          'key_id': key,
          'disabled': disabled,
          'overlap': overlap,
          'source_event_seq': rawSequence,
        }, context: _inputContext);
        if (key != null && !disabled) {
          emit('KEY_DOWN', {
            'pointer_id': pointer,
            'key_id': key,
            'overlap': overlap,
            'active_pointer_count': pointers.length,
            'source_event_seq': rawSequence,
          }, context: _inputContext);
          _userSound(pointer, key, context: _inputContext);
        }
      }
      if (windowed && phase == 'intertrial') {
        emit('INTERTRIAL_PRESS', {
          'pointer_id': pointer,
          'key_id': key,
          'source_event_seq': rawSequence,
        }, context: _inputContext);
      }
      return;
    }
    _actions++;
    _first ??= now;
    if (key == null || disabled) {
      if (disabled) {
        _disabled++;
      } else {
        _outside++;
      }
      emit('OUTSIDE_PRESS', {
        'pointer_id': pointer,
        'key_id': key,
        'overlap': overlap,
        'active_pointer_count': pointers.length,
        'disabled': disabled,
        'source_event_seq': rawSequence,
      });
      return;
    }
    emit('KEY_DOWN', {
      'pointer_id': pointer,
      'key_id': key,
      'overlap': overlap,
      'active_pointer_count': pointers.length,
      'source_event_seq': rawSequence,
    });
    _userSound(pointer, key);
    if (dual && phase == 'response') {
      _consumed.add(key);
      _dualDowns.putIfAbsent(
        key,
        () => now - _responseAnchor! - _responsePausedUs,
      );
      _extra = max(0, _consumed.length - 2);
      return;
    }
    if (overlap) {
      _overlap++;
      return;
    }
    if (phase != 'response') {
      _extra++;
      return;
    }
    if (requiresHold) {
      _shortUntil = null;
      _shortKey = null;
    }
    if (windowed || rhythm) {
      _firstHoldPointer ??= pointer;
      if (_consumed.isNotEmpty) _extra++;
      _consumed.add(key);
      _firstResponseUs ??= now - _responseAnchor! - _responsePausedUs;
    } else if (memory) {
      if (requiresHold) {
        _pendingNote = (pointer: pointer, key: key, down: now);
        return;
      }
      _consumed.add(key);
      if (_consumed.length == expected.length) {
        phase = 'tail';
        _deadline = now + config.ms(config.task(taskId), 'tail_observation_ms');
      } else {
        _deadline =
            now +
            config.ms(config.task(taskId), 'response_per_position_timeout_ms');
      }
    } else if (key == expected.single) {
      _correctSong = !requiresHold;
      if (requiresHold) _pendingNote = (pointer: pointer, key: key, down: now);
      phase = 'release';
    } else {
      _wrong++;
    }
  }

  void _userSound(int pointer, int key, {Json? context}) {
    audio.add({
      'kind': 'down',
      'pointer': pointer,
      'key_id': key,
      'generation': generation,
      'request_event_seq': _seq + 1,
      'context': {..._eventContext, ...?context},
    });
    emit('AUDIO_REQUEST', {
      'owner': 'USER',
      'key_id': key,
      'generation': generation,
    }, context: context);
  }

  void move(int pointer, Json coordinates) {
    if (!_enforceBudget()) {
      emit('POINTER_MOVE', {'pointer_id': pointer, ...coordinates});
    }
  }

  void up(int pointer, {bool cancel = false, Json? coordinates}) =>
      _atReceipt(() => _up(pointer, cancel: cancel, coordinates: coordinates));
  void _up(int pointer, {bool cancel = false, Json? coordinates}) {
    tick();
    if (ended) return;
    if (inputLocked && !pointers.containsKey(pointer)) return;
    final inputContext =
        rhythm && phase == 'holdTail' && pointer == _firstHoldPointer
        ? _eventContext
        : _inputContext;
    emit(cancel ? 'POINTER_CANCEL' : 'POINTER_UP', {
      ...?coordinates,
      'pointer_id': pointer,
      'key_id': pointers[pointer]?.key,
    }, context: inputContext);
    if (!cancel && pointers[pointer]?.key != null) {
      emit('KEY_UP', {
        'pointer_id': pointer,
        'key_id': pointers[pointer]?.key,
        'source_event_seq': _seq,
        'overlap': pointers.length > 1,
        'active_pointer_count': pointers.length,
      }, context: inputContext);
    }
    final pressed = pointers[pointer];
    if (requiresHold && _attempt != null && !cancel && pressed != null) {
      final heldUs = max(0, visualNow - pressed.down);
      if (pointer == _firstHoldPointer && _firstHoldUs == null) {
        _firstHoldUs = heldUs;
        if (heldUs < noteDurationUs) _showShort(pressed.key, heldUs);
      }
      if (_pendingNote?.pointer == pointer) {
        if (phase == 'paused') {
          _pausedRelease = (key: _pendingNote!.key, duration: heldUs);
        } else {
          _finishHeldNote(_pendingNote!.key, heldUs);
        }
      }
    }
    audio.add({'kind': 'up', 'pointer': pointer, 'generation': generation});
    pointers.remove(pointer);
    if (pointers.isEmpty) _quietSince = now;
    if (cancel && (responding || _pendingNote != null || phase == 'holdTail')) {
      pause('E_INPUT_CANCEL');
      return;
    }
    if (phase == 'release' && pointers.isEmpty) _complete();
    if (phase == 'holdTail' && _firstHoldUs != null) {
      _complete(responseEnd: _rhythmWindowEnd!);
    }
  }

  void _showShort(int? key, int duration) {
    _shortKey = key;
    _shortDuration = duration;
    _shortUntil = now + 1200000;
    emit('HOLD_TOO_SHORT', {
      'key_id': key,
      'held_us': duration,
      'required_us': noteDurationUs,
    });
  }

  void _finishHeldNote(int key, int duration) {
    _pendingNote = null;
    if (duration < noteDurationUs) {
      _short++;
      _showShort(key, duration);
      phase = 'response';
      return;
    }
    _shortUntil = null;
    _shortKey = null;
    if (memory) {
      _consumed.add(key);
      if (responsiveControls && showAnswer) {
        highlighted = _consumed.length < expected.length
            ? expected[_consumed.length]
            : null;
      }
      if (_consumed.length == expected.length) {
        phase = 'tail';
        _deadline = now + config.ms(config.task(taskId), 'tail_observation_ms');
      } else {
        _deadline =
            now +
            config.ms(config.task(taskId), 'response_per_position_timeout_ms');
      }
    } else {
      _correctSong = true;
      phase = 'release';
    }
  }

  void _complete({int? responseEnd, int? holdEnd}) {
    final completedAt = responseEnd ?? now;
    var positions = 0, prefix = 0;
    for (var i = 0; memory && i < _consumed.length; i++) {
      if (_consumed[i] == expected[i]) positions++;
      if (prefix == i && _consumed[i] == expected[i]) prefix++;
    }
    final full =
        !_timeout &&
        positions == expected.length &&
        _outside + _disabled + _overlap + _extra + _short == 0;
    final dualGap =
        dual &&
            _actions == 2 &&
            _outside + _disabled == 0 &&
            _consumed.length == 2 &&
            _consumed.toSet().containsAll(expected)
        ? (_dualDowns[expected[0]]! - _dualDowns[expected[1]]!).abs()
        : null;
    var outcome = dual
        ? dualOutcome(
            expected,
            _consumed,
            _actions,
            _outside + _disabled,
            dualGap,
            dualToleranceUs,
          )
        : windowed || rhythm
        ? windowOutcome(
            {...target, if (rhythm) 'trial_type': 'GO'},
            _actions,
            _consumed,
            _outside + _disabled + _overlap,
          )
        : memory
        ? (_timeout
              ? 'TIMEOUT'
              : full
              ? 'FULL_CORRECT'
              : 'SEQUENCE_ERROR')
        : 'COMPLETED_NOTE';
    final heldUs =
        _firstHoldUs ??
        (pointers[_firstHoldPointer] == null
            ? 0
            : max(
                0,
                (holdEnd ??
                        (rhythm && _rhythmWindowEnd != null
                            ? now
                            : completedAt)) -
                    pointers[_firstHoldPointer]!.down,
              ));
    final holdComplete = !requiresHold
        ? true
        : memory
        ? _consumed.length == expected.length
        : taskId == 'S1_GUIDED'
        ? _correctSong
        : heldUs >= noteDurationUs;
    if (requiresHold && outcome == 'HIT' && !holdComplete) {
      outcome = 'TOO_SHORT';
      if (!durationTooShort) _showShort(_consumed.first, heldUs);
    }
    final duration = max(0, completedAt - _responseAnchor! - _responsePausedUs);
    final result = <String, dynamic>{
      'schema_version': 1,
      'outcome': outcome,
      'response_action_count': _actions,
      'outside_count': _outside,
      'disabled_count': _disabled,
      'overlap_count': _overlap,
      'extra_count': _extra,
      'first_down_offset_us': _first,
      'active_duration_us': duration,
      'paused_duration_us': _responsePausedUs,
      'user_pause_count': _userPauseCount,
      'assisted': trial['assisted'] == 1,
      'help_count': trial['help_count'],
      'policy_hint_count': trial['policy_hint_count'],
      'interrupted_retry_count': trial['interrupted_retry_count'],
      if (requiresHold) ...{
        'hold_policy': 'HOLD_400_V1',
        'required_hold_us': noteDurationUs,
        'short_press_count': windowed || rhythm
            ? (target['trial_type'] != 'NO_GO' &&
                      _consumed.isNotEmpty &&
                      heldUs < noteDurationUs
                  ? 1
                  : 0)
            : _short,
        'hold_complete': target['trial_type'] == 'NO_GO' ? true : holdComplete,
        'first_hold_us': memory || taskId == 'S1_GUIDED' ? null : heldUs,
      },
      if (memory) ...{
        'expected_keys': expected,
        'consumed_keys': List<int>.from(_consumed),
        'position_correct_count': positions,
        'expected_position_count': expected.length,
        'omitted_position_count': expected.length - _consumed.length,
        'longest_correct_prefix': prefix,
        'full_correct': full,
      },
      if (taskId == 'S1_GUIDED') ...{
        'target_key': expected.single,
        'correct_down_count': _correctSong ? 1 : 0,
        'wrong_press_count': _wrong,
        'first_pass':
            _actions == 1 &&
            _wrong + _outside + _disabled + _overlap + _extra + _short == 0,
      },
      if (dual) ...{
        'left_target': expected[0],
        'right_target': expected[1],
        'left_down_us': _dualDowns[expected[0]],
        'right_down_us': _dualDowns[expected[1]],
        'gap_us': dualGap,
        'gap_tolerance_us': dualToleranceUs,
        'consumed_keys': List<int>.from(_consumed),
      },
      if (windowed && !dual) ...{
        'trial_type': target['trial_type'],
        'target_key': target['target_key'],
        'consumed_keys': List<int>.from(_consumed),
        'first_response_key': _consumed.isEmpty ? null : _consumed.first,
        'rt_us': outcome == 'HIT' ? _firstResponseUs : null,
        if (taskId == 'G3_SWITCH') ...{
          'rule_id': target['rule_id'],
          'r': target['r'],
          's': target['s'],
          'switch_flag': target['switch_flag'],
        },
      },
      if (rhythm) ...{
        'target_key': expected.single,
        'target_time_us': beatTargetUs,
        'beat_reference': 'PLANNED_BEAT_REFERENCE',
        'consumed_keys': List<int>.from(_consumed),
        'first_response_key': _consumed.isEmpty ? null : _consumed.first,
        'beat_error_us': outcome == 'HIT'
            ? _firstResponseUs! - beatBeforeUs
            : null,
      },
    };
    _attempt!.addAll({
      'validity': 'VALID',
      'ended_offset_us': max(completedAt, now),
      'response_end_us': completedAt,
      'active_duration_us': duration,
      'outcome': outcome,
      'result': result,
    });
    trial['status'] = 'COMPLETED';
    block['valid_trial_count'] = (block['valid_trial_count'] as int) + 1;
    block['active_duration_us'] =
        (block['active_duration_us'] as int) + duration;
    completed++;
    emit('ATTEMPT_FINALIZED', result);
    emit('TRIAL_FINALIZED', {'trial_id': trial['trial_id']});
    _attempt = null;
    if (windowed) _lastWindowEnd = completedAt;
    highlighted = null;
    if (responsiveControls) _shortKey = _shortUntil = null;
    if (trialIndex + 1 == trialCount) {
      block.addAll({
        'status': 'COMPLETED',
        'ended_offset_us': now,
        'ended_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
      final results = attempts
          .where(
            (a) =>
                a['block_id'] == block['block_id'] && a['validity'] == 'VALID',
          )
          .map((a) => Map<String, dynamic>.from(a['result']))
          .toList();
      final decision = policy.evaluate(
        level,
        results,
        outOfWindow: events
            .where(
              (e) =>
                  e['block_id'] == block['block_id'] &&
                  e['kind'] == 'OUT_OF_WINDOW',
            )
            .length,
      );
      decisions.add({
        'decision_id': uuid(),
        'session_id': id,
        'block_id': block['block_id'],
        'decision_key': block['commit_id'],
        'adaptive_version': config.json['adaptive_version'],
        'source': 'AUTO',
        'action': decision.action,
        'reason_code': decision.reason,
        'level_before': level,
        'level_after': decision.after,
        'parameters_before': parameters,
        'parameters_after': parametersAt(decision.after),
        'evidence': {
          'successes': results
              .where((r) => AdaptivePolicy.success(taskId, r))
              .length,
          'valid_trials': results.length,
          if (rhythm)
            'out_of_window': events
                .where(
                  (e) =>
                      e['block_id'] == block['block_id'] &&
                      e['kind'] == 'OUT_OF_WINDOW',
                )
                .length,
        },
        'decided_offset_us': now,
      });
      level = decision.after;
      emit('BLOCK_COMMITTED', {
        'commit_id': block['commit_id'],
        'action': decision.action,
      });
      if (rhythm && responsiveControls && now < phraseEndUs) {
        finishingPhrase = true;
        phase = 'phraseEnd';
        _deadline = phraseEndUs;
      } else {
        _afterBlock();
      }
    } else {
      trialIndex++;
      if (rhythm) {
        _begin();
      } else if (windowed) {
        phase = 'intertrial';
        _deadline = completedAt + config.ms(config.timing, 'trial_gap_ms');
      } else if (memory) {
        phase = 'trialFeedback';
        _deadline = now + 1000000;
      } else {
        _begin();
      }
    }
  }

  void _afterBlock() {
    finishingPhrase = false;
    if (slot + 1 == config.blocks) {
      finish('COMPLETED');
    } else {
      phase = 'feedback';
    }
  }

  void nextBlock() {
    if (phase != 'feedback') return;
    slot++;
    _block();
    phase = 'waiting';
    _quietSince = now;
  }

  void pause(String reason) {
    if (ended) return;
    if (finishingPhrase && phase != 'paused') {
      _phrasePauseRemainingUs = max(0, phraseEndUs - now);
    }
    if (reason == 'USER' && phase != 'paused') {
      _pausedPhase = phase;
      _pausedAt = now;
      _pausedHighlight = highlighted;
      if (_attempt != null) {
        _userPauseCount++;
        trial['assisted'] = 1;
        policy.upgradeAllowed = false;
        policy.highStreak = 0;
      }
      pauseReason = reason;
      phase = 'paused';
      highlighted = null;
      generation++;
      audio.add({'kind': 'off', 'generation': generation});
      emit('PAUSE_REQUESTED', {
        'reason_code': reason,
        'previous_phase': _pausedPhase,
      });
      return;
    }
    if (phase == 'paused') {
      if (_pausedPhase != null && reason != 'USER') {
        _interruptAttempt(reason);
        pauseReason = reason;
        _deadline = null;
        emit('PAUSE_REQUESTED', {'reason_code': reason});
      }
      if (errors.record(reason)) {
        pauseReason = reason;
        emit('ERROR', {
          'error_code': reason,
          'recoverable': true,
          'phase': phase,
          'same_code_count': errors.count,
        });
      }
      return;
    }
    pauseReason = reason;
    if (errors.record(reason)) {
      emit('ERROR', {
        'error_code': reason,
        'recoverable': true,
        'phase': phase,
        'same_code_count': errors.count,
      });
    }
    _interruptAttempt(reason);
    phase = 'paused';
    _deadline = null;
    highlighted = null;
    generation++;
    audio.add({'kind': 'off', 'generation': generation});
    emit('PAUSE_REQUESTED', {'reason_code': reason});
  }

  void _interruptAttempt(String reason) {
    final endedAt = now;
    final suspended = _pausedAt == null || _responseAnchor == null
        ? 0
        : endedAt - _pausedAt!;
    if (_attempt != null && _attempt!['validity'] == 'OPEN') {
      _attempt!.addAll({
        'validity': reason.startsWith('INVALID') ? 'INVALID' : 'INTERRUPTED',
        'reason_code': reason,
        'ended_offset_us': endedAt,
        'active_duration_us': _responseAnchor == null
            ? 0
            : max(
                0,
                endedAt - _responseAnchor! - _responsePausedUs - suspended,
              ),
      });
      _attempt = null;
    }
    _pausedPhase = null;
    _pausedAt = null;
    _pausedHighlight = null;
  }

  void resume({bool help = false, bool replay = false}) {
    if (phase != 'paused') return;
    if (finishingPhrase && _pausedPhase == null) {
      _beatOrigin = _beatOrigin! + now + _phrasePauseRemainingUs - phraseEndUs;
      _deadline = now + _phrasePauseRemainingUs;
      phase = 'phraseEnd';
      generation++;
      emit('RESUME_REQUESTED', {'continue_existing': true});
      return;
    }
    if (_pausedPhase != null && (finishingPhrase || !help && !replay)) {
      final resumedAt = now;
      final pausedUs = resumedAt - _pausedAt!;
      if (_responseAnchor != null) _responsePausedUs += pausedUs;
      if (_deadline != null) _deadline = _deadline! + pausedUs;
      if (_cueRequested != null) _cueRequested = _cueRequested! + pausedUs;
      if (_highlightOff != null) _highlightOff = _highlightOff! + pausedUs;
      if (_demoStart != null) _demoStart = _demoStart! + pausedUs;
      if (_leadStart != null) _leadStart = _leadStart! + pausedUs;
      if (_rhythmWindowEnd != null) {
        _rhythmWindowEnd = _rhythmWindowEnd! + pausedUs;
      }
      if (_pendingNote != null) {
        _pendingNote = (
          pointer: _pendingNote!.pointer,
          key: _pendingNote!.key,
          down: _pendingNote!.down + pausedUs,
        );
      }
      if (rhythm && _beatOrigin != null) _beatOrigin = _beatOrigin! + pausedUs;
      _quietSince += pausedUs;
      for (final entry in pointers.entries.toList()) {
        pointers[entry.key] = (
          key: entry.value.key,
          down: entry.value.down + pausedUs,
        );
      }
      phase = _pausedPhase!;
      highlighted = _pausedHighlight;
      _pausedPhase = null;
      _pausedAt = null;
      _pausedHighlight = null;
      generation++;
      emit('RESUME_REQUESTED', {
        'continue_existing': true,
        'pause_duration_us': pausedUs,
      });
      if (_pausedRelease != null) {
        final released = _pausedRelease!;
        _pausedRelease = null;
        _finishHeldNote(released.key, released.duration);
      }
      if (phase == 'release' && pointers.isEmpty) _complete();
      return;
    }
    if (_pausedPhase != null) _interruptAttempt('INTERRUPTED_HELP');
    if (trial['status'] == 'COMPLETED') {
      if (block['status'] == 'COMPLETED') {
        phase = 'feedback';
        return;
      }
      trialIndex++;
    } else {
      trial['assisted'] = 1;
      trial['interrupted_retry_count'] =
          (trial['interrupted_retry_count'] as int) + 1;
    }
    if (help) {
      emit('HELP_REQUESTED', {'trial_id': trial['trial_id']});
      trial['help_count'] = (trial['help_count'] as int) + 1;
      _hintTrial = trial['trial_id'];
      _replaySong = !cognitive;
    }
    if (replay) {
      _hintTrial = null;
      _replaySong = !cognitive;
      emit('DEMO_REPLAY_REQUESTED', {'trial_id': trial['trial_id']});
    }
    if (rhythm && (help || replay)) _demoStart = null;
    _skipNextDemo = !(help || replay);
    if (rhythm) _beatOrigin = null;
    generation++;
    phase = 'waiting';
    _quietSince = now;
    emit('RESUME_REQUESTED', {'assisted': true, 'help': help});
  }

  void lower() {
    if (phase != 'paused') return;
    if (block['status'] == 'COMPLETED') return;
    if (level == 1) {
      resume(help: true);
      return;
    }
    if (_pausedPhase != null) _interruptAttempt('INTERRUPTED_MANUAL');
    final before = level;
    final unfinished = trials
        .where(
          (t) =>
              t['block_id'] == block['block_id'] && t['status'] != 'COMPLETED',
        )
        .toList();
    for (final t in unfinished) {
      t['status'] = 'CANCELLED_MANUAL';
    }
    block['status'] = 'PARTIAL_MANUAL';
    block['ended_offset_us'] = now;
    level--;
    policy.highStreak = 0;
    policy.upgradeAllowed = false;
    planned = planned - unfinished.length + trialCount;
    decisions.add({
      'decision_id': uuid(),
      'session_id': id,
      'block_id': block['block_id'],
      'decision_key': uuid(),
      'adaptive_version': config.json['adaptive_version'],
      'source': 'USER',
      'action': 'DOWN',
      'reason_code': 'USER_LOWER',
      'level_before': before,
      'level_after': level,
      'parameters_before': block['parameters'],
      'parameters_after': parameters,
      'evidence': {'cancelled': unfinished.length},
      'decided_offset_us': now,
    });
    _block();
    generation++;
    phase = 'waiting';
    _quietSince = now;
  }

  void finish(String status) {
    if (ended) return;
    if (status != 'COMPLETED') {
      pause('INTERRUPTED_EXIT');
      if (block['status'] != 'COMPLETED') block['status'] = 'INTERRUPTED';
      for (final t in trials.where(
        (t) => t['status'] == 'PLANNED' || t['status'] == 'ACTIVE',
      )) {
        t['status'] = 'INTERRUPTED';
      }
    }
    finishStatus = status;
    finishedAt = now;
    phase = 'finished';
    generation++;
    audio.add({'kind': 'off', 'generation': generation});
    emit('SESSION_FINALIZED', {
      'status': status,
      'completed': completed,
      'planned': planned,
    });
  }

  void reconfigure(Json snapshot) {
    if (ended) return;
    pause('E_LAYOUT_CHANGED');
    layoutSnapshot = snapshot;
    policy.upgradeAllowed = false;
    policy.highStreak = 0;
    if (block['status'] != 'COMPLETED') {
      final unfinished = trials
          .where(
            (t) =>
                t['block_id'] == block['block_id'] &&
                t['status'] != 'COMPLETED',
          )
          .toList();
      for (final t in unfinished) {
        t['status'] = 'CANCELLED_RECONFIGURE';
      }
      block['status'] = 'INTERRUPTED';
      block['ended_offset_us'] = now;
      planned = planned - unfinished.length + trialCount;
      _block();
    }
    emit('ENVIRONMENT_RECONFIGURED', {'layout_snapshot': snapshot});
  }

  Json get _eventContext => {
    'block_id': block['block_id'],
    'trial_id': trial['trial_id'],
    'attempt_id': _attempt?['attempt_id'],
  };
  Json? get _inputContext =>
      windowed && phase == 'intertrial' ||
          rhythm &&
              _beatOrigin != null &&
              {'cue', 'beatPrepare', 'holdTail', 'phraseEnd'}.contains(phase)
      ? {'trial_id': null, 'attempt_id': null}
      : null;

  Json summary() => PracticeMetrics.build(
    taskId: taskId,
    version: config.json['metric_version'] as String,
    attempts: attempts,
    trials: trials,
    events: events,
    planned: planned,
    complete: finishStatus == 'COMPLETED',
  );
}
