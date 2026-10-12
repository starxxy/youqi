import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youqi/core.dart';
import 'package:youqi/ui.dart';
import 'package:youqi/editors.dart';
import 'core_test.dart' show taskInput;

void main() {
  final nativeCalls = <MethodCall>[];
  var todoPinned = false;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final iconFile = File(
        '${Platform.environment['FLUTTER_ROOT'] ?? 'E:/mic/flutter/flutter'}/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (await iconFile.exists()) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(
            Future.value(ByteData.sublistView(await iconFile.readAsBytes())));
      await icons.load();
    }
    final file = File('C:/Windows/Fonts/msyh.ttc');
    if (await file.exists()) {
      // Widget tests have no OS font fallback; load the picker aliases as well.
      for (final family in [
        'Roboto',
        'CupertinoSystemDisplay',
        'CupertinoSystemText'
      ]) {
        final font = FontLoader(family)
          ..addFont(
              Future.value(ByteData.sublistView(await file.readAsBytes())));
        await font.load();
      }
    }
  });
  setUp(() {
    nativeCalls.clear();
    todoPinned = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidRepository.channel, (call) async {
      nativeCalls.add(call);
      if (call.method == 'setTodoNotification')
        todoPinned = call.arguments as bool;
      if (call.method == 'status')
        return {
          'exact': true,
          'notifications': true,
          'fullScreen': true,
          'battery': true,
          'scheduledCount': 2,
          'nativeGeneration': 0,
          'todoPinned': todoPinned,
          'nextLabel': '下一次 10 月 12 日 07:00 · 起床'
        };
      if (call.method == 'history') return <dynamic>[];
      return null;
    });
  });
  Future<YouqiStore> seed() async {
    final s =
        YouqiStore(MemoryRepository(), clock: () => DateTime(2026, 10, 11, 8));
    await s.init();
    await s.addTask({
      ...taskInput(date: '2026-10-08'),
      'title': '完成课程作业',
      'dueDate': '2026-10-09',
      'scheduleStart': null,
      'scheduleEnd': null,
      'reminders': <Json>[]
    });
    await s.addTask({...taskInput(), 'title': '阅读 30 分钟'});
    await s.addTask({
      ...taskInput(),
      'title': '整理项目资料',
      'scheduleStart': '14:00',
      'scheduleEnd': '15:00'
    });
    return s;
  }

  for (final layout in ['a', 'b', 'c']) {
    testWidgets('滚轮 $layout：初值、午夜循环、震动、确认取消与窄屏', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final haptics = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final s = await seed();
      String? selected;
      final boundary = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
          key: boundary,
          child: UiScope(
              store: s,
              palette: Palette(layout, layout == 'c', true),
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                      platform: TargetPlatform.android,
                      brightness:
                          layout == 'c' ? Brightness.dark : Brightness.light,
                      colorSchemeSeed:
                          Palette(layout, layout == 'c', true).accent),
                  home: Scaffold(
                      body: Builder(
                          builder: (c) => TextButton(
                              onPressed: () async {
                                selected = await chooseTime(c, '23:59');
                              },
                              child: const Text('设置时间'))))))));
      await t.tap(find.text('设置时间'));
      await t.pumpAndSettle();
      expect(find.text('23:59'), findsOneWidget);
      expect(haptics, isEmpty, reason: '打开选择器不产生震动');
      if (const bool.fromEnvironment('SCREENSHOTS')) {
        await t.runAsync(() async {
          final im = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final png = await im.toByteData(format: ui.ImageByteFormat.png);
          await Directory('screenshots/v0.2.0').create(recursive: true);
          await File('screenshots/v0.2.0/$layout-time-wheel.png')
              .writeAsBytes(png!.buffer.asUint8List());
          im.dispose();
        });
      }
      // Move through the last item: hour/minute wrap independently to 00.
      final hour =
          t.widget<CupertinoPicker>(find.byKey(const ValueKey('hour-wheel')));
      final minute =
          t.widget<CupertinoPicker>(find.byKey(const ValueKey('minute-wheel')));
      hour.scrollController!.jumpToItem(24);
      minute.scrollController!.jumpToItem(60);
      await t.pumpAndSettle();
      expect(find.text('00:00'), findsOneWidget);
      expect(haptics.length, 2);
      // A repeated callback at the same detent must not vibrate again.
      hour.onSelectedItemChanged!(0);
      expect(haptics.length, 2);
      await t.tap(find.text('确认'));
      await t.pumpAndSettle();
      expect(selected, '00:00');
      expect(t.takeException(), isNull);
      t.view.physicalSize = const Size(320, 640);
      await t.tap(find.text('设置时间'));
      await t.pumpAndSettle();
      await t.drag(
          find.byKey(const ValueKey('minute-wheel')), const Offset(0, -52));
      await t.pumpAndSettle();
      expect(haptics.length, greaterThan(2));
      expect(t.takeException(), isNull);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(selected, isNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      s.dispose();
    });
    testWidgets('布局 $layout：真实手机页面、导航、编辑与窄屏', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = await seed();
      s.appearance['layout'] = layout;
      s.appearance['mode'] = layout == 'c' ? 'dark' : 'light';
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(key: key, child: YouqiApp(store: s)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (const bool.fromEnvironment('SCREENSHOTS')) {
        await t.runAsync(() async {
          final im = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final png = await im.toByteData(format: ui.ImageByteFormat.png);
          await Directory('screenshots').create(recursive: true);
          await File('screenshots/$layout-home.png')
              .writeAsBytes(png!.buffer.asUint8List());
          im.dispose();
        });
      }
      await t.tap(find.text('日程').last);
      await t.pumpAndSettle();
      expect(find.text('每日时间规划'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('闹钟').last);
      await t.pumpAndSettle();
      expect(find.text('独立闹钟'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('设置').last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.text('待办').last);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('添加待办'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '手机端新建事项');
      await t.ensureVisible(find.text('保存设置'));
      await t.tap(find.text('保存设置'));
      await t.pumpAndSettle();
      expect(s.tasks.any((x) => x['title'] == '手机端新建事项'), isTrue);
      expect(t.takeException(), isNull);
      t.view.physicalSize = const Size(320, 640);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      s.dispose();
    });
  }
  testWidgets('自定义重响数值支持非预设间隔并正确关闭弹窗', (t) async {
    Json profile = ringDefaults();
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: StatefulBuilder(
                    builder: (c, update) => RingFields(
                        profile: profile,
                        onChanged: (v) => update(() => profile = v)))))));
    await t.tap(find.text('铃声、振动与重响'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('输入自定义时长、间隔和次数'));
    await t.tap(find.text('输入自定义时长、间隔和次数'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), '75');
    await t.enterText(find.byType(TextField).at(1), '7');
    await t.enterText(find.byType(TextField).at(2), '4');
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(profile['duration'], 75);
    expect(profile['snooze'], 7);
    expect(profile['maxSnoozes'], 4);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('权限状态刷新与十秒响铃测试通过原生接口提交', (t) async {
    await t
        .pumpWidget(const MaterialApp(home: Scaffold(body: PermissionPanel())));
    await t.pumpAndSettle();
    expect(find.text('已开启'), findsNWidgets(4));
    await t.ensureVisible(find.text('10 秒后测试响铃'));
    await t.tap(find.text('10 秒后测试响铃'));
    await t.pumpAndSettle();
    final request = nativeCalls.lastWhere((c) => c.method == 'oneShot');
    expect(request.arguments['seconds'], 10);
    expect(request.arguments['ring']['vibrate'], true);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('常驻待办默认关闭，开关调用本机接口且不产生同步变更', (t) async {
    final s = await seed();
    final before = (s.data['outbox'] as List).length;
    await t.pumpWidget(YouqiApp(store: s));
    await t.pumpAndSettle();
    await t.tap(find.text('设置').last);
    await t.pumpAndSettle();
    final toggle = find.byType(SwitchListTile);
    await t.ensureVisible(toggle);
    expect(t.widget<SwitchListTile>(toggle).value, false);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(
        nativeCalls
            .lastWhere((c) => c.method == 'setTodoNotification')
            .arguments,
        true);
    expect(t.widget<SwitchListTile>(toggle).value, true);
    expect((s.data['outbox'] as List).length, before);
    await t.pumpWidget(const SizedBox());
    s.dispose();
  });
}
