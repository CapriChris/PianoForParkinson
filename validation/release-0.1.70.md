# 琴伴 0.1.70+71 构建与验证

构建日期：2026-11-13；发布整理跨至 2026-11-14。基于队友 main `8919055`（0.1.69+70）整合本机舞蹈课程界面与插画更新。GitHub 发布标签 `v0.1.70`。本次不修改 Web 后端、不部署服务器，也未安装真机验收。

## 更新范围

舞蹈插画课程卡片、独立准备页、对应课程插画与语言标签；统一舞蹈/短旋律/节奏准备页插画宽高；完成页和记录卡片也根据课程 ID 使用对应插画。合入并保留队友舒缓节奏、左右手提示，保留已有手机号登录、云端同步、AI 训练助手及三门远程课程播放缓存。详见 [更新说明](../docs/2026-11-13-0.1.70-更新说明.md)。

## 验证结果

- `flutter analyze --no-pub`：No issues found。
- `flutter test --no-pub --reporter expanded`：**858 通过、2 项既有 opt-in 联网测试跳过、0 失败**。日志 `build/release-0.1.70-tests.log`、`build/release-0.1.70-analyze.log`。
- 通用 release APK 构建成功。versionName `0.1.70`、versionCode `71`，包名 `com.pianoforparkinson.piano_practice`，最低 API 24、目标 API 36，包含 ARM64、ARMv7、x86_64。
- apksigner 验证通过。证书 SHA-256 为 `69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca`，与本机 0.1.66 正式包一致，仍为内部测试开发签名。相同包名和签名旧版可覆盖安装，保留本机数据；独立 `.validation` 包仍可并存。
- APK 中三门课程的插画及十段远程资源清单与源码逐字节一致；确认无 MP4/WebM。原图留在源码，运行时使用 WebP。
- 分发目录复制后的 APK 与原始构建产物 SHA-256 一致。
- 首次构建与测试并行时，测试插件被写入自动生成的 Android 注册文件，导致 Java 编译失败；测试结束后单独重建，生成文件恢复且构建成功。未为此修改业务代码、插件依赖或签名。首次日志保留为 `build/release-0.1.70-build-first-attempt.log`，成功日志为 `build/release-0.1.70-build.log`。
- 本次无原生代码修改，未重复原生测试。真机插画布局、三门 HEVC 视频解码/弱网缓存、通知中断、账号登录及跨端计划进度仍需按现有清单验收；自动化和构建通过不等于设备或生产复验完成。

## 安装包

本机路径：`D:/MyIdea/PianoForParkinson/releases/qinban-0.1.70-android-universal.apk`。

大小：**102,558,314 字节（97.81 MiB）**。

```text
532ad5ecc302890c15335f20b91c601c1dd785ae45bc8c7ef8d66f10656034b7  qinban-0.1.70-android-universal.apk
```

[GitHub Release](https://github.com/CapriChris/PianoForParkinson/releases/tag/v0.1.70) · [APK 下载](https://github.com/CapriChris/PianoForParkinson/releases/download/v0.1.70/qinban-0.1.70-android-universal.apk) · [校验文件](https://github.com/CapriChris/PianoForParkinson/releases/download/v0.1.70/SHA256SUMS-0.1.70.txt)。安装包作为 Release 附件发布，不写入 Git 源码历史。上传时核对 GitHub 返回的附件状态、大小及 SHA-256 后再公开发布。

## 构建参数

```powershell
flutter build apk --release --target=lib/main.dart --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=PD_API_BASE=https://ccqspace.site/pd-rehab/api --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

未启用 `ISOLATED_TEST_PACKAGE`、`DANCE_FLOW_TEST_PACKAGE` 或 `ARM64_ONLY`。线上账号 API 与现有阿里云 AI 网关只以公开地址进入构建，不包含服务端 AccessKey、AppSecret 等密钥。
