import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/contracts.dart';
import '../domain/audio_settings.dart';
import '../domain/history.dart';
import '../domain/piece_performance.dart';
import '../domain/intro_lessons.dart';
import '../domain/task_engine.dart';
import '../domain/practice_metrics.dart';
import 'record_contract.dart';
import 'record_snapshot.dart';
import 'database_safety.dart';
import 'record_integrity.dart';

class _WriteCache {
  final Map<String, String> rows = {};
  final Map<int, String> events = {};
  final Set<String> summaryBlocks = {};
}

class PracticeRepository {
  late Database db;
  late Json profile;
  final Map<String, _WriteCache> _cache = {};
  final safety = DatabaseSafety();
  Future<void> open(String directory, String locale) async {
    _cache.clear();
    await safety.prepare('$directory/practice.db');
    db = await openDatabase(
      '$directory/practice.db',
      version: DatabaseSafety.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys=ON');
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA synchronous=FULL');
        await db.rawQuery('PRAGMA busy_timeout=5000');
      },
      onCreate: (db, version) async {
        final sql = await rootBundle.loadString('assets/config/schema.sql');
        final cleaned = sql
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('--'))
            .join('\n');
        for (final statement in cleaned.split(';')) {
          if (statement.trim().isNotEmpty &&
              !statement.trim().startsWith('PRAGMA')) {
            await db.execute(statement);
          }
        }
        await db.insert('schema_migrations', {
          'version': 1,
          'applied_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
          'migration_checksum': digest(sql),
        });
        await DatabaseSafety.migrate(db, 1, DatabaseSafety.version);
      },
      onUpgrade: DatabaseSafety.migrate,
      onDowngrade: (_, _, _) =>
          throw StateError('E_SCHEMA_VERSION: database preserved'),
    );
    final migrations = await db.query('schema_migrations', orderBy: 'version');
    final schema = await rootBundle.loadString('assets/config/schema.sql');
    if (migrations.length != 3 ||
        migrations.first['version'] != 1 ||
        migrations.first['migration_checksum'] != digest(schema) ||
        migrations[1]['version'] != 2 ||
        migrations[1]['migration_checksum'] !=
            digest(DatabaseSafety.migration2) ||
        migrations.last['version'] != 3 ||
        migrations.last['migration_checksum'] !=
            digest(DatabaseSafety.migration3)) {
      await db.close();
      throw StateError('E_SCHEMA_VERSION: database preserved');
    }
    await db.transaction((tx) async {
      final open = await tx.query(
        'sessions',
        where: "status NOT IN ('COMPLETED','EXITED','RECOVERED_INTERRUPTED')",
      );
      for (final session in open) {
        final id = session['session_id'];
        await tx.update(
          'attempts',
          {
            'validity': 'INTERRUPTED',
            'reason_code': 'INTERRUPTED_PROCESS_DEATH',
            'outcome': null,
          },
          where: "session_id=? AND validity='OPEN'",
          whereArgs: [id],
        );
        await tx.update(
          'blocks',
          {'status': 'INTERRUPTED'},
          where: "session_id=? AND status IN ('PLANNED','ACTIVE')",
          whereArgs: [id],
        );
        await tx.update(
          'trials',
          {'status': 'INTERRUPTED'},
          where: "session_id=? AND status IN ('PLANNED','ACTIVE')",
          whereArgs: [id],
        );
        final last =
            Sqflite.firstIntValue(
              await tx.rawQuery(
                'SELECT MAX(seq) FROM events WHERE session_id=?',
                [id],
              ),
            ) ??
            0;
        await tx.insert('events', {
          'session_id': id,
          'seq': last + 1,
          'offset_us': null,
          'clock_epoch_id': uuid(),
          'kind': 'ERROR',
          'payload_version': 1,
          'payload_json': canonical({
            'reason_code': 'INTERRUPTED_PROCESS_DEATH',
            'recovered_at_utc_ms': DateTime.now()
                .toUtc()
                .millisecondsSinceEpoch,
          }),
        });
        await tx.update(
          'sessions',
          {
            'status': 'RECOVERED_INTERRUPTED',
            'ended_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
            'terminal_reason': 'INTERRUPTED_PROCESS_DEATH',
          },
          where: 'session_id=?',
          whereArgs: [id],
        );
        final trialRows = await tx.query(
          'trials',
          where: 'session_id=?',
          whereArgs: [id],
        );
        final allAttempts = await tx.query(
          'attempts',
          where: 'session_id=?',
          whereArgs: [id],
        );
        final eventRows = await tx.query(
          'events',
          where: 'session_id=?',
          whereArgs: [id],
          orderBy: 'seq',
        );
        final recoveredSummary = PracticeMetrics.build(
          taskId: session['task_id'] as String,
          version: session['metric_version'] as String,
          attempts: allAttempts
              .map(
                (a) => {
                  ...a,
                  'result': a['result_json'] == null
                      ? null
                      : jsonDecode(a['result_json'] as String),
                },
              )
              .toList(),
          trials: trialRows.map((t) => Map<String, dynamic>.from(t)).toList(),
          events: eventRows
              .map(
                (e) => {
                  ...e,
                  'payload': jsonDecode(e['payload_json'] as String),
                },
              )
              .toList(),
          planned: session['planned_target_count'] as int,
          complete: false,
          qualityFlags: ['PROCESS_DEATH'],
        );
        await tx.insert('summaries', {
          'summary_id': uuid(),
          'session_id': id,
          'scope': 'SESSION',
          'scope_key': 'SESSION',
          'metric_version': session['metric_version'],
          'calculated_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
          'source_last_seq': last + 1,
          'result_json': canonical(recoveredSummary),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final existing = await tx.query('profiles');
      if (existing.isEmpty) {
        await tx.insert('profiles', {
          'profile_id': uuid(),
          'created_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
          'locale': locale,
          'mode': 'ASSIST',
          'onboarding_completed': 0,
          'settings_json': canonical({
            'schema_version': 1,
            'sound_enabled': true,
            'gain_permille': defaultKeyGain,
            'speech_gain_permille': defaultSpeechGain,
            'volume_controls_version': 2,
            'speech_enabled': true,
            'decorative_animation_enabled': true,
            'high_contrast': false,
            'device_local_id': uuid(),
          }),
        });
      }
    });
    await reload();
    final oldSettings = jsonDecode(profile['settings_json'] as String) as Json;
    if (oldSettings['volume_controls_version'] != 2) {
      await settingsUpdate(settings: normalizedAudioSettings(oldSettings));
    }
    await DatabaseSafety.verify(db);
    await safety.committed();
  }

  Future<void> reload() async =>
      profile = _checkedProfile((await db.query('profiles')).single);
  Json _checkedProfile(Map<String, Object?> row) {
    final result = Map<String, dynamic>.from(row);
    RecordIntegrity.profile(result);
    RecordContract.enumeration(result, 'locale', {'zh-Hans', 'en'});
    RecordContract.enumeration(result, 'mode', {'ASSIST', 'CHALLENGE'});
    final settings = jsonDecode(result['settings_json'] as String) as Json;
    RecordContract.version(settings);
    for (final key in [
      'sound_enabled',
      'speech_enabled',
      'decorative_animation_enabled',
      'high_contrast',
    ]) {
      if (settings[key] is! bool) RecordContract.fail(key);
    }
    RecordContract.integer(settings, 'gain_permille');
    RecordContract.string(settings, 'device_local_id');
    if (settings['gain_permille'] > 1000) RecordContract.fail('gain_permille');
    if (settings.containsKey('speech_gain_permille')) {
      RecordContract.integer(settings, 'speech_gain_permille');
      if (settings['speech_gain_permille'] > 1000) {
        RecordContract.fail('speech_gain_permille');
      }
    }
    if (settings.containsKey('dual_touch_check_completed') &&
        settings['dual_touch_check_completed'] is! bool) {
      RecordContract.fail('dual_touch_check_completed');
    }
    if (settings['selected_song_id'] != null &&
        settings['selected_song_id'] is! String) {
      RecordContract.fail('selected_song_id');
    }
    return result;
  }

  Json get settings => normalizedAudioSettings(
    jsonDecode(profile['settings_json'] as String) as Json,
  );
  Future<void> settingsUpdate({
    String? locale,
    String? mode,
    Json? settings,
    bool onboard = false,
  }) async {
    if (settings != null) settings = normalizeRecordText(settings) as Json;
    _checkedProfile({
      ...profile,
      'locale': ?locale,
      'mode': ?mode,
      if (settings != null) 'settings_json': canonical(settings),
    });
    await db.update(
      'profiles',
      {
        'locale': ?locale,
        'mode': ?mode,
        if (settings != null) 'settings_json': canonical(settings),
        if (onboard) 'onboarding_completed': 1,
      },
      where: 'profile_id=?',
      whereArgs: [profile['profile_id']],
    );
    await reload();
  }

  Future<int> level(String taskId, PracticeConfig config) async {
    final rows = await db.query(
      'profile_task_state',
      where: 'profile_id=? AND task_id=? AND mode=? AND parameter_profile_version=?',
      whereArgs: [
        profile['profile_id'],
        taskId,
        profile['mode'],
        config.json['version'],
      ],
    );
    return rows.isEmpty
        ? config.initial(taskId, profile['mode'] as String)
        : rows.single['level'] as int;
  }

  Future<void> create(
    TaskEngine engine,
    Json environment,
    Json? content,
    String timezone,
  ) async {
    final storage = await File(db.path).length();
    final wal = File('${db.path}-wal');
    if (storage + (await wal.exists() ? await wal.length() : 0) >=
        engine.config.json['recording']['database_max_bytes']) {
      throw StateError('E_STORAGE_LOW');
    }
    final snapshot = {
      'parameter_profile': engine.config.json,
      'task_id': engine.taskId,
      'task_version': engine.config.task(engine.taskId)['task_version'],
      'content': content,
      'mode': engine.mode,
      'rule_version': engine.dual
          ? 'M2-1.0.0'
          : engine.responsiveControls
          ? '2.1.0'
          : engine.requiresHold
          ? '2.0.0'
          : '1.0.0',
      'instruction_locale': profile['locale'],
      'initial_level': engine.level,
      'required_block_slots': engine.config.blocks,
      'review_status': 'UNREVIEWED',
      'review_record_id': null,
    };
    RecordIntegrity.environment(environment);
    RecordIntegrity.snapshot(snapshot);
    if (environment['clock_source'] != null &&
        environment['clock_source'] != 'DART_RECEIPT') {
      RecordContract.fail('clock_source');
    }
    final data = await _capture(engine);
    final session = {
      'session_id': engine.id,
      'profile_id': profile['profile_id'],
      'task_id': engine.taskId,
      'task_version': engine.config.task(engine.taskId)['task_version'],
      'content_id': content?['content_id'],
      'content_version': content?['version'],
      'parameter_profile_version': engine.config.json['version'],
      'adaptive_version': engine.config.json['adaptive_version'],
      'metric_version': engine.config.json['metric_version'],
      'session_locale': profile['locale'],
      'mode': engine.mode,
      'input_source': 'TOUCH',
      'review_status': 'UNREVIEWED',
      'clock_epoch_id': engine.epoch,
      'clock_source': 'DART_RECEIPT',
      'rng_algorithm': 'rng-lcg32-1',
      'rng_seed': engine.block['targets']['rng_state_before'],
      'started_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      'session_timezone': timezone,
      'session_utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      'status': 'PREPARING',
      'required_block_slots': engine.config.blocks,
      'planned_target_count_initial': engine.planned,
      'planned_target_count': engine.planned,
      'snapshot_json': canonical(snapshot),
      'snapshot_sha256': digest(snapshot),
      'environment_json': canonical(environment),
    };
    final cache = await db.transaction((tx) async {
      await tx.insert('sessions', session);
      return _persist(tx, engine, data);
    });
    _cache.clear();
    _cache[engine.id] = cache;
  }

  Future<Json> _capture(TaskEngine engine) {
    final request = {
      'id': engine.id,
      'epoch': engine.epoch,
      'task_id': engine.taskId,
      'slots': engine.config.blocks,
      'maximum': engine.config.maximum(engine.taskId),
      'metric_version': engine.config.json['metric_version'],
      'prepare_rows': true,
      'data': {
        'blocks': engine.blocks,
        'trials': engine.trials,
        'attempts': engine.attempts,
        'events': engine.events,
        'decisions': engine.decisions,
        'level': engine.level,
        'planned': engine.planned,
        'status': engine.sessionStatus,
        'finish': engine.finishStatus,
        'duration': engine.validDuration,
        'interrupted': engine.interruptedDuration,
        'now': engine.finishedAt ?? engine.now,
        'auto_upgrade': engine.policy.upgradeAllowed,
        'resource_limited': engine.resourceLimited,
      },
    };
    // compute sends a frozen copy before yielding; scoring and audio can continue
    // while validation, statistics and row encoding run off the UI isolate.
    return compute(
      prepareRecordSnapshot,
      request,
      debugLabel: 'practice-record',
    );
  }

  Future<void> persist(TaskEngine engine) async {
    final data = await _capture(engine);
    final cache = await db.transaction((tx) => _persist(tx, engine, data));
    _cache[engine.id] = cache;
  }

  Future<_WriteCache> _persist(
    Transaction tx,
    TaskEngine engine,
    Json data,
  ) async {
    final session = (await tx.query(
      'sessions',
      where: 'session_id=?',
      whereArgs: [engine.id],
    )).single;
    if (session['snapshot_sha256'] !=
        digest(jsonDecode(session['snapshot_json'] as String))) {
      throw StateError('E_SNAPSHOT_HASH');
    }
    final terminal = {
      'COMPLETED',
      'EXITED',
      'RECOVERED_INTERRUPTED',
    }.contains(session['status']);
    if (terminal && session['status'] != data['finish']) {
      throw StateError('E_TERMINAL_SESSION');
    }
    final previous = _cache[engine.id];
    final cache = _WriteCache();
    if (previous != null) {
      cache.rows.addAll(previous.rows);
      cache.events.addAll(previous.events);
      cache.summaryBlocks.addAll(previous.summaryBlocks);
    } else {
      final existing = await tx.query(
        'events',
        where: 'session_id=?',
        whereArgs: [engine.id],
      );
      for (final event in existing) {
        cache.events[event['seq'] as int] = canonical(event);
      }
    }
    Future<void> row(
      String table,
      Json source,
      String primary,
      Map<String, String> jsonFields,
    ) async {
      final prepared = data['_prepared_rows']?[table]?['${source[primary]}'];
      final values = prepared != null
          ? Map<String, dynamic>.from(prepared['values'])
          : Map<String, dynamic>.from(source);
      if (prepared == null) {
        for (final entry in jsonFields.entries) {
          final value = values.remove(entry.key);
          values[entry.value] = value == null ? null : canonical(value);
        }
      }
      final key = '$table:${values[primary]}';
      final fingerprint =
          prepared?['fingerprint'] as String? ?? canonical(values);
      if (cache.rows[key] == fingerprint) return;
      final existing = await tx.query(
        table,
        where: '$primary=?',
        whereArgs: [values[primary]],
      );
      if (existing.isNotEmpty) {
        final old = existing.single;
        final immutable =
            terminal ||
            table == 'adaptive_decisions' ||
            table == 'attempts' && old['validity'] != 'OPEN' ||
            table == 'blocks' && old['status'] == 'COMPLETED' ||
            table == 'trials' && old['status'] == 'COMPLETED';
        if (immutable && values.entries.any((e) => old[e.key] != e.value)) {
          throw StateError('E_RECORD_CONFLICT: $key');
        }
      } else if (terminal) {
        throw StateError('E_TERMINAL_SESSION');
      }
      await tx.insert(
        table,
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      final updated = await tx.update(
        table,
        values,
        where: '$primary=?',
        whereArgs: [values[primary]],
      );
      if (updated != 1) {
        throw StateError('E_RECORD_CONFLICT: $key');
      }
      cache.rows[key] = fingerprint;
    }

    for (final b in data['blocks'] as List) {
      await row('blocks', Map<String, dynamic>.from(b), 'block_id', {
        'parameters': 'parameters_json',
        'targets': 'targets_json',
      });
    }
    for (final t in data['trials'] as List) {
      await row('trials', Map<String, dynamic>.from(t), 'trial_id', {
        'target': 'target_json',
      });
    }
    for (final a in data['attempts'] as List) {
      await row('attempts', Map<String, dynamic>.from(a), 'attempt_id', {
        'result': 'result_json',
      });
    }
    if (cache.events.length > (data['events'] as List).length) {
      throw StateError('E_EVENT_CONFLICT');
    }
    for (final e in data['events'] as List) {
      final prepared = data['_prepared_rows']?['events']?['${e['seq']}'];
      final values = Map<String, dynamic>.from(prepared?['values'] ?? e);
      if (prepared == null) {
        values['payload_json'] = canonical(values.remove('payload'));
      }
      final fingerprint =
          prepared?['fingerprint'] as String? ?? canonical(values);
      final old = cache.events[e['seq']];
      if (old != null) {
        if (old != fingerprint) {
          throw StateError('E_EVENT_CONFLICT: ${e['seq']}');
        }
        continue;
      }
      if (terminal) throw StateError('E_TERMINAL_SESSION');
      await tx.insert('events', values);
      cache.events[e['seq'] as int] = fingerprint;
    }
    for (final d in data['decisions'] as List) {
      await row(
        'adaptive_decisions',
        Map<String, dynamic>.from(d),
        'decision_id',
        {
          'parameters_before': 'parameters_before_json',
          'parameters_after': 'parameters_after_json',
          'evidence': 'evidence_json',
        },
      );
    }
    if (terminal) {
      final summary = (await tx.query(
        'summaries',
        where: "session_id=? AND scope='SESSION' AND metric_version=?",
        whereArgs: [engine.id, engine.config.json['metric_version']],
      )).single;
      if (summary['result_json'] != canonical(data['summary']) ||
          session['planned_target_count'] != data['planned'] ||
          session['active_duration_us'] != data['duration'] ||
          session['elapsed_duration_us'] != data['now']) {
        throw StateError('E_RECORD_CONFLICT: terminal summary');
      }
      return cache; // An acknowledged retry cannot rewrite levels or end time.
    }
    final status = data['finish'] ?? data['status'];
    await tx.update(
      'sessions',
      {
        'status': status,
        'planned_target_count': data['planned'],
        'active_duration_us': data['duration'],
        'interrupted_active_us': data['interrupted'],
        'elapsed_duration_us': data['now'],
        'auto_upgrade_allowed': data['auto_upgrade'] ? 1 : 0,
        if (data['finish'] != null)
          'ended_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'session_id=?',
      whereArgs: [engine.id],
    );
    final committed = (data['blocks'] as List).any(
      (b) => b['status'] == 'COMPLETED',
    );
    final context = {
      'snapshot': jsonDecode(session['snapshot_json'] as String),
      'environment': jsonDecode(session['environment_json'] as String),
    };
    for (final block in (data['blocks'] as List).cast<Json>()) {
      if (block['status'] == 'ACTIVE' || block['status'] == 'PLANNED') continue;
      final id = block['block_id'];
      if (cache.summaryBlocks.contains(id)) continue;
      final audioChanged = (data['events'] as List).cast<Json>().any(
        (e) =>
            e['kind'] == 'PAUSE_REQUESTED' &&
            e['payload']['reason_code'] == 'AUDIO_ROUTE_CHANGED' &&
            e['offset_us'] <= (block['ended_offset_us'] ?? data['now']),
      );
      final summary = PracticeMetrics.build(
        taskId: engine.taskId,
        version: engine.config.json['metric_version'] as String,
        attempts: (data['attempts'] as List)
            .cast<Json>()
            .where((a) => a['block_id'] == id)
            .toList(),
        trials: (data['trials'] as List)
            .cast<Json>()
            .where((t) => t['block_id'] == id)
            .toList(),
        events: (data['events'] as List).cast<Json>(),
        planned: block['planned_trial_count'] as int,
        complete: block['status'] == 'COMPLETED',
        qualityFlags: audioChanged ? ['AUDIO_CONDITIONS_CHANGED'] : [],
      );
      final key = block['status'] == 'COMPLETED' && !audioChanged
          ? PracticeMetrics.comparisonKey(context, block, summary)
          : null;
      summary['comparison_key'] = key;
      await tx.insert('summaries', {
        'summary_id': uuid(),
        'session_id': engine.id,
        'block_id': id,
        'scope': 'BLOCK',
        'scope_key': id,
        'metric_version': engine.config.json['metric_version'],
        'comparison_key': key,
        'calculated_utc_ms':
            block['ended_utc_ms'] ??
            DateTime.now().toUtc().millisecondsSinceEpoch,
        'result_json': canonical(summary),
        'source_last_seq': (data['events'] as List).last['seq'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await tx.update(
        'blocks',
        {'comparison_key': key},
        where: 'block_id=?',
        whereArgs: [id],
      );
      cache.summaryBlocks.add(id as String);
    }
    if (committed ||
        (data['decisions'] as List).any((d) => d['source'] == 'USER')) {
      await tx.insert('profile_task_state', {
        'profile_id': profile['profile_id'],
        'task_id': engine.taskId,
        'mode': engine.mode,
        'parameter_profile_version': engine.config.json['version'],
        'level': data['level'],
        'updated_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (data['finish'] != null) {
      await tx.insert('summaries', {
        'summary_id': uuid(),
        'session_id': engine.id,
        'scope': 'SESSION',
        'scope_key': 'SESSION',
        'metric_version': engine.config.json['metric_version'],
        'calculated_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
        'result_json': canonical(data['summary']),
        'source_last_seq': (data['events'] as List).last['seq'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return cache;
  }

  Future<List<Json>> history({int offset = 0}) async => (await db.rawQuery(
    'SELECT s.*, m.result_json FROM sessions s LEFT JOIN summaries m ON s.session_id=m.session_id AND m.scope=\'SESSION\' AND m.metric_version=s.metric_version '
    'WHERE s.profile_id=? ORDER BY s.started_utc_ms DESC, s.session_id ASC LIMIT 20 OFFSET ?',
    [profile['profile_id'], offset],
  )).map((r) => Map<String, dynamic>.from(r)).toList();

  Future<HistoryPage> historyPage({Json? after}) async {
    final rows = await db.rawQuery(
      'SELECT * FROM (SELECT session_id,started_utc_ms,profile_id FROM sessions '
      'UNION ALL SELECT session_id,started_utc_ms,profile_id FROM piece_performances) '
      'WHERE profile_id=? '
      '${after == null ? '' : 'AND (started_utc_ms < ? OR (started_utc_ms = ? AND session_id > ?)) '} '
      'ORDER BY started_utc_ms DESC, session_id ASC LIMIT 21',
      [
        profile['profile_id'],
        if (after != null) ...[
          after['started_utc_ms'],
          after['started_utc_ms'],
          after['session_id'],
        ],
      ],
    );
    return HistoryPage([
      for (final row in rows.take(20))
        (await detail(row['session_id'] as String))!,
    ], rows.length > 20);
  }

  static const _trendJoin =
      'FROM summaries m JOIN blocks b ON m.block_id=b.block_id AND m.session_id=b.session_id '
      'JOIN sessions s ON b.session_id=s.session_id '
      'WHERE s.profile_id=? AND m.scope=\'BLOCK\' AND m.metric_version=s.metric_version '
      'AND b.status=\'COMPLETED\' AND b.ended_utc_ms IS NOT NULL '
      'AND m.comparison_key IS NOT NULL AND m.comparison_key=b.comparison_key ';

  Future<List<Json>> trendConditions({String? taskId}) async {
    // Display fields are invariant within an exact comparison key.
    final rows = await db.rawQuery(
      'SELECT m.comparison_key, s.task_id, MAX(b.level) AS level, MAX(s.mode) AS mode, '
      'MAX(s.session_locale) AS session_locale, MAX(m.result_json) AS result_json, '
      'MAX(b.parameters_json) AS parameters_json, '
      'MAX(s.environment_json) AS environment_json, MAX(b.ended_utc_ms) AS latest_utc_ms, COUNT(*) AS block_count '
      '$_trendJoin ${taskId == null ? '' : 'AND s.task_id=? '} '
      'GROUP BY m.comparison_key, s.task_id ORDER BY latest_utc_ms DESC, m.comparison_key ASC',
      [profile['profile_id'], ?taskId],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<Json>> trendRows(String key) async => (await db.rawQuery(
    'SELECT b.block_id, b.ended_utc_ms, b.level, b.parameters_json, m.result_json, m.comparison_key, '
    's.task_id, s.mode, s.session_locale, s.session_utc_offset_minutes, s.environment_json, '
    's.parameter_profile_version, s.metric_version '
    '$_trendJoin AND m.comparison_key=? '
    'ORDER BY b.ended_utc_ms DESC, b.block_id DESC LIMIT 20',
    [profile['profile_id'], key],
  )).reversed.map((r) => Map<String, dynamic>.from(r)).toList();

  // Group the latest completed blocks by exercise, regardless of the original
  // comparison key. Keep each sealed summary and its original conditions.
  static const _taskTrendJoin =
      'FROM summaries m JOIN blocks b ON m.block_id=b.block_id AND m.session_id=b.session_id '
      'JOIN sessions s ON b.session_id=s.session_id '
      "WHERE s.profile_id=? AND m.scope='BLOCK' AND m.metric_version=s.metric_version "
      "AND b.status='COMPLETED' AND b.ended_utc_ms IS NOT NULL "
      'AND (m.comparison_key=b.comparison_key OR (m.comparison_key IS NULL AND b.comparison_key IS NULL)) ';

  Future<List<Json>> trendTasks({String? taskId}) async {
    final rows = await db.rawQuery(
      'SELECT s.task_id, MAX(b.ended_utc_ms) AS latest_utc_ms, COUNT(*) AS block_count '
      '$_taskTrendJoin ${taskId == null ? '' : 'AND s.task_id=? '}'
      'GROUP BY s.task_id ORDER BY latest_utc_ms DESC, s.task_id ASC',
      [profile['profile_id'], ?taskId],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<Json>> trendRowsForTask(String taskId) async =>
      (await db.rawQuery(
        'SELECT b.block_id, b.ended_utc_ms, b.level, b.parameters_json, m.result_json, m.comparison_key, '
        's.task_id, s.mode, s.session_locale, s.session_utc_offset_minutes, s.environment_json, '
        's.parameter_profile_version, s.metric_version '
        '$_taskTrendJoin AND s.task_id=? '
        'ORDER BY b.ended_utc_ms DESC, b.block_id DESC LIMIT 20',
        [profile['profile_id'], taskId],
      )).reversed.map((r) => Map<String, dynamic>.from(r)).toList();

  Future<Json?> detail(String id) async {
    final pieces = await db.query(
      'piece_performances',
      where: 'session_id=? AND profile_id=?',
      whereArgs: [id, profile['profile_id']],
    );
    if (pieces.isNotEmpty) {
      final row = Map<String, dynamic>.from(pieces.single);
      try {
        return PiecePerformance.historyRow(row);
      } catch (_) {
        return {...row, 'task_id': 'PIANO_PIECE', 'record_unavailable': true};
      }
    }
    final rows = await db.rawQuery(
      'SELECT s.*, m.result_json FROM sessions s LEFT JOIN summaries m ON s.session_id=m.session_id AND m.scope=\'SESSION\' AND m.metric_version=s.metric_version WHERE s.session_id=?',
      [id],
    );
    return rows.isEmpty
        ? null
        : _checkedHistory(Map<String, dynamic>.from(rows.single));
  }

  Json _checkedHistory(Json row) {
    try {
      RecordIntegrity.session(row);
      return row;
    } catch (_) {
      return {...row, 'record_unavailable': true, 'result_json': null};
    }
  }

  Future<Json> recommendations(
    List<String> songIds, {
    DateTime? localNow,
  }) async {
    final now = localNow ?? DateTime.now();
    final firstDay = DateTime(
      now.year,
      now.month,
      now.day - 6,
    ).toUtc().millisecondsSinceEpoch;
    final endDay = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).toUtc().millisecondsSinceEpoch;
    final cognitive = await db.rawQuery(
      "SELECT task_id,COUNT(*) AS n,MAX(ended_utc_ms) AS last FROM sessions s WHERE profile_id=? AND status='COMPLETED' AND ended_utc_ms>=? AND ended_utc_ms<? AND task_id IN ('G1_MEMORY','G2_INHIBITION','G3_SWITCH') AND EXISTS(SELECT 1 FROM blocks b WHERE b.session_id=s.session_id AND b.status='COMPLETED') GROUP BY task_id",
      [profile['profile_id'], firstDay, endDay],
    );
    const order = ['G1_MEMORY', 'G2_INHIBITION', 'G3_SWITCH'];
    final ranked = order.toList()
      ..sort((a, b) {
        Map<String, Object?> stats(String id) => cognitive.firstWhere(
          (r) => r['task_id'] == id,
          orElse: () => {'n': 0, 'last': 0},
        );
        final x = stats(a), y = stats(b);
        final count = (x['n'] as int).compareTo(y['n'] as int);
        if (count != 0) return count;
        final recent = (x['last'] as int).compareTo(y['last'] as int);
        return recent != 0
            ? recent
            : order.indexOf(a).compareTo(order.indexOf(b));
      });
    final recent = songIds.isEmpty
        ? <Map<String, Object?>>[]
        : await db.rawQuery(
            "SELECT content_id FROM sessions WHERE profile_id=? AND content_id IN (${List.filled(songIds.length, '?').join(',')}) ORDER BY started_utc_ms DESC,session_id ASC LIMIT 1",
            [profile['profile_id'], ...songIds],
          );
    final sortedIds = [...songIds]..sort();
    return {
      'task_id': ranked.first,
      'song_id': recent.isEmpty
          ? (sortedIds.isEmpty ? null : sortedIds.first)
          : recent.single['content_id'],
    };
  }

  Future<void> delete(String id) async {
    final active = await db.query(
      'sessions',
      columns: ['session_id'],
      where: "session_id=? AND status NOT IN ('COMPLETED','EXITED','RECOVERED_INTERRUPTED')",
      whereArgs: [id],
      limit: 1,
    );
    if (active.isNotEmpty) throw StateError('E_ACTIVE_SESSION');
    await db.delete('sessions', where: 'session_id=?', whereArgs: [id]);
    await db.delete(
      'piece_performances',
      where: 'session_id=?',
      whereArgs: [id],
    );
    _cache.remove(id);
  }

  Future<Set<String>> completedLessons() async {
    final rows = await db.query(
      'tutorial_progress',
      columns: ['lesson_id'],
      where: 'profile_id=? AND lesson_version=? AND completed=1',
      whereArgs: [profile['profile_id'], IntroLesson.version],
    );
    return rows.map((row) => row['lesson_id'] as String).toSet();
  }

  Future<void> completeLesson(String lessonId) async {
    IntroLesson.byId(lessonId);
    await db.insert('tutorial_progress', {
      'profile_id': profile['profile_id'],
      'lesson_id': lessonId,
      'lesson_version': IntroLesson.version,
      'completed': 1,
      'updated_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clear() async {
    final active = await db.query(
      'sessions',
      columns: ['session_id'],
      where: "status NOT IN ('COMPLETED','EXITED','RECOVERED_INTERRUPTED')",
      limit: 1,
    );
    if (active.isNotEmpty) throw StateError('E_ACTIVE_SESSION');
    await db.transaction((tx) async {
      await tx.delete('sessions');
      await tx.delete('piece_performances');
      await tx.delete('profile_task_state');
      await tx.delete('tutorial_progress');
    });
    _cache.clear();
  }

  Future<void> savePiecePerformance(Json record) async {
    PiecePerformance.validate(record);
    await db.transaction((tx) async {
      final existing = await tx.query(
        'piece_performances',
        where: 'session_id=?',
        whereArgs: [record['session_id']],
      );
      final hash = digest(record);
      if (existing.isNotEmpty) {
        if (existing.single['record_hash'] != hash ||
            existing.single['profile_id'] != profile['profile_id']) {
          throw StateError('E_PIECE_RECORD_CONFLICT');
        }
        return;
      }
      await tx.insert('piece_performances', {
        for (final key in [
          'session_id',
          'content_id',
          'started_utc_ms',
          'ended_utc_ms',
          'session_utc_offset_minutes',
        ])
          key: record[key],
        'profile_id': profile['profile_id'],
        'record_json': canonical(record),
        'record_hash': hash,
      });
    });
  }
}
