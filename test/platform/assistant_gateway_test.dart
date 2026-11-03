import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/platform/assistant_gateway.dart';

void main() {
  test('gateway posts UTF-8 JSON with an explicit byte length', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <({String path, int length, List<int> body})>[];
    server.listen((request) async {
      final body = await request.expand((bytes) => bytes).toList();
      received.add((
        path: request.uri.path,
        length: request.contentLength,
        body: body,
      ));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        request.uri.path == '/v1/install'
            ? '{"token":"test-installation"}'
            : '{"answer":"回答","references":[]}',
      );
      await request.response.close();
    });
    final gateway = AssistantGateway('http://127.0.0.1:${server.port}');
    final reply = await gateway.ask(
      locale: 'zh-Hans',
      question: '怎么设置重复提醒？',
      requestId: 'test-request',
      history: [],
      canSend: () => true,
      onAnswer: (_) => fail('Legacy JSON does not send streaming chunks'),
    );
    expect(reply.answer, '回答');
    expect(received.map((request) => request.path), [
      '/v1/install',
      '/v1/chat',
    ]);
    for (final request in received) {
      expect(request.length, request.body.length);
    }
    expect(
      jsonDecode(utf8.decode(received.last.body))['question'],
      '怎么设置重复提醒？',
    );
  });

  for (final interrupted in [false, true]) {
    test('streams before the final event, interrupted=$interrupted', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final allowFinish = Completer<void>();
      final partial = Completer<String>();
      String? accept;
      server.listen((request) async {
        await request.drain<void>();
        final response = request.response;
        if (request.uri.path == '/v1/install') {
          response.headers.contentType = ContentType.json;
          response.write('{"token":"test-token"}');
        } else {
          accept = request.headers.value(HttpHeaders.acceptHeader);
          response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          response.bufferOutput = false;
          response.write('data: {"delta":"正在"}\n\n');
          await response.flush();
          await allowFinish.future;
          if (!interrupted) {
            response.write('data: {"delta":"回答"}\n\n');
            response.write(
              'data: {"reply":{"answer":"正在回答","references":[]}}\n\n',
            );
          }
        }
        await response.close();
      });
      final gateway = AssistantGateway('http://127.0.0.1:${server.port}');
      final answer = gateway.ask(
        locale: 'zh-Hans',
        question: '怎么设置提醒？',
        requestId: 'test-request',
        history: [],
        canSend: () => true,
        onAnswer: (text) {
          if (!partial.isCompleted) partial.complete(text);
        },
      );
      final finished = interrupted
          ? expectLater(answer, throwsA(isA<AssistantFailure>()))
          : expectLater(
              answer,
              completion(
                isA<AssistantReply>().having((r) => r.answer, 'answer', '正在回答'),
              ),
            );
      try {
        expect(await partial.future.timeout(const Duration(seconds: 3)), '正在');
        expect(accept, contains('text/event-stream'));
      } finally {
        allowFinish.complete();
      }
      await finished;
    });
  }
}
