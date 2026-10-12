import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core.dart';
import 'editors.dart';
import 'skins.dart';

const overdueColors = [
  Color(0xffe7aeb0),
  Color(0xffd98e95),
  Color(0xffc96d7b),
  Color(0xffb65165),
  Color(0xff9c3d55),
  Color(0xff802b46),
  Color(0xff632037)
];
const revisionColors = [
  Color(0xff557bca),
  Color(0xff8d66b4),
  Color(0xff4b9a8a),
  Color(0xffc46b95),
  Color(0xffb68c42)
];

class Palette {
  Palette(this.layout, this.dark, this.glass,
      {SkinProvider provider = const BuiltInSkins()})
      : tokens = provider.resolve(layout, dark: dark);
  final SkinTokens tokens;
  final String layout;
  final bool dark, glass;
  Color get bg => tokens.background;
  Color get text => tokens.text;
  Color get muted => tokens.muted;
  Color get accent => tokens.accent;
  Color get surface => tokens.surface;
  Color get line => tokens.divider;
}

class UiScope extends InheritedWidget {
  const UiScope(
      {super.key,
      required this.store,
      required this.palette,
      required super.child});
  final YouqiStore store;
  final Palette palette;
  static UiScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiScope>()!;
  @override
  bool updateShouldNotify(UiScope old) => true;
}

class Glass extends StatelessWidget {
  const Glass(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(17),
      this.radius = 21,
      this.accent = false});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final p = UiScope.of(context).palette;
    return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: p.glass ? p.tokens.blur : 0,
                sigmaY: p.glass ? p.tokens.blur : 0),
            child: Container(
                padding: padding,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                        color: p.glass
                            ? (p.dark
                                ? Colors.white.withOpacity(.15)
                                : Colors.white.withOpacity(.88))
                            : p.line),
                    gradient: p.glass
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                                p.surface.withOpacity(p.dark ? .82 : .88),
                                p.surface.withOpacity(p.dark ? .61 : .56)
                              ])
                        : null,
                    color: p.glass ? null : p.surface),
                child: child)));
  }
}

class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = UiScope.of(context).palette;
    return Container(
        color: p.bg,
        child: Stack(children: [
          if (p.glass)
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: RadialGradient(
                            center: const Alignment(-1, -.85),
                            radius: 1.6,
                            colors: [
                  p.accent.withOpacity(p.dark ? .10 : .14),
                  Colors.transparent
                ])))),
          if (p.glass)
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: RadialGradient(
                            center: const Alignment(1, .65),
                            radius: 1.4,
                            colors: [
                  const Color(0xff66b9bf).withOpacity(p.dark ? .045 : .09),
                  Colors.transparent
                ])))),
          child
        ]));
  }
}

void message(BuildContext context, String value) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
Future<void> guarded(
    BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) message(context, e.toString());
  }
}

Widget heading(BuildContext c, String title,
    {String? subtitle, Widget? trailing}) {
  final p = UiScope.of(c).palette;
  return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (subtitle != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(subtitle,
                    style: TextStyle(color: p.muted, fontSize: 12))),
          Text(title,
              style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.8))
        ])),
        if (trailing != null) trailing
      ]));
}

Widget section(BuildContext c, String text, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 22, 0, 12),
    child: Row(children: [
      Expanded(
          child: Text(text,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      if (action != null) action
    ]));
Widget chip(BuildContext c, String label, {Color? color, IconData? icon}) {
  final p = UiScope.of(c).palette;
  return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: (color ?? p.accent).withOpacity(.12),
          borderRadius: BorderRadius.circular(7)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color ?? p.accent),
          const SizedBox(width: 5)
        ],
        Text(label, style: TextStyle(fontSize: 11, color: color ?? p.accent))
      ]));
}

Widget statusChips(BuildContext c, Json o) {
  final s = UiScope.of(c).store,
      p = UiScope.of(c).palette,
      level = overdueLevel(o['dueDate'], s.today),
      rev = o['deadlineRevisionCount'] as int;
  return Wrap(spacing: 7, runSpacing: 7, children: [
    if (o['done'] == true)
      chip(c, '已完成', icon: Icons.check)
    else if (level > 0)
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
              color: overdueColors[level - 1],
              borderRadius: BorderRadius.circular(7)),
          child: Text('逾期 ${overdueDays(o['dueDate'], s.today)} 天 · $level 级',
              style: TextStyle(
                  fontSize: 11,
                  color: level <= 2 ? const Color(0xff4d2530) : Colors.white)))
    else
      chip(c, o['dueDate'] == s.today ? '今天截止' : prettyDay(o['dueDate']),
          color: p.muted),
    if (rev > 0)
      chip(c, '改期 $rev 次', color: revisionColors[rev % 5], icon: Icons.circle)
  ]);
}

