import 'dart:convert';
import 'package:flutter/material.dart';
import 'time_wheel.dart';
import 'core.dart';
import 'ui.dart';

Future<bool> confirm(BuildContext c, String title, String text) async =>
    await showDialog<bool>(
        context: c,
        builder: (d) =>
            AlertDialog(title: Text(title), content: Text(text), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: const Text('确认'))
            ])) ??
    false;
Future<String?> chooseDate(BuildContext c, String initial) async {
  final date = await showDatePicker(
      context: c,
      initialDate: parseDay(initial),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择日期');
  return date == null ? null : day(date);
}

String timeString(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
TimeOfDay parseTime(String time) {
  final s = time.split(':');
  return TimeOfDay(hour: int.parse(s[0]), minute: int.parse(s[1]));
}

Future<String?> chooseTime(BuildContext c, String initial) async {
  return showModalBottomSheet<String>(
      context: c,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => TimeWheelSheet(initial: initial));
}

Future<void> editor(BuildContext c, Widget child) => showModalBottomSheet(
    context: c,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: UiScope.of(c).palette.bg,
    builder: (_) => FractionallySizedBox(heightFactor: .96, child: child));

class EditorFrame extends StatelessWidget {
  const EditorFrame(
      {super.key,
      required this.title,
      required this.children,
      required this.save});
  final String title;
  final List<Widget> children;
  final Future<void> Function() save;
  @override
  Widget build(BuildContext c) => Scaffold(
      appBar: AppBar(
          title: Text(title),
          leading: IconButton(
              onPressed: () => Navigator.pop(c),
              icon: const Icon(Icons.close))),
      body: ListView(
          padding: EdgeInsets.fromLTRB(
              22, 8, 22, 24 + MediaQuery.viewInsetsOf(c).bottom),
          children: [
            ...children,
            const SizedBox(height: 24),
            FilledButton(
                onPressed: () async {
                  try {
                    await save();
                    if (c.mounted) Navigator.pop(c);
                  } catch (e) {
                    if (c.mounted) message(c, e.toString());
                  }
                },
                child: const Text('保存设置'))
          ]));
}

Widget field(TextEditingController controller, String label,
        {bool number = false, int lines = 1}) =>
    Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: label),
            keyboardType: number ? TextInputType.number : TextInputType.text,
            maxLines: lines));
Widget pickerRow(String title, String value, VoidCallback onTap) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontSize: 14)),
    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 7),
      const Icon(Icons.chevron_right, size: 17)
    ]),
    onTap: onTap);
Widget dropdown(String label, String value, List<(String, String)> options,
        ValueChanged<String> onChanged) =>
    Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: options
                .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            }));
Widget weekdays(List<int> selected, ValueChanged<List<int>> changed) => Wrap(
    spacing: 6,
    runSpacing: 5,
    children: List.generate(
        7,
        (i) => FilterChip(
            label: Text('一二三四五六日'[i]),
            selected: selected.contains(i + 1),
            onSelected: (v) {
              final next = List<int>.from(selected);
              if (v)
                next.add(i + 1);
              else
                next.remove(i + 1);
              changed(next..sort());
            })));
int number(TextEditingController c, int min, int max, String label) {
  final n = int.tryParse(c.text);
  if (n == null || n < min || n > max)
    throw FormatException('$label需在 $min—$max 之间');
  return n;
}

Future<T?> controlledDialog<T>(
    {required BuildContext context,
    required List<TextEditingController> controllers,
    required WidgetBuilder builder}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  try {
    return await Navigator.of(context, rootNavigator: true).push(route);
  } finally {
    // pop resolves before the exit animation. Dispose only after its overlay is gone.
    await route.completed;
    for (final controller in controllers) {
      controller.dispose();
    }
  }
}

