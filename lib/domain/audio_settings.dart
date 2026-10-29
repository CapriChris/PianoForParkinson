import 'contracts.dart';

const defaultKeyGain = 850;
const defaultSpeechGain = 1000;

/// Additive JSON upgrade; retain mute, existing custom gains and all other
/// preferences. Only the old 60% default becomes the new 85% default once.
Json normalizedAudioSettings(Json old) => {
  ...old,
  if (old['volume_controls_version'] != 2) ...{
    'volume_controls_version': 2,
    'sound_enabled': true,
    'speech_enabled': true,
  },
  'gain_permille':
      old['volume_controls_version'] != 2 && old['sound_enabled'] == false
      ? 0
      : !old.containsKey('speech_gain_permille') && old['gain_permille'] == 600
      ? defaultKeyGain
      : old['gain_permille'],
  'speech_gain_permille':
      old['volume_controls_version'] != 2 && old['speech_enabled'] == false
      ? 0
      : old['speech_gain_permille'] ?? defaultSpeechGain,
};