Widget emptyState(BuildContext c, String title, String text,
        {VoidCallback? action, String button = '添加待办'}) =>
    Padding(
        padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 16),
        child: Column(children: [
          Icon(Icons.event_note_outlined,
              size: 42, color: UiScope.of(c).palette.accent),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 9),
          Text(text,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: UiScope.of(c).palette.muted, height: 1.7)),
          if (action != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: action,
                icon: const Icon(Icons.add),
                label: Text(button))
          ]
        ]));

class YouqiApp extends StatelessWidget {
  const YouqiApp(
      {super.key,
      required this.store,
      this.skinProvider = const BuiltInSkins()});
  final YouqiStore store;
  final SkinProvider skinProvider;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final a = store.appearance, mode = a['mode'];
        final dark = mode == 'dark' ||
            mode == 'system' &&
                WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                    Brightness.dark;
        final p = Palette(a['layout'], dark, a['glass'] == true,
            provider: skinProvider);
        return UiScope(
            store: store,
            palette: p,
            child: MaterialApp(
                title: '有期',
                locale: const Locale('zh', 'CN'),
                supportedLocales: const [Locale('zh', 'CN')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                    useMaterial3: true,
                    brightness: dark ? Brightness.dark : Brightness.light,
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: p.accent,
                        brightness: dark ? Brightness.dark : Brightness.light,
                        primary: p.accent,
                        surface: p.surface),
                    scaffoldBackgroundColor: p.bg,
                    textTheme: TextTheme(
                        bodyMedium: TextStyle(color: p.text, fontSize: 14)),
                    appBarTheme: AppBarTheme(
                        backgroundColor: Colors.transparent,
                        foregroundColor: p.text,
                        elevation: 0),
                    inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: p.surface.withOpacity(.75),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(13),
                            borderSide: BorderSide(color: p.line))),
                    filledButtonTheme: FilledButtonThemeData(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(44, 48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15))))),
                home: const HomeShell()));
      });
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int tab = 0;
  late String selectedDate;
  Timer? timer;
  Json nativeStatus = {};
  @override
  void initState() {
    super.initState();
    selectedDate = day(DateTime.now());
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        refreshStatus();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshStatus());
  }

  Future<void> refreshStatus() async {
    try {
      final r = await AndroidRepository.channel
          .invokeMapMethod<String, dynamic>('status');
      if (mounted) {
        final s = UiScope.of(context).store;
        await s.refreshNative(r?['nativeGeneration'] ?? 0);
        await s.materialize();
        if (!mounted) return;
        setState(() => nativeStatus = Map<String, dynamic>.from(r ?? {}));
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshStatus();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = UiScope.of(context), s = scope.store, p = scope.palette;
    return Scaffold(
        body: Backdrop(
            child: SafeArea(
                child: Stack(children: [
      Positioned.fill(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 115),
              children: [
            if (s.error != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Text(s.error!,
                      style: const TextStyle(color: Colors.red))),
            if (tab == 0)
              ...home(context)
            else if (tab == 1)
              ...schedule(context)
            else if (tab == 2)
              ...alarmPage(context)
            else
              ...settings(context)
          ])),
      Positioned(
          left: 14,
          right: 14,
          bottom: 12,
          child: Glass(
              radius: 26,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              child: Row(
                  children: List.generate(4, (i) {
                const labels = ['待办', '日程', '闹钟', '设置'];
                const icons = [
                  Icons.checklist_rounded,
                  Icons.calendar_today_outlined,
                  Icons.alarm_outlined,
                  Icons.tune_rounded
                ];
                return Expanded(
                    child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => setState(() => tab = i),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 13, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: i == tab
                                              ? p.accent.withOpacity(.13)
                                              : null,
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Icon(icons[i],
                                          color: i == tab ? p.accent : p.muted,
                                          size: 21)),
                                  const SizedBox(height: 4),
                                  Text(labels[i],
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: i == tab ? p.accent : p.muted))
                                ]))));
              }))))
    ]))));
  }

  Widget addButton() => IconButton.filledTonal(
      onPressed: () => editTask(context),
      icon: const Icon(Icons.add),
      tooltip: '添加待办');
  List<Widget> home(BuildContext c) {
    final s = UiScope.of(c).store,
        p = UiScope.of(c).palette,
        items = s.visible(s.today),
        late = items
            .where((o) => overdueLevel(o['dueDate'], s.today) > 0)
            .toList();
    final layout = s.appearance['layout'];
    return [
      heading(
          c,
          layout == 'a'
              ? '今天要做什么？'
              : layout == 'b'
                  ? '一天，有序展开'
                  : '只专注，眼前这一件',
          subtitle:
              '${prettyDay(s.today)} · 星期${'一二三四五六日'[parseDay(s.today).weekday - 1]}',
          trailing: addButton()),
      if (items.isEmpty)
        emptyState(c, '给今天留一个安排', '添加待办、设定期限，或先规划一段时间。',
            action: () => editTask(c))
      else if (layout == 'a') ...[
        weekStrip(c),
        const SizedBox(height: 20),
        Glass(
            child: Row(children: [
          Icon(Icons.wb_sunny_outlined, color: p.accent),
          const SizedBox(width: 13),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('给重要的事，留点时间',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text('${items.length} 项待完成，${late.length} 项需要关注',
                    style: TextStyle(fontSize: 12, color: p.muted))
              ]))
        ])),
        if (late.isNotEmpty) ...[
          section(c, '需要你关注'),
          ...late.map((o) => taskTile(c, o, urgent: true))
        ],
        section(c, '今日待办'),
        ...items.where((o) => !late.contains(o)).map((o) => taskTile(c, o)),
        const SizedBox(height: 18),
        OutlinedButton.icon(
            onPressed: () => editTask(c),
            icon: const Icon(Icons.add),
            label: const Text('添加一件事'))
      ] else if (layout == 'b') ...[
        weekStrip(c),
        if (late.isNotEmpty) ...[
          const SizedBox(height: 17),
          InkWell(
              onTap: () => openTask(c, late.first),
              child: Glass(
                  child: Row(children: [
                Icon(Icons.flag_outlined, color: p.accent),
                const SizedBox(width: 9),
                Expanded(child: Text('${late.length} 项逾期事项，安排一个下一步')),
                const Icon(Icons.chevron_right, size: 18)
              ])))
        ],
        section(c, '今天的安排',
            action: TextButton(
                onPressed: () => setState(() => tab = 1),
                child: const Text('规划时间'))),
        ...timeline(c, s.today),
        section(c, '还未安排时间'),
        ...items
            .where((o) => s.blockFor(o, s.today) == null)
            .map((o) => taskTile(c, o))
      ] else ...[
        FocusCard(occurrence: items.first),
        section(c, '之后，再做这些',
            action: TextButton(
                onPressed: () => setState(() => tab = 1),
                child: const Text('查看日程'))),
        ...items.skip(1).map((o) => taskTile(c, o)),
        const SizedBox(height: 20),
        Text(
            '今天已完成 ${s.visible(s.today, done: true).where((o) => o['completedAt'] != null && day(DateTime.parse(o['completedAt']).toLocal()) == s.today).length} 项',
            style: TextStyle(color: p.muted, fontSize: 12))
      ],
      if (s.visible(s.today, done: true).isNotEmpty)
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('已完成 (${s.visible(s.today, done: true).length})',
                style: TextStyle(color: p.muted, fontSize: 13)),
            children: s
                .visible(s.today, done: true)
                .map((o) => taskTile(c, o))
                .toList())
    ];
  }

  Widget weekStrip(BuildContext c) {
    final p = UiScope.of(c).palette,
        date = parseDay(UiScope.of(c).store.today),
        start = addDays(date, 1 - date.weekday);
    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (i) {
          final d = addDays(start, i), active = day(d) == day(date);
          return Container(
              width: 37,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                  color: active ? p.accent : null,
                  borderRadius: BorderRadius.circular(15)),
              child: Column(children: [
                Text('一二三四五六日'[i],
                    style: TextStyle(
                        fontSize: 11,
                        color: active
                            ? (p.dark ? Colors.black87 : Colors.white)
                            : p.muted)),
                const SizedBox(height: 8),
                Text('${d.day}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: active
                            ? (p.dark ? Colors.black87 : Colors.white)
                            : p.text))
              ]));
        }));
  }

  List<Widget> schedule(BuildContext c) => [
        heading(c, '每日时间规划', subtitle: '给每件事安排一段时间', trailing: addButton()),
        Row(children: [
          IconButton(
              onPressed: () =>
                  selectDate(day(addDays(parseDay(selectedDate), -1))),
              icon: const Icon(Icons.chevron_left)),
          Expanded(
              child: TextButton(
                  onPressed: () async {
                    final d = await chooseDate(c, selectedDate);
                    if (d != null) await selectDate(d);
                  },
                  child: Text(
                      '${prettyDay(selectedDate)} · ${parseDay(selectedDate).year}'))),
          IconButton(
              onPressed: () =>
                  selectDate(day(addDays(parseDay(selectedDate), 1))),
              icon: const Icon(Icons.chevron_right))
        ]),
        const SizedBox(height: 16),
        ...timeline(c, selectedDate),
        section(c, '安排到这一天'),
        ...UiScope.of(c)
            .store
            .visible(selectedDate)
            .where((o) => UiScope.of(c).store.blockFor(o, selectedDate) == null)
            .map((o) => taskTile(c, o, planningDate: selectedDate))
      ];
  Future<void> selectDate(String date) async {
    await guarded(context, () async {
      await UiScope.of(context).store.materialize(planningDate: date);
      if (mounted) setState(() => selectedDate = date);
    });
  }

  List<Widget> timeline(BuildContext c, String date) {
    final s = UiScope.of(c).store,
        p = UiScope.of(c).palette,
        events = s.eventsFor(date);
    if (events.isEmpty)
      return [emptyState(c, '这一天，还有留白', '点按下方任务，为它安排开始和结束时间。')];
    return events.map((b) {
      final t = s.task(b['taskId'])!,
          o = s.occurrences[b['occurrenceId']] as Json;
      final end = b['end'] as String, start = b['start'] as String;
      return Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 47,
                child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(start,
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 12,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])))),
            Expanded(
                child: InkWell(
                    onTap: () => editBlock(c, o, date, existing: b),
                    child: Glass(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(t['title'],
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 7),
                          Text(
                              '$start — $end${end.compareTo(start) < 0 ? '（次日结束）' : ''}',
                              style: TextStyle(color: p.muted, fontSize: 12)),
                          const SizedBox(height: 11),
                          Wrap(spacing: 7, runSpacing: 7, children: [
                            chip(c, '${(b['reminders'] as List).length} 个提醒',
                                icon: Icons.notifications_none),
                            if (o['done'] == true) chip(c, '已完成'),
                            if (overdueLevel(o['dueDate'], s.today) > 0 &&
                                o['done'] != true)
                              chip(c,
                                  '逾期 ${overdueDays(o['dueDate'], s.today)} 天',
                                  color: const Color(0xffb65165))
                          ])
                        ]))))
          ]));
    }).toList();
  }

  List<Widget> alarmPage(BuildContext c) {
    final s = UiScope.of(c).store, p = UiScope.of(c).palette;
    return [
      heading(c, '让提醒，准时发生',
          subtitle: '闹钟中心',
          trailing: IconButton.filledTonal(
              onPressed: () => editAlarm(c),
              icon: const Icon(Icons.add),
              tooltip: '新增闹钟')),
      Glass(
          child: Row(children: [
        Icon(Icons.alarm, color: p.accent),
        const SizedBox(width: 12),
        Expanded(
            child: Text(nativeStatus['nextLabel'] ?? '设置闹钟，让时间来提醒你',
                style: const TextStyle(height: 1.6)))
      ])),
      const SizedBox(height: 14),
      Wrap(spacing: 10, children: [
        ActionChip(
            label: const Text('循环排班'),
            avatar: const Icon(Icons.repeat, size: 17),
            onPressed: () => Navigator.of(c)
                .push(MaterialPageRoute(builder: (_) => const ShiftPage()))),
        ActionChip(
            label: const Text('权限与响铃测试'), onPressed: () => openPermissions(c))
      ]),
      if (nativeStatus['exact'] == false ||
          nativeStatus['notifications'] == false)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child:
                Text('尚有闹钟权限未开启，请先完成权限设置。', style: TextStyle(color: p.accent))),
      section(c, '已登记提醒',
          action:
              TextButton(onPressed: refreshStatus, child: const Text('刷新'))),
      ...((nativeStatus['upcoming'] as List?) ?? []).map((record) {
        final at = DateTime.fromMillisecondsSinceEpoch(record['fireAt'] as int);
        return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.alarm_on, color: p.accent),
            title: Text(record['title'] as String),
            subtitle: Text(
                '${prettyDay(day(at))} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')} · ${record['kind']}'));
      }),
      section(c, '独立闹钟'),
      if (s.alarms.where((a) => a['deletedAt'] == null).isEmpty)
        emptyState(c, '从一个闹钟开始', '每天、工作日、间隔重复或轮班，都可以自己设定。',
            action: () => editAlarm(c), button: '新增闹钟'),
      ...s.alarms.where((a) => a['deletedAt'] == null).map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Glass(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                      child: InkWell(
                          onTap: () => editAlarm(c, existing: a),
                          child: Text(a['time'] ?? '排班',
                              style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w400,
                                  color:
                                      a['enabled'] == true ? p.text : p.muted,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])))),
                  Switch(
                      value: a['enabled'] == true,
                      onChanged: (v) =>
                          guarded(c, () => s.putAlarm({...a, 'enabled': v})))
                ]),
                Text(a['title'],
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text(alarmRuleLabel(a),
                    style:
                        TextStyle(color: p.muted, fontSize: 12, height: 1.7)),
                const Divider(height: 25),
                Row(children: [
                  Expanded(
                      child: Text(
                          '贪睡 ${a['ring']['snooze']} 分钟 · 最多 ${a['ring']['maxSnoozes']} 次',
                          style: TextStyle(color: p.muted, fontSize: 11))),
                  TextButton(
                      onPressed: () => editAlarm(c, existing: a),
                      child: const Text('自定义'))
                ])
              ])))),
      section(c, '任务关联提醒'),
      ...s
          .eventsFor(s.today)
          .where((b) => (b['reminders'] as List).isNotEmpty)
          .map((b) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.notifications_none, color: p.accent),
              title: Text(s.task(b['taskId'])!['title']),
              subtitle: Text(
                  '${b['start']}—${b['end']} · ${(b['reminders'] as List).length} 个提醒'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => editBlock(
                  c, s.occurrences[b['occurrenceId']], s.today,
                  existing: b)))
    ];
  }

  List<Widget> settings(BuildContext c) {
    final s = UiScope.of(c).store;
    return [
      heading(c, '按你的习惯来', subtitle: '有期 · 0.2.1'),
      Glass(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Column(children: [
            menu(
                c,
                Icons.palette_outlined,
                '布局与皮肤',
                () => Navigator.of(c).push(
                    MaterialPageRoute(builder: (_) => const AppearancePage()))),
            menu(
                c,
                Icons.sync,
                '同步与数据备份',
                () => Navigator.of(c)
                    .push(MaterialPageRoute(builder: (_) => const SyncPage()))),
            menu(
                c,
                Icons.repeat,
                '循环排班',
                () => Navigator.of(c).push(
                    MaterialPageRoute(builder: (_) => const ShiftPage()))),
            menu(c, Icons.verified_user_outlined, '权限与响铃测试',
                () => openPermissions(c)),
            menu(c, Icons.history, '响铃记录', () => showAlarmHistory(c))
          ])),
      const SizedBox(height: 14),
      Glass(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: SwitchListTile(
              title: const Text('通知栏常驻待办', style: TextStyle(fontSize: 14)),
              subtitle: const Text('静默显示未完成数量和最多 5 条事项，点击返回 APP'),
              value: nativeStatus['todoPinned'] == true,
              onChanged: (enabled) => guarded(c, () async {
                    await AndroidRepository.channel
                        .invokeMethod('setTodoNotification', enabled);
                    await refreshStatus();
                    if (enabled &&
                        nativeStatus['notifications'] == false &&
                        c.mounted) {
                      message(c, '请允许通知，才能在通知栏显示待办');
                      await AndroidRepository.channel
                          .invokeMethod('permission', 'notifications');
                    }
                  }))),
      const SizedBox(height: 20),
      Text('给待办一个期限，给今天一个安排。',
          style: TextStyle(color: UiScope.of(c).palette.muted, fontSize: 12)),
      const SizedBox(height: 14),
      Text('所有数据保存在本机。三套布局共享任务与闹钟，可随时切换。',
          style: TextStyle(
              color: UiScope.of(c).palette.muted, fontSize: 12, height: 1.8)),
      if (s.error != null) Text(s.error!)
    ];
  }
}

