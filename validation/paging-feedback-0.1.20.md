# 琴伴 0.1.20 构建记录

日期：2026-10-20，北京时间。版本：0.1.20+21。

## 实现

按用户四项修订固定入门教学翻页位置、统一 G1 单项记录反馈、修正 G1／G2 记录阶段项号，为 6／7 号琴键增加六边形／十字形。细节见 [设计修订](../../设计修订/2026-10-20-教学翻页位置与单项记录反馈.md)。

普通教学固定操作区；T3 第一页不显示琴键但保留相同下部空间。第一页上一页置灰，末页完成教学使用下一页位置。两列时上一页／下一步组成同一行，四列时维持既有顺序。极矮窗口仍可滚动，不声称所有字号和窗口下都能固定无滚动。

G1 的 trialFeedback 与 G2 的 intertrial 使用单独的只读显示分支，显示“已记录”和 completed 对应项号；真正开始下一项时继续使用原 currentItemNumber。整组完成与下一组操作保留。没有更改 TaskEngine、试次推进、计分、时序或数据写入。

## 已执行

- `dart format` 完成。
- `flutter analyze --no-pub` 最终通过：`No issues found!`，2.9 秒。
- `flutter build apk --release` 通过；Gradle 最后用时 34.5 秒。保留锁定依赖，未升级库。
- 对照改动前备份，16 个领域／数据／平台源文件保持一致，领域契约仅更新版本／构建号。见 [源码核对](paging-feedback-source-audit-0.1.20.json)。
- `aapt dump badging` 确认名称“琴伴”，包名 `com.pianoforparkinson.piano_practice`，versionName 0.1.20、versionCode 21、minSdk 24、targetSdk 36。
- emulator-5554 上 `adb install -r` 返回 Success，读取已安装版本为 0.1.20／21。没有卸载或清除数据，也没有由代理启动应用。

## 未执行

沿用此前先不测试的安排，本轮没有运行单元、组件、集成或手工训练回归，没有新增练习记录。未做逐页截图位置测量、多字号／双语／高对比矩阵、七键实际触控、音频中断或 M1 停帧专项。源码与编译通过不代表这些运行场景已经通过。

## 交付

- [琴伴-0.1.20-internal.apk](../../releases/琴伴-0.1.20-internal.apk)：56,761,352 字节。
- SHA-256：`3f7cfd776acc44d5ba24fec46d1d7767fe6e33b61593897a7c353d994516537d`。
- 构建输出与交付副本哈希一致。
- [机器可读报告](../../releases/build-report-0.1.20.json)、[安装包核对](paging-feedback-artifact-0.1.20.json)。

旧安装包、构建记录和源码备份继续保留。本次没有把此前版本的手工或测试结果复用为本版结论。