void editTask(BuildContext c, {Json? existing}) =>
    editor(c, TaskEditor(existing: existing));

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, this.existing});
  final Json? existing;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late TextEditingController title, notes, estimate, interval;
  late String start, due, repeat;
  String? begin, end;
  late List<int> week;
  late List<Json> reminders;
  bool hasDue = true;
  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    title = TextEditingController(text: t?['title'] ?? '');
    notes = TextEditingController(text: t?['notes'] ?? '');
    estimate = TextEditingController(text: '${t?['estimate'] ?? 1}');
    interval = TextEditingController(text: '${t?['interval'] ?? 2}');
    start = t?['startDate'] ?? day(DateTime.now());
    due = t?['dueDate'] ?? start;
    repeat = t?['repeat'] ?? 'none';
    begin = t?['scheduleStart'];
    end = t?['scheduleEnd'];
    week = List<int>.from(t?['weekdays'] ?? [1, 2, 3, 4, 5]);
    reminders = t == null
        ? <Json>[]
        : (jsonDecode(jsonEncode(t['reminders'])) as List).cast<Json>();
    hasDue = t == null || t['dueDate'] != null;
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    estimate.dispose();
    interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => EditorFrame(
          title: widget.existing == null ? '给一件事，留个位置' : '编辑任务与重复模板',
          save: () async {
            if (title.text.trim().isEmpty)
              throw const FormatException('请填写待办名称');
            final n = number(estimate, 1, 365, '预计天数'),
                step = number(interval, 1, 365, '间隔天数');
            if (hasDue && due.compareTo(start) < 0)
              throw const FormatException('截止日期不能早于开始日期');
            if (repeat == 'weekly' && week.isEmpty)
              throw const FormatException('请至少选择一个星期');
            final input = <String, dynamic>{
              'title': title.text.trim(),
              'notes': notes.text.trim(),
              'startDate': start,
              'dueDate': hasDue ? due : null,
              'estimate': n,
              'repeat': repeat,
              'interval': step,
              'weekdays': week,
              'scheduleStart': begin,
              'scheduleEnd': end,
              'reminders': begin == null ? <Json>[] : reminders
            };
            final s = UiScope.of(c).store;
            if (widget.existing == null)
              await s.addTask(input);
            else {
              await s.editTask(widget.existing!, input);
              await s.materialize();
            }
          },
          children: [
            field(title, '待办名称'),
            field(notes, '备注', lines: 3),
            dropdown(
                '任务类型',
                repeat,
                const [
                  ('none', '持续显示，直到完成'),
                  ('daily', '每日重复，每次独立完成'),
                  ('weekly', '自选星期重复'),
                  ('interval', '每隔若干天重复')
                ],
                (v) => setState(() => repeat = v)),
            if (repeat == 'weekly')
              weekdays(week, (v) => setState(() => week = v)),
            if (repeat == 'interval') field(interval, '每隔多少天', number: true),
            pickerRow('开始日期', prettyDay(start), () async {
              if (widget.existing != null) {
                message(c, '已有任务的起点保留；可以另建新的重复计划');
                return;
              }
              final d = await chooseDate(c, start);
              if (d != null) setState(() => start = d);
            }),
            field(estimate, '预计需要的自然日天数', number: true),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('设置截止日期'),
                value: hasDue,
                onChanged: (v) => setState(() => hasDue = v)),
            if (hasDue) ...[
              pickerRow(
                  widget.existing == null ? '截止日期' : '模板默认截止日期', prettyDay(due),
                  () async {
                final d = await chooseDate(c, due);
                if (d != null) setState(() => due = d);
              }),
              TextButton(
                  onPressed: () {
                    try {
                      final n = number(estimate, 1, 365, '预计天数');
                      setState(
                          () => due = day(addDays(parseDay(start), n - 1)));
                    } catch (e) {
                      message(c, e.toString());
                    }
                  },
                  child: const Text('按开始日期与预计天数填写'))
            ],
            if (widget.existing != null)
              const Text('已有记录的截止日期请在任务详情中改期。此处修改重复模板，保留历史记录。',
                  style: TextStyle(fontSize: 12, height: 1.8)),
            section(c, '默认时间安排'),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('同时安排开始与结束时间'),
                value: begin != null,
                onChanged: (v) => setState(() {
                      begin = v ? '09:00' : null;
                      end = v ? '10:30' : null;
                      if (v && reminders.isEmpty)
                        reminders = [
                          {
                            'id': uid(),
                            'anchor': 'start',
                            'offset': -30,
                            'enabled': true,
                            'ring': ringDefaults()
                          }
                        ];
                    })),
            if (begin != null) ...[
              pickerRow('开始时间', begin!, () async {
                final v = await chooseTime(c, begin!);
                if (v != null) setState(() => begin = v);
              }),
              pickerRow('结束时间', end!, () async {
                final v = await chooseTime(c, end!);
                if (v != null) setState(() => end = v);
              }),
              const Text('结束早于开始表示次日结束；重复任务沿用该时间安排。',
                  style: TextStyle(fontSize: 12)),
              ...reminders.map((r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(offsetLabel(r)),
                  onTap: () async {
                    final edited = await reminderDialog(c, r);
                    if (edited != null)
                      setState(() => reminders[reminders.indexOf(r)] = edited);
                  },
                  trailing: IconButton(
                      onPressed: () => setState(() => reminders.remove(r)),
                      icon: const Icon(Icons.close),
                      tooltip: '移除此提醒'))),
              OutlinedButton.icon(
                  onPressed: () async {
                    final r = await reminderDialog(c);
                    if (r != null) setState(() => reminders.add(r));
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('添加相对提醒'))
            ]
          ]);
}