Widget menu(BuildContext c, IconData icon, String title, VoidCallback action) =>
    ListTile(
        leading: Icon(icon, color: UiScope.of(c).palette.accent),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        trailing: const Icon(Icons.chevron_right, size: 19),
        onTap: action);
Widget taskTile(BuildContext c, Json o,
    {bool urgent = false, String? planningDate}) {
  final s = UiScope.of(c).store,
      p = UiScope.of(c).palette,
      t = s.task(o['taskId'])!;
  final row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(
        width: 38,
        height: 45,
        child: Checkbox(
            value: o['done'] == true,
            onChanged: (_) => guarded(c, () => s.toggleDone(o)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6)))),
    const SizedBox(width: 7),
    Expanded(
        child: InkWell(
            onTap: () => planningDate != null
                ? editBlock(c, o, planningDate)
                : openTask(c, o),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['title'],
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              decoration: o['done'] == true
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: o['done'] == true ? p.muted : p.text)),
                      const SizedBox(height: 7),
                      Text(
                          '${t['repeat'] == 'none' ? '预计 ${t['estimate']} 天' : '独立重复 · ${prettyDay(o['date'])}'}${planningDate != null ? ' · 点按安排时间' : ''}',
                          style: TextStyle(fontSize: 11, color: p.muted)),
                      const SizedBox(height: 8),
                      statusChips(c, o)
                    ])))),
    IconButton(
        onPressed: () => openTask(c, o),
        icon: const Icon(Icons.chevron_right, size: 17),
        tooltip: '任务详情')
  ]);
  return Padding(
      padding: EdgeInsets.only(bottom: urgent ? 11 : 2),
      child: urgent
          ? Glass(padding: const EdgeInsets.fromLTRB(7, 7, 4, 7), child: row)
          : Column(children: [row, Divider(color: p.line, height: 8)]));
}

