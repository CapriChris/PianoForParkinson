# 模拟器实播录音与声部调整

日期：2026-10-25。版本：0.1.38+39。

当前环境不支持直接音频听辨；本报告为实播录音和客观核对，不是人工听感通过结论。模拟器：`emulator-5554`，Android 17。只安装和更新 `.validation` 隔离副本，主包未覆盖；保护快照 `qin-audio-before-20261025-0137` 已保存并核对仍在。

## 实播证据

[六首 80 拍录音核对](audio-audit-0.1.37/objective-before.json) 包含完整结束、实际伴奏状态、预期数量的主旋律发声请求，以及录音音量。对应 WebM/WAV 和日志均在 `audio-audit-0.1.37/` 中，文件名为各曲 slug 加 `-before`。

[最终版 80 拍](audio-audit-0.1.37/objective-final.json) 与 [最终版 60 拍](audio-audit-0.1.37/objective-final-60.json) 均完整播放《圣者进行曲》，分别发出 32 个主旋律请求，结束后无活动琴音或伴奏。两档复录覆盖最终实际音轨。

混音的相位／起音模板匹配不是校准后的音频延迟测量；低相关系数部分不据以判定精确同步。没有提供物理手机时延或主观契合度的结论。

## 调整及核对

六处紧邻 E4／F4 的钢琴和弦声部最终暂时省略，保留原旋律、节奏、全部 61 个行进低音及其余和弦。原始源谱 241 个事件，最终伴奏 235 个；每次调整可在 `tools/score_sources/backing-score-saints.json` 的 `voicing_adjustments` 追溯。

降八度的中间候选保存在 `*-after*` 录音中，不是最终交付。最终文件标记为 `*-final*`。可直接试听相同乐句： [原版片段](audio-audit-0.1.37/saints-comparison-before.wav) · [最终片段](audio-audit-0.1.37/saints-comparison-final.wav)。

71 项电脑端定向用例通过，见 [日志](audio-audit-0.1.37/host-tests-final.log)。原有来源、音轨哈希、时间轴、预览／完成页及滚动缓存检查继续通过。未执行全量回归或物理设备测试。

## 数据保护

[主包测试前状态](audio-audit-0.1.37/primary-package-before.txt) 与 [测试后状态](audio-audit-0.1.37/primary-package-after.txt) 中的版本、首次安装时间和更新时间相同。主包不可调试，未读取其私有数据库，也未声称数据库逐行一致。没有卸载、清除或覆盖主包，没有恢复旧数据库。测试副本已停止，原应用已回到前台。

[生产构建日志](audio-audit-0.1.37/production-build-0.1.38.log) · [发布记录](../../releases/build-report-0.1.38.json) · [安装包](../../releases/琴伴-0.1.38-internal.apk)

生产 APK 构建通过，aapt 核对正常主包名、版本名 0.1.38 和版本码 39。六份内容 JSON 和全部 30 个音轨与最终模拟器隔离副本逐字节相同，逐个核对哈希和音轨帧数；只有《圣者进行曲》伴奏变化，六首主旋律和其余五首内容保持。生产 APK 仅保存到发布目录，未覆盖模拟器主包。
