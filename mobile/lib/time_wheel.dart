import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui.dart';

/// Two independent, looping wheels. Controllers live through the exit animation.
class TimeWheelSheet extends StatefulWidget {
  const TimeWheelSheet({super.key, required this.initial});
  final String initial;
  @override
  State<TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<TimeWheelSheet> {
  late int hour, minute;
  late FixedExtentScrollController hours, minutes;
  @override
  void initState() {
    super.initState();
    final values = widget.initial.split(':').map(int.parse).toList();
    hour = values[0];
    minute = values[1];
    hours = FixedExtentScrollController(initialItem: hour);
    minutes = FixedExtentScrollController(initialItem: minute);
  }

  @override
  void dispose() {
    hours.dispose();
    minutes.dispose();
    super.dispose();
  }

  String get value =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext c) {
    final p = UiScope.of(c).palette;
    Widget wheel(bool isHour) => Expanded(
            child: Column(children: [
          Text(isHour ? '时' : '分',
              style: TextStyle(color: p.muted, fontSize: 14)),
          const SizedBox(height: 12),
          Expanded(
              child: CupertinoPicker(
                  key: ValueKey(isHour ? 'hour-wheel' : 'minute-wheel'),
                  scrollController: isHour ? hours : minutes,
                  itemExtent: 52,
                  diameterRatio: 1.8,
                  squeeze: 1.05,
                  useMagnifier: true,
                  magnification: 1.12,
                  looping: true,
                  selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                      background: p.accent.withOpacity(.09),
                      capStartEdge: isHour,
                      capEndEdge: !isHour),
                  onSelectedItemChanged: (v) {
                    if (v == (isHour ? hour : minute)) return;
                    // CupertinoPicker handles iOS itself; Android uses the View haptic API,
                    // which respects the system's touch-feedback setting.
                    if (Theme.of(c).platform == TargetPlatform.android)
                      HapticFeedback.selectionClick();
                    setState(() {
                      if (isHour) {
                        hour = v;
                      } else {
                        minute = v;
                      }
                    });
                  },
                  children: List.generate(
                      isHour ? 24 : 60,
                      (i) => Center(
                          child: Text(i.toString().padLeft(2, '0'),
                              style: TextStyle(
                                  fontSize: 30,
                                  color: p.text,
                                  fontWeight: FontWeight.w500)))))),
        ]));
    return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: p.glass ? 24 : 0, sigmaY: p.glass ? 24 : 0),
            child: Container(
                decoration: BoxDecoration(
                    color: p.surface.withOpacity(p.glass ? .92 : 1),
                    border: Border.all(color: p.line.withOpacity(.6))),
                child: SafeArea(
                    top: false,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: p.muted.withOpacity(.25),
                                  borderRadius: BorderRadius.circular(8))),
                          const SizedBox(height: 16),
                          Row(children: [
                            TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('取消')),
                            Expanded(
                                child: Column(children: [
                              Text('选择时间',
                                  style: TextStyle(
                                      color: p.text,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600)),
                              Text(value,
                                  key: const ValueKey('selected-time'),
                                  style:
                                      TextStyle(color: p.accent, fontSize: 16))
                            ])),
                            TextButton(
                                onPressed: () => Navigator.pop(c, value),
                                child: const Text('确认'))
                          ]),
                          const SizedBox(height: 24),
                          SizedBox(
                              height: (MediaQuery.sizeOf(c).height - 240)
                                  .clamp(72.0, 286.0),
                              child: Row(children: [
                                wheel(true),
                                const SizedBox(width: 16),
                                wheel(false)
                              ])),
                          const SizedBox(height: 16),
                          Text('24 小时制 · 滑动选择',
                              style: TextStyle(color: p.muted, fontSize: 12))
                        ]))))));
  }
}
