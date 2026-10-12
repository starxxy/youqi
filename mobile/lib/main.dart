import 'package:flutter/material.dart';
import 'core.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = YouqiStore(AndroidRepository());
  try {
    await store.init();
    runApp(YouqiApp(store: store));
  } catch (e) {
    runApp(MaterialApp(
        home: Scaffold(
            body: SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        '无法读取本机数据。为避免覆盖已有内容，应用已停止写入。\n请保留应用数据并反馈此信息：\n$e'))))));
  }
}
