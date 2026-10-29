# 速度滑块与试听演奏预览验证

日期：2026-10-22。版本：0.1.28+29。

## 交付与构建

- [安装包](../../releases/琴伴-0.1.28-internal.apk)：56,928,512 字节。
- SHA-256：`D0B2D374B11BC39AFF14E4E2B9A736D0057CE4BE19DBB90F71390CE0FACDC968`；发布副本与 Flutter 构建产物一致。
- `flutter analyze --no-pub` 无问题：[日志](piece-preview-analyze-0.1.28.log)。
- `flutter build apk --release` 成功：[日志](piece-preview-build-0.1.28.log)。依赖版本未更新。
- `emulator-5554` 覆盖安装成功，原生包信息确认 versionName 0.1.28、versionCode 29。

## 相关测试

51 项通过：[日志](piece-preview-tests-0.1.28.log)。

```powershell
flutter test test/data/content_test.dart test/data/piano_piece_test.dart test/domain/scrolling_piece_test.dart test/widgets/piano_pieces_page_test.dart test/widgets/layout_test.dart --reporter expanded
```

内容与谱面时值、五档速度边界、原页面布局回归继续通过。本轮增加和调整的检查覆盖：

- 中英文速度单位与无障碍滑块读数；真实点击滑块调整至 40／80。
- 中英文、360×640 竖屏、800×360 横屏、1×／2× 字号下的准备页与试听预览布局。
- 准备页不显示旧曲目说明与操作长句；试听前无预览，试听后出现曲谱和只读五键。
- 音符长条随时钟向左移动，自动亮键与当前音对应；试听中调速从头播放，停止后冻结并熄灭亮键。
- 30 个音的声音开始／结束调用，含附点四分、八分与二分时值；试听完成、后台与退出停止声音。
- 进入正式弹奏前停止试听，继承所选速度；返回恢复方向且不自动试听。正式横屏布局、按键与暂停回归通过。

## 模拟器画面与操作

1. 首页 → 钢琴曲目 → 欢乐颂，显示五档速度滑块和“60 拍/分钟”。已删除用户指定的两段文字。[准备页截图](../screenshots/piece-preview-0.1.28/preparation.png)。
2. 点击试听，按钮下方完整显示滚动长条、演奏线与自动亮键。[试听截图](../screenshots/piece-preview-0.1.28/audition.png)、[16 秒演示](../screenshots/piece-preview-0.1.28/audition-demo.mp4)。视频为屏幕画面录制，不作为声学验证。
3. 试听中拖动滑块至 40，显示“40 拍/分钟”，新速度从第一音开始。[调速截图](../screenshots/piece-preview-0.1.28/tempo-40.png)。
4. 切后台再返回，按钮恢复试听，画面保留且自动亮键熄灭。间隔两次截屏的预览区域 RGB 像素完全一致，确认冻结。[停止截图](../screenshots/piece-preview-0.1.28/stopped.png)。
5. 试听中进入弹奏，仍自动横屏；返回恢复竖屏、保留 40 拍/分钟、试听保持停止。用于验证的模拟器方向设置已恢复 free。

层级证据：[试听中](piece-preview-playing.xml)、[后台返回](piece-preview-stopped.xml)、[进入演奏](piece-preview-entered.xml)、[返回准备页](piece-preview-return.xml)。

## 范围

未向实体手机安装、清除数据或运行原七种正式训练。独立曲目不创建原训练成绩。自动测试验证声音调用与时值，本轮没有实体设备声学／延迟或临床验证。原有完整设备音频矩阵及 M1 停帧专项仍是历史待办。
