import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../domain/dance_training.dart';

const _cache = MethodChannel('piano_training/dance_media_cache/v1');
const danceRemoteManifestAsset = 'assets/video/remote_manifest.json';

/// Packaged metadata locates offline cache without contacting a catalogue API.
class DanceVideoSource {
  const DanceVideoSource._(
    this.part,
    this.uri,
    this.partId,
    this.needsNetworkNotice,
  );
  final DancePart part;
  final Uri? uri;
  final String? partId;
  final bool needsNetworkNotice;
  bool get isRemote => uri != null;

  VideoPlayerController createController(VideoPlayerOptions options) =>
      uri == null
      ? VideoPlayerController.asset(part.asset, videoPlayerOptions: options)
      : VideoPlayerController.networkUrl(
          uri!,
          httpHeaders: {'X-PQ-Dance-Part': partId!},
          videoPlayerOptions: options,
        );
}

Future<DanceVideoSource> resolveDanceVideoSource(DancePart part) async {
  // Fandango stays local until that separate resource has been published.
  if (!const {
    'balance-six-1',
    'balance-six-2',
    'balance-six-3',
  }.contains(part.id)) {
    return DanceVideoSource._(part, null, null, false);
  }
  final manifest = jsonDecode(
    await rootBundle.loadString(danceRemoteManifestAsset),
  ) as Map<String, dynamic>;
  if (manifest['schemaVersion'] != 1) {
    throw const FormatException('Invalid dance resource manifest');
  }
  final matches = (manifest['items'] as List)
      .cast<Map<String, dynamic>>()
      .where((item) => item['partId'] == part.id)
      .toList();
  if (matches.length != 1) {
    throw const FormatException('Missing dance resource');
  }
  final item = matches.single;
  final uri = Uri.parse(item['url'] as String);
  final bytes = item['bytes'];
  if (uri.scheme != 'https' ||
      uri.host != 'ccqspace.site' ||
      uri.userInfo.isNotEmpty ||
      uri.path != '/pd-rehab/assets/dance/v1/${item['fileName']}' ||
      item['courseId'] != 'hkpdf-balance-six' ||
      item['resourceVersion'] != 'v1' ||
      part.asset != 'assets/video/${item['fileName']}' ||
      bytes is! int ||
      bytes <= 0 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch('${item['sha256']}')) {
    throw const FormatException('Invalid dance resource identity');
  }
  var notice = true;
  try {
    final status = await _cache.invokeMapMethod<String, dynamic>('status', {
      'partId': part.id,
    });
    final complete =
        status?['complete'] == true &&
        status?['cachedBytes'] == bytes &&
        status?['totalBytes'] == bytes;
    notice = !complete && status?['metered'] != false;
  } on MissingPluginException {
    // Test/non-Android platforms can still use the normal network controller.
  } on PlatformException {
    // A cache/storage failure must not prevent an online playback attempt.
  }
  return DanceVideoSource._(part, uri, part.id, notice);
}