void openTask(BuildContext c, Json o) => Navigator.of(c)
    .push(MaterialPageRoute(builder: (_) => TaskPage(occurrenceId: o['id'])));

class TaskPage extends StatelessWidget {
  const TaskPage({super.key, required this.occurrenceId});
  final String occurrenceId;
  @override
  Widget build(BuildContext c) {
    final s = UiScope.of(c).store,
        p = UiScope.of(c).palette,
        o = s.occurrences[occurrenceId] as Json,
        t = s.task(o['taskId'])!,
        b = s.blockFor(o, s.today);
    return Scaffold(
        appBar: AppBar(title: const Text('任务详情'), actions: [
          IconButton(
              onPressed: () => editTask(c, existing: t),
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑任务'),
          IconButton(
              onPressed: () async {
                if (await confirm(
                    c, '删除任务？', '这将删除该任务及其重复计划，并取消相关提醒。历史以删除标记保留供后续同步。')) {
                  await guarded(c, () => s.deleteTask(t));
                  if (c.mounted) Navigator.pop(c);
                }
              },
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除任务')
        ]),
        body: Backdrop(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
                children: [
              Text(t['title'],
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w600, height: 1.5)),
              const SizedBox(height: 13),
              statusChips(c, o),
              const SizedBox(height: 16),
              if ((t['notes'] ?? '').isNotEmpty)
                Text(t['notes'], style: TextStyle(color: p.muted, height: 1.8)),
              const SizedBox(height: 17),
              Glass(
                  child: Column(children: [
                infoRow('任务类型', t['repeat'] == 'none' ? '持续到完成' : '每次独立完成'),
                infoRow('本次日期', prettyDay(o['date'])),
                infoRow('预计需要', '${t['estimate']} 天'),
                infoRow('当前截止', prettyDay(o['dueDate'])),
                infoRow(
                    '今天安排', b == null ? '尚未安排' : '${b['start']} — ${b['end']}')
              ])),
              section(c, '逾期与改期'),
              Row(
                  children: List.generate(
                      7,
                      (i) => Expanded(
                          child: Container(
                              margin: const EdgeInsets.only(right: 4),
                              height: 28,
                              decoration: BoxDecoration(
                                  color: overdueColors[i],
                                  borderRadius: BorderRadius.circular(5)),
                              alignment: Alignment.center,
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: i < 2
                                          ? const Color(0xff4d2530)
                                          : Colors.white)))))),
              const SizedBox(height: 10),
              Text('每天加深一级，最高 7 级；改期标识色与深浅分别显示。',
                  style: TextStyle(color: p.muted, fontSize: 11, height: 1.8)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                  onPressed: () => message(c, '保留当前截止日期，逾期等级继续按天累计'),
                  icon: const Icon(Icons.schedule),
                  label: const Text('继续延后，保留截止日期')),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                  onPressed: () async {
                    final date = await chooseDate(c, o['dueDate'] ?? s.today);
                    if (date != null)
                      await guarded(c, () => s.reschedule(o, date));
                  },
                  icon: const Icon(Icons.event),
                  label: const Text('重新设置截止日期')),
              section(c, '时间与多个提醒',
                  action: TextButton(
                      onPressed: () => editBlock(c, o, s.today, existing: b),
                      child: Text(b == null ? '安排今天' : '编辑'))),
              if (b != null)
                ...(b['reminders'] as List).cast<Json>().map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.notifications_none, color: p.accent),
                    title: Text(offsetLabel(r)),
                    subtitle: Text(reminderTime(b, r)),
                    trailing: Text(r['enabled'] == false
                        ? '停用'
                        : o['done'] == true
                            ? '任务已完成'
                            : '已启用'))),
              if ((o['history'] as List).isNotEmpty) ...[
                section(c, '改期记录'),
                ...(o['history'] as List).cast<Json>().reversed.map((h) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.circle,
                        size: 10,
                        color: revisionColors[(h['ordinal'] as int) % 5]),
                    title: Text(
                        '${prettyDay(h['from'])} → ${prettyDay(h['to'])}',
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                        '第 ${h['ordinal']} 次改期 · 当时逾期 ${h['overdueDaysAtChange']} 天')))
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                  onPressed: () => guarded(c, () => s.toggleDone(o)),
                  icon: const Icon(Icons.check),
                  label: Text(o['done'] == true ? '撤销完成' : '标记完成'))
            ])));
  }
}

