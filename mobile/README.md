# 有期 Android 0.2.1

Flutter 负责三套 UI 与业务模型，Kotlin 负责系统闹钟、响铃、锁屏入口、权限与文件选择器。支持 Android 8.0+（minSdk 26，targetSdk 35），离线使用，无第三方 Flutter 运行依赖。

## 功能

持续任务与独立重复实例、预计自然日、独立截止日期、每天递增的七级逾期、改期换色与历史；每日时间段、跨午夜、相对开始/结束的多个提醒；每天、星期、每隔 N 天、时段内周期、1—31 天循环排班与临时例外；铃声、音量、振动、自定义响铃时长、贪睡间隔和重响次数；专注倒计时；备份导入导出。

A 澄明 / B 时序 / C 聚焦在设置中切换，保留同一份数据。明暗主题与液态玻璃可独立选择。

0.2.0 修复响铃时点击图标的处理页入口，增加关闭本次、延后 5/10 分钟与每次延后加深一级（七级封顶）。时间选择统一为带刻度轻震动的双滚轮，排班多时间也通过滚轮添加/编辑。详见 [第二版说明](../docs/v0.2.0.md)。

0.2.1 修复到期广播与刷新/保存的竞争丢失、重新打开时系统登记未恢复的问题。新增已登记提醒列表和通知栏常驻待办开关。每次触发使用独立 fireKey 与持久交付记录，到期记录保留 15 分钟，服务启动失败一分钟后重试。详见 [修复与验证说明](../docs/v0.2.1.md)。

## 结构

| 文件 | 职责 |
| --- | --- |
| lib/core.dart | 实例生成、逾期与改期、离线写入、outbox、SyncTransport |
| lib/skins.dart | 可注入 SkinProvider 与语义颜色 |
| lib/ui.dart | 三套布局、详情、外观、备份与权限入口 |
| lib/editors.dart | 任务、日程、多个提醒、闹钟与排班编辑器 |
| lib/time_wheel.dart | 24 小时双滚轮时间选择、触觉反馈与控制器生命周期 |
| android/.../RuleEngine.kt | 不依赖 Android 的日期与周期计算 |
| android/.../AlarmHub.kt | setAlarmClock、重启恢复、完成/停用后对账、触发去重 |
| android/.../AlarmService.kt | 前台音频、振动、超时、重响与同时到达队列 |
| android/.../AlarmActivity.kt | 锁屏全屏提醒与处理按钮 |
| android/.../AlarmPolicy.kt | 七级加深、延后时间及操作身份校验 |
| android/.../TodoNotification.kt | 本机常驻待办、静默通知、跨日汇总刷新 |
| android/.../MainActivity.kt | Flutter 通道、本地存储与系统文件选择 |

数据保存与调度登记依次执行；nativeRules 为派生数据。原生锁屏上的停用操作产生 nativeGeneration 与 outbox，Flutter 恢复时读取原生修改，避免旧页面重新启用该闹钟。系统 SharedPreferences 提供持久化写入，当前预览版保存完整 JSON；大量历史数据时可替换 LocalRepository 为数据库。

跨端同步接口和字段映射见 [../contracts/mobile-v1.md](../contracts/mobile-v1.md)。本版尚未连接真实同步服务，也不包含桌面安装包。

## 构建

已验证工具：Flutter 3.24.5 / Dart 3.5.4、JDK 17、Android SDK 35、AGP 8.5.2、Kotlin 1.9.24、Gradle 8.9。

使用 PowerShell 7 执行 `./build-android.ps1`。可通过 FlutterRoot / AndroidSdk / JavaRoot / GradleRoot / GradleCache 参数指定工具路径。

Windows 上此版本 Flutter 的 AOT 工具无法可靠处理中文绝对路径；脚本保留原源码，将构建复制到新的英文临时目录。BuildDirectory 可显式指定，必须是尚不存在的英文路径。脚本执行 release 构建、Kotlin 单元测试和 Android lint，再复制 APK 与 SHA256 到 `../installers/<pubspec版本>/`。版本从 pubspec.yaml 读取，已有同版本安装包则拒绝覆盖；先提升版本再交付。构建目录保留报告，不执行自动递归清理。

在源码目录可运行 `flutter analyze` 和 `flutter test`。`flutter test --dart-define=SCREENSHOTS=true` 额外保存三套真实 Widget 渲染截图；Windows 若有微软雅黑，会用于截图字体，其他环境可跳过字体加载。

原生测试使用 JUnit 4 与 Robolectric 4.16.1（仅测试依赖），Android 9/15 上推进虚拟时钟验证实际 AlarmHub、PendingIntent 和 AlarmService 操作链路；测试不代表厂商真机后台行为或扬声器输出已验收。首次运行需要从 Maven Central 下载测试依赖与 Android framework 测试镜像。

本包使用 Android 调试证书签名，Dart 按 release 优化，供个人试用。正式发布需配置自己的签名、发布渠道及对应权限审核。
