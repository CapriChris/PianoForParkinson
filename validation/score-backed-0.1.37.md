# 逐曲参考谱伴奏检查

日期：2026-10-25。版本：0.1.37+38。

六首逐曲导入记录见 [来源与事件哈希](score-backed-import-0.1.37.json)，原始谱与逐音 manifest 见 [来源目录](../tools/score_sources/README.md)。全部应用主旋律与 0.1.36 相同，30 个伴奏音轨全部替换、逐个解码并核对格式、精确帧数、哈希及无削波，见 [资产记录](score-backed-assets-0.1.37.json) 和 [渲染日志](score-backed-render-0.1.37.log)。

以下电脑端定向用例共 70 项通过，见 [测试日志](score-backed-tests-0.1.37.log)：

- `test/data/score_backing_source_test.dart`
- `test/data/piece_score_audit_test.dart`
- `test/data/piano_piece_test.dart`
- `test/domain/piece_backing_audio_test.dart`
- `test/domain/scrolling_piece_test.dart`
- `test/domain/piece_performance_test.dart`
- `test/widgets/piano_pieces_page_test.dart`
- `test/widgets/piece_result_test.dart`
- `test/widgets/scrolling_score_cache_test.dart`

检查逐曲原谱哈希、每个事件的源声部／谱表／小节、典型低音与和弦、五档音轨、同步控制和缓存复用。不把不同编配参考旋律的差异强行写回现有训练旋律。

未执行全量测试、静态分析、Android 集成测试或设备听感／性能验收，未安装或操作设备。PangfunJ Studio 参考谱限定个人学习、不供转售，按当前内部学习演示用途制作并在许可页说明，未宣称取得开放再分发许可。

Release 构建通过，aapt 核对主包名、版本名 0.1.37 和版本码 38。安装包中六份内容 JSON 与源文件相同，30 个 Ogg 伴奏逐个核对 SHA-256 并确认非压缩存储；逐曲来源署名文件已打入包内。

[构建日志](score-backed-build-0.1.37.log) · [发布记录](../../releases/build-report-0.1.37.json) · [安装包](../../releases/琴伴-0.1.37-internal.apk)
