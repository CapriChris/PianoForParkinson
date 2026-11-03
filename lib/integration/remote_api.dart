/// Authenticated, HTTPS-only API client shared by the Cloud Sync and AI pages.
/// Access tokens intentionally remain in RAM; credentials never go into SQLite.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

class RemoteApiException implements Exception {
  final int status;
  final String message;
  const RemoteApiException(this.status, this.message);
  @override
  String toString() => message;
}

class RemoteApi {
  RemoteApi(String baseUrl)
    : base = Uri.parse(baseUrl.trim().replaceFirst(RegExp(r'/$'), '')) {
    if (base.scheme != 'https' ||
        base.host.isEmpty ||
        !base.path.endsWith('/api')) {
      throw const FormatException('请填写 HTTPS 地址，且必须以 /api 结尾。');
    }
  }
  final Uri base;
  String? _token;
  String? get currentToken => _token;
  bool get signedIn => _token != null;

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${base.toString()}$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client
          .openUrl(method, uri(path, query))
          .timeout(const Duration(seconds: 15));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (_token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      if (data != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(data)));
      }
      final res = await req.close().timeout(const Duration(seconds: 60));
      final body = await utf8.decoder.bind(res).join();
      final parsed = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final error = parsed is Map ? parsed['error'] : null;
        final msg = error is Map ? error['message'] : null;
        throw RemoteApiException(
          res.statusCode,
          '$msg'.trim() == 'null' ? '请求失败 (${res.statusCode})' : '$msg',
        );
      }
      return Map<String, dynamic>.from(parsed as Map);
    } on SocketException {
      throw const RemoteApiException(0, '无法连接到服务器。请检查网络后重试。');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final result = await request(
      'POST',
      '/auth/login',
      data: {'username': username, 'password': password},
    );
    _token = result['access_token'] as String;
    return Map<String, dynamic>.from(result['user'] as Map);
  }

  void signOut() => _token = null;

  Future<Map<String, dynamic>> bootstrap({int offset = 0}) => request(
    'GET',
    '/integration/v1/bootstrap',
    query: {'offset': '$offset', 'limit': '100'},
  );

  Future<Map<String, dynamic>> bindPatient(
    String deviceId,
    String profileId,
    String patientId,
  ) => request(
    'POST',
    '/integration/v1/bindings',
    data: {
      'device_id': deviceId,
      'local_profile_id': profileId,
      'patient_id': patientId,
    },
  );

  Future<Map<String, dynamic>> patientData(
    String patientId, {
    int offset = 0,
  }) => request(
    'GET',
    '/integration/v1/patient-data',
    query: {'patient_id': patientId, 'offset': '$offset'},
  );

  Future<Map<String, dynamic>> syncRecord(Map<String, dynamic> payload) =>
      request('POST', '/integration/v1/records', data: payload);

  Future<Map<String, dynamic>> ask(String question, {String? patientId}) =>
      request(
        'POST',
        '/integration/v1/expert/chat',
        data: {'question': question, 'patient_id': ?patientId},
      );

  Future<Map<String, dynamic>> faceJob(
    String path, {
    required String patientId,
    required String profileId,
    required String deviceId,
  }) async {
    // Multipart upload streams file bytes, so a long recording is never loaded
    // entirely into the Flutter heap. No platform plugin is required here.
    final file = File(path);
    if (!await file.exists()) throw const RemoteApiException(0, '视频文件不存在。');
    final size = await file.length();
    if (size <= 0 || size > 50 * 1024 * 1024) {
      throw const RemoteApiException(0, '视频为空或超过 50 MB 上传限制（服务器可能设置更低上限）。');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.postUrl(uri('/integration/v1/face/jobs'));
      if (_token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      final boundary =
          'pd-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(100000)}';
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      final fields = {
        'patient_id': patientId,
        'device_id': deviceId,
        'local_profile_id': profileId,
      };
      for (final field in fields.entries) {
        req.add(
          utf8.encode(
            '--$boundary\r\nContent-Disposition: form-data; name="${field.key}"\r\n\r\n${field.value}\r\n',
          ),
        );
      }
      final ext = path.toLowerCase().split('.').last;
      final mime =
          {
            'mp4': 'video/mp4',
            'mov': 'video/quicktime',
            'webm': 'video/webm',
          }[ext] ??
          'application/octet-stream';
      req.add(
        utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="video"; filename="upload.$ext"\r\nContent-Type: $mime\r\n\r\n',
        ),
      );
      await req.addStream(file.openRead());
      req.add(utf8.encode('\r\n--$boundary--\r\n'));
      final res = await req.close().timeout(const Duration(minutes: 5));
      final body = await utf8.decoder.bind(res).join();
      final data = jsonDecode(body) as Map;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final error = data['error'];
        throw RemoteApiException(
          res.statusCode,
          error is Map ? '${error['message']}' : '上传失败',
        );
      }
      return Map<String, dynamic>.from(data);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> faceStatus(String jobId) =>
      request('GET', '/integration/v1/face/jobs/$jobId');

  Future<Map<String, dynamic>> faceCandidates(String jobId) =>
      request('GET', '/integration/v1/face/jobs/$jobId/candidates');

  Future<Map<String, dynamic>> reviewFrames(
    String jobId,
    int onset,
    int apex,
    int offset,
  ) => request(
    'POST',
    '/integration/v1/face/jobs/$jobId/review',
    data: {
      'onset_frame': onset,
      'apex_frame': apex,
      'offset_frame': offset,
      'review_confirmed': true,
    },
  );
}
