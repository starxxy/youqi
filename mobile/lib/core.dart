import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef Json = Map<String, dynamic>;
String uid() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(1 << 30).toRadixString(36)}';
String day(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
DateTime parseDay(String value) => DateTime.parse(value);
DateTime addDays(DateTime value, int count) =>
    DateTime(value.year, value.month, value.day + count);
int daysBetween(String a, String b) =>
    DateTime.utc(parseDay(b).year, parseDay(b).month, parseDay(b).day)
        .difference(
            DateTime.utc(parseDay(a).year, parseDay(a).month, parseDay(a).day))
        .inDays;
String prettyDay(String? value) => value == null || value.isEmpty
    ? '不设截止'
    : '${parseDay(value).month} 月 ${parseDay(value).day} 日';
int overdueDays(String? due, String today) =>
    due == null || due.isEmpty ? 0 : max(0, daysBetween(due, today));
int overdueLevel(String? due, String today) => min(7, overdueDays(due, today));
String offsetLabel(Json reminder) {
  final anchor = reminder['anchor'] == 'end' ? '结束' : '开始';
  final n = reminder['offset'] as int;
  return n == 0 ? '$anchor 时' : '$anchor${n < 0 ? '前' : '后'} ${n.abs()} 分钟';
}

bool matches(Json task, String date) {
  if (task['deletedAt'] != null || date.compareTo(task['startDate']) < 0)
    return false;
  switch (task['repeat']) {
    case 'daily':
      return true;
    case 'weekly':
      return (task['weekdays'] as List).contains(parseDay(date).weekday);
    case 'interval':
      return daysBetween(task['startDate'], date) % (task['interval'] as int) ==
          0;
    default:
      return date == task['startDate'];
  }
}

String occurrenceId(Json task, String date) =>
    '${task['id']}@${task['repeat'] == 'none' ? task['startDate'] : date}';
Json ringDefaults() => {
      'tone': '',
      'volume': .85,
      'vibrate': true,
      'duration': 60,
      'snooze': 5,
      'maxSnoozes': 3,
      'autoRepeat': false
    };

abstract interface class LocalRepository {
  Future<String?> load();
  Future<void> write(String json);
}

class AndroidRepository implements LocalRepository {
  static const channel = MethodChannel('cn.youqi/native');
  @override
  Future<String?> load() => channel.invokeMethod<String>('load');
  @override
  Future<void> write(String json) => channel.invokeMethod('save', json);
}

class MemoryRepository implements LocalRepository {
  String? value;
  @override
  Future<String?> load() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }
}

/// Platform-neutral sync boundary. No remote provider is configured yet.
abstract interface class SyncTransport {
  Future<Json> pull({required String deviceId, String? cursor});
  Future<Json> push({required String deviceId, required List<Json> mutations});
  Future<Json> resolve(
      {required String conflictId,
      required String remoteRevision,
      required Json merged});
}

class NotConnectedTransport implements SyncTransport {
  Never unavailable() => throw StateError('尚未配置同步服务');
  @override
  Future<Json> pull({required String deviceId, String? cursor}) async =>
      unavailable();
  @override
  Future<Json> push(
          {required String deviceId, required List<Json> mutations}) async =>
      unavailable();
  @override
  Future<Json> resolve(
          {required String conflictId,
          required String remoteRevision,
          required Json merged}) async =>
      unavailable();
}

class YouqiStore extends ChangeNotifier {
  YouqiStore(this.repository, {DateTime Function()? clock})
      : clock = clock ?? DateTime.now;
  final LocalRepository repository;
  final DateTime Function() clock;
  late Json data;
  String? error;
  Future<void> _writing = Future.value();
  String get today => day(clock());
  List<Json> get tasks => (data['tasks'] as List).cast<Json>();
  List<Json> get alarms => (data['alarms'] as List).cast<Json>();
  List<Json> get shifts => (data['shifts'] as List).cast<Json>();
  List<Json> get blocks => (data['blocks'] as List).cast<Json>();
  Json get occurrences => data['occurrences'];
  Json get appearance => data['appearance'];
  String get deviceId => data['deviceId'];
  Json empty() => {
        'schemaVersion': 1,
        'deviceId': uid(),
        'tasks': <Json>[],
        'occurrences': <String, dynamic>{},
        'blocks': <Json>[],
        'alarms': <Json>[],
        'shifts': <Json>[],
        'outbox': <Json>[],
        'conflicts': <Json>[],
        'cursor': null,
        'appearance': {'layout': 'a', 'mode': 'light', 'glass': true},
        'deviceMode': 'ring'
      };
  Future<void> init() async {
    final raw = await repository.load();
    data = raw == null ? empty() : jsonDecode(raw) as Json;
    if (data['schemaVersion'] != 1) throw StateError('数据版本不兼容，请保留备份后升级应用');
    await materialize();
  }

