import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/contracts.dart';

class PlatformService {
  static const channel = MethodChannel('piano_training/platform/v1');
  static const events = EventChannel('piano_training/platform_events/v1');
  int generation = 0;
  Future<Json> call(String method, [Json values = const {}]) async {
    final request = uuid();
    final response = await channel
        .invokeMapMethod<String, dynamic>(method, {
          'protocol_version': 1,
          'request_id': request,
          'generation': generation,
          ...values,
        })
        .timeout(
          Duration(
            seconds: method == 'preparePieceBacking' || method == 'prepareAudio'
                ? 30
                : 10,
          ),
        );
    if (response == null ||
        response['request_id'] != request ||
        response['ok'] != true) {
      throw StateError(response?['error_code'] as String? ?? 'E_PLATFORM');
    }
    return Map<String, dynamic>.from(response['data'] as Map? ?? {});
  }

  Future<void> activate(int next) async {
    generation = next;
    await call('activateGeneration', {'new_generation': next});
  }

  Future<void> prepare(Json soundPack) async => call('prepareAudio', {
    'assets': soundPack['assets'],
    'sound_pack_id': soundPack['version'],
  });
  Future<int> play(
    int key,
    int gain, {
    String owner = 'USER',
    int ratePermille = 1000,
  }) async {
    final data = await call('playNote', {
      'note_id': key,
      'voice_request_id': uuid(),
      'gain_permille': gain,
      'owner': owner,
      if (ratePermille != 1000) 'rate_permille': ratePermille,
    });
    return data['voice_id'] as int;
  }

  Future<void> stop(int voice) async => call('stopVoice', {'voice_id': voice});
  Future<void> off() async => call('allNotesOff');
}
