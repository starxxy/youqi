# Android 0.1.0 数据与扩展接口

手机先离线工作。当前没有远程地址、账号登录、真实跨端数据传输或冲突合并；界面明确显示“尚未连接同步服务”。

## 已实现的边界

- `mobile/lib/core.dart`：`LocalRepository.load/write` 与 `SyncTransport.pull/push/resolve`。Android 存储适配器通过 `cn.youqi/native` 通道保存 JSON，测试使用内存适配器。以后可替换为数据库和同步传输适配器。
- `mobile/lib/skins.dart`：`SkinProvider.ids/resolve` 返回 `SkinTokens`，通过 `YouqiApp(skinProvider: ...)` 注入。颜色、玻璃模糊与业务计算分开。
- Android `AlarmHub.reconcile`：由派生规则重新计算平台闹钟；远端变更应用成功后也需调用这一流程。Windows / macOS 各自实现调度器。

## 手机持久化格式

顶层 `schemaVersion: 1`、`deviceId`、`tasks`、`occurrences`、`blocks`、`alarms`、`shifts`、`outbox`、`conflicts`、`cursor`、`appearance`、`deviceMode`。

| 手机字段 | 含义 / 对应目标契约 |
| --- | --- |
| task.id | TaskTemplate.id，跨设备稳定 |
| task.startDate / dueDate / estimate | 开始日期、默认截止日期、预计自然日；开始当天算第 1 天 |
| task.repeat | none / daily / weekly / interval；分别映射 Recurrence |
| task.interval / weekdays | 间隔天数 / 周一=1 到周日=7 |
| task.scheduleStart / scheduleEnd / reminders | 默认时间与相对提醒模板；实例时间可以覆盖 |
| occurrence.id | `任务ID@发生日期`；持续任务固定使用开始日期 |
| occurrence.taskId / date | TaskOccurrence.templateId / localDate |
| occurrence.done / completedAt | 实例独立完成状态，重复任务的其他日期不受影响 |
| occurrence.dueDate / originalDueDate | 当前与最初截止日期 |
| occurrence.deadlineRevisionCount / history | 改期次数与完整历史；历史同时生成 deadlineChange 变更 |
| block.id | `实例ID@规划日期`；同一任务可安排到不同日期，每日一个独立时间段 |
| block.start / end / date | 本地时间；end 早于 start 表示次日结束 |
| reminder.anchor / offset | start/end 锚点，负数提前、正数延后；每条提醒独立 ring 配置 |
| alarm.type | once / daily / weekly / interval / window |
| shift.startDate / days / exceptions | 第 1 天日期、每一天的 times 数组、按日期覆盖；空数组表示休息 |
| deviceMode | 本机 ring / notify / silent，后续映射 TargetingPolicy.perDevice |

实体写入时带 `schemaVersion`、`createdAt`、`updatedAt`、`updatedByDeviceId`、`revision`。本地新增 `revision: null`，接入服务后改为服务端签发的不可解释修订号。删除保留 `deletedAt`，不立即物理删除。

`appearance`、`focus`、`nativeGeneration`、`nativeOverrides`、派生的 `nativeRules` 和原生响铃记录属于本机状态，不作为任务实体直接跨端同步。`deviceId` 在导入备份时保留当前设备身份。

Android 0.2.0 继续使用 schemaVersion 1，新增的运行时 cycleId / snoozeCount 与 oneShots 延后记录也仅留在本机，不进入实体 outbox。未来桌面应同步任务/闹钟规则及各端响铃策略，不直接复制手机正在进行的响铃或贪睡倒计时，避免多个设备重复执行。

## 变更队列与未来服务

每条 outbox 记录包含 `mutationId`、`entityType`、`entityId`、`baseRevision`、`operation`、`originatingDeviceId`、`payload`。payload 为当次修改的深拷贝，不受后续编辑污染；类型为 task、occurrence、timeBlock、alarm、shift、deadlineChange。

实现同步适配器时：

1. 服务端按账户鉴权并按 mutationId 幂等处理 push，返回 accepted 与 conflicts。仅确认成功的队列项才能移除。
2. pull 返回 changes / nextCursor / hasMore。本地事务应用远端实体和新 cursor 后，再触发调度对账。
3. baseRevision 不匹配时保留冲突双方；调用 resolve 时携带 expectedRemoteRevision，避免解决期间再次覆盖新版本。
4. 删除与编辑、完成与编辑、改期与改期均需明确冲突策略。不能仅靠本机时间戳覆盖另一端。
5. 铃声 URI 只在当前 Android 设备有效。跨端用逻辑 toneId / 素材 ID 映射，不能把 Android URI 直接当作桌面音频路径。
6. 当前调度随设备当地时间；DST 不存在的时间顺延，重复时间采用较早偏移。后续固定 IANA 时区须从模型到各端一起实现。

`NotConnectedTransport` 会明确报“尚未配置同步服务”，不会假装上传成功。账户凭证与远程请求尚未实现，Android 当前也未申请网络权限。

## 后续桌面接入顺序

先确定认证与同步后端、落地上述数据映射和同步引擎，再增加 Windows / macOS 存储及通知适配器。布局可扩展为侧栏与详情栏；同一业务模型、七级逾期和改期历史继续复用。各端独立设置响铃策略，避免所有设备同时响铃。