Widget infoRow(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
      Flexible(
          child: Text(value,
              style: const TextStyle(fontSize: 12), textAlign: TextAlign.right))
    ]));
String reminderTime(Json b, Json r) {
  final start = DateTime.parse('${b['date']}T${b['start']}'),
      end = DateTime.parse('${b['date']}T${b['end']}');
  final base = r['anchor'] == 'end'
      ? (end.isBefore(start) ? end.add(const Duration(days: 1)) : end)
      : start;
  final at = base.add(Duration(minutes: r['offset']));
  return '${day(at) != b['date'] ? prettyDay(day(at)) + ' ' : ''}${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')} 响铃';
}

class FocusCard extends StatefulWidget {
  const FocusCard({super.key, required this.occurrence});
  final Json occurrence;
  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final s = UiScope.of(c).store,
        p = UiScope.of(c).palette,
        o = widget.occurrence,
        t = s.task(o['taskId'])!;
    final focus = s.data['focus'] as Json?,
        active = focus?['occurrenceId'] == o['id'] &&
            DateTime.parse(focus!['until']).isAfter(s.clock());
    final remaining = active
        ? DateTime.parse(focus['until']).difference(s.clock()).inSeconds
        : 0;
    return Glass(
        radius: 27,
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(active ? '正在专注' : '现在适合做',
              style: TextStyle(fontSize: 12, color: p.accent)),
          const SizedBox(height: 20),
          Text(t['title'],
              style: const TextStyle(
                  fontSize: 28, height: 1.6, fontWeight: FontWeight.w500)),
          const SizedBox(height: 19),
          statusChips(c, o),
          const SizedBox(height: 24),
          if (active)
            Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: Text(
                    '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 36,
                        fontFeatures: [FontFeature.tabularFigures()]))),
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  onPressed: () async {
                    if (active) {
                      await guarded(c, () async {
                        await AndroidRepository.channel
                            .invokeMethod('cancelOneShot', 'focus:${o['id']}');
                        s.data.remove('focus');
                        await s.save();
                      });
                    } else {
                      final minutes = await showDialog<int>(
                          context: c,
                          builder: (d) => SimpleDialog(
                              title: const Text('专注多久？'),
                              children: [25, 45, 60, 90]
                                  .map((m) => SimpleDialogOption(
                                      onPressed: () => Navigator.pop(d, m),
                                      child: Text('$m 分钟')))
                                  .toList()));
                      if (minutes != null && c.mounted)
                        await guarded(c, () async {
                          final until =
                              s.clock().add(Duration(minutes: minutes));
                          await AndroidRepository.channel
                              .invokeMethod('oneShot', {
                            'key': 'focus:${o['id']}',
                            'title': '专注结束：${t['title']}',
                            'seconds': minutes * 60,
                            'occurrenceId': o['id'],
                            'ring': ringDefaults()
                          });
                          s.data['focus'] = {
                            'occurrenceId': o['id'],
                            'until': until.toIso8601String()
                          };
                          await s.save();
                        });
                    }
                  },
                  icon: Icon(
                      active ? Icons.stop_outlined : Icons.play_arrow_outlined),
                  label: Text(active ? '停止专注' : '进入专注'))),
          const SizedBox(height: 10),
          TextButton(
              onPressed: () => openTask(c, o), child: const Text('查看任务详情'))
        ]));
  }
}

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});
  @override
  Widget build(BuildContext c) {
    final s = UiScope.of(c).store, p = UiScope.of(c).palette;
    return Scaffold(
        appBar: AppBar(title: const Text('布局与皮肤')),
        body: Backdrop(
            child: ListView(padding: const EdgeInsets.all(22), children: [
          heading(c, '换一种，喜欢的样子', subtitle: '三套布局，共享同一份数据'),
          ...['a', 'b', 'c'].map((layout) {
            final i = ['a', 'b', 'c'].indexOf(layout);
            return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                    onTap: () => guarded(c, () async {
                          await s.setAppearance('layout', layout);
                          await s.setAppearance(
                              'mode', layout == 'c' ? 'dark' : 'light');
                        }),
                    child: Glass(
                        child: Row(children: [
                      Container(
                          width: 43,
                          height: 56,
                          decoration: BoxDecoration(
                              color: [
                                const Color(0xff315bd6),
                                const Color(0xff7155bb),
                                const Color(0xffd39650)
                              ][i]
                                  .withOpacity(.15),
                              borderRadius: BorderRadius.circular(10)),
                          child: Icon(
                              [
                                Icons.checklist,
                                Icons.view_timeline_outlined,
                                Icons.center_focus_strong
                              ][i],
                              color: [
                                const Color(0xff315bd6),
                                const Color(0xff7155bb),
                                const Color(0xffd39650)
                              ][i])),
                      const SizedBox(width: 15),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(['A 澄明', 'B 时序', 'C 聚焦'][i],
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(
                                [
                                  '清爽列表 · 先处理待办',
                                  '时间轴 · 安排全天节奏',
                                  '专注看板 · 眼前这一件'
                                ][i],
                                style: TextStyle(fontSize: 12, color: p.muted))
                          ])),
                      if (s.appearance['layout'] == layout)
                        Icon(Icons.check_circle, color: p.accent)
                    ]))));
          }),
          section(c, '材质与明暗'),
          Glass(
              child: Column(children: [
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('液态玻璃'),
                subtitle: const Text('透光、高光边缘与背景模糊'),
                value: s.appearance['glass'] == true,
                onChanged: (v) =>
                    guarded(c, () => s.setAppearance('glass', v))),
            DropdownButtonFormField<String>(
                value: s.appearance['mode'],
                decoration: const InputDecoration(labelText: '显示模式'),
                items: const [
                  DropdownMenuItem(value: 'light', child: Text('浅色')),
                  DropdownMenuItem(value: 'dark', child: Text('深色')),
                  DropdownMenuItem(value: 'system', child: Text('跟随系统'))
                ],
                onChanged: (v) => guarded(c, () => s.setAppearance('mode', v)))
          ])),
          section(c, '状态始终清楚'),
          Text('逾期显示天数与 7 级深浅；改期保留累计次数。所有皮肤都保留这些提示。',
              style: TextStyle(color: p.muted, height: 1.8))
        ])));
  }
}

