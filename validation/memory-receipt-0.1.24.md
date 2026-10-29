# 琴伴 0.1.24 即时连续反馈验证

日期：2026-10-20（北京时间）。版本：0.1.24+25。

## 改动与范围

旋律记忆最后一个音达到时值并松开后，立即显示“已记录”与本项组／项编号；后台继续执行既有 300 毫秒收尾观察。观察结束后沿用同一面板，不经过空白、隐藏或重复完成提示；下一项开始后才更新编号。收尾多按造成等待释放时仍保留同一反馈。

“已记录”表示接收输入，不表示正确或已落库。任务引擎只增加一项只读 getter，执行状态机、窗口、判分与数据层不变。[设计修订](../../设计修订/2026-10-20-旋律记忆即时连续反馈.md) · [源码对照](memory-receipt-source-audit-0.1.24.json)。

## 自动化检查

本轮重新运行 `flutter test test/widgets/item_feedback_regression_test.dart --reporter expanded`，**18 项通过**：

- 中英文最后音仍按住时不报记录，松开后的首帧立即显示一份记录反馈与当前项号。
- 299999 微秒与 300000 微秒边界没有空白；反馈 Element 保持，文字位置和编号不跳动。
- 收尾期间多按并保持到窗口结束，反馈连续；最终仍统计 extra_count=1，full_correct=false。
- 单项、组末、下一项及其余模式项号／反馈回归。

测试挂载实际 TrainingPage，使用虚拟时钟与平台替身，不写入用户模拟器记录。[日志](memory-receipt-regression-0.1.24.log)。

`flutter analyze --no-pub` 通过；`flutter build apk --release` 通过，Gradle 28.7 秒。[分析日志](memory-receipt-analyze-0.1.24.log) · [构建日志](memory-receipt-build-0.1.24.log)。

## 构建安装

安装包与构建输出 SHA-256 相同，使用 `adb install -r` 覆盖安装到 emulator-5554，查询确认版本 0.1.24／25。未卸载、清数据或由代理开始正式练习。包体和哈希见 [构建报告](../../releases/build-report-0.1.24.json)，交付 [琴伴-0.1.24-internal.apk](../../releases/琴伴-0.1.24-internal.apk)。

未进行设备端输入到显示的延迟测量、手工训练、全套测试、Android 集成、音频或 M1 停帧专项；自动化首帧反馈通过不等于这些范围已验收。
