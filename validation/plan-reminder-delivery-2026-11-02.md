# 训练提醒投递修复（2026-11-02）

## 发现

- 当前 emulator-5554 主应用已有 POST_NOTIFICATIONS，训练频道 importance=4，但 SCHEDULE_EXACT_ALARM 未授权。系统中已登记的提醒 window=1h，代码此前静默降级到 inexactAllowWhileIdle，无法按用户选择的分钟准时触发。
- 刷新会将“时间已到但系统尚未投递”的提醒从 desired 排除并取消，导致非精确提醒永久丢失。
- 模拟器系统时区为 GMT，较北京时间慢8小时；应用按设备本地时间调度。未修改模拟器的时间或时区。

## 修改

- 计划页及编辑页显示真实权限状态：应用通知未开启、频道横幅未开启、准时提醒未开启。提供对应操作按钮。
- 保存计划及读取状态不打开特殊权限设置；仅用户点击“开启准时提醒”后请求精确定时权限。已授权会先检查并直接返回。
- 从设置返回后重新读取权限并同步提醒，将未来提醒升级为 exactAllowWhileIdle。
- 各品牌Android共用标准适配：Android13及以上处理通知运行时授权，Android12及以上检查精确定时特殊权限；较早系统由插件按系统能力处理。通知渠道通过系统API读取，不假设所有设备都有相同的设置菜单。不会自动开启或绕过系统权限。
- 保留到期后一小时内、系统仍在等待投递的有效提醒，包括跨午夜；启用状态、完成进度及修改后的时间仍会参与校验。新 payload 包含调度时间，避免保留修改前的旧提醒。
- 本次不改 AndroidManifest。用户确认通过 APK 使用后，版本更新为0.1.55+56，提供各品牌Android手机使用的通用包；测试 APK 不发布给用户。

## 验证

- flutter analyze --no-pub 通过。
- 通知及计划界面25项测试通过，含权限入口仅显式触发、已授权不重定向、到期后刷新不取消、跨午夜、编辑及禁用时取消旧提醒。
- 独立 dance_flow_test 包 debug 构建通过。原主包及 validation 包不卸载、不清除数据；权限测试只操作测试包。
- Android 集成测试先登记非精确提醒，检测到缺少权限后由测试主机仅授权测试包，再同步为精确提醒，保持原通知ID。系统 dumpsys alarm 确认 window=0、exactAllowReason=permission。
- 测试主机将测试应用退到后台后，等待真实系统通知投递，通过 getActiveNotifications 校验通知ID及正文；集成测试通过（约83秒）。
- 测试后确认原主包及 validation 包仍安装，测试包已由 driver 卸载。只清理与测试APK哈希及测试包元数据匹配的默认调试产物，避免后续运行误读测试包身份；归档 build/reminder-fix-qa.apk 仅供验证。
- 日志：build/reminder-fix-tests.log、build/reminder-fix-analyze.log、build/reminder-fix-native-build.log、build/reminder-fix-native-alarms.log、build/reminder-fix-native-test.log。

## 使用

开发环境请 Hot Restart，进入计划页，点击“开启准时提醒”并在系统中允许“闹钟和提醒”，返回应用后自动重新安排。通知本身和训练提醒频道也须允许显示。测试时选择晚于当前设备时间的时间，并确保计划当日生效且未完成。

用户确认故障发生在 vivo X100s、Android16、通过APK安装。上述 GMT 设置仅属于当前电脑模拟器，不能认定为用户真机的故障原因。模拟器后台投递验证通过不代表用户手机已经验证通过。代码使用Android标准API，没有加入厂商专用逻辑或硬编码设置路径；不同品牌均采用同一权限检查、渠道检查、精确定时和待机调度流程。安装更新包后需重新打开一次应用以同步提醒，代码热重载不能更新独立安装的旧APK。

Android 非精确闹钟可能在预定时间后一小时内投递（省电限制下还可能更晚），依据：https://developer.android.com/develop/background-work/services/alarms 。因此普通通知权限不能代替精确定时权限。

## 发布包

- 版本0.1.55+56，通用Release包：`../releases/琴伴-0.1.55-通知修复-通用-isolated.apk`，658860058字节（约628.3MiB）。
- 应用ID沿用此前预览包的 `com.pianoforparkinson.piano_practice.validation`，签名证书SHA256与0.1.54预览包一致，可覆盖该预览版本，不卸载旧应用。
- APK SHA256：`73EC9AB0A09F1B7296D72F4DFFB87EF2D8981627261CEB1F14A98C82F9A01F7B`。
- 首次从集成测试切换到Release并使用 `--no-pub` 时，生成的插件注册文件残留测试插件导致编译失败；正常执行包含pub阶段的主入口Release构建后自动重新生成，构建成功。未手改生成文件或插件缓存。