class SyncPage extends StatelessWidget {
  const SyncPage({super.key});
  @override
  Widget build(BuildContext c) {
    final s = UiScope.of(c).store, p = UiScope.of(c).palette;
    return Scaffold(
        appBar: AppBar(title: const Text('同步与数据备份')),
        body: Backdrop(
            child: ListView(padding: const EdgeInsets.all(22), children: [
          heading(c, '每一端，都接得上', subtitle: '本机可用 · 桌面同步待接入'),
          Glass(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Icon(Icons.phone_android, color: p.accent),
                  const SizedBox(width: 11),
                  const Text('当前手机 · Android')
                ]),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    value: s.data['deviceMode'],
                    decoration: const InputDecoration(labelText: '这台设备如何提醒'),
                    items: const [
                      DropdownMenuItem(value: 'ring', child: Text('响铃与振动')),
                      DropdownMenuItem(value: 'notify', child: Text('仅通知')),
                      DropdownMenuItem(value: 'silent', child: Text('静默'))
                    ],
                    onChanged: (v) => guarded(c, () => s.setDeviceMode(v!))),
                const SizedBox(height: 12),
                const Text('仅通知与静默不会播放闹铃。', style: TextStyle(fontSize: 12))
              ])),
          const SizedBox(height: 17),
          Glass(
              child: Column(children: [
            infoRow('Windows / macOS', '后续接入'),
            infoRow('本地变更', '${(s.data['outbox'] as List).length} 条待同步'),
            infoRow('连接状态', '未连接同步服务')
          ])),
          const SizedBox(height: 17),
          Text('任务、时间段、改期历史与排班均已保留稳定标识和增量同步字段。桌面端接入后可分别设置响铃、通知与静默；冲突将保留双方修改。',
              style: TextStyle(color: p.muted, height: 1.9, fontSize: 13)),
          section(c, '本机备份'),
          FilledButton.icon(
              onPressed: () => guarded(c, () async {
                    await AndroidRepository.channel
                        .invokeMethod('exportBackup', s.exportData());
                  }),
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('导出 JSON 备份')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: () => guarded(c, () async {
                    final raw = await AndroidRepository.channel
                        .invokeMethod<String>('importBackup');
                    if (raw == null || !c.mounted) return;
                    jsonDecode(raw);
                    if (await confirm(
                        c, '从备份恢复？', '当前数据将被替换。建议先导出当前数据；同步版本会重新建立。'))
                      await s.restore(raw);
                  }),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('从备份恢复'))
        ])));
  }
}

