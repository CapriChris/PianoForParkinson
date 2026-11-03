# 琴伴 0.1.59+60 构建与验证

2026-11-03 · Android 本地测试版

## 安装包

- 产物为 `releases/qinban-0.1.59-android-universal.apk`，位于本地工作区。大小 659,372,432 字节（628.83 MiB）。
- 运行 `flutter build apk --release --target=lib/main.dart`，只构建主应用。包名 `com.pianoforparkinson.piano_practice`，版本 `0.1.59`，构建号 `60`。支持 ARM64、ARMv7 和 x86_64，最低 Android API 24，目标 API 36。
- 开发签名通过校验，证书与 0.1.58 主包一致。本次未上传 GitHub。
- APK 中的四个舞蹈视频逐个核对大小与 SHA-256，全部匹配资源清单。包内无 `INTERNET` 权限。

```text
4d9ef66f427303a3a6d43c9c3aa46b41cf7b3e0a29bf22e8b14c7990e566955f  qinban-0.1.59-android-universal.apk
```

## 测试

- `flutter analyze --no-pub` 通过。
- `flutter test --no-pub --reporter expanded` 共 611 项通过、102 项失败。按测试名称比较，102 项失败与目标布局修复前的基线一致。新增的目标布局回归测试通过。
- 本次未在模拟器或真机上安装验证。

本地日志位于 `build/release-0.1.59-build.log`、`build/release-0.1.59-analyze.log` 和 `build/release-0.1.59-tests.log`。对照基线为 `build/phone-layout-full.log`。[更新说明](../docs/2026-11-03-0.1.59-更新说明.md)
