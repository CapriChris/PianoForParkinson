# 曲谱修正与同步伴奏检查

日期：2026-10-25。版本：0.1.35+36。

《圣者进行曲》全部 32 个音高、起音时刻、时值与独立参考逐项相同。六首伴奏文件的 SHA-256、PCM 格式、精确长度、峰值及结束淡出检查通过，见 [资产检查](piece-backing-assets-0.1.35.json)。其余五首主旋律与 0.1.34 相同，内容哈希因新增伴奏元数据而更新。

以下电脑端用例共 61 项通过，见 [日志](piece-backing-tests-0.1.35.log)：

- `test/data/piece_score_audit_test.dart`
- `test/data/piano_piece_test.dart`
- `test/domain/piece_backing_audio_test.dart`
- `test/domain/scrolling_piece_test.dart`
- `test/domain/piece_performance_test.dart`
- `test/widgets/piano_pieces_page_test.dart`
- `test/widgets/piece_result_test.dart`

本轮未执行全量回归、Android 集成测试、设备安装或设备验收。原生伴奏的实际听感、时延及设备变速表现没有作运行验证。

Release 构建通过，aapt 核对包名 `com.pianoforparkinson.piano_practice`、版本名 0.1.35、版本码 36。安装包内六份曲目 JSON 与工作区一致；六个 WAV 均以可用于 openFd 的非压缩资产存储，文件 SHA-256 与内容元数据一致。构建日志见 [构建输出](piece-backing-build-0.1.35.log)，发布大小和校验和见 [构建报告](../../releases/build-report-0.1.35.json)。

[安装包](../../releases/琴伴-0.1.35-internal.apk) · [编配及实现说明](../../设计修订/2026-10-25-曲谱修正与同步伴奏.md)
