# 琴伴 0.1.11 · 命名与入门教学验证

日期：2026-10-17（北京时间）。范围为名称、T1／T2／T3 教学，以及受影响的首页、设置、语言、声音和控制布局；未重跑全部正式任务判定套件。

## 结果

- `flutter analyze`：无问题。
- 新增教学界面测试 19 项：首页／任务说明入口、可退出与重复学习、失败后重试、三键高低音顺序、按住进度、可选朗读、节拍弹奏与等待、后台及音频焦点中断、400 ms 后示范键明确松开；12 组布局矩阵覆盖三种尺寸、中英文和 1／2 倍字号，每组遍历三课三页。
- 原首页／设置／详情布局 8 项、受影响的声音／语言／交互控制回归 45 项通过。合计 **72 个唯一单元／界面用例**；重复运行不重复计数。
- Android SQLite 教学集成用例 1 项通过；另用截图 driver 重复该流程，仍按 1 个唯一用例统计。
- release APK 构建成功，Android 标签“琴伴”，版本名 0.1.11、版本号 12，包名 `com.pianoforparkinson.piano_practice`，minSdk 24／targetSdk 36；无 INTERNET 权限。
- release 在 API 37 模拟器安装与冷启动成功。未清除正常应用数据；没有单独构造旧版本数据来验证升级保留。
- 与 0.1.10 APK 比较，15 个配置、内容、音频文件逐一 SHA-256 相同，包括 schema.sql；本轮不变更正式任务参数、音源或旧分数。

## Android 流程

设备：`sdk_gphone16k_x86_64`，Android API 37，`emulator-5554`。自动化使用独立包 `com.pianoforparkinson.piano_practice.validation`，每次创建随机 no-backup 数据目录，结束后检查绝对路径边界并删除该测试目录。

从实际首页打开教学，退出未完成课不会产生完成标记；随后三课逐一演示、翻页并完成。数据库只有三条教学完成记录，`sessions`、`events`、`attempts`、`summaries`、`profile_task_state` 均为空。重复完成不重复插入；未知课 ID 拒绝写入。关闭／重开数据库后三课标记仍在；清除全部记录后教学标记清空，语言和设置保持一致。

## 画面检查

截图 driver 运行完整流程并生成截图，已人工查看：首页名称／入口、三课列表和节拍教学可读，没有控件互相遮挡；教学内容超出屏幕时可以滚动。截图流程启用高对比设置；正常主题 release 冷启动另有截图。

- [首页](../screenshots/qinban-0.1.11-home.png)
- [教学列表](../screenshots/qinban-0.1.11-lessons.png)
- [节拍与等待](../screenshots/qinban-0.1.11-beat.png)
- [release 冷启动](../screenshots/qinban-0.1.11-release.png)

## 证据与复现

[静态分析](lessons-0.1.11-analyze.log)、[教学与原布局测试](lessons-0.1.11-widgets.log)、[受影响回归](lessons-0.1.11-regression.log)、[Android 流程](lessons-0.1.11-android.log)、[截图 driver](lessons-0.1.11-screenshots.log)、[release 构建](lessons-0.1.11-release-build.log)、[APK 元数据](lessons-0.1.11-apk-metadata.log)、[安装版本](lessons-0.1.11-installed.log)、[素材哈希对照](lessons-0.1.11-assets.json)。APK 字节数和 SHA-256 见 [构建报告](../build-report.json)。

在启用项目开发环境后，于 app 目录执行：

```powershell
flutter analyze
flutter test test/widgets/intro_lessons_test.dart test/widgets/layout_test.dart
flutter test test/widgets/refinements_test.dart test/widgets/responsive_controls_test.dart
flutter test integration_test/intro_lessons_test.dart -d emulator-5554 --dart-define=ISOLATED_TEST_PACKAGE=true
flutter drive --driver=test_driver/lessons_screenshots.dart --target=integration_test/intro_lessons_test.dart --dart-define=ISOLATED_TEST_PACKAGE=true --dart-define=CAPTURE_LESSONS=true -d emulator-5554
flutter build apk --release
```

本轮未做新版本真机、TalkBack／完整无障碍矩阵或声学延迟测量，不将模拟器结果扩大为患者验收。下一任务为 M2 双区配合，具体设备门槛与验收项见 [设计修订](../../设计修订/2026-10-17-琴伴与入门教学.md)。
