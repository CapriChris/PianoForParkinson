# 0.1.8 节奏模式专项验证

日期：2026-10-15。本轮遵照用户要求，只运行 S2 节奏练习的测试，不运行其他模式测试。设备为 Medium Phone / emulator-5554 / API 37，沿用此前临时 software GPU 实例。

## 修复

- 演示前增加四拍“演示预备拍”，第四拍后的下一拍开始演示。重看演示也包含这四拍；普通继续保持原阶段。
- 演示和用户弹奏的整句进度统一使用同一 `rhythmPulse / 8`，和音符高亮、摆锤保持同一拍点。首拍之前进度为 0，每拍推进八分之一，修复正式进度从首拍前就开始且分母过短的问题。
- 暂停冻结进度与原点，45／50／55 BPM 的整数微秒边界保持同步；匹配窗口、按住时值及计分规则未改。
- 仅 S2 任务配置升至 task_version=2.1.1，并添加 demo_lead_in_beats=4。与 0.1.7 APK 的配置逐项比较，其他任务配置、全局参数版本和指标版本一致，保留原难度记录。数据库仍为 schema 1，旧封存成绩不改写。

## 检查结果

`flutter analyze` 无问题。23 项 S2 单元／界面用例通过，其中领域 15、页面 8；包含四种速度、演示前四拍顺序与准确边界、演示和正式进度逐点相等、首拍前为零、暂停、重播、中英和双倍字号。日志：[rhythm-sync-0.1.8-unit.log](rhythm-sync-0.1.8-unit.log)。使用 `--name S2` 筛选指定文件，没有运行其中其他模式的测试。

初次边界测试把第一个被观察到的 demo tick 当作计划起点，在 45／55 BPM 时会包含轮询迟到量；改为精确推进到预备拍的计划结束边界后，严格的逐拍边界断言通过，未放宽时间容差或计时保护。

3 项 Android S2 集成用例串行通过：已提交首组恢复并排除开放窗口；完整两组、16 个成绩、暂停继续、SQLite／结果／趋势；MonotonicClock＋SoundPool 实际按住、节拍请求、全屏、暂停与返回保存。日志：[rhythm-sync-0.1.8-integration.log](rhythm-sync-0.1.8-integration.log)。随机隔离测试数据库运行后清理，未把失败运行重复累计。

## 发布包实测

0.1.8+9 release 构建、安装及启动通过；versionCode=9，minSdk=24，targetSdk=36，无 INTERNET 权限。开发签名，内部演示。引导仅作为进入节奏练习前的必要设置流程；没有进入其他练习模式。

已实际查看截图：

- [演示预备拍](../screenshots/release-0.1.8-demo-prep.png)：明确的演示预备拍、拍点、摆锤，整句进度仍为零。
- [演示进度](../screenshots/release-0.1.8-demo-progress.png)：当前高亮音符、琴键及整句进度正常。
- [正式弹奏前段](../screenshots/release-0.1.8-playing-progress-1.png)与[后续拍点](../screenshots/release-0.1.8-playing-progress-2.png)：进度落在对应高亮音符区段，随计划拍点推进，没有首拍提前填充。

视觉检查后从左上角确认退出，本轮唯一的节奏部分记录在历史中可读，随后单条删除；空历史证据为 release-0.1.8-history-clean.xml。未使用清除全部记录。临时 sdcard 截图／XML 已清理。`release-0.1.8-ui.log` 按 AndroidRuntime:E／flutter:E 过滤，为零行。这些证据不代替实体手机音频输出延迟、最低 API 24 或默认 GPU 验证。

APK：`releases/piano-practice-0.1.8-internal.apk`，55,561,315 字节；SHA-256：`c2d22593e9a0638b0478967a03019b33e4faec89bdbd8c316384c211e6ea370c`。构建报告归档至 releases/build-report-0.1.8.json，旧包与旧报告保留。

规则说明见 [设计修订](../../设计修订/2026-10-15-节奏演示预备拍与进度同步.md)。
