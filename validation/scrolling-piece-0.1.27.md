# 横屏滚动长条曲谱验证

日期：2026-10-22。版本：0.1.27+28。

## 交付

- [安装包](../../releases/琴伴-0.1.27-internal.apk)，57,190,696 字节。
- SHA-256：`5CB5C8550E91A3E4F3802C877B4BAA73239229FC04B55D35D22B232DEF18ACE9`，发布副本与 Flutter 构建产物一致。
- 已在 `emulator-5554` 覆盖安装，系统包信息确认 versionName 0.1.27、versionCode 28。
- [横屏效果](../screenshots/scrolling-piece-0.1.27/performance.png) · [准备页](../screenshots/scrolling-piece-0.1.27/preparation-portrait.png) · [22 秒滚动视频](../screenshots/scrolling-piece-0.1.27/scrolling-demo.mp4)。

## 自动检查

以下 50 项测试通过：[日志](scrolling-piece-tests-0.1.27.log)。

```powershell
flutter test test/data/content_test.dart test/data/piano_piece_test.dart test/domain/scrolling_piece_test.dart test/widgets/piano_pieces_page_test.dart test/widgets/layout_test.dart --reporter expanded
```

覆盖独立目录、曲目时值与示范；五档速度下每个长条前后端与演奏线的时间对应；0.5／1／1.5／2 拍长度比例；预备、漏按仍推进、重复音需重新按、暂停恢复；准备页选择速度、试听与进入前停音；长音到尾停音、后台中断与退出停音；中英文、多窗口、双倍字号、高对比、小横屏与原页面布局回归。长条边界容差 0.001 逻辑像素，允许整数微秒取整误差。

`flutter analyze --no-pub` 无问题：[日志](scrolling-piece-analyze-0.1.27.log)。正常 `flutter build apk --release` 成功：[日志](scrolling-piece-build-0.1.27.log)。未更新依赖版本。

## 安卓模拟器检查

1. 首页 → 钢琴曲目 → 欢乐颂 → 准备页；选择 50 BPM，试听按钮切为停止试听，进入演奏前结束试听。
2. 从竖屏准备页进入后自动变为 2400×1080 横屏；顶部状态栏、标题与速度项隐藏。保留左上返回、左下暂停／继续、曲谱和五键，没有独立时值进度条。
3. 录制 50 BPM 连续滚动 22 秒，四拍视觉预备后按时间轴推进。暂停截图能见八分、二分与四分音符的不同宽度；琴键位置固定。
4. 手动暂停后继续，运行中切后台再返回显示继续图标。两次间隔截屏的曲谱区域 RGB 像素一致，确认暂停冻结；像素差异仅在琴键区域的状态过渡。没有自动继续。
5. 返回准备页恢复竖屏与状态栏，仍为 50 BPM，试听保持停止。用于验证的模拟器方向设置已恢复原先 free 状态。

原生层级证据：[横屏入口](scrolling-piece-rotated.xml)、[返回准备页](scrolling-piece-restored.xml)、[运行中](scrolling-piece-running.xml)、[暂停](scrolling-piece-paused.xml)。层级中的键号／拍数辅助语义供无障碍读取，不是可见说明文字。

## 范围

独立曲目演奏不生成原七种训练的正式成绩，本轮未执行原七种正式训练、清除数据或安装到实体手机。自动检查验证声音调用和时间戳，未作实体设备听感、声学延迟或临床效果验证。原有 M1 停帧与完整设备音频矩阵仍是历史待办。
