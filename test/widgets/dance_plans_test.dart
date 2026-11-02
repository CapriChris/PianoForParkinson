import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:piano_practice/data/database_safety.dart';
import 'package:piano_practice/domain/dance_training.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/features/dance_page.dart';
import 'package:piano_practice/features/plans_page.dart';
import 'package:piano_practice/ui/qin_theme.dart';
import 'package:piano_practice/ui/qin_components.dart';

import 'cognitive_pages_test.dart' show mocks;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'Asia/Shanghai',
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            if (call.method == 'pendingNotificationRequests') {
              return <dynamic>[];
            }
            if (call.method == 'getNotificationAppLaunchDetails') {
              return {'notificationLaunchedApp': false};
            }
            return true;
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform_events/v1'),
          (_) async => null,
        );
  });
  testWidgets('plans show a quiet empty state and retain management actions', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform_events/v1'),
          (_) async => null,
        );
    sqfliteFfiInit();
    final c = AppController();
    addTearDown(c.dispose);
    mocks(tester, const Size(320, 640), 'zh-Hans', 2, c);
    c.repository.profile['profile_id'] = 'plan-ui';
    await tester.runAsync(() async {
      c.repository.db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      for (final sql in DatabaseSafety.migration4.split(';')) {
        if (sql.trim().isNotEmpty) await c.repository.db.execute(sql);
      }
    });
    addTearDown(() => c.repository.db.close());
    Future<void> settleStore() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    Widget page(Key key) => MaterialApp(
      key: key,
      theme: qinTheme(highContrast: false),
      home: Scaffold(
        body: PlansPage(c: c, onStart: (_) async {}),
      ),
    );
    await tester.pumpWidget(page(const ValueKey('empty')));
    await settleStore();
    expect(find.text('暂无计划'), findsOneWidget);
    expect(find.text('点击下方按钮创建你的计划'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('plan-empty-card')),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    final create = find.byKey(const ValueKey('create-plan-floating'));
    final pageBounds = tester.getRect(find.byType(PlansPage));
    final createBounds = tester.getRect(create);
    expect(createBounds.center.dx, closeTo(pageBounds.center.dx, 1));
    expect(
      pageBounds.bottom - createBounds.bottom,
      closeTo(planAddButtonBottomGap, 1),
    );
    expect(find.text('新建计划'), findsNothing);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.byType(PlanEditor), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(PlanEditor), findsNothing);
    expect(find.text('管理计划'), findsNothing);
    expect(find.textContaining('提醒暂不可用'), findsNothing);
    await tester.runAsync(
      () => scheduleStore(c).savePlan({
        'id': 'plan-ui',
        'title': '每日舞蹈',
        'kind': 'dance',
        'start': localDay(DateTime.now()),
        'end': null,
        'days': [],
        'target_type': 'count',
        'target': 1,
        'paused': false,
        'reminder': false,
        'hour': 15,
        'minute': 0,
      }),
    );
    await tester.runAsync(() async {
      final existing = (await scheduleStore(c).plans()).single;
      await scheduleStore(c).saveDance({
        'session_id': 'completed-for-card',
        'started_utc_ms': DateTime.now().millisecondsSinceEpoch,
        'active_ms': 1000,
        'covered_ms': 1000,
        'confirmed': true,
      });
      await scheduleStore(c).savePlan({
        ...existing,
        'id': 'future-plan',
        'title': '未来舞蹈',
        'start': '2099-01-01',
      });
    });
    await tester.pumpWidget(page(const ValueKey('populated')));
    await settleStore();
    final scroll = find.byType(Scrollable).last;
    expect(find.text('管理计划'), findsNothing);
    expect(find.text('关联记录'), findsNothing);
    expect(find.text('跳过'), findsNothing);
    expect(find.text('今天'), findsNothing);
    final card = find.byKey(const ValueKey('plan-card-plan-ui'));
    expect(find.text('已完成'), findsOneWidget);
    await tester.ensureVisible(find.text('已完成'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanEditor), findsNothing);
    await tester.scrollUntilVisible(find.text('开始练习'), 100, scrollable: scroll);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('开始练习'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    final enabled = find.byKey(const ValueKey('plan-enabled-plan-ui'));
    await tester.scrollUntilVisible(enabled, -100, scrollable: scroll);
    await tester.pumpAndSettle();
    await tester.tap(enabled);
    await tester.pumpAndSettle();
    await settleStore();
    expect(tester.widget<Switch>(enabled).value, isFalse);
    expect(
      tester.widget<Text>(find.text('每日舞蹈')).style?.color,
      QinPalette.standard.muted.withValues(alpha: .72),
    );
    expect(
      (await tester.runAsync(() => scheduleStore(c).plans()))!
          .firstWhere((p) => p['id'] == 'plan-ui')['paused'],
      isTrue,
    );
    await tester.tap(find.text('每日舞蹈'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanEditor), findsOneWidget);
    expect(find.text('编辑计划'), findsOneWidget);
    Navigator.of(tester.element(find.byType(PlanEditor))).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('每日舞蹈'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsWidgets);
    final toolbar = find.byKey(const ValueKey('plan-selection-toolbar'));
    final toolbarBounds = tester.getRect(toolbar);
    await tester.drag(scroll, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.getRect(toolbar), toolbarBounds);
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);
    expect(find.text('全不选'), findsOneWidget);
    await tester.tap(find.text('全不选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除这 2 项计划？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await tester.pumpAndSettle();
    expect(
      (await tester.runAsync(() => scheduleStore(c).plans()))!
          .where((p) => p['deleted'] != true)
          .length,
      2,
    );
    await tester.ensureVisible(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除').last);
    await tester.pumpAndSettle();
    await settleStore();
    expect(find.text('暂无计划'), findsOneWidget);
    final now = DateTime.now();
    await tester.runAsync(
      () => scheduleStore(c).savePlan({
        'id': 'expired-plan',
        'title': '已过期计划',
        'kind': 'dance',
        'start': localDay(DateTime(now.year, now.month, now.day - 1)),
        'end': null,
        'days': <int>[],
        'target_type': 'count',
        'target': 1,
        'paused': false,
        'reminder': false,
        'hour': 10,
        'minute': 0,
      }),
    );
    await tester.pumpWidget(page(const ValueKey('expired')));
    await settleStore();
    final expired = find.byKey(const ValueKey('plan-enabled-expired-plan'));
    expect(tester.widget<Switch>(expired).value, isFalse);
    expect(tester.widget<Switch>(expired).onChanged, isNull);
    expect(find.text('已结束'), findsOneWidget);
    expect(
      (await tester.runAsync(() => scheduleStore(c).plans()))!
          .firstWhere((p) => p['id'] == 'expired-plan')['paused'],
      isTrue,
    );
    await tester.tap(expired);
    await tester.pumpAndSettle();
    expect(find.byType(PlanEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final editing in [false, true]) {
    testWidgets(
      'target stepper supports buttons and typing, editing=$editing',
      (tester) async {
        final c = AppController();
        addTearDown(c.dispose);
        mocks(tester, const Size(390, 844), 'zh-Hans', 1, c);
        final plan = <String, dynamic>{
          'id': 'edit-counter',
          'title': 'Plan',
          'kind': 'dance',
          'target': 5,
          'start': localDay(DateTime.now()),
          'end': null,
          'days': <int>[],
          'target_type': 'count',
          'reminder': false,
          'hour': 10,
          'minute': 0,
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: qinTheme(highContrast: false),
            home: PlanEditor(c: c, plan: editing ? plan : null),
          ),
        );
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('plan-target-input'));
        final plus = find.byKey(const ValueKey('plan-target-increase'));
        final minus = find.byKey(const ValueKey('plan-target-decrease'));
        String value() => tester.widget<TextField>(input).controller!.text;
        expect(value(), editing ? '5' : '1');
        await tester.ensureVisible(plus);
        await tester.pumpAndSettle();
        await tester.tap(plus);
        await tester.pumpAndSettle();
        expect(value(), editing ? '6' : '2');
        await tester.tap(minus);
        await tester.pumpAndSettle();
        expect(value(), editing ? '5' : '1');
        await tester.enterText(input, '42');
        await tester.pumpAndSettle();
        await tester.tap(plus);
        await tester.pumpAndSettle();
        expect(value(), '43');
        await tester.enterText(input, '1000');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.descendant(of: plus, matching: find.byType(IconButton)),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(input, '1');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.descendant(of: minus, matching: find.byType(IconButton)),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(input, '');
        await tester.pumpAndSettle();
        await tester.tap(plus);
        await tester.pumpAndSettle();
        expect(value(), '1');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'editor saves a specific piano activity, custom repeat and wheel time',
    (tester) async {
      sqfliteFfiInit();
      final c = AppController();
      addTearDown(c.dispose);
      mocks(tester, const Size(390, 844), 'zh-Hans', 1, c);
      c.repository.profile['profile_id'] = 'editor';
      await tester.runAsync(() async {
        await c.content.load();
        c.repository.db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
        );
        for (final sql in DatabaseSafety.migration4.split(';')) {
          if (sql.trim().isNotEmpty) await c.repository.db.execute(sql);
        }
      });
      addTearDown(() => c.repository.db.close());
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => PlanEditor(c: c)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      Future<void> reveal(Finder finder) async {
        await tester.scrollUntilVisible(
          finder,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byType(TextField).first, '钢琴计划');
      await tester.tap(find.text('舞蹈训练'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('钢琴训练').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('请选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旋律记忆'));
      await tester.pumpAndSettle();
      await reveal(find.byKey(const ValueKey('plan-repeat')));
      await tester.tap(find.byKey(const ValueKey('plan-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repeat-weekdays')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repeat-custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repeat-day-1')));
      await tester.tap(find.byKey(const ValueKey('repeat-day-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanRepeatPage), findsNothing);
      await reveal(find.byType(SwitchListTile));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await reveal(find.byKey(const ValueKey('plan-hour-picker')));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      final initialHour = tester
          .widget<CupertinoPicker>(
            find.byKey(const ValueKey('plan-hour-picker')),
          )
          .scrollController!
          .initialItem;
      await tester.drag(
        find.byKey(const ValueKey('plan-hour-picker')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '完成'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      final plan = (await tester.runAsync(() => scheduleStore(c).plans()))!
          .single;
      expect(plan['kind'], 'exercise');
      expect(plan['training_id'], 'G1_MEMORY');
      expect(plan['target_type'], 'count');
      expect(plan['repeat_mode'], 'custom');
      expect(plan['days'], [1, 3]);
      expect(plan['hour'], isNot(initialHour));
      expect(plan['reminder'], isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test('weekday summaries distinguish continuous and separate days', () {
    final c = AppController();
    c.repository.profile = {'locale': 'zh-Hans'};
    addTearDown(c.dispose);
    expect(repeatDaysLabel({2, 3, 4}, c), '周二到周四');
    expect(repeatDaysLabel({5, 1, 3}, c), '周一、周三、周五');
    expect(repeatDaysLabel({1, 2, 3, 4, 5, 6, 7}, c), '每天');
    expect(repeatDaysLabel({7}, c), '周日');
  });

  testWidgets(
    'back saves or discards changes and validation failure keeps the editor',
    (tester) async {
      sqfliteFfiInit();
      final c = AppController();
      addTearDown(c.dispose);
      mocks(tester, const Size(390, 844), 'zh-Hans', 1, c);
      c.repository.profile['profile_id'] = 'back';
      await tester.runAsync(() async {
        c.repository.db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
        );
        for (final sql in DatabaseSafety.migration4.split(';')) {
          if (sql.trim().isNotEmpty) await c.repository.db.execute(sql);
        }
      });
      addTearDown(() => c.repository.db.close());
      final plan = <String, dynamic>{
        'id': 'back-plan',
        'title': '原名称',
        'kind': 'dance',
        'start': localDay(DateTime.now()),
        'days': <int>[],
        'target_type': 'count',
        'target': 1,
        'reminder': false,
        'paused': false,
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PlanEditor(c: c, plan: plan),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      Future<void> back() async {
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
      }

      await open();
      await back();
      expect(find.byType(PlanEditor), findsNothing);
      expect(find.text('是否保存更改？'), findsNothing);
      await open();
      await tester.enterText(find.byType(TextField).first, '放弃的名称');
      await back();
      expect(find.text('是否保存更改？'), findsOneWidget);
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanEditor), findsNothing);
      expect(await tester.runAsync(() => scheduleStore(c).plans()), isEmpty);
      await open();
      await tester.enterText(find.byType(TextField).first, '已保存名称');
      await back();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlanEditor), findsNothing);
      expect(
        (await tester.runAsync(() => scheduleStore(c).plans()))!
            .single['title'],
        '已保存名称',
      );
      await open();
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('是否保存更改？'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanEditor), findsOneWidget);
      expect(find.textContaining('请填写名称'), findsOneWidget);
      expect(
        (await tester.runAsync(() => scheduleStore(c).plans()))!
            .single['title'],
        '已保存名称',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('piano piece selection is a single general option', (
    tester,
  ) async {
    final c = AppController();
    addTearDown(c.dispose);
    mocks(tester, const Size(390, 844), 'zh-Hans', 1, c);
    await tester.runAsync(c.content.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: PlanTrainingPicker(
          c: c,
          selectedKind: 'piece',
          selectedId: 'any',
        ),
      ),
    );
    expect(find.byType(ListTile), findsNWidgets(8));
    expect(find.text('钢琴曲目'), findsOneWidget);
    for (final piece in c.content.pieces) {
      expect(find.text(piece.title(c.locale)), findsNothing);
    }
  });

  for (final preset in <String, Set<int>>{
    'weekdays': {1, 2, 3, 4, 5},
    'weekends': {6, 7},
    'daily': {1, 2, 3, 4, 5, 6, 7},
  }.entries) {
    testWidgets('custom repeat normalizes to ${preset.key}', (tester) async {
      final c = AppController();
      addTearDown(c.dispose);
      mocks(tester, const Size(390, 844), 'zh-Hans', 1, c);
      (String, Set<int>)? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.push<(String, Set<int>)>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlanRepeatPage(
                        c: c,
                        mode: 'custom',
                        days: preset.value,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(selected!.$1, preset.key);
      expect(selected!.$2, preset.value);
    });
  }
  for (final locale in ['zh-Hans', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('dance and plan form fit 320dp $locale $scale', (
        tester,
      ) async {
        final c = AppController();
        addTearDown(c.dispose);
        mocks(tester, const Size(320, 640), locale, scale, c);
        await tester.pumpWidget(
          MaterialApp(
            theme: qinTheme(highContrast: false),
            home: DancePage(c: c),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: qinTheme(highContrast: false),
            home: PlanEditor(c: c),
            key: const ValueKey("plan-editor-app"),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byType(SwitchListTile),
          200,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
        expect(tester.takeException(), isNull);
      });
      testWidgets('practice categories filter entries $locale $scale', (
        tester,
      ) async {
        final c = AppController();
        addTearDown(c.dispose);
        mocks(tester, const Size(320, 640), locale, scale, c);
        await tester.runAsync(c.content.load);
        await tester.pumpWidget(
          MaterialApp(
            theme: qinTheme(highContrast: false),
            home: HomePage(c: c),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(c.text('练习', 'Practice')).last);
        await tester.pumpAndSettle();
        final dance = find.text(c.text('舞蹈跟练', 'Dance practice'));
        final pieces = find.text(c.text('钢琴曲目', 'Piano pieces'));
        final list = find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last;
        Future<void> reveal(Finder entry) async {
          await tester.scrollUntilVisible(entry, 100, scrollable: list);
          await tester.pumpAndSettle();
        }

        Future<void> choose(String value) async {
          tester.state<ScrollableState>(list).position.jumpTo(0);
          await tester.pumpAndSettle();
          final chip = find.byKey(ValueKey('practice-category-$value'));
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
          final categories = [
            'all',
            'piano',
            'dance',
          ].map((id) => find.byKey(ValueKey('practice-category-$id'))).toList();
          final width = tester.getRect(categories.first).width;
          for (final category in categories) {
            expect(tester.getRect(category).width, closeTo(width, 1));
            expect(
              tester
                  .getRect(
                    find
                        .descendant(
                          of: category,
                          matching: find.byType(Material),
                        )
                        .first,
                  )
                  .width,
              closeTo(width, 1),
            );
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        await choose('dance');
        await reveal(dance);
        expect(dance, findsOneWidget);
        expect(find.byType(PracticeCard), findsOneWidget);
        expect(
          tester.widget<PracticeCard>(find.byType(PracticeCard)).title,
          c.text('舞蹈跟练', 'Dance practice'),
        );
        await choose('piano');
        await reveal(pieces);
        expect(dance, findsNothing);
        expect(pieces, findsOneWidget);
        await choose('all');
        await reveal(pieces);
        expect(pieces, findsOneWidget);
        await reveal(dance);
        expect(dance, findsOneWidget);
      });
      testWidgets('four navigation entries fit 320dp $locale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: qinTheme(highContrast: false),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                bottomNavigationBar: QinNavigationBar(
                  selected: 2,
                  labels: locale == 'en'
                      ? ['Home', 'Practice', 'Plan', 'History']
                      : ['首页', '练习', '计划', '记录'],
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
      });
    }
  }
}