Future<void> openPermissions(BuildContext c) async {
  await showModalBottomSheet(
      context: c,
      isScrollControlled: true,
      builder: (d) => const PermissionPanel());
}

class PermissionPanel extends StatefulWidget {
  const PermissionPanel({super.key});
  @override
  State<PermissionPanel> createState() => _PermissionPanelState();
}

class _PermissionPanelState extends State<PermissionPanel>
    with WidgetsBindingObserver {
  Json status = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  Future<void> refresh() async {
    try {
      final value = await AndroidRepository.channel
          .invokeMapMethod<String, dynamic>('status');
      if (mounted)
        setState(() => status = Map<String, dynamic>.from(value ?? {}));
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => SafeArea(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('权限与响铃测试',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                const SizedBox(height: 15),
                ...[
                  'notifications',
                  'exact',
                  'fullScreen',
                  'battery'
                ].map((key) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text({
                      'notifications': '允许通知',
                      'exact': '精确闹钟',
                      'fullScreen': '锁屏全屏提醒',
                      'battery': '后台与电池设置'
                    }[key]!),
                    subtitle: Text(status[key] == true ? '已开启' : '点击前往系统设置'),
                    trailing: Icon(status[key] == true
                        ? Icons.check_circle_outline
                        : Icons.chevron_right),
                    onTap: () => guarded(c, () async {
                          await AndroidRepository.channel
                              .invokeMethod('permission', key);
                        }))),
                const Text('系统强制停止应用会取消闹钟，需重新打开应用。不同手机的后台限制需要在真机确认。',
                    style: TextStyle(fontSize: 12, height: 1.8)),
                TextButton.icon(
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新权限状态')),
                const SizedBox(height: 15),
                FilledButton(
                    onPressed: () => guarded(c, () async {
                          await AndroidRepository.channel
                              .invokeMethod('oneShot', {
                            'key': 'test:${uid()}',
                            'title': '有期 · 响铃测试',
                            'seconds': 10,
                            'ring': ringDefaults()
                          });
                          if (c.mounted) message(c, '已安排 10 秒后测试，请锁屏验证响铃');
                        }),
                    child: const Text('10 秒后测试响铃'))
              ])));
}

Future<void> showAlarmHistory(BuildContext c) async {
  try {
    final list =
        await AndroidRepository.channel.invokeListMethod('history') ?? [];
    if (!c.mounted) return;
    await showDialog(
        context: c,
        builder: (d) =>
            AlertDialog(
                title: const Text('最近响铃记录'),
                content: SizedBox(
                    width: 350,
                    child: list.isEmpty
                        ? const Text('还没有响铃记录')
                        : ListView(
                            shrinkWrap: true,
                            children: list.reversed
                                .take(30)
                                .map((h) => ListTile(
                                    title: Text(h['title'] ?? '闹钟'),
                                    subtitle:
                                        Text('${h['at']} · ${h['action']}')))
                                .toList())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d),
                      child: const Text('关闭'))
                ]));
  } catch (e) {
    if (c.mounted) message(c, e.toString());
  }
}
