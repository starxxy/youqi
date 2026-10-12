import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:youqi/core.dart';

Json taskInput({String repeat = 'none', String date = '2026-10-11'}) => {
      'title': '完成产品原型',
      'notes': '核心页面',
      'startDate': date,
      'dueDate': date,
      'estimate': 1,
      'repeat': repeat,
      'interval': 2,
      'weekdays': [1, 2, 3, 4, 5],
      'scheduleStart': '09:00',
      'scheduleEnd': '10:30',
      'reminders': [
        {
          'id': 'r1',
          'anchor': 'start',
          'offset': -30,
          'enabled': true,
          'ring': ringDefaults()
        },
        {
          'id': 'r2',
          'anchor': 'end',
          'offset': -30,
          'enabled': true,
          'ring': ringDefaults()
        }
      ]
    };
void main() {
  test('七级逾期封顶而实际天数保留', () {
    expect(overdueLevel('2026-10-11', '2026-10-11'), 0);
    expect(overdueLevel('2026-10-11', '2026-10-12'), 1);
    expect(overdueLevel('2026-10-11', '2026-11-11'), 7);
    expect(overdueDays('2026-10-11', '2026-11-11'), 31);
    expect(overdueLevel(null, '2026-10-11'), 0);
  });
  test('每日重复的完成、改期与历史互不污染，离线重启保存', () async {
    final repo = MemoryRepository();
    var now = DateTime(2026, 10, 11);
    final s = YouqiStore(repo, clock: () => now);
    await s.init();
    await s.addTask(taskInput(repeat: 'daily'));
    final first = s.visible(s.today).single;
    await s.toggleDone(first);
    now = DateTime(2026, 10, 12);
    await s.materialize();
    expect(s.visible(s.today).length, 1);
    final second = s.visible(s.today).single;
    expect(second['done'], false);
    await s.reschedule(second, '2026-10-15');
    expect(second['deadlineRevisionCount'], 1);
    expect((second['history'] as List).single['overdueDaysAtChange'], 0);
    expect(first['dueDate'], '2026-10-11');
    final loaded = YouqiStore(repo, clock: () => now);
    await loaded.init();
    expect(loaded.occurrences[first['id']]['done'], true);
    expect(loaded.occurrences[second['id']]['dueDate'], '2026-10-15');
  });
  test('完成持续任务撤销其所有事件规则；单日调整替换模板不重复', () async {
    final s =
        YouqiStore(MemoryRepository(), clock: () => DateTime(2026, 10, 11));
    await s.init();
    await s.addTask(taskInput());
    final o = s.visible(s.today).single;
    expect(s.nativeRules().length, 2);
    final b = s.blockFor(o, s.today)!;
    b['start'] = '11:00';
    await s.saveBlock(b);
    expect(
        s.nativeRules().where((r) => r['key'].startsWith('block:')).length, 2);
    expect(
        s
            .nativeRules()
            .where((r) => r['key'].startsWith('block:'))
            .every((r) => r['occurrenceId'] == o['id']),
        true);
    expect(
        s
            .nativeRules()
            .where((r) => r['key'].startsWith('task:'))
            .first['excludedDates'],
        ['2026-10-11']);
    await s.toggleDone(o);
    expect(s.nativeRules(), isEmpty);
    await s.toggleDone(o);
    expect(s.nativeRules().length, 4);
  });
  test('删除保留 tombstone，保存队列快照不被后续修改污染', () async {
    final repo = MemoryRepository();
    final s = YouqiStore(repo, clock: () => DateTime(2026, 10, 11));
    await s.init();
    await s.addTask(taskInput());
    final initial = (s.data['outbox'] as List).first['payload'];
    s.tasks.single['reminders'][0]['offset'] = -60;
    expect(initial['reminders'][0]['offset'], -30);
    await s.deleteTask(s.tasks.single);
    expect(s.visible(s.today), isEmpty);
    expect(s.tasks.single['deletedAt'], isNotNull);
    expect((jsonDecode(repo.value!)['outbox'] as List).last['operation'],
        'delete');
  });
  test('备份往返恢复、变更队列类型与设备身份', () async {
    final s =
        YouqiStore(MemoryRepository(), clock: () => DateTime(2026, 10, 11));
    await s.init();
    await s.addTask(taskInput());
    final original = s.deviceId;
    final backup = s.exportData();
    await s.deleteTask(s.tasks.single);
    await s.restore(backup);
    expect(s.deviceId, original);
    expect(s.visible(s.today).length, 1);
    expect(s.data['outbox'].first['entityType'], 'task');
    final malformed = jsonDecode(backup);
    malformed['tasks'][0]['startDate'] = 'bad';
    await expectLater(s.restore(jsonEncode(malformed)), throwsFormatException);
    expect(s.visible(s.today).length, 1);
  });
  test('未来日程可提前规划，补齐明天记录时不跳日也不重复', () async {
    var now = DateTime(2026, 10, 11);
    final s = YouqiStore(MemoryRepository(), clock: () => now);
    await s.init();
    await s.addTask(taskInput(repeat: 'daily'));
    await s.materialize(planningDate: '2026-10-13');
    expect(s.eventsFor('2026-10-13').length, 1);
    expect(s.visible(s.today).length, 1);
    now = DateTime(2026, 10, 12);
    await s.materialize();
    expect(s.eventsFor('2026-10-12').length, 1);
    now = DateTime(2026, 10, 13);
    await s.materialize();
    expect(s.eventsFor('2026-10-13').length, 1);
    expect(s.occurrences.length, 3);
  });
}
