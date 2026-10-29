# 琴伴 0.1.16 构建记录

日期：2026-10-18（北京时间）。版本：0.1.16+17。

## 完成内容

趋势页新增“切换指标”，按所选条件的任务提供对应选择。主要正确率保留，新增各任务已有摘要中的无帮助正确率、位置正确率、等待／规则／切换正确率、无帮助首次响应中位数／P95，以及 S2 节拍误差、M1 连续命中间隔／CV、M2 双区时间差。

数据直接读取已封存 BLOCK 摘要，不改变任务／指标版本、比较键或原成绩。比例固定百分比纵轴，用时与 CV 使用自适应纵轴。无值保留组位置、不当成零、不跨缺口连线；CV 至少 10 个间隔，至少 3 组有效值才显示相邻连线。每组列表保留时间、样本数或分子／分母，并可高亮图点。

## 本轮执行范围

沿用上一轮无需测试的要求：没有运行单元、界面、集成、手工或性能测试，没有提供新截图，没有将旧版通过数记成本版通过数。

- `dart format`：完成。
- `flutter analyze`：No issues found，日志 `trend-metrics-0.1.16-analyze.log`。
- `flutter build apk --release`：成功，日志 `trend-metrics-0.1.16-release-build.log`。
- `adb install -r`：当前 emulator-5554 返回 Success；包信息确认 versionName=0.1.16、versionCode=17。日志 `trend-metrics-0.1.16-install.log`。没有启动应用进行流程验收。

## 发布包

- 包名：`com.pianoforparkinson.piano_practice`
- 文件：`releases/琴伴-0.1.16-internal.apk`
- 大小：55,971,499 字节
- SHA-256：`46b2323b24a5628e36015a0fe56970af8f45385953bbede46db8487ece50d3a5`
- SQLite schema：1，无迁移或历史得分重算。

下一任务：本机记录契约补齐与完整性校验。旧版 M1 模拟器停止出帧的问题没有在本轮修改或复测。
