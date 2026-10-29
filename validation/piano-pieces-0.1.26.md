# 独立钢琴曲库与乐谱时值验证

日期：2026-10-22（北京时间）。版本：0.1.26+27。

## 自动化检查

命令：`flutter test test/data/content_test.dart test/data/piano_piece_test.dart test/widgets/piano_pieces_page_test.dart test/widgets/layout_test.dart --reporter expanded`。最终 39 项全部通过，日志 piano-pieces-tests-0.1.26.log。

- 短旋律目录恢复原三个原创八音条目及原哈希；独立曲目目录载入《欢乐颂》，30 音、32 拍、8 个完整小节。
- 验证四分、附点四分、八分与二分时值，修改哈希、越界琴键、非法时值或不完整小节均拒绝载入。
- 40、50、60、70、80 BPM 的每个音符起止边界、完整示范及全曲按住判定通过；每音短 1 微秒不前进，按满对应时值后前进。累计整数 tick 换算微秒，无逐音取整累积误差。
- 示范暂停冻结当前音与进度，恢复后播放剩余部分；暂停中的用户按住、错误键、取消触摸不冒充完成。
- 实际页面触摸手势覆盖 400 ms 短按重试，以及 1、1.5、0.5、2 拍提示切换。声音平台替身记录全部 30 次发声与停音，确认附点音 1500 ms、八分音 500 ms、二分音 2000 ms，后台中断后不继续请求发声，页面移除停音。
- 首页独立入口、曲目列表、演奏页，中英文、360×640／800×360、正常／双倍字号布局通过。短旋律列表不再出现《欢乐颂》。旧版记录重弹进入独立曲目页，不改写原历史或切换成第一首原创短句。
- 原首页、设置和结果页 8 项布局回归通过。

本轮发现并修复共用控件的 Flutter 断言：导航 tab 显式语义点击、QinPanel／ModePicker 的透明 Material，以及音量 Slider 的外框居中布局。保存初轮错误日志 existing-layout-check-0.1.26.log，最终回归通过，不将初轮失败当作通过。

`flutter analyze --no-pub` 通过，无问题；日志 piano-pieces-analyze-0.1.26.log。`flutter build apk --release` 通过，最终 Gradle 29.8 秒；日志 piano-pieces-build-0.1.26.log。

## 构建与设备检查

release APK 约 54.5 MB，复制至 releases/琴伴-0.1.26-internal.apk，复制件与构建件 SHA-256 一致。`adb -s emulator-5554 install -r` 成功，包信息确认 versionName=0.1.26、versionCode=27。哈希与包体字节数见 releases/build-report-0.1.26.json。

模拟器检查：

1. 首页“钢琴曲目”进入独立列表，再选《欢乐颂》进入演奏页。
2. 开始示范约 12.5 秒后切至桌面再返回，保持暂停在第 4 小节、第 13 音；显示 1.5、0.5、2 拍及附点四分音符，未自动恢复。
3. 结束示范后开始弹奏，实际长按 3 号键约 1100 ms，第一四分音符完成，推进到第 2 音。
4. 第 2 音短按约 200 ms，提示时值不足，保留第 2 音。结束后停留在准备页面，供用户试用。

以上独立曲目演奏未创建原训练模式的会话记录，未卸载、清数据、修改旧记录或向真机安装。

已打开并查看截图，无裁切或重叠：

- screenshots/piano-pieces-0.1.26/01-home.png
- screenshots/piano-pieces-0.1.26/02-library.png
- screenshots/piano-pieces-0.1.26/03-ready.png
- screenshots/piano-pieces-0.1.26/04-durations-paused.png

## 范围

当前曲目是主题前两句，共 8 小节，保留节奏但移调为 C 大调五键版本。示范按固定乐谱时间轴播放；跟随弹奏由用户逐音起奏，按对应时值前进，没有新增固定拍点起音误差评分或训练历史。

未进行独立声学录音测量、真机输入延迟、完整旧模式矩阵或 M1 停帧专项；这些不包含在本轮通过范围中。乐谱来源与实现边界见 ../../设计修订/2026-10-22-独立钢琴曲库与乐谱时值.md。
