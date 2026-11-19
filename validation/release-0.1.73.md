# 琴伴 0.1.73（构建 74）构建与验证

2026-11-19 从 `feature/android-apk-updates` 构建。GitHub 预发布标签为 `v0.1.73`。

## 更新内容

- 新增应用内完整 APK 更新。支持启动时检查、从设置手动检查、查看下载进度、取消和重试。校验安装包后，由 Android 安装器确认安装。
- 首页移除姓名显示，保留「我的账号」中的姓名编辑及与 Web 的双向同步。

## 验证与安装

- 应用内更新、姓名编辑和账号页面的 22 项 Flutter 测试通过。
- 通用 release 构建通过，沿用账号 API、云同步及 AI 网关配置。
- APK 包名为 `com.pianoforparkinson.piano_practice`，版本 0.1.73，构建 74，含 ARM64、ARMv7 和 x86_64，舞蹈视频按需播放。签名与 0.1.72 一致，可覆盖安装同包名、同签名的旧版。
- 本次在本机校验 APK，真机覆盖安装仍待验证。应用内正式更新提示需由 Web 端发布 [更新清单](../docs/android-apk-update.md)。

## 安装包

本机文件为 `releases/qinban-0.1.73-android-universal.apk`，大小为 102,920,214 字节。

```text
10aa14e14aa293824721219c7396ee6be6622afc4711f10792f4395b370cf12f  qinban-0.1.73-android-universal.apk
```

[GitHub Release](https://github.com/CapriChris/PianoForParkinson/releases/tag/v0.1.73) · [下载 APK](https://github.com/CapriChris/PianoForParkinson/releases/download/v0.1.73/qinban-0.1.73-android-universal.apk) · [SHA-256 校验文件](https://github.com/CapriChris/PianoForParkinson/releases/download/v0.1.73/SHA256SUMS-0.1.73.txt)
