import 'dart:convert';

import '../domain/contracts.dart';
import 'record_contract.dart';

class RecordIntegrity {
  static void profile(Json row) {
    RecordContract.enumeration(row, 'locale', {'zh-Hans', 'en'});
    RecordContract.enumeration(row, 'mode', {'ASSIST', 'CHALLENGE'});
    final settings = object(
      jsonDecode(row['settings_json'] as String),
      'settings',
    );
    RecordContract.version(settings);
    RecordContract.string(settings, 'device_local_id');
    for (final key in [
      'sound_enabled',
      'speech_enabled',
      'decorative_animation_enabled',
      'high_contrast',
    ]) {
      if (settings[key] is! bool) RecordContract.fail(key);
    }
    for (final key in ['gain_permille', 'speech_gain_permille']) {
      if (key == 'speech_gain_permille' && !settings.containsKey(key)) continue;
      RecordContract.integer(settings, key);
      if (settings[key] > 1000) RecordContract.fail(key);
    }
    if (settings['text_scale_percent'] != null) {
      RecordContract.integer(settings, 'text_scale_percent', min: 80);
      if (settings['text_scale_percent'] > 200) {
        RecordContract.fail('text_scale_percent');
      }
    }
    if (settings['text_size_percent_v2'] != null) {
      RecordContract.integer(settings, 'text_size_percent_v2', min: 80);
      if (settings['text_size_percent_v2'] > 120) {
        RecordContract.fail('text_size_percent_v2');
      }
    }
    if (settings['text_size_percent_v3'] != null) {
      RecordContract.integer(settings, 'text_size_percent_v3', min: 80);
      if (settings['text_size_percent_v3'] > 120) {
        RecordContract.fail('text_size_percent_v3');
      }
    }
    if (settings.containsKey('dual_touch_check_completed') &&
        settings['dual_touch_check_completed'] is! bool) {
      RecordContract.fail('dual_touch_check_completed');
    }
    if (settings['selected_song_id'] != null) {
      RecordContract.string(settings, 'selected_song_id');
    }
  }

  static Json object(Object? value, String field) {
    if (value is! Map<String, dynamic>) RecordContract.fail(field);
    return value;
  }

  static void layout(Json value, {bool legacy = false}) {
    for (final key in [
      'canvas_width_dp',
      'canvas_height_dp',
      'text_scale_permille',
    ]) {
      if (!legacy || value.containsKey(key)) {
        RecordContract.integer(value, key, min: 1);
      }
    }
    RecordContract.string(value, 'layout_id');
    if (legacy && !value.containsKey('keyboard_rect')) return;
    if (value['coordinate_unit'] != 'MILLIDP' || value['layout_version'] != 1) {
      RecordContract.fail('layout unit/version');
    }
    void rect(Object? raw) {
      if (raw is! List ||
          raw.length != 4 ||
          raw.any((v) => v is! int) ||
          raw[2] <= 0 ||
          raw[3] <= 0) {
        RecordContract.fail('layout rectangle');
      }
    }

    rect(value['keyboard_rect']);
    final keys = value['keys'];
    if (keys is! List || keys.isEmpty || keys.length > 7) {
      RecordContract.fail('layout keys');
    }
    final ids = <int>{};
    for (final raw in keys) {
      final key = object(raw, 'layout key');
      RecordContract.integer(key, 'key_id');
      if (key['key_id'] > 6 || !ids.add(key['key_id'] as int)) {
        RecordContract.fail('layout key id');
      }
      rect(key['hit_rect']);
    }
    if (value['snapshot_id'] != null) {
      final geometry = {...value}..remove('snapshot_id');
      if (value['snapshot_id'] != digest(geometry)) {
        RecordContract.fail('layout hash');
      }
    }
  }