Future<Json?> reminderDialog(BuildContext c, [Json? existing]) async {
  final offset = existing?['offset'] as int? ?? -30;
  var anchor = existing?['anchor'] as String? ?? 'start',
      direction = offset < 0
          ? '-1'
          : offset > 0
              ? '1'
              : '0';
  final count = TextEditingController(text: '${offset.abs()}');
  Json ring = Map.from(existing?['ring'] ?? ringDefaults());
  bool enabled = existing?['enabled'] != false;
  final result = await controlledDialog<Json>(
      context: c,
      controllers: [count],
      builder: (d) => StatefulBuilder(
          builder: (d, set) => AlertDialog(
                  title: const Text('相对时间提醒'),
                  content: SizedBox(
                      width: 340,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        dropdown(
                            '时间锚点',
                            anchor,
                            const [('start', '事件开始'), ('end', '事件结束')],
                            (v) => set(() => anchor = v)),
                        dropdown(
                            '提醒时机',
                            direction,
                            const [('-1', '提前'), ('0', '准时'), ('1', '延后')],
                            (v) => set(() => direction = v)),
                        if (direction != '0')
                          field(count, '分钟（可跨天）', number: true),
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('启用此提醒'),
                            value: enabled,
                            onChanged: (v) => set(() => enabled = v)),
                        RingFields(
                            profile: ring,
                            onChanged: (v) => set(() => ring = v))
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(d),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () {
                          try {
                            final n = direction == '0'
                                ? 0
                                : number(count, 0, 10080, '偏移分钟');
                            Navigator.pop(d, {
                              'id': existing?['id'] ?? uid(),
                              'anchor': anchor,
                              'offset': int.parse(direction) * n,
                              'enabled': enabled,
                              'ring': ring
                            });
                          } catch (e) {
                            message(d, e.toString());
                          }
                        },
                        child: const Text('保存'))
                  ])));
  return result;
}

void editBlock(BuildContext c, Json occurrence, String date,
        {Json? existing}) =>
    editor(
        c,
        BlockEditor(
            occurrence: occurrence,
            date: date,
            existing: existing,
            defaults: UiScope.of(c).store.task(occurrence['taskId'])));