  Json meta(Json object) => {
        ...object,
        'schemaVersion': 1,
        'createdAt': object['createdAt'] ?? clock().toUtc().toIso8601String(),
        'updatedAt': clock().toUtc().toIso8601String(),
        'updatedByDeviceId': deviceId,
        'revision': object['revision'] ?? null
      };
  void mutation(String type, Json object, {String operation = 'upsert'}) {
    object.addAll(meta(object));
    (data['outbox'] as List).add({
      'mutationId': uid(),
      'entityType': type,
      'entityId': object['id'],
      'baseRevision': object['revision'],
      'operation': operation,
      'originatingDeviceId': deviceId,
      'payload': jsonDecode(jsonEncode(object))
    });
  }

  Future<void> save() {
    final snapshot = jsonEncode({...data, 'nativeRules': nativeRules()});
    notifyListeners();
    _writing = _writing.catchError((_) {}).then((_) async {
      try {
        await repository.write(snapshot);
        error = null;
      } catch (e) {
        error = '保存失败，修改尚未落盘：$e';
        notifyListeners();
        rethrow;
      }
    });
    return _writing;
  }

  Future<void> materialize({String? planningDate}) async {
    bool changed = false;
    for (final t in tasks.where((t) => t['deletedAt'] == null)) {
      if (planningDate != null && t['repeat'] == 'none') continue;
      final from = planningDate ??
          (t['generatedThrough'] == null
              ? t['startDate'] as String
              : day(addDays(parseDay(t['generatedThrough']), 1)));
      final to = planningDate ??
          (t['repeat'] == 'none' ? t['startDate'] as String : today);
      for (var d = parseDay(from);
          day(d).compareTo(to) <= 0;
          d = addDays(d, 1)) {
        final date = day(d);
        if (!matches(t, date)) continue;
        final id = occurrenceId(t, date);
        if (occurrences.containsKey(id)) continue;
        final due = t['dueDate'] as String?;
        final occurrenceDue = due == null
            ? null
            : t['repeat'] == 'none'
                ? due
                : day(addDays(d, daysBetween(t['startDate'], due)));
        final item = <String, dynamic>{
          'id': id,
          'taskId': t['id'],
          'date': date,
          'dueDate': occurrenceDue,
          'originalDueDate': occurrenceDue,
          'done': false,
          'deadlineRevisionCount': 0,
          'history': <Json>[]
        };
        occurrences[id] = item;
        mutation('occurrence', item);
        changed = true;
      }
      if (planningDate == null &&
          to.compareTo(t['startDate']) >= 0 &&
          (t['generatedThrough'] == null ||
              to.compareTo(t['generatedThrough']) > 0)) {
        t['generatedThrough'] = to;
        changed = true;
      }
    }
    if (changed)
      await save();
    else
      notifyListeners();
  }

  Json? task(String id) {
    for (final t in tasks) {
      if (t['id'] == id) return t;
    }
    return null;
  }

  List<Json> visible(String date, {bool done = false}) =>
      occurrences.values.cast<Json>().where((o) {
        final t = task(o['taskId']);
        return t != null &&
            t['deletedAt'] == null &&
            o['deletedAt'] == null &&
            o['date'].compareTo(date) <= 0 &&
            (o['done'] == done);
      }).toList()
        ..sort((a, b) {
          final ad = overdueDays(a['dueDate'], date),
              bd = overdueDays(b['dueDate'], date);
          return bd == ad ? a['date'].compareTo(b['date']) : bd.compareTo(ad);
        });
  Future<void> addTask(Json input) async {
    final t = meta({
      'id': uid(),
      ...input,
      'createdAt': clock().toUtc().toIso8601String(),
      'deletedAt': null
    });
    tasks.add(t);
    mutation('task', t);
    await materialize();
    await save();
  }

