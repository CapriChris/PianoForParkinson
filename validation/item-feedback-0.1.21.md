# 琴伴 0.1.21 记录反馈与项号验证

日期：2026-10-20，北京时间。版本：0.1.21+22。

## 问题与改动

用户确认旋律记忆仍有重复完成提示，并要求排查其他模式项号时机。复盘发现上一版仅修复两个局部反馈分支，未覆盖收尾、组末、G3／双区及提前打开的节奏响应窗口。

本版让七种模式共用只读项号投影与计数文字组件。旋律记忆尾部观察不提前报已记录；单项／组末使用单一记录面板，组末保留下一组按钮。G2／G3／双区间隔显示刚记录的项号；S2／M1 随可见拍点更新；S1 按住时不再落入记录提示。G3 原有规则标题在记录间隔继续保留。

具体阶段说明见 [设计修订](../../设计修订/2026-10-20-全模式记录反馈与项号时机修复.md)。

## 针对性回归

| 测试文件 | 唯一用例数 | 覆盖 |
| --- | --- | --- |
| `test/domain/item_number_regression_test.dart` | 14 | 七模式两组阶段编号、记录及普通暂停恢复、只读访问不修改事件／试次／结果、旧时值策略 |
| `test/domain/phrase_finish_test.dart` | 36 | 末拍与暂停、两组封存结果不变、快照冻结、当前项号；节奏用例明确区分提前窗口和真正拍点 |
| `test/widgets/item_feedback_regression_test.dart` | 16 | 中英文实际 TrainingPage：G1 收尾／单项／组末、G2／G3／双区间隔及暂停、S2／M1 拍点边界、S1 按住阶段；G3 规则标题保留 |
| 合计 | **66** | 最终选择的三文件全部通过，不重复计算开发中重跑的用例 |

旧反馈实现上，16 个新增界面用例全部失败；修正后相同用例及所选状态回归全部通过。

日志：[修正前复现](item-feedback-before-0.1.21.log)、[修正后最终 66 项](item-feedback-regression-0.1.21.log)。

最终命令：

```powershell
flutter test test/domain/item_number_regression_test.dart test/domain/phrase_finish_test.dart test/widgets/item_feedback_regression_test.dart --reporter expanded
flutter analyze --no-pub
flutter build apk --release
```

测试采用虚拟时钟与平台替身，直接挂载真实训练页面，没有在用户模拟器中创建测试记录。初始尝试复用根导航测试壳时遇到既有导航语义断言，随后将反馈测试限定在训练页独立壳；本报告不将首页导航语义或整 App 流程计为通过。

## 源码边界

对照改动前备份，任务引擎仅修改 currentItemNumber 只读 getter；执行状态机、尾部观察、响应窗口、判分、事件生成和写入保持。其他领域／数据／平台文件保持，领域契约仅更新版本与构建号。见 [源码核对](item-feedback-source-audit-0.1.21.json)。数据库 schema 2、JSON schema 1、参数版本与指标版本不变，旧记录不重算。

## 构建、安装与未验范围

静态分析通过。最终 release 编译和 emulator-5554 覆盖安装、版本确认及 APK 哈希见 [机器可读报告](../../releases/build-report-0.1.21.json) 与 [安装包核对](item-feedback-artifact-0.1.21.json)。安装不卸载或清除数据，代理未在模拟器启动正式训练。

交付：[琴伴-0.1.21-internal.apk](../../releases/琴伴-0.1.21-internal.apk)。

没有运行全测试套件或 Android 集成测试；没有进行实体设备声音／多触点、全窗口／字号／读屏矩阵和 M1 停帧专项。66 项通过只对应上述指定状态与界面用例，不能作为这些范围已验收的证据。
