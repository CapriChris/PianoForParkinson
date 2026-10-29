# 曲目完成记录与五线谱验证

日期：2026-10-22。版本：0.1.29+30。

## 安装包

- [琴伴 0.1.29](../../releases/琴伴-0.1.29-internal.apk)：57,157,888 字节。
- SHA-256：`E60BCB6A77ADCF7949D709075FFA8C61FB6D7DB3DAB26C01150205275C015150`。
- release 构建成功：[日志](piece-record-build-0.1.29.log)。确认 applicationId 为 `com.pianoforparkinson.piano_practice`，versionName 0.1.29、versionCode 30。
- 静态分析无问题：[日志](piece-record-analyze-0.1.29.log)。

## 本次相关检查

58 项单元／界面检查通过：[日志](piece-record-tests-0.1.29.log)。包括四拍试听准备且预备时无声音／亮键、滑块读数在左、双语与双倍字号、目录作者文案、C4–G4 的五线谱位置、长条前后端时值、匹配不重复计数、完成跳转、保存失败与同一 ID 重试、历史回看不重复保存及原布局回归。

安卓 SQLite 专项 1 项通过：[日志](piece-record-android-0.1.29.log)。独立临时数据库验证 v2→v3、旧记录与设置不变、24 条曲目记录各保存两次仍为 24 条、混合 25 条历史在时间戳相同情况下分页无重复／遗漏、进程重新打开可读取、冲突拒绝、篡改标记和删除。完整性检查包含曲目表。

扩大运行全部单元／界面测试，结果为 **492 通过、48 失败**：[日志](piece-record-full-tests-0.1.29.log)。失败涉及原认知、节奏、教学等页面的暂停文字、布局与旧断言。本轮未修改这些训练页面来消除失败，不能宣称全套回归通过。相关 58 项最终重新运行通过。

## 设备画面

- [目录](../screenshots/piece-record-0.1.29/library.png)：歌名下仅作者，无辅助句或选择速度文字。
- [最终 release 试听画面](../screenshots/piece-record-0.1.29/preview.png)、[12 秒试听演示](../screenshots/piece-record-0.1.29/preview-demo.mp4)：读数位于滑块左侧，四拍预备后开始；五线谱的 C4 下加线及 E4 底线等音高位置正确，谱号限制在左侧区域。
- [完成页](../screenshots/piece-record-0.1.29/completion.png)、[历史页](../screenshots/piece-record-0.1.29/history.png)：独立 validation 包中实际跑完 80 拍/分钟曲目后自动进入完成页，显示已保存；返回记录可打开同一条详情。该流转检查没有按键，截图的 0/30 为真实测试结果。
- 完成页及历史数据检查使用独立测试应用和临时库，未向日常曲目记录表插入演奏测试数据；实体手机未安装或改动。视频为屏幕画面，不作为声学延迟验证。

## 测试工具意外与恢复

尽管测试 APK 使用 `.validation` 包标识，Flutter 集成测试退出时仍误移除了模拟器中的原应用。重新安装后发现原应用首次安装时间变为 15:01，日常本地数据库为空。这是本轮操作造成的意外，不能声称模拟器全部原数据保持。

恢复过程只读取原 AVD 的快照并在工作区复制的 AVD 磁盘中操作。旧 RAM 快照与当前渲染器／模拟器特性不兼容，因此在复制磁盘上应用 `default_boot` 的内部磁盘快照后启动第二台模拟器，从其中导出旧 SQLite 与 WAL，生成独立备份。

从 **2026-10-20 19:18 快照**恢复 **53 条原训练记录**。覆盖前备份并验证当前数据库的训练及曲目记录均为空；恢复后启动新版完成 schema 2→3，再导出核对：53 条均存在，profiles、sessions、blocks、trials、attempts、events、summaries、adaptive_decisions、profile_task_state、tutorial_progress 共 10 张旧表与快照备份逐行一致，quick_check 和外键检查通过。见 [恢复报告](piece-recovered-records/recovery-report.json) 与 [独立数据库备份](piece-recovered-records/recovered-practice.db)。

**10 月 20 日快照之后新增的数据未恢复。**没有从实体手机读取或修改数据。原 AVD 快照未回退，恢复副本保留在工作区供进一步排查；临时第二模拟器已关闭，其临时 AVD 注册项已移除。主模拟器已恢复 free 方向设置并重新安装 release 包。

后续设备专项使用 [检查脚本](../../环境配置/验证曲目记录.ps1)：先构建并核对隔离包，再显式传入 `--no-uninstall`，禁止 Flutter 测试自动卸载。脚本已做 PowerShell 语法检查，本轮未再次执行集成测试以验证该防护，避免继续影响日常应用。