  static void configuration(Json config) {
    RecordContract.version(config);
    for (final key in [
      'version',
      'metric_version',
      'adaptive_version',
      'rng_algorithm',
    ]) {
      RecordContract.string(config, key);
    }
    if (config['required_block_slots'] != 2 ||
        config['clock_source'] != 'DART_RECEIPT') {
      RecordContract.fail('configuration clock/slots');
    }
    for (final name in [
      'input',
      'layout',
      'audio',
      'recording',
      'timing',
      'tasks',
    ]) {
      object(config[name], name);
    }
    final input = object(config['input'], 'input');
    for (final key in [
      'max_pointers',
      'release_quiet_ms',
      'held_touch_hint_ms',
      'held_touch_pause_ms',
      'countdown_steps',
      'countdown_step_ms',
    ]) {
      RecordContract.integer(input, key, min: 1);
    }
    if (input['held_touch_pause_ms'] <= input['held_touch_hint_ms']) {
      RecordContract.fail('held timing');
    }
    final recording = object(config['recording'], 'recording');
    for (final key in [
      'flush_interval_ms',
      'flush_event_count',
      'database_max_bytes',
      'minimum_free_bytes',
    ]) {
      RecordContract.integer(recording, key, min: 1);
    }
    final tasks = object(config['tasks'], 'tasks');
    for (final entry in tasks.entries) {
      final task = object(entry.value, 'task');
      RecordContract.string(task, 'task_version');
      RecordContract.integer(task, 'maximum_level', min: 1);
      if (task.containsKey('pool')) RecordContract.keys(task['pool']);
      final modes = object(task['modes'], 'modes');
      for (final mode in ['ASSIST', 'CHALLENGE']) {
        final settings = object(modes[mode], mode);
        RecordContract.integer(settings, 'initial_level', min: 1);
        if (settings['initial_level'] > task['maximum_level']) {
          RecordContract.fail('initial level');
        }
      }
    }
    void fields(Map value) {
      for (final entry in value.entries) {
        final key = entry.key as String;
        final field = entry.value;
        if (field is Map) {
          fields(field);
          continue;
        }
        if (key.endsWith('_enabled') && field is! bool) {
          RecordContract.fail(key);
        }
        if (key.endsWith('_by_level')) {
          if (field is! List ||
              field.isEmpty ||
              field.any((v) => v is! int || v < 0)) {
            RecordContract.fail(key);
          }
        } else if (RegExp(
          r'_(ms|us|bytes|dp|permille|steps|bpm|count|hz|bits)$',
        ).hasMatch(key)) {
          if (field is! int || field < 0) RecordContract.fail(key);
        }
      }
    }

    fields(config);
    // Constructing the versioned profile also checks hold/interaction policies.
    PracticeConfig(config);
  }

  static void environment(Json env, {bool legacy = false}) {
    RecordContract.version(env);
    for (final field in [
      'platform',
      'os_version',
      'app_version',
      'build_id',
      'device_model',
      'device_local_id',
      'clock_source',
      'layout_id',
      'audio_backend',
      'audio_route_category',
    ]) {
      if (!legacy || env.containsKey(field)) RecordContract.string(env, field);
    }
    for (final field in ['sound_enabled', 'screen_reader_active']) {
      if ((!legacy || env.containsKey(field)) && env[field] is! bool) {
        RecordContract.fail(field);
      }
    }
    if (!legacy || env.containsKey('app_gain_permille')) {
      RecordContract.integer(env, 'app_gain_permille');
      if (env['app_gain_permille'] > 1000) RecordContract.fail('gain');
    }
    if (env['clock_source'] != null && env['clock_source'] != 'DART_RECEIPT') {
      RecordContract.fail('clock_source');
    }
    if (env['layout_snapshot'] != null) {
      layout(object(env['layout_snapshot'], 'layout'), legacy: legacy);
    }
    if (env['platform'] != null && env['platform'] != 'ANDROID') {
      RecordContract.fail('platform');
    }
    if (env['audio_route_category'] != null &&
        !{
          'BUILT_IN',
          'WIRED',
          'BLUETOOTH',
          'MUTED',
          'UNKNOWN',
        }.contains(env['audio_route_category'])) {
      RecordContract.fail('audio route');
    }
    for (final key in [
      'window_width_dp',
      'window_height_dp',
      'text_scale_permille',
    ]) {
      if (!legacy || env.containsKey(key)) {
        RecordContract.integer(env, key, min: 1);
      }
    }
    if (env['layout_snapshot'] is Map &&
        env['layout_id'] != env['layout_snapshot']['layout_id']) {
      RecordContract.fail('environment layout');
    }
  }

  static void snapshot(Json value, {bool legacy = false}) {
    for (final field in [
      'task_id',
      'task_version',
      'mode',
      'instruction_locale',
    ]) {
      RecordContract.string(value, field);
    }
    RecordContract.enumeration(value, 'mode', {'ASSIST', 'CHALLENGE'});
    RecordContract.enumeration(value, 'instruction_locale', {'zh-Hans', 'en'});
    configuration(object(value['parameter_profile'], 'parameter_profile'));
    if (value['content'] != null) {
      final content = object(value['content'], 'content');
      final raw = {...content}..remove('content_hash');
      if (content['content_hash'] != digest(raw)) {
        RecordContract.fail('content_hash');
      }
    }
    canonical(value);
  }