class BlockEditor extends StatefulWidget {
  const BlockEditor(
      {super.key,
      required this.occurrence,
      required this.date,
      this.existing,
      this.defaults});
  final Json occurrence;
  final String date;
  final Json? existing;
  final Json? defaults;
  @override
  State<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends State<BlockEditor> {
  late String start, end;
  late List<Json> reminders;
  @override
  void initState() {
    super.initState();
    start = widget.existing?['start'] ??
        widget.defaults?['scheduleStart'] ??
        '09:00';
    end = widget.existing?['end'] ?? widget.defaults?['scheduleEnd'] ?? '10:00';
    reminders = (jsonDecode(jsonEncode(widget.existing?['reminders'] ??
            widget.defaults?['reminders'] ??
            <Json>[])) as List)
        .cast<Json>();
  }

  @override
  Widget build(BuildContext c) {
    final s = UiScope.of(c).store, t = s.task(widget.occurrence['taskId'])!;
    return EditorFrame(
        title: '调整这段时间',
        save: () async {
          final id = '${widget.occurrence['id']}@${widget.date}',
              a = DateTime.parse('${widget.date}T$start');
          var b = DateTime.parse('${widget.date}T$end');
          if (b.isBefore(a)) b = b.add(const Duration(days: 1));
          if (a == b) throw const FormatException('开始和结束时间不能相同');
          final conflicts = [
            ...s.eventsFor(day(addDays(parseDay(widget.date), -1))),
            ...s.eventsFor(widget.date),
            ...s.eventsFor(day(addDays(parseDay(widget.date), 1)))
          ].where((e) {
            if (e['id'] == id) return false;
            final x = DateTime.parse('${e['date']}T${e['start']}');
            var y = DateTime.parse('${e['date']}T${e['end']}');
            if (y.isBefore(x)) y = y.add(const Duration(days: 1));
            return a.isBefore(y) && x.isBefore(b);
          }).toList();
          if (conflicts.isNotEmpty &&
              !await confirm(
                  c, '时间有重叠', '这段时间与 ${conflicts.length} 项安排重叠，仍然保留？'))
            throw const FormatException('时间尚未保存，请调整后重试');
          await s.saveBlock({
            'id': id,
            'occurrenceId': widget.occurrence['id'],
            'taskId': t['id'],
            'date': widget.date,
            'start': start,
            'end': end,
            'reminders': reminders
          });
        },
        children: [
          Text(t['title'],
              style:
                  const TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('${prettyDay(widget.date)} · 仅调整这一天'),
          pickerRow('开始时间', start, () async {
            final v = await chooseTime(c, start);
            if (v != null) setState(() => start = v);
          }),
          pickerRow('结束时间', end, () async {
            final v = await chooseTime(c, end);
            if (v != null) setState(() => end = v);
          }),
          if (end.compareTo(start) < 0) const Text('结束时间在次日。'),
          section(c, '多个提醒'),
          ...reminders.map((r) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(offsetLabel(r)),
              subtitle: Text(reminderTime(
                  {'date': widget.date, 'start': start, 'end': end}, r)),
              onTap: () async {
                final v = await reminderDialog(c, r);
                if (v != null)
                  setState(() => reminders[reminders.indexOf(r)] = v);
              },
              trailing: IconButton(
                  onPressed: () => setState(() => reminders.remove(r)),
                  icon: const Icon(Icons.close),
                  tooltip: '删除提醒'))),
          OutlinedButton.icon(
              onPressed: () async {
                final r = await reminderDialog(c);
                if (r != null) setState(() => reminders.add(r));
              },
              icon: const Icon(Icons.add),
              label: const Text('添加提醒')),
          const SizedBox(height: 12),
          const Text('修改开始或结束时间后，所有相对提醒随之更新。',
              style: TextStyle(fontSize: 12, height: 1.8))
        ]);
  }
}

class RingFields extends StatelessWidget {
  const RingFields({super.key, required this.profile, required this.onChanged});
  final Json profile;
  final ValueChanged<Json> onChanged;
  void set(String key, dynamic value) => onChanged({...profile, key: value});
  List<(String, String)> options(String key, List<(String, String)> values) => [
        ...values,
        if (!values.any((v) => v.$1 == '${profile[key]}'))
          ('${profile[key]}', '自定义：${profile[key]}')
      ];
  Future<void> customize(BuildContext c) async {
    final duration = TextEditingController(text: '${profile['duration']}');
    final snooze = TextEditingController(text: '${profile['snooze']}');
    final count = TextEditingController(text: '${profile['maxSnoozes']}');
    String? error;
    final result = await controlledDialog<Json>(
        context: c,
        controllers: [duration, snooze, count],
        builder: (d) => StatefulBuilder(
            builder: (d, update) => AlertDialog(
                    title: const Text('自定义响铃参数'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      field(duration, '响铃秒数（10—1800）', number: true),
                      field(snooze, '重响间隔 / 分钟（1—1440）', number: true),
                      field(count, '重响次数（0—100）', number: true),
                      if (error != null)
                        Text(error!, style: const TextStyle(color: Colors.red))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(d),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () {
                            try {
                              Navigator.pop(d, {
                                ...profile,
                                'duration': number(duration, 10, 1800, '响铃秒数'),
                                'snooze': number(snooze, 1, 1440, '重响间隔'),
                                'maxSnoozes': number(count, 0, 100, '重响次数')
                              });
                            } catch (e) {
                              update(() => error = e.toString());
                            }
                          },
                          child: const Text('应用'))
                    ])));
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext c) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('铃声、振动与重响', style: TextStyle(fontSize: 14)),
          children: [
            pickerRow(
                '铃声', (profile['tone'] ?? '').isEmpty ? '系统默认闹铃' : '已选自定义铃声',
                () async {
              try {
                final tone = await AndroidRepository.channel
                    .invokeMethod<String>('pickTone');
                if (tone != null) set('tone', tone);
              } catch (e) {
                if (c.mounted) message(c, e.toString());
              }
            }),
            Row(children: [
              const Text('音量'),
              Expanded(
                  child: Slider(
                      value: (profile['volume'] as num).toDouble(),
                      min: 0,
                      max: 1,
                      onChanged: (v) => set('volume', v)))
            ]),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('振动'),
                value: profile['vibrate'] == true,
                onChanged: (v) => set('vibrate', v)),
            dropdown(
                '单次响铃时长',
                '${profile['duration']}',
                options('duration', const [
                  ('15', '15 秒'),
                  ('30', '30 秒'),
                  ('60', '1 分钟'),
                  ('120', '2 分钟'),
                  ('300', '5 分钟'),
                  ('600', '10 分钟')
                ]),
                (v) => set('duration', int.parse(v))),
            dropdown(
                '贪睡间隔',
                '${profile['snooze']}',
                options('snooze', const [
                  ('1', '1 分钟'),
                  ('3', '3 分钟'),
                  ('5', '5 分钟'),
                  ('10', '10 分钟'),
                  ('15', '15 分钟'),
                  ('30', '30 分钟')
                ]),
                (v) => set('snooze', int.parse(v))),
            dropdown(
                '最多重响次数',
                '${profile['maxSnoozes']}',
                options('maxSnoozes', const [
                  ('0', '不允许重响'),
                  ('1', '1 次'),
                  ('2', '2 次'),
                  ('3', '3 次'),
                  ('5', '5 次'),
                  ('10', '10 次')
                ]),
                (v) => set('maxSnoozes', int.parse(v))),
            TextButton.icon(
                onPressed: () => customize(c),
                icon: const Icon(Icons.tune),
                label: const Text('输入自定义时长、间隔和次数')),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('未处理时自动再次响铃'),
                subtitle: const Text('单次响铃结束后，按贪睡间隔重响，受次数上限约束'),
                value: profile['autoRepeat'] == true,
                onChanged: (v) => set('autoRepeat', v))
          ]);
}

