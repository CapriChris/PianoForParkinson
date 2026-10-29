# 琴伴 0.1.22 收尾文字与节拍器修复验证

日期：2026-10-20（北京时间）。版本：0.1.22+23。

## 改动

旋律记忆删除尾部观察阶段的收尾文字，保留标题高度与当前项号，判定结束后显示单一“已记录”。教学节拍器原先杆端与圆点独立横向平移，杆长和圆点相对位置随摆动改变；现在二者以固定支点、固定杆长共同旋转。正式节奏使用相同绘制器同步修复，原时钟与相位保留。

详见 [设计修订](../../设计修订/2026-10-20-旋律记忆收尾文字与节拍器摆杆修复.md) 和 [改动前备份核对](pendulum-source-audit-0.1.22.json)。

## 针对性验证

| 测试文件 | 唯一用例 | 覆盖 |
| --- | --- | --- |
| `test/widgets/metronome_pendulum_test.dart` | 4 | 两种尺寸的固定杆长、圆点共线与边界；绘制重建条件；教学左右摆动、拍边界连续、拍点／进度、减少动画及静止状态 |
| `test/widgets/item_feedback_regression_test.dart` | 16 | 中英文 G1 无收尾文字、记录时机／唯一提示／项号，其他六模式项号与反馈回归 |
| `test/domain/lesson_demo_test.dart` | 2 | 教学示范键序、按键时值与四拍时长 |
| `test/domain/item_number_regression_test.dart` | 14 | 七模式阶段项号与只读投影 |
| `test/domain/phrase_finish_test.dart` | 36 | 末拍、暂停、结果封存与项号 |
| 合计 | **72** | 本轮重新运行全部通过；其中 55 个普通测试、17 个界面测试 |

命令：

```powershell
flutter test test/widgets/metronome_pendulum_test.dart test/widgets/item_feedback_regression_test.dart test/domain/lesson_demo_test.dart test/domain/item_number_regression_test.dart test/domain/phrase_finish_test.dart --reporter expanded
flutter analyze --no-pub
flutter build apk --release
```

[测试日志](pendulum-regression-0.1.22.log)、[静态分析](pendulum-analyze-0.1.22.log)、[release 构建](pendulum-build-0.1.22.log) 均通过。测试使用虚拟时钟和隔离平台替身，没有写入用户记录。

## 构建与安装

0.1.22+23 release 构建通过，Gradle 29.6 秒。安装包与输出 SHA-256 一致，已使用 `adb install -r` 覆盖安装到 emulator-5554，查询安装版本确认 0.1.22／23。没有卸载、清数据或由代理开始正式练习。

[安装包](../../releases/琴伴-0.1.22-internal.apk) · [构建报告](../../releases/build-report-0.1.22.json) · [包体与安装核对](pendulum-artifact-0.1.22.json)。

本轮未进行设备上的动画／音频手工复核、全 App 导航、全套测试、Android 集成、字号／读屏矩阵或 M1 停帧专项。已确认的是源码几何缺陷及上述自动化检查，不把未指定的设备异常均计为已复现。
