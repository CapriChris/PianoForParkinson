# 0.1.58+59 恢复随包离线视频

日期：2026-11-03。根据用户决定，暂缓国内托管及按需下载，恢复四个视频随APK打包。新版本仅在本地构建，未推送或发布新的GitHub Release；现有0.1.56 Release保持不变。

## 当前行为

- 中文使用新平衡舞步六式第一、第二、第三部分，英文使用Fandango，均由VideoPlayerController.asset读取。
- 四个ASCII播放文件在pubspec中显式列出，不包含重复原片；安装后无需网络或下载地址。
- 下载管理入口、下载模块、运行时清单、联网权限声明及自定义网络状态桥接均撤下，配置network_requests_enabled恢复false。
- 发布APK不含INTERNET权限。播放器原有Media3依赖仍合并ACCESS_NETWORK_STATE，它不提供联网能力；通知权限与接收器保留。
- 记录、训练计划、课程和分段ID保持。保留退出过程中禁止重开/自动播放视频的保护，以及不会因固定日期过期而失效的通知测试夹具。
- 按需下载已纳入[未来开发计划](../docs/未来开发计划.md)。0.1.57原型已在本机build目录归档，host-pending包已标记停用，不再分发。

## 构建结果

| 安装包 | 包名 | 字节数 | 大小 |
| --- | --- | ---: | ---: |
| qinban-0.1.58-android-universal.apk | com.pianoforparkinson.piano_practice | 659372432 | 628.83 MiB |
| qinban-0.1.58-android-universal-preview-update.apk | com.pianoforparkinson.piano_practice.validation | 659372440 | 628.83 MiB |

本机产物位于原工作区releases目录。主入口lib/main.dart，release/AOT构建，包含armeabi-v7a、arm64-v8a、x86_64。主包命令 `flutter build apk --release --target=lib/main.dart`，兼容包追加 `--dart-define=ISOLATED_TEST_PACKAGE=true`。版本号0.1.58、构建号59；沿用开发签名，证书SHA-256为69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca，包名及版本均已核验。覆盖安装须选择匹配原包名的APK，不要先卸载。

```text
7b99a8a9a3ea4222eb50c093615fd88f5ad9a617aa9a0f74db3ffd6995188511  qinban-0.1.58-android-universal.apk
93a2bb8f30ce8f0082fbd6a5014bffc1590e8683b82176eff70ede75a07a0e3f  qinban-0.1.58-android-universal-preview-update.apk
```

## 验证

- 四个本机视频的字节数与SHA-256核对通过。
- 两个APK恰好包含这四个视频，共564458700字节；分别流式核验每个视频的大小与SHA-256通过，未打入按需下载清单。
- flutter analyze --no-pub：No issues found。
- 63项相关回归通过，覆盖舞蹈准备/播放/部分切换/保存/拖动/倍率/全屏/大字号、历史与计划数据、通知权限及跨午夜、按压及字号。
- 本轮未运行完整测试套件；0.1.56完整套件606通过/102失败的历史限制保留，不宣称全套通过。
- 本轮没有安装、卸载用户手机或模拟器上的App，没有新建模拟器；未执行新版真机视觉或音视频验收。

构建与检查日志：build/bundled-video-*.log。机器可读报告及校验文件：原工作区releases/build-report-0.1.58.json、releases/SHA256SUMS-0.1.58.txt。