String alarmRuleLabel(Json a) {
  switch (a['type']) {
    case 'once':
      return '${prettyDay(a['startDate'])}，仅一次';
    case 'daily':
      return '每天';
    case 'weekly':
      return '每周 ${(a['weekdays'] as List).map((d) => '一二三四五六日'[d - 1]).join('、')}';
    case 'interval':
      return '从 ${prettyDay(a['startDate'])}起，每隔 ${a['interval']} 天';
    case 'window':
      return '${a['time']}—${a['windowEnd']}，每隔 ${a['intervalMinutes']} 分钟';
    default:
      return '循环排班';
  }
}

void editAlarm(BuildContext c, {Json? existing}) =>
    editor(c, AlarmEditor(existing: existing));

class AlarmEditor extends StatefulWidget {
  const AlarmEditor({super.key, this.existing});
  final Json? existing;
  @override
  State<AlarmEditor> createState() => _AlarmEditorState();
}

class _AlarmEditorState extends State<AlarmEditor> {
  late TextEditingController title, interval, minutes;
  late String type, time, start, end;
  late List<int> week;
  late Json ring;
  bool enabled = true;
  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    title = TextEditingController(text: a?['title'] ?? '');
    interval = TextEditingController(text: '${a?['interval'] ?? 2}');
    minutes = TextEditingController(text: '${a?['intervalMinutes'] ?? 60}');
    type = a?['type'] ?? 'daily';
    time = a?['time'] ?? '07:00';
    start = a?['startDate'] ?? day(DateTime.now());
    end = a?['windowEnd'] ?? '18:00';
    week = List<int>.from(a?['weekdays'] ?? [1, 2, 3, 4, 5]);
    ring = Map.from(a?['ring'] ?? ringDefaults());
    enabled = a?['enabled'] != false;
  }

  @override
  void dispose() {
    title.dispose();
    interval.dispose();
    minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => EditorFrame(
          title: widget.existing == null ? '新增闹钟' : '自定义闹钟',
          save: () async {
            if (title.text.trim().isEmpty)
              throw const FormatException('请填写闹钟名称');
            if ((type == 'weekly' || type == 'window') && week.isEmpty)
              throw const FormatException('请至少选择一个星期');
            await UiScope.of(c).store.putAlarm({
              ...?widget.existing,
              'id': widget.existing?['id'] ?? uid(),
              'title': title.text.trim(),
              'enabled': enabled,
              'type': type,
              'time': time,
              'startDate': start,
              'windowEnd': end,
              'weekdays': week,
              'interval': number(interval, 1, 365, '间隔天数'),
              'intervalMinutes': number(minutes, 1, 1440, '间隔分钟'),
              'ring': ring
            });
          },
          children: [
            field(title, '闹钟名称'),
            pickerRow('响铃 / 时段开始', time, () async {
              final v = await chooseTime(c, time);
              if (v != null) setState(() => time = v);
            }),
            dropdown(
                '重复规则',
                type,
                const [
                  ('once', '仅一次'),
                  ('daily', '每天'),
                  ('weekly', '工作日 / 自选星期'),
                  ('interval', '每隔若干天'),
                  ('window', '指定时段内周期提醒')
                ],
                (v) => setState(() => type = v)),
            if (type == 'weekly' || type == 'window')
              weekdays(week, (v) => setState(() => week = v)),
            if (type == 'once' || type == 'interval')
              pickerRow(type == 'once' ? '响铃日期' : '间隔起点', prettyDay(start),
                  () async {
                final v = await chooseDate(c, start);
                if (v != null) setState(() => start = v);
              }),
            if (type == 'interval') field(interval, '每隔多少天', number: true),
            if (type == 'window') ...[
              pickerRow('时段结束', end, () async {
                final v = await chooseTime(c, end);
                if (v != null) setState(() => end = v);
              }),
              field(minutes, '间隔多少分钟', number: true),
              if (end.compareTo(time) <= 0) const Text('此时段跨午夜，结束时间在次日。')
            ],
            RingFields(
                profile: ring, onChanged: (v) => setState(() => ring = v)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用此闹钟'),
                value: enabled,
                onChanged: (v) => setState(() => enabled = v)),
            if (widget.existing != null)
              TextButton.icon(
                  onPressed: () async {
                    if (await confirm(c, '删除闹钟？', '未来响铃与贪睡重响将一并取消。')) {
                      await UiScope.of(c).store.putAlarm({
                        ...widget.existing!,
                        'enabled': false,
                        'deletedAt': DateTime.now().toUtc().toIso8601String()
                      });
                      if (c.mounted) Navigator.pop(c);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除这个闹钟'))
          ]);
}

class ShiftPage extends StatelessWidget {
  const ShiftPage({super.key});
  @override
  Widget build(BuildContext c) {
    final s = UiScope.of(c).store;
    return Scaffold(
        appBar: AppBar(title: const Text('循环排班'), actions: [
          IconButton(
              onPressed: () => editor(c, const ShiftEditor()),
              icon: const Icon(Icons.add),
              tooltip: '新增排班')
        ]),
        body: Backdrop(
            child: ListView(padding: const EdgeInsets.all(22), children: [
          heading(c, '跟着你的班次走', subtitle: '任意天数循环 · 每天可以多个闹钟'),
          if (s.shifts.where((s) => s['deletedAt'] == null).isEmpty)
            emptyState(c, '设定自己的班次', '例如：第 1 天 07:00，第 2 天 06:00，第 3 天休息。',
                action: () => editor(c, const ShiftEditor()), button: '创建循环排班'),
          ...s.shifts.where((x) => x['deletedAt'] == null).map((shift) =>
              Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Glass(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Expanded(
                              child: Text(shift['title'],
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600))),
                          Switch(
                              value: shift['enabled'] == true,
                              onChanged: (v) => guarded(c,
                                  () => s.putShift({...shift, 'enabled': v})))
                        ]),
                        Text(
                            '从 ${prettyDay(shift['startDate'])} 起，${(shift['days'] as List).length} 天一轮'),
                        const SizedBox(height: 15),
                        Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: (shift['days'] as List)
                                .asMap()
                                .entries
                                .map((e) => chip(c,
                                    '第 ${e.key + 1} 天：${(e.value['times'] as List).isEmpty ? '休息' : (e.value['times'] as List).join(' / ')}'))
                                .toList()),
                        const SizedBox(height: 15),
                        OutlinedButton(
                            onPressed: () =>
                                editor(c, ShiftEditor(existing: shift)),
                            child: const Text('编辑整个循环')),
                        TextButton(
                            onPressed: () => shiftException(c, shift),
                            child: const Text('仅修改某一天')),
                        const Divider(),
                        const Text('未来 7 天',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        ...List.generate(7, (i) {
                          final date = day(addDays(parseDay(s.today), i)),
                              delta = daysBetween(shift['startDate'], date),
                              days = shift['days'] as List,
                              override = shift['exceptions'][date] as List?;
                          final times = delta < 0
                              ? <dynamic>[]
                              : override ??
                                  days[delta % days.length]['times'] as List;
                          return infoRow(
                              '${prettyDay(date)}${override != null ? ' · 临时调整' : ''}',
                              delta < 0
                                  ? '尚未开始'
                                  : times.isEmpty
                                      ? '休息'
                                      : times.join(' / '));
                        })
                      ]))))
        ])));
  }
}

