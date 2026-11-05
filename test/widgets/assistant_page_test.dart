import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/assistant_page.dart';
import 'package:piano_practice/platform/assistant_gateway.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import 'cognitive_pages_test.dart' show mocks;
import 'rhythm_pages_test.dart' show MemoryPreferences;

class _Records extends MemoryPreferences {
  int queries = 0;
  int details = 0;

  @override
  Future<List<Json>> assistantRecords({
    required DateTime from,
    required DateTime until,
    String? taskId,
    String? contentId,
  }) async {
    queries++;
    return [
      {'session_id': 'private-local-id'},
    ];
  }

  @override
  Future<Json?> detail(String id) async {
    details++;
    return {
      'session_id': id,
      'task_id': 'DANCE',
      'content_id': 'hkpdf-balance-six',
      'status': 'COMPLETED',
      'started_utc_ms': DateTime.now().millisecondsSinceEpoch,
      'session_utc_offset_minutes': 480,
      'result_json': jsonEncode({
        'active_ms': 62000,
        'title_zh': '新平衡舞步六式',
        'parts': [
          {'title': '第一部分', 'active_ms': 62000, 'reached_end': true},
        ],
        'private_data': 'must not be transmitted',
      }),
    };
  }
}

class _ManyRecords extends _Records {
  @override
  Future<List<Json>> assistantRecords({
    required DateTime from,
    required DateTime until,
    String? taskId,
    String? contentId,
  }) async => [
    for (var i = 0; i < 9; i++) {'session_id': 'record-$i'},
  ];
}

class _Gateway extends AssistantGateway {
  _Gateway() : super('https://example.invalid');
  final calls = <Json>[];

  @override
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
    expect(canSend(), isTrue);
    calls.add({'question': question, 'history': history, 'context': context});
    return AssistantReply(
      answer: context == null ? '已回答普通问题' : '已根据记录整理表现',
      references: context == null
          ? {}
          : {
              1: {'playback_seconds'},
            },
    );
  }
}

