import 'dart:convert';

import 'contracts.dart';

/// Engineering usability profile. Scoring formulas and the input clock stay
/// unchanged; the complete effective profile is stored with each session.
PracticeConfig practicePace(PracticeConfig base, String pace) {
  if (pace == 'STANDARD') return base;
  if (pace != 'COMFORT') throw ArgumentError.value(pace, 'pace');
  final json = jsonDecode(jsonEncode(base.json)) as Json;
  json['version'] = '${base.json['version']}-comfort-1';
  json['pace'] = 'COMFORT';
  json['automatic_upgrade_enabled'] = false;
  json['timing']['trial_gap_ms'] = 1500;
  final tasks = json['tasks'] as Map;
  for (final mode in ['ASSIST', 'CHALLENGE']) {
    tasks['G1_MEMORY']['modes'][mode]['demo_onset_interval_ms'] = 1500;
    tasks['G2_INHIBITION']['modes'][mode]['response_window_ms_by_level'] = [
      5000,
      5000,
      5000,
      5000,
      5000,
    ];
    tasks['G3_SWITCH']['modes'][mode]['response_window_ms'] = 5000;
  }
  for (final id in ['G1_MEMORY', 'S1_GUIDED']) {
    tasks[id]['demo_end_gap_ms'] = 1000;
  }
  tasks['S1_GUIDED']['demo_onset_interval_ms'] = 1500;
  tasks['G3_SWITCH']['rule_header_ms'] = 2500;
  tasks['M2_DUAL_ZONE']['response_window_ms'] = 5000;
  for (final id in ['S2_RHYTHM', 'M1_ALTERNATE']) {
    tasks[id]['bpm_by_level'] = [30, 35, 40, 45];
  }
  return PracticeConfig(json);
}
