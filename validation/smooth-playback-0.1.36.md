# 伴奏与滚动优化检查

日期：2026-10-25。版本：0.1.36+37。

以下电脑端定向检查共 63 项通过，见 [测试日志](smooth-playback-tests-0.1.36.log)：

- `test/data/piece_score_audit_test.dart`
- `test/data/piano_piece_test.dart`
- `test/domain/piece_backing_audio_test.dart`
- `test/domain/scrolling_piece_test.dart`
- `test/domain/piece_performance_test.dart`
- `test/widgets/piano_pieces_page_test.dart`
- `test/widgets/piece_result_test.dart`
- `test/widgets/scrolling_score_cache_test.dart`

覆盖五档音轨选择、开始及继续时单次同步、播放中无轮询、准备静音、取消和错误回调；连续 180 帧及父组件重建不重新排版，尺寸／主题变化刷新，销毁时释放资源。未执行全量测试或静态分析。

六首主旋律与 0.1.35 相同。30 个音轨已逐个解码，格式、总帧数、哈希、非静音和无削波通过，见 [资产记录](smooth-playback-assets-0.1.36.json)；生成日志见 [音轨渲染](backing-render-0.1.36.log)。

本轮未进行设备安装、Android 集成测试或性能验收，未获得设备端的 FPS、掉帧率、声音连续性或长期时钟漂移测量。原生编译、打包和资产核对独立于这些设备运行结论。

Release 构建通过。aapt 核对主包名、版本名 0.1.36 和版本码 37；安装包六份内容资产与源 JSON 一致，30 个 Ogg 文件逐个核对 SHA-256 并确认采用 openFd 可读的非压缩存储，旧版六个伴奏 WAV 已不在包内。

[构建日志](smooth-playback-build-0.1.36.log) · [发布记录](../../releases/build-report-0.1.36.json) · [安装包](../../releases/琴伴-0.1.36-internal.apk)