void main() {
  test('debug gateway permits USB loopback and rejects external cleartext', () {
    expect(AssistantGateway('http://127.0.0.1:8080/').available, isTrue);
    expect(AssistantGateway('http://192.168.1.10:8080/').available, isFalse);
    expect(AssistantGateway('http://example.invalid/').available, isFalse);
  });

  AppController setup(
    WidgetTester tester,
    _Records records,
    _Gateway gateway, {
    double scale = 1,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform_events/v1'),
          (_) async => null,
        );
    final c = AppController(repository: records, assistant: gateway);
    mocks(tester, const Size(360, 800), 'zh-Hans', scale, c);
    records.profile['profile_id'] = 'test-profile';
    addTearDown(c.dispose);
    return c;
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    final input = find.byKey(const ValueKey('assistant-question'));
    await tester.ensureVisible(input);
    await tester.enterText(input, text);
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('assistant-send')));
  }

  testWidgets(
    'home asks without a selected record and authorizes recent data',
    (tester) async {
      final records = _Records();
      final gateway = _Gateway();
      final c = setup(tester, records, gateway);
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('home-assistant')));
      expect(find.byType(AssistantPage), findsOneWidget);
      expect(find.byTooltip('移除关联练习'), findsNothing);
      expect(tester.getCenter(find.text('今天想聊天什么？')).dy, closeTo(200, 1));

      await send(tester, '怎么设置提醒？');
      expect(records.queries, 0);
      expect(records.details, 0);
      expect(gateway.calls.single['context'], isNull);

      await send(tester, '我最近舞蹈练得怎么样？');
      expect(find.text('结合训练记录？'), findsOneWidget);
      expect(records.queries, 0);
      expect(gateway.calls, hasLength(1));
      await tap(tester, find.text('允许结合记录'));
      expect(records.queries, 1);
      expect(records.details, 1);
      final payload = jsonEncode(gateway.calls.last['context']);
      expect(payload, contains('"playback_seconds":62'));
      expect(payload, isNot(contains('private-local-id')));
      expect(payload, isNot(contains('private_data')));
      await tap(tester, find.text('查看参考依据'));
      expect(find.textContaining('播放秒数 62'), findsOneWidget);
      await tap(tester, find.text('新平衡舞步六式'));
      expect(find.text('完成练习'), findsOneWidget);
    },
  );

  testWidgets(
    'selected practice is optional and revocation excludes prior summaries',
    (tester) async {
      final records = _Records();
      final gateway = _Gateway();
      final c = setup(tester, records, gateway, scale: 1.5);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: AssistantPage(
            c: c,
            recordId: 'private-local-id',
            recordLabel: '本次练习 · 舞蹈跟练',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('本次练习 · 舞蹈跟练'), findsOneWidget);
      await send(tester, '怎么设置提醒？');
      expect(records.details, 0);
      await send(tester, '这次练习怎么样？');
      await tap(tester, find.text('仅提问').last);
      expect(gateway.calls.last['context'], isNull);
      expect(records.details, 0);
      await send(tester, '请点评这次练习');
      await tap(tester, find.text('允许结合记录'));
      expect(gateway.calls.last['context']['evidence'], hasLength(1));
      expect(find.text('训练记录已开启'), findsNothing);
      expect(find.text('自动选择范围'), findsNothing);
      await c.setAssistantRecordsAllowed(false);
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('移除关联练习'));
      await send(tester, '怎么设置通知提醒？');
      expect(gateway.calls.last['context'], isNull);
      expect(gateway.calls.last['history'], isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the unconfigured page fits a narrow screen with large text', (
    tester,
  ) async {
    final c = AppController(
      repository: _Records(),
      assistant: AssistantGateway(''),
    );
    addTearDown(c.dispose);
    mocks(tester, const Size(320, 640), 'en', 2, c);
    c.repository.profile['profile_id'] = 'test-profile';
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: true),
        home: AssistantPage(c: c),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text('What would you like to talk about today?'),
      findsOneWidget,
    );
    expect(find.text('Online service is not configured'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Online service is not configured')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('assistant-question'))).dy,
      ),
    );
    await send(tester, '?');
    expect(find.text('Online Q&A is not configured'), findsOneWidget);
    expect(find.text('Local summaries and help'), findsNothing);
    await tap(tester, find.byTooltip('Conversations'));
    expect(find.text('New chat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'right swipe opens a compact sidebar from the conversation body',
    (tester) async {
      final records = _Records();
      final c = setup(tester, records, _Gateway());
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: AssistantPage(c: c),
        ),
      );
      await tester.pumpAndSettle();
      await send(tester, '怎么设置提醒？');
      // Start well inside the page, rather than at the screen's left edge.
      await tester.dragFrom(const Offset(100, 350), const Offset(230, 0));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );
      final drawer = find.byType(Drawer);
      expect(
        find.descendant(of: drawer, matching: find.text('历史对话')),
        findsNothing,
      );
      expect(
        find.descendant(of: drawer, matching: find.byIcon(Icons.close)),
        findsNothing,
      );
      expect(find.text('对话保存在本机。同一对话会延续上下文；新对话独立开始。'), findsNothing);
      expect(find.text('允许助手按问题查询训练记录，可随时撤回。'), findsNothing);
      expect(
        find.descendant(of: drawer, matching: find.text('AI 结合训练记录')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('assistant-new-chat')), findsOneWidget);
      await tester.tapAt(const Offset(350, 400));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isFalse,
      );
      await tap(tester, find.byTooltip('历史对话'));
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'conversation sidebar restores history and new chats isolate memory',
    (tester) async {
      final records = _Records();
      final gateway = _Gateway();
      final c = setup(tester, records, gateway);
      Widget page() => MaterialApp(
        theme: qinTheme(highContrast: false),
        home: AssistantPage(c: c),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await send(tester, '设置提醒的问题 $i');
      }
      expect(gateway.calls.last['history'], hasLength(8));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('历史对话'));
      await tap(tester, find.text('设置提醒的问题 0'));
      await send(tester, '继续说说通知设置');
      expect(gateway.calls.last['history'], hasLength(10));
      await tap(tester, find.byTooltip('新对话'));
      await send(tester, '一个新的普通问题');
      expect(gateway.calls.last['history'], isEmpty);
      expect(
        (await c.assistantConversations.list('test-profile')),
        hasLength(2),
      );
      await tap(tester, find.byTooltip('历史对话'));
      await tap(tester, find.byType(PopupMenuButton<String>).first);
      await tap(tester, find.text('重命名'));
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '练习讨论',
      );
      await tap(tester, find.text('保存'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('练习讨论'), findsOneWidget);
      await tap(tester, find.byType(PopupMenuButton<String>).first);
      await tap(tester, find.text('删除'));
      await tap(tester, find.widgetWithText(TextButton, '删除'));
      expect(await c.assistantConversations.list('test-profile'), hasLength(1));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('authorized record requests can include more than six records', (
    tester,
  ) async {
    final records = _ManyRecords();
    final gateway = _Gateway();
    final c = setup(tester, records, gateway);
    await c.setAssistantRecordsAllowed(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: AssistantPage(c: c),
      ),
    );
    await tester.pumpAndSettle();
    await send(tester, '查看我的所有舞蹈记录');
    expect(gateway.calls.last['context']['evidence'], hasLength(9));
    expect(tester.takeException(), isNull);
  });

  test(
    'online reply cannot cite a record or metric absent from the request',
    () {
      const context = {
        'evidence': [
          {
            'ref': 1,
            'metrics': {'matched_notes': 8},
          },
        ],
      };
      expect(
        () => AssistantReply.parse({
          'answer': '练习结果',
          'references': [
            {
              'ref': 1,
              'metrics': ['tempo_bpm'],
            },
          ],
        }, context),
        throwsA(isA<AssistantFailure>()),
      );
      expect(
        () => AssistantReply.parse({
          'answer': '练习结果',
          'references': [
            {
              'ref': 2,
              'metrics': ['matched_notes'],
            },
          ],
        }, context),
        throwsA(isA<AssistantFailure>()),
      );
    },
  );
}