  Future<void> editTask(Json t, Json input) async {
    t.addAll(input);
    if (t['repeat'] != 'none')
      t['generatedThrough'] = day(addDays(clock(), -1));
    mutation('task', t);
    await save();
  }

  Future<void> toggleDone(Json o) async {
    o['done'] = !o['done'];
    o['completedAt'] = o['done'] ? clock().toUtc().toIso8601String() : null;
    mutation('occurrence', o);
    await save();
  }

  Future<void> deleteTask(Json t) async {
    t['deletedAt'] = clock().toUtc().toIso8601String();
    mutation('task', t, operation: 'delete');
    await save();
  }

  Future<void> reschedule(Json o, String due) async {
    final history = <String, dynamic>{
      'id': uid(),
      'occurrenceId': o['id'],
      'from': o['dueDate'],
      'to': due,
      'overdueDaysAtChange': overdueDays(o['dueDate'], today),
      'changedAt': clock().toUtc().toIso8601String(),
      'ordinal': o['deadlineRevisionCount'] + 1
    };
    (o['history'] as List).add(history);
    o['dueDate'] = due;
    o['deadlineRevisionCount']++;
    mutation('deadlineChange', history);
    mutation('occurrence', o);
    await save();
  }

  Json? blockFor(Json o, String date) {
    for (final b in blocks) {
      if (b['occurrenceId'] == o['id'] && b['date'] == date) return b;
    }
    final t = task(o['taskId'])!;
    if (t['scheduleStart'] == null ||
        date != (t['repeat'] == 'none' ? t['startDate'] : o['date']))
      return null;
    return {
      'id': '${o['id']}@$date',
      'occurrenceId': o['id'],
      'taskId': t['id'],
      'date': date,
      'start': t['scheduleStart'],
      'end': t['scheduleEnd'],
      'reminders': List<Json>.from(
          (t['reminders'] as List).map((r) => Map<String, dynamic>.from(r)))
    };
  }

  List<Json> eventsFor(String date) {
    final result = <Json>[];
    for (final o in occurrences.values.cast<Json>()) {
      final t = task(o['taskId']);
      if (t == null || t['deletedAt'] != null || o['deletedAt'] != null)
        continue;
      final b = blockFor(o, date);
      if (b != null) result.add(b);
    }
    return result..sort((a, b) => a['start'].compareTo(b['start']));
  }

  Future<void> saveBlock(Json b) async {
    final i = blocks.indexWhere((x) => x['id'] == b['id']);
    if (i < 0)
      blocks.add(b);
    else
      blocks[i] = b;
    mutation('timeBlock', b);
    await save();
  }

  Future<void> putAlarm(Json alarm) async {
    final i = alarms.indexWhere((a) => a['id'] == alarm['id']);
    if (i < 0)
      alarms.add(alarm);
    else
      alarms[i] = alarm;
    mutation('alarm', alarm);
    await save();
  }

  Future<void> putShift(Json shift) async {
    final i = shifts.indexWhere((s) => s['id'] == shift['id']);
    if (i < 0)
      shifts.add(shift);
    else
      shifts[i] = shift;
    mutation('shift', shift);
    await save();
  }

  Future<void> setAppearance(String key, dynamic value) async {
    appearance[key] = value;
    await save();
  }

  Future<void> setDeviceMode(String value) async {
    data['deviceMode'] = value;
    await save();
  }