Future<void> shiftException(BuildContext c, Json shift) async {
  var date = UiScope.of(c).store.today;
  final times = TextEditingController();
  List<String>? chosenTimes;
  final result = await controlledDialog<bool>(
      context: c,
      controllers: [times],
      builder: (d) => StatefulBuilder(
          builder: (d, set) => AlertDialog(
                  title: const Text('仅调整这一天'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    pickerRow('日期', prettyDay(date), () async {
                      final v = await chooseDate(d, date);
                      if (v != null) set(() => date = v);
                    }),
                    WheelTimeList(controller: times, label: '当天响铃时间'),
                    const Text('只替换当天闹钟，不移动后续循环位置。',
                        style: TextStyle(fontSize: 12))
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () {
                          try {
                            chosenTimes = validTimes(times.text);
                            if (date.compareTo(shift['startDate']) < 0)
                              throw const FormatException('例外日期不能早于排班起点');
                            Navigator.pop(d, true);
                          } catch (e) {
                            message(d, e.toString());
                          }
                        },
                        child: const Text('保存'))
                  ])));
  if (result == true && c.mounted) {
    final exceptions = Map<String, dynamic>.from(shift['exceptions']);
    exceptions[date] = chosenTimes!;
    await guarded(
        c,
        () =>
            UiScope.of(c).store.putShift({...shift, 'exceptions': exceptions}));
  }
}