  static void summary(Json value, String version) {
    if (value['version'] != version) {
      RecordContract.fail('summary metric version');
    }
    final rates = object(value['rates'], 'rates');
    for (final raw in rates.values) {
      final rate = object(raw, 'rate');
      RecordContract.integer(rate, 'numerator');
      RecordContract.integer(rate, 'denominator');
      if (rate['numerator'] > rate['denominator']) {
        RecordContract.fail('rate range');
      }
    }
    final groups = value['timing_groups'];
    if (groups != null) {
      for (final raw in object(groups, 'timing_groups').values) {
        final timing = object(raw, 'timing');
        RecordContract.integer(timing, 'samples');
        if (timing['samples'] > 0) {
          RecordContract.integer(timing, 'median_numerator_us');
          RecordContract.integer(timing, 'median_denominator', min: 1);
          RecordContract.integer(timing, 'p95_us');
        }
        if (timing['cv_ppm'] != null) {
          RecordContract.integer(timing, 'cv_ppm');
          if (timing['samples'] < 10) RecordContract.fail('CV samples');
        }
      }
    }
    canonical(value);
  }

  /// Non-mutating checks used by history and by the complete, paged audit.
  static void session(Json row) {
    for (final field in ['session_id', 'task_id', 'status']) {
      RecordContract.string(row, field);
    }
    RecordContract.integer(row, 'started_utc_ms');
    RecordContract.enumeration(row, 'task_id', {
      'G1_MEMORY',
      'G2_INHIBITION',
      'G3_SWITCH',
      'S1_GUIDED',
      'S2_RHYTHM',
      'M1_ALTERNATE',
      'M2_DUAL_ZONE',
    });
    RecordContract.enumeration(row, 'status', {
      'PREPARING',
      'DEMONSTRATING',
      'WAIT_ALL_UP',
      'COUNTDOWN',
      'ACTIVE',
      'BLOCK_FEEDBACK',
      'PAUSED',
      'PAUSED_ERROR',
      'FINISHING',
      'COMPLETED',
      'EXITED',
      'RECOVERED_INTERRUPTED',
    });
    if (row['session_utc_offset_minutes'] is! int) {
      RecordContract.fail('timezone');
    }
    final snapshotText = row['snapshot_json'];
    if (snapshotText != null) {
      final snap = object(jsonDecode(snapshotText as String), 'snapshot');
      if (row['snapshot_sha256'] != digest(snap)) {
        RecordContract.fail('snapshot_sha256');
      }
      snapshot(snap, legacy: true);
      if (snap['task_id'] != row['task_id'] ||
          snap['parameter_profile']['version'] !=
              row['parameter_profile_version']) {
        RecordContract.fail('snapshot ownership/version');
      }
    }
    if (row['environment_json'] != null) {
      environment(
        object(jsonDecode(row['environment_json'] as String), 'environment'),
        legacy: true,
      );
    }
    if (row['result_json'] != null) {
      summary(
        object(jsonDecode(row['result_json'] as String), 'summary'),
        row['metric_version'] as String,
      );
    }
  }

  static void event(Json value) {
    final payload = object(value['payload'], 'event payload');
    if (payload.containsKey('pointer_id') && payload['pointer_id'] is! int) {
      RecordContract.fail('pointer_id');
    }
    for (final key in ['x_norm', 'y_norm', 'raw_timestamp_us']) {
      if (payload.containsKey(key) && payload[key] is! int) {
        RecordContract.fail(key);
      }
    }
    if (payload['raw_timestamp_us'] != null &&
        payload['raw_timestamp_us'] < 0) {
      RecordContract.fail('raw_timestamp_us');
    }
    if (payload['device_kind'] != null &&
        !{'TOUCH', 'ACCESSIBILITY'}.contains(payload['device_kind'])) {
      RecordContract.fail('device_kind');
    }
    if (payload['layout_snapshot_id'] != null &&
        payload['layout_snapshot_id'] is! String) {
      RecordContract.fail('layout_snapshot_id');
    }
  }
}