  List<Json> nativeRules() {
    final rules = <Json>[];
    for (final a in alarms.where((a) => a['deletedAt'] == null))
      rules.add({
        ...a,
        'key': 'alarm:${a['id']}',
        'enabled': a['enabled'] == true,
        'sourceKind': 'alarm',
        'sourceId': a['id']
      });
    for (final s in shifts.where((s) => s['deletedAt'] == null))
      rules.add({
        ...s,
        'key': 'shift:${s['id']}',
        'type': 'shift',
        'sourceKind': 'shift',
        'sourceId': s['id']
      });
    for (final t in tasks.where((t) => t['deletedAt'] == null)) {
      final os = occurrences.values
          .cast<Json>()
          .where((o) => o['taskId'] == t['id'])
          .toList();
      final completed = os
          .where((o) => o['done'] == true || o['deletedAt'] != null)
          .map((o) => o['date'])
          .toList();
      if (t['repeat'] == 'none' && completed.isNotEmpty) continue;
      final overrides = blocks.where((b) => b['taskId'] == t['id']).toList();
      if (t['scheduleStart'] != null) {
        for (final r in (t['reminders'] as List).cast<Json>()) {
          final end = r['anchor'] == 'end';
          rules.add({
            'id': r['id'],
            'key': 'task:${t['id']}:${r['id']}',
            'title': t['title'],
            'type': t['repeat'] == 'none' ? 'once' : t['repeat'],
            'startDate': t['startDate'],
            'time': end ? t['scheduleEnd'] : t['scheduleStart'],
            'dayOffset':
                end && t['scheduleEnd'].compareTo(t['scheduleStart']) < 0
                    ? 1
                    : 0,
            'offset': r['offset'],
            'interval': t['interval'],
            'weekdays': t['weekdays'],
            'excludedDates': [...completed, ...overrides.map((b) => b['date'])],
            'enabled': r['enabled'] != false,
            'ring': r['ring'] ?? ringDefaults(),
            'sourceKind': 'task',
            'sourceId': t['id']
          });
        }
      }
      for (final b in overrides) {
        final occurrence = occurrences[b['occurrenceId']];
        if (occurrence == null ||
            occurrence['done'] == true ||
            occurrence['deletedAt'] != null) continue;
        for (final r in (b['reminders'] as List).cast<Json>()) {
          final end = r['anchor'] == 'end';
          rules.add({
            'id': r['id'],
            'key': 'block:${b['id']}:${r['id']}',
            'occurrenceId': b['occurrenceId'],
            'title': t['title'],
            'type': 'once',
            'startDate': b['date'],
            'time': end ? b['end'] : b['start'],
            'dayOffset': end && b['end'].compareTo(b['start']) < 0 ? 1 : 0,
            'offset': r['offset'],
            'enabled': r['enabled'] != false,
            'ring': r['ring'] ?? ringDefaults(),
            'sourceKind': 'task',
            'sourceId': t['id']
          });
        }
      }
    }
    return rules;
  }

  String exportData() => const JsonEncoder.withIndent('  ')
      .convert({...data, 'exportedAt': clock().toUtc().toIso8601String()});
  Future<void> refreshNative(int generation) async {
    if (generation <= (data['nativeGeneration'] ?? 0)) return;
    await _writing.catchError((_) {});
    final raw = await repository.load();
    if (raw == null) return;
    final newer = jsonDecode(raw) as Json;
    if ((newer['nativeGeneration'] ?? 0) > (data['nativeGeneration'] ?? 0)) {
      data = newer;
      notifyListeners();
    }
  }