List<String> validTimes(String raw) {
  final list = raw
      .split(RegExp('[,，]'))
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  if (list.any((t) => !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t)))
    throw const FormatException('请使用 24 小时时间，如 07:00, 12:30');
  return list;
}

class ShiftEditor extends StatefulWidget {
  const ShiftEditor({super.key, this.existing});
  final Json? existing;
  @override
  State<ShiftEditor> createState() => _ShiftEditorState();
}

class _ShiftEditorState extends State<ShiftEditor> {
  late TextEditingController title, length;
  late List<TextEditingController> days;
  final retired = <TextEditingController>[];
  late String anchor;
  late Json ring;
  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    title = TextEditingController(text: s?['title'] ?? '三天循环排班');
    length =
        TextEditingController(text: '${(s?['days'] as List?)?.length ?? 3}');
    days = (s?['days'] as List? ??
            [
              {
                'times': ['07:00']
              },
              {
                'times': ['06:00']
              },
              {'times': []}
            ])
        .map(
            (d) => TextEditingController(text: (d['times'] as List).join(', ')))
        .toList();
    anchor = s?['startDate'] ?? day(DateTime.now());
    ring = Map.from(s?['ring'] ?? ringDefaults());
  }

  @override
  void dispose() {
    title.dispose();
    length.dispose();
    for (final d in [...days, ...retired]) {
      d.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => EditorFrame(
          title: '自定义循环排班',
          save: () async {
            if (title.text.trim().isEmpty)
              throw const FormatException('请填写排班名称');
            final count = number(length, 1, 31, '循环天数');
            if (count != days.length)
              throw const FormatException('请先点击“应用循环长度”');
            final defs =
                days.map((d) => {'times': validTimes(d.text)}).toList();
            await UiScope.of(c).store.putShift({
              ...?widget.existing,
              'id': widget.existing?['id'] ?? uid(),
              'title': title.text.trim(),
              'startDate': anchor,
              'enabled': widget.existing?['enabled'] ?? true,
              'days': defs,
              'exceptions':
                  widget.existing?['exceptions'] ?? <String, dynamic>{},
              'ring': ring
            });
          },
          children: [
            field(title, '排班名称'),
            pickerRow('第 1 天的日期', prettyDay(anchor), () async {
              final v = await chooseDate(c, anchor);
              if (v != null) setState(() => anchor = v);
            }),
            field(length, '循环长度 / 天（1—31）', number: true),
            TextButton(
                onPressed: () {
                  try {
                    final n = number(length, 1, 31, '循环长度');
                    setState(() {
                      while (days.length < n) {
                        days.add(TextEditingController());
                      }
                      while (days.length > n) {
                        retired.add(days.removeLast());
                      }
                    });
                  } catch (e) {
                    message(c, e.toString());
                  }
                },
                child: const Text('应用循环长度')),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('点击时间用滚轮调整；每天可添加多个时间，没有时间表示休息。',
                    style: TextStyle(fontSize: 12))),
            ...days.asMap().entries.map((e) =>
                WheelTimeList(controller: e.value, label: '第 ${e.key + 1} 天')),
            RingFields(
                profile: ring, onChanged: (v) => setState(() => ring = v)),
            if (widget.existing != null)
              TextButton.icon(
                  onPressed: () async {
                    if (await confirm(c, '删除循环排班？', '该排班的未来闹钟将取消。')) {
                      await UiScope.of(c).store.putShift({
                        ...widget.existing!,
                        'enabled': false,
                        'deletedAt': DateTime.now().toUtc().toIso8601String()
                      });
                      if (c.mounted) Navigator.pop(c);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除此排班'))
          ]);
}

/// Schedule days and exceptions use the same wheel as independent alarms.
class WheelTimeList extends StatelessWidget {
  const WheelTimeList(
      {super.key, required this.controller, required this.label});
  final TextEditingController controller;
  final String label;
  void save(List<String> times) =>
      controller.text = (times.toSet().toList()..sort()).join(', ');
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (c, value, _) {
        final times = validTimes(value.text);
        return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$label${times.isEmpty ? ' · 休息' : ''}'),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (var i = 0; i < times.length; i++)
                  InputChip(
                      label: Text(times[i]),
                      onPressed: () async {
                        final result = await chooseTime(c, times[i]);
                        if (result != null && c.mounted) {
                          times[i] = result;
                          save(times);
                        }
                      },
                      onDeleted: () {
                        times.removeAt(i);
                        save(times);
                      }),
                ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('添加时间'),
                    onPressed: () async {
                      final result = await chooseTime(
                          c, times.isEmpty ? '07:00' : times.last);
                      if (result != null && c.mounted) save([...times, result]);
                    })
              ])
            ]));
      });
}
