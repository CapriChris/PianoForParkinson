# 计划、通知及按压反馈验证（2026-11-01）

## 实现

- 计划开关写入期间不再短暂禁用整页按钮；写入互斥继续保留。
- 开始练习/已完成区域拦截自身点击及长按，避免冒泡到卡片编辑、多选；已完成保留正常颜色和描边。
- 时间滚轮整体居中。计划类型用统一圆角/配色的单选底部卡片，所有表单行使用相同标签列宽。保存入口统一为右上角完成。
- 自定义星期在完成时归并到每天、工作日、周末；普通自定义仍保留。
- AppBar 标题统一居中；返回键加入统一反馈。设置页插画为文字下方背景，contain 显示完整图片。
- 新增 QinPress 及按钮、卡片和列表项包装器：约 75ms 轻微缩小下压、95ms 回弹后执行动作；禁用控件不执行；嵌套控件只由最内层拥有反馈；系统减少动态效果时立即执行。交互反馈独立于应用装饰动画开关。
- 通知新增 POST_NOTIFICATIONS、SCHEDULE_EXACT_ALARM，首次启用请求授权；高优先级训练提醒频道 training_plans_v2。精确定时获准时使用 exactAllowWhileIdle，否则使用允许待机的近似调度。通知 ID 按计划日期稳定生成，修改/禁用/删除时取消旧安排，刷新不清空已显示通知。
- 保存计划即同步提醒；钢琴及舞蹈训练保存成功后异步同步，通知失败不影响训练记录保存。
- 修复 Android 返回 GMT 时 timezone 库无法识别的问题；支持 UTC/GMT 及固定偏移 GMT±HH:mm。区域时区继续采用 IANA 数据。
- 未来30天的安排在保存计划、应用恢复和计划页读取时更新；关机、系统强行停止、省电、权限和勿扰设置仍受 Android 管理。横幅由通知频道及手机设置控制。

## 验证

1. flutter analyze --no-pub：通过。
2. 42 项相关测试通过：计划/分类、通知时区和权限、稳定通知ID及取消、自动进度、按压先于动作、减少动态效果、按钮点击/长按隔离、自定义星期归并、舞蹈播放流程等。
3. Android debug 构建通过。
4. integration_test/plan_notification_test.dart 在 emulator-5554 独立 dance_flow_test 包实际定时：登记提醒后等待手机时间到达，通过 Android getActiveNotifications 确认收到指定 App 通知及正文。最终运行约31秒，通过。
5. 测试包独立数据目录，测试数据库及通知已清理；Flutter driver 仅卸载测试包。测试后确认原主包及 validation 包仍安装。没有创建新的模拟器。
6. 归档日志：build/plan-motion-all-tests.log、build/plan-native-build.log、build/plan-notification-native-build.log、build/plan-notification-native-test.log。
7. 测试 APK 保存在 build/plan-notification-qa.apk，仅供测试。已清理与该测试包匹配的默认调试输出和元数据，避免后续 Flutter 运行读取过期测试身份。此 APK 不作为用户安装包发布。

系统权限变更需重新构建安装；Hot Reload/Hot Restart 无法更新 AndroidManifest。