  void validateBackup(Json c) {
    Never bad() => throw const FormatException('备份内容不完整或包含无效值，原数据未修改');
    bool date(dynamic v) =>
        v is String &&
        RegExp(r'^20\d\d-\d{2}-\d{2}$').hasMatch(v) &&
        DateTime.tryParse(v) != null &&
        day(DateTime.parse(v)) == v;
    bool time(dynamic v) =>
        v is String && RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(v);
    bool integer(dynamic v, int min, int max) =>
        v is int && v >= min && v <= max;
    void ring(dynamic r) {
      if (r is! Json ||
          r['tone'] is! String ||
          r['vibrate'] is! bool ||
          r['autoRepeat'] is! bool ||
          r['volume'] is! num ||
          r['volume'] < 0 ||
          r['volume'] > 1 ||
          !integer(r['duration'], 10, 1800) ||
          !integer(r['snooze'], 1, 1440) ||
          !integer(r['maxSnoozes'], 0, 100)) bad();
    }

    void reminders(dynamic rs) {
      if (rs is! List) bad();
      for (final r in rs) {
        if (r is! Json ||
            r['id'] is! String ||
            !['start', 'end'].contains(r['anchor']) ||
            !integer(r['offset'], -10080, 10080) ||
            r['enabled'] is! bool) bad();
        ring(r['ring']);
      }
    }

    if (c['appearance'] is! Json ||
        !['a', 'b', 'c'].contains(c['appearance']['layout']) ||
        !['light', 'dark', 'system'].contains(c['appearance']['mode']) ||
        c['appearance']['glass'] is! bool ||
        !['ring', 'notify', 'silent'].contains(c['deviceMode'])) bad();
    for (final kind in ['tasks', 'alarms', 'shifts', 'blocks']) {
      if (c[kind] is! List) bad();
      final ids = <String>{};
      for (final item in c[kind]) {
        if (item is! Json || item['id'] is! String || !ids.add(item['id']))
          bad();
        if (kind != 'blocks' &&
            (item['title'] is! String || !date(item['startDate']))) bad();
        if (kind == 'tasks') {
          if (item['notes'] is! String ||
              !integer(item['estimate'], 1, 365) ||
              !['none', 'daily', 'weekly', 'interval']
                  .contains(item['repeat']) ||
              !integer(item['interval'], 1, 365) ||
              (item['dueDate'] != null && !date(item['dueDate'])) ||
              item['weekdays'] is! List ||
              (item['weekdays'] as List).any((d) => !integer(d, 1, 7)) ||
              (item['scheduleStart'] != null &&
                  (!time(item['scheduleStart']) || !time(item['scheduleEnd']))))
            bad();
          reminders(item['reminders']);
        }
        if (kind == 'blocks') {
          if (item['occurrenceId'] is! String ||
              item['taskId'] is! String ||
              !date(item['date']) ||
              !time(item['start']) ||
              !time(item['end'])) bad();
          reminders(item['reminders']);
        }
        if (kind == 'alarms') {
          if (!['once', 'daily', 'weekly', 'interval', 'window']
                  .contains(item['type']) ||
              !time(item['time']) ||
              item['enabled'] is! bool ||
              !integer(item['interval'], 1, 365) ||
              !integer(item['intervalMinutes'], 1, 1440) ||
              !time(item['windowEnd']) ||
              item['weekdays'] is! List ||
              (item['weekdays'] as List).any((d) => !integer(d, 1, 7))) bad();
          ring(item['ring']);
        }
        if (kind == 'shifts') {
          if (item['enabled'] is! bool ||
              item['days'] is! List ||
              (item['days'] as List).isEmpty ||
              (item['days'] as List).length > 31 ||
              item['exceptions'] is! Json) bad();
          for (final d in item['days']) {
            if (d is! Json ||
                d['times'] is! List ||
                (d['times'] as List).any((t) => !time(t))) bad();
          }
          for (final e in (item['exceptions'] as Json).entries) {
            if (!date(e.key) ||
                e.value is! List ||
                (e.value as List).any((t) => !time(t))) bad();
          }
          ring(item['ring']);
        }
      }
    }
    if (c['occurrences'] is! Json) bad();
    for (final e in (c['occurrences'] as Json).entries) {
      final o = e.value;
      if (o is! Json ||
          o['id'] != e.key ||
          o['taskId'] is! String ||
          !date(o['date']) ||
          (o['dueDate'] != null && !date(o['dueDate'])) ||
          o['done'] is! bool ||
          !integer(o['deadlineRevisionCount'], 0, 100000) ||
          o['history'] is! List) bad();
      for (final h in o['history']) {
        if (h is! Json ||
            !date(h['to']) ||
            (h['from'] != null && !date(h['from'])) ||
            h['changedAt'] is! String ||
            !integer(h['ordinal'], 1, 100000) ||
            !integer(h['overdueDaysAtChange'], 0, 100000)) bad();
      }
    }
  }

  Future<void> restore(String raw) async {
    final candidate = jsonDecode(raw);
    if (candidate is! Map<String, dynamic> ||
        candidate['schemaVersion'] != 1 ||
        candidate['tasks'] is! List ||
        candidate['occurrences'] is! Map ||
        candidate['alarms'] is! List ||
        candidate['shifts'] is! List ||
        candidate['blocks'] is! List) throw const FormatException('备份格式或版本不正确');
    validateBackup(candidate);
    final originalDevice = deviceId;
    final generation = data['nativeGeneration'] ?? 0;
    data = candidate;
    data['deviceId'] = originalDevice;
    data['nativeGeneration'] = generation;
    data.remove('nativeOverrides');
    data.remove('focus');
    data['cursor'] = null;
    data['conflicts'] = <Json>[];
    data['outbox'] = <Json>[];
    const types = {
      'tasks': 'task',
      'alarms': 'alarm',
      'shifts': 'shift',
      'blocks': 'timeBlock'
    };
    for (final kind in types.keys)
      for (final item in (data[kind] as List).cast<Json>())
        mutation(types[kind]!, item,
            operation: item['deletedAt'] != null ? 'delete' : 'upsert');
    for (final item in occurrences.values.cast<Json>())
      mutation('occurrence', item);
    await materialize();
    await save();
  }
}
