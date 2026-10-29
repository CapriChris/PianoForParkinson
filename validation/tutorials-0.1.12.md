# 琴伴 0.1.12 · 教学与全模式声音中断验证

日期：2026-10-17（北京时间）。范围：用户六项修订，版本 0.1.12+13。

## 自动化结果

| 验证 | 结果与范围 |
|---|---|
| 静态分析 | `flutter analyze` 无问题 |
| 全套单元／内容／界面 | 412 个唯一用例通过，包括教学随机参数、示范时值、连续进度、入口隐藏、语音入口、布局与六种模式回归 |
| Android 教学流程 | 1 项：三课三页、完成标记、重启恢复、清除重置、完成后隐藏教学链接；同一流程归档 10 张截图 |
| Android 全模式中断 | 1 项内覆盖六种任务 × 焦点丢失／后台两种中断，共 12 个组合；真实 SQLite 与 SoundPool |
| Android 原生后台 | 1 项：由宿主发送 HOME、再恢复独立测试应用；真实 Android onPause／onResume |
| release | 构建、APK 元数据、模拟器安装与冷启动通过 |

三个 Android 用例按唯一用例统计，不把每个内部断言或重复运行算成新用例。全部使用独立测试包 `com.pianoforparkinson.piano_practice.validation` 和随机 no-backup 数据目录，测试结束清理对应目录；没有清空正常应用记录。

## 本轮关键断言

- T1 随机生成三键之一，100 个固定种子验证短按在 100～200 ms 内、按满为 400 ms、第三页两次为同一随机键；短按时值条停在 25%～50%，按满条到 100%。示范可见琴键高亮，用户输入仍锁定。
- T3 第一页没有琴键，实际示范请求只含 4 个节拍器音；第二页 4 个节拍音＋4 个钢琴音；第三页保留交替等待。进度跟随单调时钟，四拍完整走完才到 100%，自然结束保留满进度。
- 三课完成后六种正式练习说明中的教学链接即时隐藏；重新读取和重新初始化控制器后仍隐藏，首页仍可重看。清除记录后恢复未完成状态。
- 去掉教学右上叉号和列表跳过按钮。语音图标位于对应说明首字左侧，点击朗读对应文字；“试按琴键”不再发起语音。退出与翻页保持可用。
- 六种任务在正式响应阶段发生中断时暂停，不生成有效零分；停止后原生 `active_voice_count=0`，中断记录成功落库，回前台后仍暂停。
- 首次引导、试按弹层、G3 试玩和教学的持有键状态能清除；回前台不会自动发声。异步声音迟到返回也会停止，后台不发起新的试按／语音。
- 原生后台测试先确认有真实 SoundPool voice，再由 HOME 切后台，确认 voice 数归零；直接绕过 Dart 的后台 playNote／speakLocal 请求均返回 `E_AUDIO_BACKGROUND`。恢复前台后 voice 数保持零。

教学截图使用注入时钟固定画面；全模式中断用例注入 Dart 焦点事件／生命周期，并使用真实音频后端和数据库。原生后台用例执行真实 HOME／恢复流程。焦点抢占没有在实体手机上用外部来电／音乐应用验证，不声称已完成该设备矩阵或声学延迟测量。

## 截图与日志

人工查看教学列表、T1 短按／按满／连按、T3 三页和完成后的练习说明：语音图标、时值条和全程进度可读，无控件互相覆盖。内容超出竖屏可滚动；12 组教学布局矩阵覆盖 360×640、800×1280、800×360 dp，中英文、1／2 倍字号。

- [短按](../screenshots/qinban-0.1.12-T1-page-1.png)、[按满](../screenshots/qinban-0.1.12-T1-page-2.png)、[示范按下中的高亮](../screenshots/qinban-0.1.12-T1-held.png)
- [纯节拍器](../screenshots/qinban-0.1.12-T3-page-1.png)、[四拍弹奏](../screenshots/qinban-0.1.12-T3-page-2.png)、[弹奏与等待](../screenshots/qinban-0.1.12-T3-page-3.png)
- [完成教学后的练习说明](../screenshots/qinban-0.1.12-instruction-complete.png)
- [静态分析](tutorials-0.1.12-analyze.log)、[全套测试](tutorials-0.1.12-all-tests.log)、[试按专项](tutorials-0.1.12-preview-tests.log)
- [教学 Android 与截图](tutorials-0.1.12-lessons-android.log)、[全模式 Android 中断](tutorials-0.1.12-audio-android.log)、[真实 Android 后台](tutorials-0.1.12-native-background.log)
- [release 构建](tutorials-0.1.12-release-build.log)、[APK 元数据](tutorials-0.1.12-apk-metadata.log)、[安装信息](tutorials-0.1.12-installed.log)、[内容／参数哈希](tutorials-0.1.12-assets.json)

安装包大小、SHA-256 与工具链见 [构建报告](../build-report.json)。沿用开发签名，仅供内部体验；本轮没有进行新版实体手机验收。

## 复现

启用项目开发环境后，在 app 目录执行：

```powershell
flutter analyze
flutter test
flutter test integration_test/audio_interruption_test.dart -d emulator-5554 --dart-define=ISOLATED_TEST_PACKAGE=true
flutter drive --driver=test_driver/lessons_screenshots.dart --target=integration_test/intro_lessons_test.dart --dart-define=ISOLATED_TEST_PACKAGE=true --dart-define=CAPTURE_LESSONS=true -d emulator-5554
.\tools\test_native_background.ps1
flutter build apk --release
```

原生后台测试需配合脚本，由脚本在独立测试包就绪后执行 HOME 并恢复；直接单独运行该测试会等待宿主操作。脚本不改变手机系统设置，不操作正常包中的记录。
