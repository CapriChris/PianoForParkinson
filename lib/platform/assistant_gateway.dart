import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/contracts.dart';

class AssistantFailure implements Exception {
  const AssistantFailure(this.code);
  final String code;
}

class AssistantReply {
  const AssistantReply({
    required this.answer,
    this.nextStep,
    this.references = const {},
  });

  final String answer;
  final String? nextStep;
  final Map<int, Set<String>> references;

  factory AssistantReply.parse(Json body, Json? context) {
    final answer = body['answer'];
    final nextStep = body['next_step'];
    final refs = body['references'];
    if (answer is! String ||
        answer.trim().isEmpty ||
        answer.length > 2400 ||
        (nextStep != null && (nextStep is! String || nextStep.length > 600)) ||
        refs is! List ||
        refs.length > 6) {
      throw const AssistantFailure('invalid_reply');
    }
    final allowed = <int, Set<String>>{
      for (final row in (context?['evidence'] as List? ?? []).cast<Json>())
        row['ref'] as int: (row['metrics'] as Map).keys.cast<String>().toSet(),
    };
    final references = <int, Set<String>>{};
    for (final item in refs) {
      if (item is! Map || item['ref'] is! int || item['metrics'] is! List) {
        throw const AssistantFailure('invalid_reply');
      }
      final id = item['ref'] as int;
      final keys = item['metrics'] as List;
      if (keys.isEmpty ||
          keys.any(
            (key) => !allowed.containsKey(id) || !allowed[id]!.contains(key),
          ) ||
          references.containsKey(id)) {
        throw const AssistantFailure('invalid_reply');
      }
      references[id] = keys.cast<String>().toSet();
    }
    return AssistantReply(
      answer: answer.trim(),
      nextStep: (nextStep as String?)?.trim(),
      references: references,
    );
  }
}

class AssistantGateway {
  AssistantGateway(String address) : base = _gatewayAddress(address);
  AssistantGateway.fromEnvironment()
    : this(const String.fromEnvironment('QIN_AI_GATEWAY'));

  final Uri? base;
  String? _credential;
  bool get available => base != null;
  static const providerName = String.fromEnvironment('QIN_AI_PROVIDER_NAME');

  static Uri? _gatewayAddress(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final debugLoopback =
        kDebugMode && uri.isScheme('http') && uri.host == '127.0.0.1';
    if (!uri.isScheme('https') && !debugLoopback) return null;
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  String get consentVersion =>
      '${base ?? 'local'}#${const String.fromEnvironment('QIN_AI_PRIVACY_VERSION', defaultValue: '1')}';

  Future<AssistantReply> ask({
    required String locale,
    required String question,
    required String requestId,
    required List<Json> history,
    Json? context,
    required bool Function() canSend,
    String? installationToken,
    Future<void> Function(String)? saveInstallationToken,
    void Function(String)? onAnswer,
  }) async {
    if (!available) throw const AssistantFailure('unconfigured');
    final payload = {
      'request_id': requestId,
      'locale': locale,
      'question': question,
      'history': history,
      'context': ?context,
    };
    _credential ??= installationToken;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!canSend()) throw const AssistantFailure('cancelled');
      if (_credential == null) {
        final token = await _install();
        _credential = token;
        if (canSend()) await saveInstallationToken?.call(token);
      }
      if (!canSend()) throw const AssistantFailure('cancelled');
      try {
        return AssistantReply.parse(
          await _post(
            'v1/chat',
            payload,
            token: _credential,
            canSend: canSend,
            onAnswer: onAnswer,
          ),
          context,
        );
      } on AssistantFailure catch (failure) {
        if (failure.code != 'unauthorized' || attempt != 0) rethrow;
        _credential = null;
      }
    }
    throw const AssistantFailure('unauthorized');
  }

  Future<String> _install() async {
    final result = await _post('v1/install', {});
    final token = result['token'];
    if (token is! String || token.isEmpty || token.length > 256) {
      throw const AssistantFailure('invalid_reply');
    }
    return token;
  }

  Future<Json> _post(
    String path,
    Json body, {
    String? token,
    bool Function()? canSend,
    void Function(String)? onAnswer,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.postUrl(base!.resolve(path));
        if (canSend?.call() == false) {
          request.abort();
          throw const AssistantFailure('cancelled');
        }
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        if (onAnswer != null) {
          request.headers.set(
            HttpHeaders.acceptHeader,
            'text/event-stream, application/json',
          );
        }
        final payload = utf8.encode(jsonEncode(body));
        request.contentLength = payload.length;
        if (token != null) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        request.add(payload);
        final response = await request.close();
        if (response.statusCode != 200) {
          throw _failure(response.statusCode);
        }
        if (response.headers.contentType?.mimeType == 'text/event-stream') {
          return _readStream(response, canSend: canSend, onAnswer: onAnswer);
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 32 * 1024) {
            throw const AssistantFailure('invalid_reply');
          }
          bytes.addAll(chunk);
        }
        final data = jsonDecode(utf8.decode(bytes));
        if (data is! Json) throw const AssistantFailure('invalid_reply');
        return data;
      })().timeout(
        const Duration(seconds: 38),
        onTimeout: () => throw const AssistantFailure('timeout'),
      );
    } on IOException {
      throw const AssistantFailure('network');
    } on FormatException {
      throw const AssistantFailure('invalid_reply');
    } finally {
      client.close(force: true);
    }
  }

  static AssistantFailure _failure(int status) =>
      AssistantFailure(switch (status) {
        401 => 'unauthorized',
        422 => 'invalid_reply',
        429 => 'quota',
        504 => 'timeout',
        _ => 'unavailable',
      });

  Future<Json> _readStream(
    HttpClientResponse response, {
    bool Function()? canSend,
    void Function(String)? onAnswer,
  }) async {
    var received = 0;
    final bounded = response.map((bytes) {
      received += bytes.length;
      if (received > 128 * 1024) throw const AssistantFailure('invalid_reply');
      return bytes;
    });
    var answer = '';
    await for (final line
        in bounded.transform(utf8.decoder).transform(const LineSplitter())) {
      if (canSend?.call() == false) throw const AssistantFailure('cancelled');
      if (!line.startsWith('data: ')) continue;
      final event = jsonDecode(line.substring(6));
      if (event is! Json) throw const AssistantFailure('invalid_reply');
      switch (event) {
        case {'delta': final String delta}:
          answer += delta;
          if (answer.length > 4800) {
            throw const AssistantFailure('invalid_reply');
          }
          onAnswer?.call(answer);
        case {'reply': final Json reply}:
          return reply;
        case {'error': final int status}:
          throw _failure(status);
        default:
          throw const AssistantFailure('invalid_reply');
      }
    }
    throw const AssistantFailure('network');
  }
}
