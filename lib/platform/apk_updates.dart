import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _manifestUrl = String.fromEnvironment(
  'PD_ANDROID_UPDATE_MANIFEST',
  defaultValue:
      'https://ccqspace.site/pd-rehab/assets/app-releases/latest-android.json',
);
const _networkTimeout = Duration(seconds: 15);
const _maxApkBytes = 1024 * 1024 * 1024;

class ApkUpdate {
  const ApkUpdate._(
    this.version,
    this.versionCode,
    this.url,
    this.size,
    this.sha256Hex,
    this.notesZh,
    this.notesEn,
  );

  final String version, sha256Hex, notesZh, notesEn;
  final int versionCode, size;
  final Uri url;

  static ApkUpdate? fromManifest(
    Map<String, dynamic> json,
    Uri manifest, {
    required String packageName,
    required int installedVersionCode,
  }) {
    if (json['schemaVersion'] != 1 || json['packageName'] is! String) {
      throw const FormatException('Invalid update manifest');
    }
    if (json['packageName'] != packageName) return null;
    final code = json['versionCode'];
    if (code is! int || code < 1 || code > 2100000000) {
      throw const FormatException('Invalid update build number');
    }
    if (code <= installedVersionCode) return null;
    final version = json['versionName'];
    final size = json['sizeBytes'];
    final digest = json['sha256'];
    final link = json['apkUrl'];
    final url = link is String ? Uri.tryParse(link) : null;
    if (version is! String ||
        !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$')
            .hasMatch(version) ||
        version.length > 64 ||
        size is! int ||
        size < 1 ||
        size > _maxApkBytes ||
        digest is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(digest) ||
        url == null ||
        !_https(url) ||
        url.origin != manifest.origin ||
        !url.path.endsWith('.apk')) {
      throw const FormatException('Invalid APK metadata');
    }
    String notes(String key) {
      final value = json[key];
      return value is String && value.length <= 2000 ? value.trim() : '';
    }

    return ApkUpdate._(
      version,
      code,
      url,
      size,
      digest.toLowerCase(),
      notes('notesZh'),
      notes('notesEn'),
    );
  }
}

bool _https(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    !uri.hasFragment;

class ApkDownloadCancelled implements Exception {
  const ApkDownloadCancelled();
}

class ApkUpdates {
  ApkUpdates._();

  static final instance = ApkUpdates._();
  static const _channel = MethodChannel('piano_companion/apk_updates/v1');

  static bool get available =>
      !kIsWeb && Platform.isAndroid && _manifestUrl.isNotEmpty;

  final Set<int> _promptedCodes = {};
  Future<ApkUpdate?>? _checking;
  HttpClient? _download;
  bool _cancelled = false;

  bool markPrompted(int versionCode) => _promptedCodes.add(versionCode);

  Future<ApkUpdate?> check() async {
    if (!available) return null;
    if (_checking case final pending?) return pending;
    final pending = _check();
    _checking = pending;
    try {
      return await pending;
    } finally {
      _checking = null;
    }
  }

  Future<ApkUpdate?> _check() async {
    final manifest = Uri.parse(_manifestUrl);
    if (!_https(manifest)) throw const FormatException('Unsafe manifest URL');
    final app = (await _channel.invokeMapMethod<String, dynamic>('installed'))!;
    final client = _client();
    try {
      final response = await _get(client, manifest);
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw const HttpException('Update check failed');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(_networkTimeout)) {
        if (bytes.length + chunk.length > 32 * 1024) {
          throw const FormatException('Update manifest is too large');
        }
        bytes.addAll(chunk);
      }
      return ApkUpdate.fromManifest(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        manifest,
        packageName: app['packageName'] as String,
        installedVersionCode: app['versionCode'] as int,
      );
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _client() => HttpClient()..connectionTimeout = _networkTimeout;

  Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri).timeout(_networkTimeout);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    return request.close().timeout(_networkTimeout);
  }

  Future<void> download(
    ApkUpdate update,
    ValueChanged<double> onProgress,
  ) async {
    if (_download != null) {
      throw StateError('An update download is already running');
    }
    final client = _client();
    _download = client;
    _cancelled = false;
    File? temporary;
    try {
      final directory = (await _channel.invokeMethod<String>(
        'downloadDirectory',
      ))!;
      _throwIfCancelled();
      final apk = File('$directory/update.apk');
      final partial = temporary = File('$directory/update.part');
      if (await apk.exists()) {
        if (await _matches(apk, update)) {
          _throwIfCancelled();
          onProgress(1);
          return;
        }
        await apk.delete();
      }
      final response = await _get(client, update.url);
      if (response.statusCode != 200) {
        throw const HttpException('APK download failed');
      }
      if (response.contentLength >= 0 &&
          response.contentLength != update.size) {
        throw const FormatException('Incorrect APK size');
      }
      final sink = await partial.open(mode: FileMode.write);
      try {
        var received = 0;
        await for (final chunk in response.timeout(_networkTimeout)) {
          _throwIfCancelled();
          received += chunk.length;
          if (received > update.size) {
            throw const FormatException('Incorrect APK size');
          }
          await sink.writeFrom(chunk);
          onProgress(received / update.size);
        }
      } finally {
        await sink.close();
      }
      _throwIfCancelled();
      if (!await _matches(partial, update)) {
        throw const FormatException('APK checksum mismatch');
      }
      _throwIfCancelled();
      await partial.rename(apk.path);
    } catch (_) {
      _throwIfCancelled();
      rethrow;
    } finally {
      client.close(force: true);
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } finally {
        _download = null;
      }
    }
  }

  Future<bool> _matches(File file, ApkUpdate update) async =>
      await file.length() == update.size &&
      (await sha256.bind(file.openRead()).first).toString() == update.sha256Hex;

  void cancelDownload() {
    if (_download == null) return;
    _cancelled = true;
    _download!.close(force: true);
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const ApkDownloadCancelled();
  }

  Future<bool> install(ApkUpdate update) async =>
      (await _channel.invokeMethod<bool>('install', {
        'versionCode': update.versionCode,
        'sizeBytes': update.size,
        'sha256': update.sha256Hex,
      }))!;

  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');
}
