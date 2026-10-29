# 曲谱核对与八度标记验证

日期：2026-10-25。版本：0.1.34+35。

六首曲目的参考依据和修正详见 [核对说明](../../设计修订/2026-10-25-曲谱核对与八度标记.md)。独立 MusicXML 核对及与上版资产的差异见 [JSON 记录](score-source-audit-0.1.34.json)。

电脑端仅运行 `test/data/piece_score_audit_test.dart`、`test/data/piano_piece_test.dart` 和 `test/domain/scrolling_piece_test.dart`，共 27 项通过，见 [日志](score-audit-tests-0.1.34.log)。覆盖六首旋律的预期音序与总时值、《你是我的阳光》逐事件时值、低音和高音圆点、跨八度图形映射及滚动时间轴。未运行 Android 集成测试，也未安装、启动、卸载应用或操作设备。

Release APK 构建通过，见 [构建日志](score-audit-build-0.1.34.log)。aapt 核对主包 ID、版本码 35 和版本名 0.1.34；安装包内六份曲目 JSON 与工作区源数据一致。未进行设备上的显示或试听验收，未执行全量回归或静态分析。

[安装包](../../releases/琴伴-0.1.34-internal.apk) · [大小与 SHA-256](../../releases/build-report-0.1.34.json)
