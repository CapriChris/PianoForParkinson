# 琴伴 0.1.73（构建 74）构建与验证

2026-11-19 首次发布。2026-11-20 从 `feature/android-apk-updates` 重新构建并替换 GitHub `v0.1.73` 预发布的 APK 与校验文件，沿用构建号 74。

## 更新内容

- 新增应用内完整 APK 更新。支持启动时检查、从设置手动检查、查看下载进度、取消和重试。校验安装包后，由 Android 安装器确认安装。
- 首页移除姓名显示，保留「我的账号」中的姓名编辑及与 Web 的双向同步。
- 11 月 20 日更新移除了正式练习页标题下方的姓名显示，同时移除这一行占用的空间。

## 验证与安装

- 首次发布时，应用内更新、姓名编辑和账号页面的 22 项 Flutter 测试通过。此次改动通过 56 项相关 Flutter 测试，覆盖正式练习布局、暂停及退出流程和账号姓名编辑。
- 通用 release 构建通过，沿用账号 API、云同步及 AI 网关配置。
- APK 包名为 `com.pianoforparkinson.piano_practice`，版本 0.1.73，构建 74，含 ARM64、ARMv7 和 x86_64，舞蹈视频按需播放。签名与 0.1.72 一致，可覆盖安装同包名、同签名的旧版。
- 本次在本机校验 APK，真机覆盖安装仍待验证。应用内正式更新提示需由 Web 端发布 [更新清单](../docs/android-apk-update.md)。
- 已安装构建 74 的用户可以重新下载 APK 后手动覆盖安装。

## 安装包

本机文件为 `releases/qinban-0.1.73-android-universal.apk`，大小为 102,920,214 字节。

```text
457eff09c8852865d4a719d2039d41b4369c0c1679128c4cdf227a34ca7a9d5c  qinban-0.1.73-android-universal.apk
```

[GitHub Release](https://github.com/CapriChris/PianoForParkinson/releases/tag/v0.1.73) · [下载 APK](https://github.com/CapriChris/PianoForParkinson/releases/download/v0.1.73/qinban-0.1.73-android-universal.apk) · [SHA-256 校验文件](https://github.com/CapriChris/PianoForParkinson/releases/download/v0.1.73/SHA256SUMS-0.1.73.txt)
