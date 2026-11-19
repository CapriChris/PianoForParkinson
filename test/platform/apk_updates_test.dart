import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/platform/apk_updates.dart';

final _manifest = Uri.parse('https://updates.example.test/latest.json');
const _package = 'com.pianoforparkinson.piano_practice';
const _apk = [1, 2, 3, 4];

Map<String, dynamic> _metadata() => {
  'schemaVersion': 1,
  'packageName': _package,
  'versionName': '0.1.74',
  'versionCode': 75,
  'apkUrl': 'https://updates.example.test/0.1.74/app.apk',
  'sizeBytes': _apk.length,
  'sha256': sha256.convert(_apk).toString(),
};

ApkUpdate? _parse(Map<String, dynamic> json, {int installed = 74}) =>
    ApkUpdate.fromManifest(
      json,
      _manifest,
      packageName: _package,
      installedVersionCode: installed,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only higher installed build numbers and matching packages qualify', () {
    expect(_parse(_metadata())?.versionCode, 75);
    expect(_parse(_metadata(), installed: 75), isNull);
    expect(_parse(_metadata(), installed: 76), isNull);
    expect(
      _parse(_metadata()..['packageName'] = '$_package.validation'),
      isNull,
    );
  });

  test('refuses unsafe download locations and incomplete metadata', () {
    for (final link in [
      'http://updates.example.test/app.apk',
      'https://example.test/app.apk',
      'https://updates.example.test:8443/app.apk',
      'https://name@updates.example.test/app.apk',
      'https://updates.example.test/index.html',
    ]) {
      expect(
        () => _parse(_metadata()..['apkUrl'] = link),
        throwsFormatException,
      );
    }
    expect(
      () => _parse(_metadata()..['sha256'] = 'bad'),
      throwsFormatException,
    );
    expect(() => _parse(_metadata()..['sizeBytes'] = 0), throwsFormatException);
  });

  test(
    'only verified bytes reach the cache file used by the installer',
    () async {
      final directory = await Directory.systemTemp.createTemp('qin-apk-test-');
      addTearDown(() => directory.delete(recursive: true));
      const channel = MethodChannel('piano_companion/apk_updates/v1');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'downloadDirectory');
        return directory.path;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final update = _parse(_metadata())!;
      final updates = ApkUpdates.instance;
      final apk = File('${directory.path}/update.apk');
      final partial = File('${directory.path}/update.part');
      Future<void> get(List<int> bytes) => HttpOverrides.runZoned(
        () => updates.download(update, (_) {}),
        createHttpClient: (_) => _Client(bytes),
      );

      await expectLater(get([4, 3, 2, 1]), throwsFormatException);
      expect(await apk.exists(), isFalse);
      expect(await partial.exists(), isFalse);
      await get(_apk);
      expect(await apk.readAsBytes(), _apk);
      expect(await partial.exists(), isFalse);
      await get([
        4,
        3,
        2,
        1,
      ]); // The verified cache is reused without a new transfer.
      expect(await apk.readAsBytes(), _apk);
    },
  );
}

class _Client implements HttpClient {
  _Client(this.bytes);
  final List<int> bytes;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(bytes);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.bytes);
  final List<int> bytes;
  @override
  bool followRedirects = true;
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => _Response(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes);
  final List<int> bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
